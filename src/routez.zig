pub usingnamespace @import("routez/http.zig");

const s = @import("routez/server.zig");
pub const Server = s.Server;

pub const mime = @import("routez/mime.zig");

const r = @import("routez/router.zig");
pub const ErrorHandler = r.ErrorHandler;
pub const Route = r.Route;

pub usingnamespace @import("routez/routes.zig");

test "routez" {
    _ = @import("routez/http.zig");
    _ = @import("routez/mime.zig");
    _ = @import("routez/router.zig");
    _ = @import("routez/routes.zig");
    _ = @import("routez/server.zig");
}
