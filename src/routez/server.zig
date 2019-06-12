const std = @import("std");
const os = std.os;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const TcpServer = std.event.net.Server;
const Loop = std.event.Loop;
const Address = std.net.Address;
const File = std.os.File;
const request = @import("http/request.zig");
const response = @import("http/response.zig");
use @import("http.zig");
use @import("router.zig");

pub const Stream = std.os.File.OutStream.Stream;

pub fn writeResponse(stream: *Stream, version: Version, res: Response) !void {
    const body = res.body.buf.toSlice();
    try stream.print("{} {} {}\r\n", version.toString(), @enumToInt(res.status_code), res.status_code.toString());
    for (res.headers.list.toSlice()) |header| {
        try stream.print("{}: {}\r\n", header.name, header.value);
    }
    try stream.print("content-length: {}\r\n\r\n", body.len);
    try stream.write(body);
}

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
        errdefer server.close();
        try server.server.listen(address, handleRequest);
        server.loop.run();
    }

    pub fn close(s: *Server) void {
        s.server.close();
        s.server.deinit();
        s.loop.deinit();
    }

    pub async<*Allocator> fn handleRequest(server: *TcpServer, addr: *const std.net.Address, socket: File) void {
        const stream = &socket.outStream().stream;
        handleHttpRequest(@fieldParentPtr(Server, "server", server), socket) catch return;
    }

    fn handleHttpRequest(server: *Server, socket: File) !void {
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

        var socket_in = socket.inStream();
        var buf = try server.allocator.alloc(u8, os.page_size);
        defer server.allocator.free(buf);
        _ = try socket_in.stream.read(buf);
        var socket_out = socket.outStream();

        if (request.Request.parse(&arena.allocator, buf[0..buf.len])) |req| {
            defer req.deinit();
            server.handler(&req, &res) catch |e| {
                try defaultErrorHandler(e, &req, &res);
            };
            return writeResponse(&socket_out.stream, req.version, &res);
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
        return writeResponse(&socket_out.stream, .Http11, &res);
    }

    fn defaultErrorHandler(err: anyerror, req: Request, res: Response) !void {
        res.status_code = .InternalServerError;
        try res.headers.put("content-type", "application/json;charset=UTF-8");
        try res.print("{{\"error\":\"{}\"}}", @errorName(err));
    }
};
