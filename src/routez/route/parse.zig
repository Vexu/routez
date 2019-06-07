const std = @import("std");
const Allocator = std.mem.Allocator;
const mem = std.mem;

pub fn match(comptime route: []const u8, path: []const u8) bool {
    const State = enum {
        Start,
        Path,
        AmperStart,
        AmperFirst,
        Format,
    };

    comptime const hex_digits = "0123456789ABCDEF";
    comptime var state = State.Start;
    comptime var index: usize = 0;
    comptime var begin: usize = 0;
    comptime var pathbuf: [256]u8 = undefined;
    comptime var fmt_begin: usize = 0;
    comptime var fmt_index: usize = 0;
    var path_index: usize = 0;

    inline for (route) |c, i| {
        switch (state) {
            .Start => switch (c) {
                '/' => comptime {
                    pathbuf[index] = '/';
                    state = .Path;
                    index += 1;
                },
                else => @compileError("route must begin with a '/'"),
            },
            .Path => switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9', '-', '.', '_', '~', '!', '$', '&', '\'', '(', ')', '*', '+', ',', ';', '=', ':', '@', '%', '/' => comptime {
                    pathbuf[index] = c;
                    index += 1;
                    if (c == '%') {
                        state = .AmperStart;
                    }
                },
                '{' => {
                    state = .Format;
                    comptime var r = route[begin..i];
                    fmt_begin = i + 1;
                    if (!mem.eql(u8, r, path[path_index..r.len])) {
                        return false;
                    }
                    path_index += r.len;
                },
                else => comptime {
                    pathbuf[index] = '%';
                    pathbuf[index + 1] = hex_digits[(c & 0xF0) >> 4];
                    pathbuf[index + 2] = hex_digits[c & 0x0F];
                    index += 3;
                },
            },
            .AmperStart, .AmperFirst => switch (c) {
                '0'...'9', 'a'...'f', 'A'...'F' => comptime {
                    pathbuf[index] = c;
                    index += 1;
                    if (state == .AmperStart) {
                        state = .AmperFirst;
                    } else {
                        state = .Path;
                    }
                },
                else => @compileError("'%' must be followed by two hexadecimal digits"),
            },
            .Format => switch (c) {
                '}' => {
                    state = .Path;
                    begin = pathbuf.len;
                    comptime const Fmt = struct {
                        min: usize,
                        max: usize,
                        num: bool,
                        base: usize,
                        signed: bool,
                    };
                    comptime var kind = Fmt{
                        .min = 0,
                        .max = 0,
                        .num = true,
                        .base = 10,
                        .signed = false,
                    };
                    comptime const Fstate = enum {
                        First,
                        Base,
                        Min,
                        Max,
                    };
                    comptime var fstate = .First;
                    comptime {
                        var fmt = route[fmt_begin..i];
                        if (fmt.len == 0) {
                            @compileError("empty format string");
                        }
                        for (fmt) |fc, fi| {
                            switch (fstate) {
                                .First => switch (fc) {
                                    's', 'S' => {
                                        kind.num = false;
                                        fstate = .Min;
                                    },
                                    'x', 'X' => {
                                        kind.base = 16;
                                        fstate = .Min;
                                    },
                                    'd', 'D' => {
                                        kind.signed = true;
                                        fstate = .Min;
                                    },
                                    'u', 'U' => fstate = .Min,
                                    'b', 'B' => fstate = .Base,
                                    else => @compileError("unknown format character"),
                                },
                                .Base => switch (fc) {
                                    '0'...'9' => {
                                        kind.base *= 10;
                                        kind.base += fc - 0x30;
                                    },
                                    ';' => fstate = .Min,
                                    else => @compileError("base must be a base 10 number"),
                                },
                                .Min => switch (fc) {
                                    '0'...'9' => {
                                        kind.min *= 10;
                                        kind.min += fc - 0x30;
                                    },
                                    ';' => fstate = .Max,
                                    else => @compileError("min size must be a base 10 number"),
                                },
                                .Max => switch (fc) {
                                    '0'...'9' => {
                                        kind.max *= 10;
                                        kind.max += fc - 0x30;
                                    },
                                    else => @compileError("max size must be a base 10 number"),
                                },
                                else => unreachable,
                            }
                        }
                    }

                    // if (kind.min )

                    for (path) |pc| {

                    }
                },
                else => unreachable,
            },
            else => @compileError("todo"),
        }
    }
    if (state != .Path) {
        @compileError("Invalid route");
    }

    return mem.eql(u8, pathbuf[begin..], path[path_index..]);
}

test "match" {
    std.debug.assert(match("/test/ä{s}/", "/test/%C3%A4/"));
}
