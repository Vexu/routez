const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const HashMap = std.HashMap;

pub const Headers = struct {
    map: HeaderMap,
    pub const Error = error{
        InvalidChar,
        Invalid,
        OutOfMemory,
    };

    const HeaderMap = HashMap([]const u8, []const u8, mem.hash_slice_u8, mem.eql_slice_u8);

    pub fn init(allocator: *Allocator) Headers {
        return Headers{
            .map = HeaderMap.init(allocator),
        };
    }

    pub fn parse(h: *Headers, buffer: []const u8) Error!usize {
        const State = enum {
            Start,
            Name,
            AfterName,
            Value,
            Cr,
            AfterCr,
            Done,
        };

        var state = State.Start;
        var i: usize = 0;
        var begin: usize = 0;
        var name: []const u8 = "";
        while (i < buffer.len) : (i += 1) {
            const c = buffer[i];
            switch (state) {
                .Start => {
                    switch (c) {
                        'a'...'z', 'A'...'Z', '0'...'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '/', '^', '_', '`', '|', '~' => state = .Name,
                        '\r' => {
                            state = .Done;
                            break;
                        },
                        else => return Error.InvalidChar,
                    }
                },
                .Name => {
                    switch (c) {
                        'a'...'z', 'A'...'Z', '0'...'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '/', '^', '_', '`', '|', '~' => {},
                        ':' => {
                            state = .AfterName;
                            name = buffer[begin..i];
                        },
                        else => return Error.InvalidChar,
                    }
                },
                .AfterName => {
                    if (c == ' ') {
                        state = .Value;
                        begin = i + 1;
                    } else {
                        return Error.InvalidChar;
                    }
                },
                .Value => {
                    switch (c) {
                        'a'...'z', 'A'...'Z', '0'...'9', '(', ')', '<', '>', '@', ',', ';', ':', '\\', '\"', '/', '[', ']', '?', '=', '{', '}', ' ', '\t' => {},
                        '\r' => {
                            state = .Cr;
                            _ = try h.map.put(name, buffer[begin..i]);
                        },
                        else => return Error.InvalidChar,
                    }
                },
                .Cr => {
                    if (c != '\n') {
                        return Error.InvalidChar;
                    }
                    state = .AfterCr;
                },
                .AfterCr => {
                    switch (c) {
                        ' ', '\t' => {
                            state = .Value;
                            // begin = i + 1; todo currently includes '\t' or ' ' in header value
                        },
                        '\r' => {
                            state = .Done;
                            break;
                        },
                        'a'...'z', 'A'...'Z', '0'...'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '/', '^', '_', '`', '|', '~' => {
                            state = .Name;
                            begin = i;
                        },
                        else => return Error.InvalidChar,
                    }
                },
                .Done => unreachable,
            }
        }

        if (state != .Done) {
            return Error.Invalid;
        }

        return i;
    }
};
