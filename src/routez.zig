pub use @import("routez/http.zig");

pub use @import("routez/router.zig");

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
