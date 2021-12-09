const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const Context = @import("../server.zig").Server.Context;

// TODO use std.http.Headers
pub const Headers = struct {
    list: HeaderList,

    pub const Error = error{
        InvalidChar,
        OutOfMemory,
    };

    const HeaderList = ArrayList(Header);
    const Header = struct {
        name: []const u8,
        value: []const u8,

        fn from(allocator: Allocator, name: []const u8, value: []const u8) Error!Header {
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
            for (mem.trim(u8, value, " \t")) |c| {
                if (c == '\r' or c == '\n') {
                    // obs-fold
                } else if (c < ' ' or c > '~') {
                    return Error.InvalidChar;
                } else {
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

    pub fn init(allocator: Allocator) Headers {
        return Headers{
            .list = HeaderList.init(allocator),
        };
    }

    pub fn deinit(headers: Headers) void {
        const a = headers.list.allocator;
        for (headers.list.items) |h| {
            a.free(h.name);
            a.free(h.value);
        }
        headers.list.deinit();
    }

    pub fn get(headers: *const Headers, allocator: Allocator, name: []const u8) Error!?[]const *Header {
        var list = ArrayList(*Header).init(allocator);
        errdefer list.deinit();
        for (headers.list.items) |*h| {
            if (mem.eql(u8, h.name, name)) {
                const new = try list.addOne();
                new.* = h;
            }
        }
        if (list.items.len == 0) {
            return null;
        } else {
            return list.toOwnedSlice();
        }
    }

    // pub fn set(h: *Headers, name: []const u8, value: []const u8) Error!?[]const u8 {
    //     // var old = get()
    // }

    pub fn has(headers: *Headers, name: []const u8) bool {
        for (headers.list.items) |*h| {
            if (mem.eql(u8, h.name, name)) {
                return true;
            }
        }
        return false;
    }

    pub fn hasTokenIgnoreCase(headers: *const Headers, name: []const u8, token: []const u8) bool {
        for (headers.list.items) |*h| {
            if (ascii.eqlIgnoreCase(h.name, name) and ascii.eqlIgnoreCase(h.value, token)) {
                return true;
            }
        }
        return false;
    }

    pub fn put(h: *Headers, name: []const u8, value: []const u8) Error!void {
        try h.list.append(try Header.from(h.list.allocator, name, value));
    }
};
