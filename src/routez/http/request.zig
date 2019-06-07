const http = @import("../http.zig");

pub const Request = struct {
    code: u32,
    method: http.Method,
    path: []const u8,
    // body: []const u8,
};
