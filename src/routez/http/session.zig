const std = @import("std");
const os = std.os;

pub const Session = struct {
    buf: []u8,
    index: usize,
    count: usize,
    socket: os.fd_t,
    connection: Connection,
    upgrade: Upgrade,
    state: State,
    last_message: u64,
    handle: ?promise,

    const Upgrade = enum {
        WebSocket,
        Http2,
        Unknown,
        None,
    };

    const Connection = enum {
        Close,
        KeepAlive,
    };

    const State = enum {
        Message,
        KeepAlive,
    };
};
