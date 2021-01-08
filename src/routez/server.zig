const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const StreamServer = std.net.StreamServer;
const Address = std.net.Address;
const File = std.fs.File;
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
    discards: DiscardStack,

    const DiscardStack = std.atomic.Stack(*Context);

    pub const Config = struct {
        keepalive_time: u64 = 5000,
        max_request_size: u32 = 1024 * 1024,
        stack_size: usize = 4 * 1024 * 1024,
    };

    pub const Context = struct {
        stack: []align(16) u8,
        buf: []u8,
        index: usize = 0,
        count: usize = 0,
        writer: std.io.BufferedWriter(4096, File.Writer),
        server: *Server,
        file: File,

        frame: @Frame(handleRequest),

        node: DiscardStack.Node,

        pub fn init(server: *Server, file: File) !*Context {
            var ctx = try server.allocator.create(Context);
            errdefer server.allocator.destroy(ctx);

            var stack = try server.allocator.alignedAlloc(u8, 16, server.config.stack_size);
            errdefer server.allocator.free(stack);

            var buf = try server.allocator.alloc(u8, server.config.max_request_size);
            errdefer server.allocator.free(buf);

            ctx.* = .{
                .stack = stack,
                .buf = buf,
                .writer = std.io.bufferedWriter(file.writer()),
                .server = server,
                .file = file,
                .frame = undefined,
                .node = .{
                    .next = null,
                    .data = ctx,
                },
            };

            return ctx;
        }

        pub fn deinit(context: *Context) void {
            context.file.close();
            context.server.allocator.free(context.stack);
            context.server.allocator.free(context.buf);
        }

        pub fn read(context: *Context) !void {
            context.index = 0;
            context.count = try context.file.read(context.buf);
        }
    };

    const Upgrade = enum {
        webSocket,
        http2,
        none,
    };

    pub fn init(allocator: *Allocator, config: Config, handlers: anytype) Server {
        return .{
            .server = StreamServer.init(.{}),
            .handler = Router(handlers),
            .allocator = allocator,
            .config = config,
            .discards = DiscardStack.init(),
        };
    }

    pub const ListenError = error{
        AddressInUse,
        AddressNotAvailable,
        ListenError,
        AcceptError,
        BlockedByFirewall,
    };

    pub fn listen(server: *Server, address: Address) ListenError!void {
        defer server.server.deinit();
        server.server.listen(address) catch |err| switch (err) {
            error.AddressInUse,
            error.AddressNotAvailable,
            => |e| return e,
            else => return error.ListenError,
        };

        while (true) {
            var conn = server.server.accept() catch |err| switch (err) {
                error.ConnectionAborted,
                error.ProcessFdQuotaExceeded,
                error.SystemFdQuotaExceeded,
                error.SystemResources,
                error.ProtocolFailure,
                error.Unexpected,
                error.ConnectionResetByPeer,
                error.NetworkSubsystemFailed,
                error.PermissionDenied,
                => continue,
                error.BlockedByFirewall => |e| return e,
                error.FileDescriptorNotASocket,
                error.SocketNotListening,
                error.OperationNotSupported,
                => return error.ListenError,
            };
            var context = Context.init(server, conn.file) catch {
                conn.file.close();
                continue;
            };

            context.frame = async handleRequest(context);

            while (server.discards.pop()) |c| {
                c.data.deinit();
                server.allocator.destroy(c.data);
            }
        }
    }

    fn handleRequest(context: *Context) callconv(.Async) void {
        defer context.server.discards.push(&context.node);

        const up = handleHttp(context) catch |e| {
            std.debug.warn("error in http handler: {}\n", .{e});
            return;
        };

        switch (up) {
            .webSocket => {
                // handleWs(self, socket.handle) catch |e| {};
            },
            .http2 => {},
            .none => {},
        }
    }

    fn handleHttp(ctx: *Context) callconv(.Async) !Upgrade {
        var buf = std.ArrayList(u8).init(ctx.server.allocator);
        defer buf.deinit();

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
                .body = buf.writer(),
                .allocator = alloc,
            };
            try ctx.read();

            if (parser.parse(&req, ctx)) {
                var frame = @asyncCall(ctx.stack, {}, ctx.server.handler, .{ &req, &res, req.path });
                await frame catch |e| {
                    try defaultErrorHandler(e, &req, &res);
                };
            } else |e| {
                try defaultErrorHandler(e, &req, &res);
                try writeResponse(ctx.server, ctx.writer.writer(), &req, &res);
                try ctx.writer.flush();
                return .none;
            }

            try writeResponse(ctx.server, ctx.writer.writer(), &req, &res);
            try ctx.writer.flush();

            // reset for next request
            arena.deinit();
            arena = ArenaAllocator.init(ctx.server.allocator);
            buf.resize(0) catch unreachable;
            // TODO keepalive here
            return .none;
        }
        return .none;
    }

    fn writeResponse(server: *Server, writer: anytype, req: Request, res: Response) !void {
        const body = res.body.context.items;
        const is_head = mem.eql(u8, req.method, Method.Head);

        try writer.print("{} {} {}\r\n", .{ req.version.toString(), @enumToInt(res.status_code), res.status_code.toString() });

        for (res.headers.list.items) |header| {
            try writer.print("{}: {}\r\n", .{ header.name, header.value });
        }
        try writer.writeAll("connection: close\r\n");
        if (is_head) {
            try writer.writeAll("content-length: 0\r\n\r\n");
        } else {
            try writer.print("content-length: {}\r\n\r\n", .{body.len});
        }

        if (!is_head) {
            try writer.writeAll(body);
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
                , .{req.path});
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
                    , .{@errorName(err)});
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
                        \\</body>
                        \\</html>
                    );
                }
            },
        }
    }
};
