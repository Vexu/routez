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

    pub fn setType(res: *Response, mimetype: []const u8) Headers.Error!void {
        try res.headers.put("content-type", mimetype);
    }

    pub const SendFileError = error {
        SystemError,
        AccessDenied,
        FileNotFound,
    } || WriteError;

    // todo improve, cache control
    pub fn sendFile(res: *Response, path: []const u8) SendFileError!void {
        var in_stream = (std.fs.cwd().openRead(path) catch |err| switch (err) {
            error.AccessDenied,
            error.FileNotFound,
            => |e| return e,
            else => return error.SystemError,
        }).inStream();
        defer in_stream.file.close();
        const stream = &in_stream.stream;

        const content = stream.readAllAlloc(res.allocator, 1024 * 1024) catch |err| switch (err) {
            error.OutOfMemory,
            => |e| return e,
            else => return error.SystemError,
        };
        defer res.allocator.free(content);
        try res.body.stream.write(content);

        var mimetype: []const u8 = mime.default;

        if (std.mem.lastIndexOfScalar(u8, path, '.')) |i| {
            if (mime.fromExtension(path[i + 1 ..])) |m| mimetype = m;
        }
        try res.setType(mimetype);
    }

    pub const WriteError = error {
        OutOfMemory,
    } || Headers.Error;

    pub fn write(res: *Response, bytes: []const u8) WriteError!void {
        try res.setType(mime.html);
        try res.body.stream.write(bytes);
    }

    pub fn print(res: *Response, comptime format: []const u8, args: ...) WriteError!void {
        try res.setType(mime.html);
        try res.body.stream.print(format, args);
    }
};
