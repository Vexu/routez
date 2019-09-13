const std = @import("std");
const mime = @import("../mime.zig");
usingnamespace @import("headers.zig");
usingnamespace @import("common.zig");

pub const Response = struct {
    status_code: StatusCode,
    headers: Headers,
    body: std.io.BufferOutStream,

    /// arena allocator that frees everything when response has been sent
    allocator: *std.mem.Allocator,

    pub fn setType(res: *Response, mimetype: []const u8) !void {}

    // todo improve, cache control
    pub fn sendFile(res: *Response, path: []const u8) !void {
        var out_stream = (try std.fs.File.openRead(path)).inStream();
        defer out_stream.file.close();
        const stream = &out_stream.stream;

        const content = try stream.readAllAlloc(res.allocator, 1024 * 1024);
        defer res.allocator.free(content);
        try res.body.stream.write(content);

        var mimetype: []const u8 = mime.text;

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
