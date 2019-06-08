const req = @import("http/request.zig");
const res = @import("http/response.zig");
const headers = @import("http/headers.zig");

pub const Headers = headers.Headers;

pub const Method = req.Method;

pub const Request = *const req.Request;
pub const Response = *res.Response;

pub const request = req.Request;
pub const response = res.Response;

test "http" {
    _ = @import("http/request.zig");
    _ = @import("http/response.zig");
    _ = @import("http/headers.zig");
}
