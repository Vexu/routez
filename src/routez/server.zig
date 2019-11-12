const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const StreamServer = std.net.StreamServer;
const Address = std.net.Address;
const File = std.fs.File;
const BufferOutStream = std.io.BufferOutStream;
const builtin = @import("builtin");
const request = @import("http/request.zig");
const response = @import("http/response.zig");
const parser = @import("http/parser.zig");
usingnamespace @import("http.zig");
usingnamespace @import("router.zig");

pub const Server = struct {
    server: StreamServer,
    handler: HandlerFn,
    allocator: *Allocator,
    config: Config,

    pub const Config = struct {
        multithreaded: bool = true,
        keepalive_time: u64 = 5000,
        max_request_size: u32 = 1024 * 1024,
        stack_size: usize = 4 * 1024 * 1024,
    };

    pub const Context = struct {
        stack: []align(16) u8,
        buf: []u8,
        index: usize = 0,
        count: usize = 0,
        out_stream: File.OutStream,
        server: *Server,
        file: File,

        frame: @Frame(handleRequest),

        pub fn init(server: *Server, file: File) !*Context {
            var ctx = try server.allocator.create(Context);
            errdefer server.allocator.destroy(ctx);

            var stack = try server.allocator.alignedAlloc(u8, 16, server.config.stack_size);
            errdefer server.allocator.free(stack);

            var buf = try server.allocator.alloc(u8, server.config.max_request_size);
            errdefer server.allocator.free(buf);

            ctx.* = Context{
                .stack = stack,
                .buf = buf,
                .out_stream = file.outStream(),
                .server = server,
                .file = file,
                .frame = undefined,
            };

            return ctx;
        }

        pub fn deinit(context: *Context) void {
            context.file.close();
            context.server.allocator.free(context.stack);
            context.server.allocator.free(context.buf);
            context.server.allocator.destroy(context);
        }

        pub fn read(context: *Context) !usize {
            const count = try context.file.read(context.buf[context.count..]);
            context.count += count;
            return count;
        }
    };

    const Upgrade = enum {
        WebSocket,
        Http2,
        None,
    };

    pub fn init(allocator: *Allocator, config: Config, comptime routes: []Route, comptime err_handlers: ?[]ErrorHandler) Server {
        return Server{
            .server = StreamServer.init(StreamServer.Options{}),
            .handler = Router(routes, err_handlers),
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn listen(server: *Server, address: Address) !void {
        defer server.server.deinit();
        try server.server.listen(address);

        while (true) {
            var client_file = try server.server.accept();
            var context = try Context.init(server, client_file);

            context.frame = async handleRequest(context);
        }
    }

    async fn handleRequest(context: *Context) void {
        defer context.deinit();

        const up = handleHttp(context) catch |e| {
            std.debug.warn("error in http handler: {}\n", e);
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
        var buf = try std.Buffer.initSize(ctx.server.allocator, 0);
        defer buf.deinit();
        var out_stream = BufferOutStream.init(&buf);

        // for use in headers and allocations in handlers
        var arena = ArenaAllocator.init(ctx.server.allocator);
        defer arena.deinit();
        const alloc = &arena.allocator;

        while (true) {
            var req = request.Request{
                .method = "",
                .headers = Headers.init(alloc),
                .path = "",
                .query = "",
                .body = "",
                .version = .Http11,
            };
            var res = response.Response{
                .status_code = undefined,
                .headers = Headers.init(alloc),
                .body = out_stream,
                .allocator = alloc,
            };

            if (parser.parse(&req, ctx)) {
                @newStackCall(ctx.stack, ctx.server.handler, &req, &res) catch |e| {
                    try defaultErrorHandler(e, &req, &res);
                };
            } else |e| {
                try defaultErrorHandler(e, &req, &res);
                try writeResponse(ctx.server, &ctx.out_stream.stream, &req, &res);
                return .None;
            }

            try writeResponse(ctx.server, &ctx.out_stream.stream, &req, &res);

            // reset for next request
            arena.deinit();
            arena = ArenaAllocator.init(ctx.server.allocator);
            buf.resize(0) catch unreachable;
            ctx.count = 0;
            ctx.index = 0;
            // TODO keepalive here
            return .None;
        }
        return .None;
    }

    fn writeResponse(server: *Server, stream: *File.OutStream.Stream, req: Request, res: Response) !void {
        const body = res.body.buffer.toSlice();
        const is_head = mem.eql(u8, req.method, Method.Head);

        try stream.print("{} {} {}\r\n", req.version.toString(), @enumToInt(res.status_code), res.status_code.toString());

        for (res.headers.list.toSlice()) |header| {
            try stream.print("{}: {}\r\n", header.name, header.value);
        }
        if (is_head) {
            try stream.write("content-length: 0\r\n\r\n");
        } else {
            try stream.print("content-length: {}\r\n\r\n", body.len);
        }

        if (!is_head) {
            try stream.write(body);
        }
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
