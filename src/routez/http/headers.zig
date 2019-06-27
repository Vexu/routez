const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
usingnamespace @import("session.zig");

pub const Headers = struct {
    list: HeaderList,

    pub const Error = error{
        InvalidChar,
        InvalidHeader,
        OutOfMemory,
    };

    const HeaderList = ArrayList(Header);
    const Header = struct {
        name: []const u8,
        value: []const u8,

        fn fromVerified(name: []u8, value: []u8) Error!Header {
            var i: usize = 0;
            while (i < name.len) : (i += 1) {
                switch (name[i]) {
                    'A'...'Z' => name[i] = (name[i] | 0x20),
                    else => {},
                }
            }

            i = 0;
            var offset: usize = 0;
            while (i < value.len - offset) : (i += 1) {
                if (value[i] == '\r') {
                    offset += 2;
                }
                value[i] = value[i + offset];
            }

            return Header{
                .name = name,
                .value = value[0 .. value.len - offset],
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

    pub fn has(h: *Headers, name: []const u8) bool {
        for (headers.list.toSlice()) |*h| {
            if (mem.eql(u8, h.name, name)) {
                return true;
            }
        }
        return false;
    }

    pub fn put(h: *Headers, name: []const u8, value: []const u8) Error!void {
        const new = try h.list.addOne();
        new.* = try Header.from(h.list.allocator, name, value);
    }

    pub async fn parse(h: *Headers, s: *Session) Error!void {
        const State = enum {
            Start,
            Name,
            AfterName,
            Value,
            Cr,
            AfterCr,
        };

        var state = State.Start;
        var begin: usize = s.index;
        var name: []u8 = "";
        var header: *Header = undefined;
        while (true) : (s.index += 1) {
            if (s.index >= s.count) {
                if (s.count < s.buf.len) {
                    // message ended, error if state is incorrect
                    if (state == .AfterCr) {
                        header = try h.list.addOne();
                        header.* = try Header.fromVerified(name, s.buf[begin .. s.index - 2]);
                        return;
                    } else return Error.InvalidHeader;
                }
                suspend;
            }

            const c = s.buf[s.index];
            switch (state) {
                .Start => {
                    switch (c) {
                        'a'...'z', 'A'...'Z', '0'...'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '/', '^', '_', '`', '|', '~' => state = .Name,
                        '\r' => {
                            return;
                        },
                        else => return Error.InvalidChar,
                    }
                },
                .Name => {
                    switch (c) {
                        'a'...'z', 'A'...'Z', '0'...'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '/', '^', '_', '`', '|', '~' => {},
                        ':' => {
                            state = .AfterName;
                            name = s.buf[begin..s.index];
                        },
                        else => return Error.InvalidChar,
                    }
                },
                .AfterName => {
                    if (c < ' ' or c > '~') {
                        return Error.InvalidChar;
                    } else if (c != ' ' and c != '\t') {
                        begin = s.index;
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
                        'a'...'z', 'A'...'Z', '0'...'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '/', '^', '_', '`', '|', '~', '\r' => {
                            header = try h.list.addOne();
                            header.* = try Header.fromVerified(name, s.buf[begin .. s.index - 2]);

                            if (c == '\r') {
                                return;
                            }
                            state = State.Name;
                            begin = s.index;
                        },
                        else => return Error.InvalidChar,
                    }
                },
            }
        }
        unreachable;
    }
};

// test "parse" {
//     var h = try async<std.debug.global_allocator> parseTest();
//     resume h;
//     cancel h;
// }

async fn parseTest() !void {
    suspend;
    const str = "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:67.0) Gecko/20100101 Firefox/67.0\r\n" ++
        "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n" ++
        "Accept-Language: en-US,en;q=0.5\r\n" ++
        "Accept-Encoding: gzip, deflate\r\n" ++
        "DNT: 1\r\n" ++
        "Connection: keep-alive\r\n" ++
        "Upgrade-Insecure-Requests: 1\r\n\r\n";

    const buf = try std.debug.global_allocator.alloc(u8, str.len);
    defer std.debug.global_allocator.free(buf);
    mem.copy(u8, buf, str);

    var h = Headers.init(std.debug.global_allocator);
    defer h.deinit();
    var i: usize = 0;
    var count: usize = str.len;
    var done = false;
    _ = try await (try async h.parse(buf, &i, &count, &done));

    var slice = h.list.toSlice();
    assert(mem.eql(u8, slice[0].name, "user-agent"));
    assert(mem.eql(u8, slice[0].value, "Mozilla/5.0 (X11; Linux x86_64; rv:67.0) Gecko/20100101 Firefox/67.0"));
    assert(mem.eql(u8, slice[0].name, "accept"));
    assert(mem.eql(u8, slice[1].value, "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"));
    assert(mem.eql(u8, slice[0].name, "accept-language"));
    assert(mem.eql(u8, slice[2].value, "en-US,en;q=0.5"));
    assert(mem.eql(u8, slice[0].name, "accept-encoding"));
    assert(mem.eql(u8, slice[3].value, "gzip, deflate"));
    assert(mem.eql(u8, slice[0].name, "dnt"));
    assert(mem.eql(u8, slice[4].value, "1"));
    assert(mem.eql(u8, slice[0].name, "connection"));
    assert(mem.eql(u8, slice[5].value, "keep-alive"));
    assert(mem.eql(u8, slice[0].name, "upgrade-Insecure-Requests"));
    assert(mem.eql(u8, slice[6].value, "1"));
}
