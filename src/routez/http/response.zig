const std = @import("std");
const mime = @import("../mime.zig");
use @import("headers.zig");
use @import("common.zig");

pub const Response = struct {
    status_code: StatusCode,
    headers: Headers,
    body: OutStream,

    // todo improve
    pub fn sendFile(res: *Response, path: []const u8) !void {
        var out_stream = (try std.os.File.openRead(path)).inStream();
        defer out_stream.file.close();
        const stream = &out_stream.stream;

        const content = try stream.readAllAlloc(res.body.buf.allocator, 1024 * 1024);
        defer res.body.buf.allocator.free(content);
        try res.body.stream.write(content);

        var mimetype: []const u8 = mime.html;

        if (std.mem.lastIndexOfScalar(u8, path, '.')) |i| {
            if (mime.fromExtension(path[i + 1 ..])) |m| mimetype = m;
        }
        try res.headers.put("content-type", mimetype);
    }

    pub fn write(res: *Response, bytes: []const u8) !void {
        try res.headers.put("content-type", mime.html);
        try res.body.stream.write(bytes);
    }

    pub fn print(res: *Response, comptime format: []const u8, args: ...) !void {
        try res.headers.put("content-type", mime.html);
        try res.body.stream.print(format, args);
    }
};

pub const OutStream = struct {
    buf: std.ArrayList(u8),
    stream: Stream,

    pub fn init(allocator: *std.mem.Allocator) OutStream {
        return OutStream{
            .buf = std.ArrayList(u8).init(allocator),
            .stream = Stream{ .writeFn = writeFn },
        };
    }

    pub const Error = error{OutOfMemory};
    pub const Stream = std.io.OutStream(Error);

    fn writeFn(out_stream: *Stream, bytes: []const u8) Error!void {
        const self = @fieldParentPtr(OutStream, "stream", out_stream);
        return self.buf.appendSlice(bytes);
    }
};
