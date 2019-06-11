const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

pub const Headers = struct {
    list: HeaderList,

    pub const Error = error{
        InvalidChar,
        Invalid,
        OutOfMemory,
    };

    const HeaderList = ArrayList(Header);
    const Header = struct {
        name: []const u8,
        value: []const u8,

        fn fromVerified(allocator: *Allocator, name: []const u8, value: []const u8) Error!Header {
            var copy_name = try allocator.alloc(u8, name.len);
            var copy_value = try allocator.alloc(u8, value.len);
            errdefer allocator.free(copy_name);
            errdefer allocator.free(copy_value);

            for (name) |c, i| {
                copy_name[i] = switch (c) {
                    'A'...'Z' => c | 0x20,
                    else => c,
                };
            }
            var i: usize = 0;
            for (value) |c| {
                switch (c) {
                    '\r', '\n' => {},
                    else => {
                        copy_value[i] = c;
                        i += 1;
                    },
                }
            }
            copy_value = allocator.shrink(copy_value, i);
            return Header{
                .name = copy_name,
                .value = copy_value,
            };
        }

        fn from(allocator: *Allocator, name: []const u8, value: []const u8) Error!Header {
            var copy_name = try allocator.alloc(u8, name.len);
            var copy_value = try allocator.alloc(u8, value.len);
            errdefer allocator.free(copy_name);
            errdefer allocator.free(copy_value);

            for (name) |c, i| {
                copy_name[i] = switch (c) {
                    'a'...'z', '0'...'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '/', '^', '_', '`', '|', '~' => c,
                    'A'...'Z' => c | 0x20,
                    else => return Error.InvalidChar,
                };
            }
            var i: usize = 0;
            for (value) |c| {
                if (c < ' ' or c > '~') {
                    return Error.InvalidChar;
                } else if (c != '\r' and c != '\n') {
                    copy_value[i] = c;
                    i += 1;
                }
            }
            copy_value = allocator.shrink(copy_value, i);
            return Header{
                .name = copy_name,
                .value = copy_value,
            };
        }
    };

    pub fn init(allocator: *Allocator) Headers {
        return Headers{
            .list = HeaderList.init(allocator),
        };
    }

    pub fn deinit(headers: Headers) void {
        const a = headers.list.allocator;
        for (headers.list.toSlice()) |h| {
            a.free(h.name);
            a.free(h.value);
        }
        headers.list.deinit();
    }

    pub fn get(headers: *const Headers, allocator: *Allocator, name: []const u8) Error!?[]const *Header {
        var list = ArrayList(*Header).init(allocator);
        errdefer list.deinit();
        for (headers.list.toSlice()) |*h| {
            if (mem.eql(u8, h.name, name)) {
                const new = try list.addOne();
                new.* = h;
            }
        }
        if (list.len == 0) {
            return null;
        } else {
            return list.toOwnedSlice();
        }
    }

    // pub fn set(h: *Headers, name: []const u8, value: []const u8) Error!?[]const u8 {
    //     // var old = get()
    // }

    pub fn put(h: *Headers, name: []const u8, value: []const u8) Error!void {
        const new = try h.list.addOne();
        new.* = try Header.from(h.list.allocator, name, value);
    }

    fn putVerified(h: *Headers, name: []const u8, value: []const u8) Error!void {
        const new = try h.list.addOne();
        new.* = try Header.fromVerified(h.list.allocator, name, value);
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
                    if (c < ' ' or c > '~') {
                        return Error.InvalidChar;
                    } else if (c != ' ' and c != '\t') {
                        begin = i;
                        state = .Value;
                    }
                },
                .Value => {
                    if (c == '\r') {
                        state = .Cr;
                    } else if (c < ' ' or c > '~') {
                        return Error.InvalidChar;
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
                        },
                        '\r' => {
                            try h.putVerified(name, buffer[begin..i]);
                            state = .Done;
                            break;
                        },
                        'a'...'z', 'A'...'Z', '0'...'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '/', '^', '_', '`', '|', '~' => {
                            try h.putVerified(name, buffer[begin..i]);
                            state = if (c == '\r') State.Done else State.Name;
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

test "Headers.parse" {
    var h = Headers.init(std.debug.global_allocator);
    defer h.deinit();
    _ = try h.parse("User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:67.0) Gecko/20100101 Firefox/67.0\r\n" ++
        "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n" ++
        "Accept-Language: en-US,en;q=0.5\r\n" ++
        "Accept-Encoding: gzip, deflate\r\n" ++
        "DNT: 1\r\n" ++
        "Connection: keep-alive\r\n" ++
        "Upgrade-Insecure-Requests: 1\r\n\r\n");
}
