const std = @import("std");
use @import("headers.zig");
use @import("common.zig");

pub const Response = struct {
    status_code: StatusCode,
    headers: Headers,
    body: *OutStream.Stream,
};

pub const OutStream = struct {
    buf: std.ArrayList(u8),
    stream: Stream,

    pub fn init(allocator: *std.mem.Allocator) OutStream {
        return OutStream{
            .buf = std.ArrayList(u8).init(allocator),
            .stream = Stream{ .writeFn = writeFn },
        };
    }

    pub const Error = error{OutOfMemory};
    pub const Stream = std.io.OutStream(Error);

    fn writeFn(out_stream: *Stream, bytes: []const u8) Error!void {
        const self = @fieldParentPtr(OutStream, "stream", out_stream);
        return self.buf.appendSlice(bytes);
    }
};
