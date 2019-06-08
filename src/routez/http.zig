const req = @import("http/request.zig");
const res = @import("http/response.zig");
const headers = @import("http/headers.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const ZServer = std.event.net.Server;
const Loop = std.event.Loop;
const Address = std.net.Address;
const File = std.os.File;

use @import("router.zig");

pub const Headers = headers.Headers;

pub const Method = req.Method;

pub const Request = *const req.Request;
pub const Response = *res.Response;

pub const request = req.Request;
pub const response = res.Response;

pub const Handler = fn handle(Request, Response) void;

test "http" {
    _ = @import("http/request.zig");
    _ = @import("http/response.zig");
    _ = @import("http/headers.zig");
}

pub const Settings = struct {
    multithreaded: bool,
    address: Address,
};

pub const Server = struct {
    server: ZServer,
    router: Handler,

    pub fn listen(allocator: *Allocator, settings: Settings, router: Handler) !Server {
        var loop: Loop = undefined;
        const loop_init = if (settings.multithreaded) Loop.initMultiThreaded else Loop.initSingleThreaded;
        try loop_init(&loop, allocator);
        errdefer loop.deinit();

        var s = Server{
            .server = ZServer.init(&loop),
            .router = router,
        };
        defer s.server.deinit();
        try s.server.listen(&settings.address, handleRequest);

        loop.run();

        return s;
    }

    pub fn close(s: *Server) void {
        s.server.close();
        s.server.deinit();
        s.server.deinit();
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

// test "" {
//     _ = try Server.listen(std.debug.global_allocator, Settings{ .address = Address.initIp4(std.net.parseIp4("127.0.0.1") catch unreachable, 1234), .multithreaded = true }, Router(&[]Route{}, defaultErrorHandler));
// }
