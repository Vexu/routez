const std = @import("std");
const os = std.os;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const TcpServer = std.event.net.Server;
const Loop = std.event.Loop;
const Address = std.net.Address;
const File = std.os.File;
const net = std.event.net;
const Stream = std.event.net.OutStream.Stream;
const request = @import("http/request.zig");
const response = @import("http/response.zig");
use @import("http.zig");
use @import("router.zig");

pub const Server = struct {
    server: TcpServer,
    handler: HandlerFn,
    loop: Loop,
    allocator: *Allocator,

    pub const Properties = struct {
        multithreaded: bool,
    };

    pub fn init(s: *Server, allocator: *Allocator, properties: Properties, comptime routes: []Route, comptime err_handlers: ?[]ErrorHandler) !void {
        const loop_init = if (properties.multithreaded) Loop.initMultiThreaded else Loop.initSingleThreaded;

        s.handler = Router(routes, err_handlers);
        s.allocator = allocator;
        try loop_init(&s.loop, allocator);
        s.server = TcpServer.init(&s.loop);
    }

    pub fn listen(server: *Server, address: *Address) !void {
        errdefer server.deinit();
        errdefer server.loop.deinit();
        // todo error AddressInUse
        try server.server.listen(address, handleRequest);
        server.loop.run();
    }

    pub fn close(s: *Server) void {
        s.server.close();
    }

    pub fn deinit(s: *Server) void {
        s.server.deinit();
        s.loop.deinit();
    }

    pub async<*Allocator> fn handleRequest(server: *TcpServer, addr: *const std.net.Address, socket: File) void {
        const handle = async handleHttpRequest(@fieldParentPtr(Server, "server", server), socket) catch return;
        (await handle) catch |err| {
            std.debug.warn("unable to handle connection: {}\n", err);
        };

        // workaround to fix some requests not arriving
        // todo fix properly
        socket.close();
    }

    async fn handleHttpRequest(server: *Server, socket: File) !void {
        var out_stream = response.OutStream.init(server.allocator);
        defer out_stream.buf.deinit();

        // for use in headers and allocations in handlers
        var arena = ArenaAllocator.init(server.allocator);
        defer arena.deinit();

        var res = response.Response{
            .status_code = .InternalServerError,
            .headers = Headers.init(&arena.allocator),
            .body = out_stream,
        };

        var socket_in = net.InStream.init(&server.loop, socket.handle);

        if (await (try async request.Request.parse(&arena.allocator, &socket_in.stream))) |req| {
            defer req.deinit();
            server.handler(&req, &res) catch |e| {
                try defaultErrorHandler(e, &req, &res);
            };
            return await (try async writeResponse(server, socket.handle, req.version, &res));
        } else |e| {
            std.debug.warn("error parsing: {}\n", e);
            return e;
        }
        // TODO: zig: /build/zig/src/zig-0.4.0/src/ir.cpp:21059: IrInstruction*
        //      ir_analyze_instruction_check_switch_prongs(IrAnalyze*, IrInstructionCheckSwitchProngs*):
        //      Assertion `start_value->value.type->id == ZigTypeIdErrorSet' failed.
        // switch (e) {
        //     .InvalidVersion => res.status_code = .HttpVersionNotSupported,
        //     .OutOfMemory => res.status_code = .InternalServerError,
        //     else => res.status_code = .BadRequest,
        // }
        // return writeResponse(&socket_out.stream, .Http11, &res);
    }

    async fn writeResponse(server: *Server, fd: os.FileHandle, version: Version, res: Response) !void {
        const body = res.body.buf.toSlice();

        var buf_stream = response.OutStream.init(server.allocator);
        try buf_stream.buf.ensureCapacity(512);
        defer buf_stream.buf.deinit();
        var stream = &buf_stream.stream;

        try stream.print("{} {} {}\r\n", version.toString(), @enumToInt(res.status_code), res.status_code.toString());
        try stream.print("content-length: {}\r\n", body.len);
        for (res.headers.list.toSlice()) |header| {
            try stream.print("{}: {}\r\n", header.name, header.value);
        }
        try stream.write("\r\n");

        try await (try async write(&server.loop, fd, buf_stream.buf.toSlice()));
        try await (try async write(&server.loop, fd, body));
    }

    // copied from std.event.net with proper error values
    async fn write(loop: *Loop, fd: os.FileHandle, buffer: []const u8) !void {
        const iov = os.posix.iovec_const{
            .iov_base = buffer.ptr,
            .iov_len = buffer.len,
        };
        const iovs: *const [1]os.posix.iovec_const = &iov;
        return await (async net.writevPosix(loop, fd, iovs, 1) catch unreachable);
    }

    fn defaultErrorHandler(err: anyerror, req: Request, res: Response) !void {
        res.status_code = .InternalServerError;
        try res.headers.put("content-type", "application/json;charset=UTF-8");
        try res.print("{{\"error\":\"{}\"}}", @errorName(err));
    }
};
