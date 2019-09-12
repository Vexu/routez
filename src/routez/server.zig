const std = @import("std");
const os = std.os;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const TcpServer = std.event.net.Server;
const Loop = std.event.Loop;
const Address = std.net.Address;
const File = std.fs.File;
const net = std.event.net;
const BufferOutStream = std.io.BufferOutStream;
const time = std.time;
const builtin = @import("builtin");
const request = @import("http/request.zig");
const response = @import("http/response.zig");
usingnamespace @import("http.zig");
usingnamespace @import("router.zig");

pub const Server = struct {
    server: TcpServer,
    handler: HandlerFn,
    loop: Loop,
    allocator: *Allocator,
    config: Config,

    pub const Config = struct {
        multithreaded: bool = true,
        keepalive_time: u64 = 5000,
        max_request_size: u32 = 1024 * 1024,
        stack_size: usize = 4 * 1024 * 1024,
    };

    pub const Context = struct {
        stack: []u8,
        buf: []u8,
        index: usize = 0,
        count: usize = 0,
        socket: os.fd_t,
        server: *Server,

        pub fn init(server: *Server, socket: os.fd_t) !Context {
            return Context {
                .stack = try server.allocator.alloc(u8, server.config.stack_size),
                .buf = try server.allocator.alloc(u8, server.config.max_request_size),
                .socket = socket,
                .server = server,
            };
        }
    };

    const Upgrade = enum {
        WebSocket,
        Http2,
        None,
    };

    pub fn init(s: *Server, allocator: *Allocator, config: Config, comptime routes: []Route, comptime err_handlers: ?[]ErrorHandler) !void {
        const loop_init = if (config.multithreaded) Loop.initMultiThreaded else Loop.initSingleThreaded;

        s.handler = Router(routes, err_handlers);
        s.allocator = allocator;
        try loop_init(&s.loop, allocator);
        s.server = TcpServer.init(&s.loop);
        s.config = config;
    }

    pub fn listen(server: *Server, address: *Address) void {
        errdefer server.deinit();
        errdefer server.loop.deinit();
        server.server.listen(address, handleRequest) catch |e| {
            std.debug.warn("{}\n", e);
            os.abort();
        };
        server.loop.run();
    }

    pub fn close(s: *Server) void {
        s.server.close();
    }

    pub fn deinit(s: *Server) void {
        s.server.deinit();
        s.loop.deinit();
    }

    pub async fn handleRequest(server: *TcpServer, addr: *const std.net.Address, socket: File) void {
        const self = @fieldParentPtr(Server, "server", server);
        self.loop.linuxWait(
            socket.handle,
            Loop.ResumeNode{
                .id = .Basic,
                .handle = @frame(),
                .overlapped = Loop.ResumeNode.overlapped_init,
            },
            // TODO correct flags?
            os.EPOLLIN | os.EPOLLPRI | os.EPOLLERR | os.EPOLLHUP,
        );
        defer self.loop.linuxRemoveFd(socket.handle);
        defer socket.close();

        var ctx = Context.init() catch {
            std.debug.warn("could not handle request: Out of memory");
            return;
        };

        const up = handleHttp(&ctx) catch |e| {
            std.debug.warn("error in http handler: {}", e);
            return;
        };

        switch (up) {
            .WebSocket => {
                // handleWs(self, socket.handle) catch |e| {};
            },
            .Http2 => {},
            .None => {},
        }
    }

    async fn handleHttp(ctx: *Context) !Upgrade {
        var out_stream = BufferOutStream.init(ctx.server.allocator);
        defer out_stream.buf.deinit();

        // for use in headers and allocations in handlers
        var arena = ArenaAllocator.init(ctx.server.allocator);
        defer arena.deinit();

        while (true) {
            var req = request.Request{
                .method = "",
                .headers = Headers.init(&arena.allocator),
                .path = "",
                .query = "",
                .body = "",
                .version = .Http11,
            };
            var res = response.Response{
                .status_code = undefined,
                .headers = Headers.init(&arena.allocator),
                .body = out_stream,
                .allocator = &arena.allocator,
            };

            if (request.Request.parse(&req, &ctx)) {
                @newStackCall(ctx.buf, ctx.server.handler, &req, &res) catch |e| {
                    try defaultErrorHandler(e, &req, &res);
                };
            } else |e| {
                try defaultErrorHandler(e, &req, &res);
                try writeResponse(ctx.server, ctx.socket, &req, &res);
                return .None;
            }

            writeResponse(ctx.server, ctx.socket, &req, &res);

            // reset for next request
            arena.deinit();
            arena.init(ctx.server.allocator);
            out_stream.buffer.resize(0);
            // TODO keepalive here
            return .None;
        }
        return .None;
    }

    fn writeResponse(server: *Server, fd: os.fd_t, req: Request, res: Response) !void {
        const body = res.body.buffer.toSlice();
        const is_head = mem.eql(u8, req.method, Method.Head);

        // TODO bufferedOutStream
        // var out_stream = OutStream.init(&server.loop, fd);
        // var buf_stream = std.io.BufferedOutStream(anyerror).init()
        // // defer buf_stream.buf.deinit();
        // var stream = &buf_stream.stream;

        try stream.print("{} {} {}\r\n", req.version.toString(), @enumToInt(res.status_code), res.status_code.toString());

        for (res.headers.list.toSlice()) |header| {
            try stream.print("{}: {}\r\n", header.name, header.value);
        }
        if (is_head) {
            try stream.write("content-length: 0\r\n\r\n");
        } else {
            try stream.print("content-length: {}\r\n\r\n", body.len);
        }

        try write(&server.loop, fd, buf_stream.buf.toSlice());
        if (!is_head) {
            try write(&server.loop, fd, body);
        }
    }

    // copied from std.event.net with proper error values
    async fn write(loop: *Loop, fd: os.fd_t, buffer: []const u8) !void {
        const iov = os.iovec_const{
            .iov_base = buffer.ptr,
            .iov_len = buffer.len,
        };
        const iovs: *const [1]os.iovec_const = &iov;
        return net.writevPosix(loop, fd, iovs, 1);
    }

    fn defaultErrorHandler(err: anyerror, req: Request, res: Response) !void {
        switch (err) {
            error.FileNotFound => {
                res.status_code = .NotFound;
                try res.print(
                    \\<!DOCTYPE html>
                    \\<html>
                    \\<head>
                    \\    <title>404 - Not Found</title>
                    \\</head>
                    \\<body>
                    \\    <h1>Not Found</h1>
                    \\    <p>Requested URL {} was not found.</p>
                    \\</body>
                    \\</html>
                , req.path);
            },
            else => {
                if (builtin.mode == .Debug) {
                    res.status_code = .InternalServerError;
                    try res.print(
                        \\<!DOCTYPE html>
                        \\<html>
                        \\<head>
                        \\    <title>500 - Internal Server Error</title>
                        \\</head>
                        \\<body>
                        \\    <h1>Internal Server Error</h1>
                        \\    <p>Debug info - Error: {}</p>
                        \\</body>
                        \\</html>
                    , @errorName(err));
                } else {
                    res.status_code = .InternalServerError;
                    try res.write(
                        \\<!DOCTYPE html>
                        \\<html>
                        \\<head>
                        \\    <title>500 - Internal Server Error</title>
                        \\</head>
                        \\<body>
                        \\    <h1>Internal Server Error</h1>
                        \\    <p>Requested URL {} was not found.</p>
                        \\</body>
                        \\</html>
                    );
                }
            },
        }
    }
};
