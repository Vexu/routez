const Version = @import("common.zig").Version;
const Headers = @import("headers.zig").Headers;

pub const Request = struct {
    method: []const u8,
    headers: Headers,
    path: []const u8,
    query: []const u8,
    body: []const u8,
    version: Version,
};
