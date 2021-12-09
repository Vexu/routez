const std = @import("std");
const mime = @import("../mime.zig");
const Headers = @import("headers.zig").Headers;
const StatusCode = @import("common.zig").StatusCode;

pub const Response = struct {
    status_code: ?StatusCode,
    headers: Headers,
    body: std.ArrayList(u8).Writer,

    /// arena allocator that frees everything when response has been sent
    allocator: std.mem.Allocator,

    pub fn setType(res: *Response, mimetype: []const u8) Headers.Error!void {
        try res.headers.put("content-type", mimetype);
    }

    pub const SendFileError = error{
        SystemError,
        AccessDenied,
        FileNotFound,
    } || WriteError;

    // todo improve, cache control
    pub fn sendFile(res: *Response, path: []const u8) SendFileError!void {
        var in_file = (std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.AccessDenied,
            error.FileNotFound,
            => |e| return e,
            else => return error.SystemError,
        });
        defer in_file.close();

        const content = in_file.reader().readAllAlloc(res.allocator, 1024 * 1024) catch |err| switch (err) {
            error.OutOfMemory => |e| return e,
            else => return error.SystemError,
        };
        defer res.allocator.free(content);
        try res.body.writeAll(content);

        var mimetype: []const u8 = mime.default;

        if (std.mem.lastIndexOfScalar(u8, path, '.')) |i| {
            if (mime.map.get(path[i + 1 ..])) |m| mimetype = m;
        }
        try res.setType(mimetype);
    }

    pub const WriteError = std.mem.Allocator.Error || Headers.Error;

    pub fn write(res: *Response, bytes: []const u8) WriteError!void {
        try res.setType(mime.html);
        try res.body.writeAll(bytes);
    }

    pub fn print(res: *Response, comptime format: []const u8, args: anytype) WriteError!void {
        try res.setType(mime.html);
        try res.body.print(format, args);
    }
};
