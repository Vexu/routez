const req = @import("http/request.zig");
const res = @import("http/response.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const ZServer = std.event.net.Server;
const Loop = std.event.Loop;
const Address = std.net.Address;
const File = std.os.File;
pub use @import("http/headers.zig");
pub use @import("http/version.zig");

use @import("router.zig");

pub const Method = req.Method;
pub const StatusCode = res.StatusCode;

pub const Request = *const req.Request;
pub const Response = *res.Response;

pub const request = req.Request;
pub const response = res.Response;

pub const Handler = fn handle(Request, Response) anyerror!void;

test "http" {
    _ = @import("http/request.zig");
    _ = @import("http/response.zig");
    _ = @import("http/headers.zig");
}

pub const Server = struct {
    server: ZServer,
    handler: Handler,
    loop: Loop,

    pub const Properties = struct {
        multithreaded: bool,
    };

    pub fn init(allocator: *Allocator, properties: Properties, comptime routes: []Route, comptime err_handlers: ?[]ErrorHandler) !Server {
        const loop_init = if (properties.multithreaded) Loop.initMultiThreaded else Loop.initSingleThreaded;

        var s = Server{
            .server = undefined,
            .handler = Router(routes, err_handlers),
            .loop = undefined,
        };
        try loop_init(&s.loop, allocator);
        s.server = ZServer.init(&s.loop);
        return s;
    }

    pub fn listen(server: *Server, address: *Address) !void {
        errdefer server.close();
        try server.server.listen(address, handleRequest);
        server.loop.run();
    }

    pub fn close(s: *Server) void {
        s.server.close();
        s.server.deinit();
        s.loop.deinit();
    }

    async<*Allocator> fn handleRequest(server: *ZServer, addr: *const std.net.Address, file: File) void {
        std.debug.warn("got request\n");

        const self = @fieldParentPtr(Server, "server", server);
        var socket = file; // TODO https://github.com/ziglang/zig/issues/1592
        defer socket.close();
        // TODO guarantee elision of this allocation
        const next_handler = async errorableHandler(self, addr, socket) catch unreachable;
        (await next_handler) catch |err| {
            std.debug.panic("unable to handle connection: {}\n", err);
        };
        suspend {
            cancel @handle();
        }
    }
    async fn errorableHandler(self: *Server, _addr: *const std.net.Address, _socket: File) !void {
        const addr = _addr.*; // TODO https://github.com/ziglang/zig/issues/1592
        var socket = _socket; // TODO https://github.com/ziglang/zig/issues/1592

        const stream = &socket.outStream().stream;
        try stream.print("HTTP/1.1 200 OK\r\n\r\nhello world\n");
    }
};

// test "server" {
//     var server = try Server.init(
//         std.debug.global_allocator,
//         Server.Properties{ .multithreaded = true },
//         &[]Route{get("/", indexHandler)},
//         null,
//     );
//     try server.listen(&Address.initIp4(try std.net.parseIp4("127.0.0.1"), 5555));
// }

fn indexHandler(_: Request, resp: Response) void {
    resp.status_code = .Ok;
}
