const std = @import("std");
const os = std.os;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const TcpServer = std.event.net.Server;
const Loop = std.event.Loop;
const Address = std.net.Address;
const File = std.os.File;
const net = std.event.net;
const Stream = std.event.net.OutStream.Stream;
const builtin = @import("builtin");
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
        // todo handle keep-alive
        socket.close();
        cancel @handle();
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
            return await (try async writeResponse(server, socket.handle, &req, &res));
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

    async fn writeResponse(server: *Server, fd: os.FileHandle, req: Request, res: Response) !void {
        const body = res.body.buf.toSlice();
        const is_head = mem.eql(u8, req.method, Method.Head);

        var buf_stream = response.OutStream.init(server.allocator);
        try buf_stream.buf.ensureCapacity(512);
        defer buf_stream.buf.deinit();
        var stream = &buf_stream.stream;

        try stream.print("{} {} {}\r\n", req.version.toString(), @enumToInt(res.status_code), res.status_code.toString());

        // workaround to fix some requests not arriving
        // todo properly support keep-alive
        try stream.write("connection: close\r\n");

        for (res.headers.list.toSlice()) |header| {
            try stream.print("{}: {}\r\n", header.name, header.value);
        }
        if (is_head) {
            try stream.write("content-length: 0\r\n\r\n");
        } else {
            try stream.print("content-length: {}\r\n\r\n", body.len);
        }

        try await (try async write(&server.loop, fd, buf_stream.buf.toSlice()));
        if (!is_head) {
            try await (try async write(&server.loop, fd, body));
        }
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
