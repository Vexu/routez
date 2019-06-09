const h = @import("routez/http.zig");
pub const http = struct {
    pub const Headers = h.Headers;
    pub const Method = h.Method;
    pub const Request = h.Request;
    pub const Response = h.Response;
    pub const Version = h.Version;
    pub const StatusCode = h.StatusCode;
};
pub const Server = h.Server;

// Java's package private would be nice
const r = @import("routez/router.zig");
pub const ErrorHandler = r.ErrorHandler;
pub const Route = r.Route;
pub const all = r.all;
pub const get = r.get;
pub const head = r.head;
pub const post = r.post;
pub const put = r.put;
pub const delete = r.delete;
pub const connect = r.connect;
pub const options = r.options;
pub const trace = r.trace;
pub const patch = r.patch;
pub const subRoute = r.subRoute;
pub const static = r.static;

pub const version = struct {
    pub const major = 0;
    pub const minor = 0;
    pub const patch = 0;
    pub const string = "0.0.0";
};

test "routez" {
    _ = @import("routez/http.zig");
    _ = @import("routez/router.zig");
}
