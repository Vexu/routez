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
const Stream = std.event.net.OutStream.Stream;
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
        max_header_size: u32 = 80 * 1024,
    };

    pub const Session = struct {
        buf: []u8,
        index: usize,
        count: usize,
        socket: os.fd_t,
        connection: Connection,
        upgrade: Upgrade,
        state: State,
        last_message: u64,
        server: *Server,

        const Upgrade = enum {
            WebSocket,
            Http2,
            Unknown,
            None,
        };

        const Connection = enum {
            Close,
            KeepAlive,
        };

        const State = enum {
            Message,
            KeepAlive,
        };
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

        var s = Session{
            .buf = undefined,
            .index = 0,
            .count = 0,
            .socket = socket.handle,
            .connection = .KeepAlive,
            .upgrade = .None,
            .state = .Message,
            .last_message = 0,
        };

        s.buf = self.allocator.alloc(u8, 1024) catch return;
        defer self.allocator.free(s.buf);

        var socket_in = net.InStream.init(&self.loop, socket.handle);
        var stream = &socket_in.stream;
        var read: usize = undefined;

        var handle = async handleHttpRequest(self, &s);

        // TODO connection upgrade
        while (true) {
            if (s.count >= s.buf.len) {
                // todo improve
                if (s.buf.len * 2 > self.config.max_header_size) {
                    return;
                }
                s.buf = self.allocator.realloc(s.buf, s.buf.len * 2) catch return;
            }
            read = stream.read(s.buf[s.count..]) catch {
                // todo probably incorrect way to handle this
                return;
            };
            if (read != 0) {
                s.state = .Message;
            }
            s.count += read;
            switch (s.state) {
                .Message => {
                    resume handle;
                },
                .KeepAlive => {
                    if (s.connection != .KeepAlive) {
                        return;
                    }
                    // resume other operations, return when keepalive_time reached
                    suspend;
                    // if (time.timestamp() - s.last_message > self.config.keepalive_time) {
                    //     return;
                    // }
                },
            }
        }
    }

    async fn handleHttpRequest(server: *Server, s: *Session) !void {
        suspend;

        var out_stream = response.OutStream.init(server.allocator);
        defer out_stream.buf.deinit();

        // for use in headers and allocations in handlers
        var arena = ArenaAllocator.init(server.allocator);
        defer arena.deinit();

        defer s.count = 0;
        defer s.index = 0;
        defer s.last_message = time.timestamp();
        defer s.state = .KeepAlive;
        defer s.handle = null;

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
        };

        if (request.Request.parse(&req, s)) {
            server.handler(&req, &res) catch |e| {
                try defaultErrorHandler(e, &req, &res);
            };
        } else |e| try defaultErrorHandler(e, &req, &res);
        return writeResponse(server, s.socket, &req, &res);
    }

    fn writeResponse(server: *Server, fd: os.fd_t, req: Request, res: Response) !void {
        const body = res.body.buf.toSlice();
        const is_head = mem.eql(u8, req.method, Method.Head);

        var buf_stream = response.OutStream.init(server.allocator);
        try buf_stream.buf.ensureCapacity(512);
        defer buf_stream.buf.deinit();
        var stream = &buf_stream.stream;

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
