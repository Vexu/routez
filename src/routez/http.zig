const req = @import("http/request.zig");
const res = @import("http/response.zig");

pub const Request = *const req.Request;
pub const Response = *res.Response;

pub const request = req.Request;
pub const response = res.Response;

pub const Method = enum {
    All,
    Get,
    Head,
    Post,
    Put,
    Delete,
    Connect,
    Options,
    Trace,
    Patch,
};
