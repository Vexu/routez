const std = @import("std");
const io = std.io;

pub const Response = struct {
    status_code: u32,
    // body: [] u8,todo outstream
};
