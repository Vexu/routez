pub use @import("routez/http.zig");

const s = @import("routez/server.zig");
pub const Server = s.Server;

pub const mime = @import("routez/server.zig");

const r = @import("routez/router.zig");
pub const ErrorHandler = r.ErrorHandler;
pub const Route = r.Route;

pub use @import("routez/routes.zig");

pub const version = struct {
    pub const major = 0;
    pub const minor = 0;
    pub const patch = 0;
    pub const string = "0.0.0";
};

test "routez" {
    _ = @import("routez/http.zig");
    _ = @import("routez/router.zig");
    _ = @import("routez/server.zig");
    _ = @import("routez/mime.zig");
    _ = @import("routez/routes.zig");
}
