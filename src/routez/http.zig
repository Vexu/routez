const req = @import("http/request.zig");
const res = @import("http/response.zig");

pub usingnamespace @import("http/common.zig");
pub usingnamespace @import("http/headers.zig");

pub const Request = *const req.Request;
pub const Response = *res.Response;

test "http" {
    _ = @import("http/headers.zig");
    _ = @import("http/parser.zig");
    _ = @import("http/request.zig");
    _ = @import("http/response.zig");
}
