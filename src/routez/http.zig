const req = @import("http/request.zig");
const res = @import("http/response.zig");

pub usingnamespace @import("http/headers.zig");
pub usingnamespace @import("http/common.zig");

pub const Request = *const req.Request;
pub const Response = *res.Response;

test "http" {
    _ = @import("http/request.zig");
    _ = @import("http/response.zig");
    _ = @import("http/headers.zig");
    _ = @import("http/parser.zig");
}
