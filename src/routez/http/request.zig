const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const assert = std.debug.assert;
usingnamespace @import("headers.zig");
usingnamespace @import("common.zig");
usingnamespace @import("zuri");
const Context = @import("../server.zig").Server.Context;

pub const Request = struct {
    method: []const u8,
    headers: Headers,
    path: []const u8,
    query: []const u8,
    body: []const u8,
    version: Version,

    pub const Error = error{
        InvalidMethod,
        TooShort,
        InvalidPath,
        InvalidVersion,
        UnsupportedVersion,
        Invalid,
    } || Uri.Error || Headers.Error;

    // TODO streaming parser
    pub fn parse(req: *Request, ctx: *Context) Error!void {
        const State = enum {
            Method,
            Path,
            AfterPath,
            Version,
            Cr,
            Lf,
            EmptyLine,
            Body,
        };

        var state = State.Method;
        var begin: usize = 0;

        while (true) : (ctx.index += 1) {
            if (ctx.index >= ctx.count) {
                if (ctx.count <= ctx.buf.len) {
                    // message has been read in its entirety
                    if (state != .Body) {
                        // message did not end properly
                        return Error.TooShort; // todo this is incorrectly being returned
                    }
                    req.body = ctx.buf[begin..ctx.index];
                    return;
                } else {
                    suspend;
                }
            }
            if (state == .Body) {
                ctx.index = ctx.count - 1;
                continue;
            }

            switch (state) {
                .Method => {
                    // todo should probably validate given chars
                    if (ctx.buf[ctx.index] == ' ') { // Conditional jump or move depends on uninitialised value(s), possible problem
                        if (ctx.index == 0) {
                            return Error.InvalidMethod;
                        }
                        req.method = ctx.buf[0..ctx.index];
                        begin = ctx.index + 1;
                        state = .Path;
                    }
                },
                .Path => {
                    if (ctx.buf[ctx.index] == ' ') {
                        const uri = try Uri.parse(ctx.buf[begin..ctx.index], true);
                        req.path = try Uri.collapsePath(req.headers.list.allocator, uri.path);
                        req.query = uri.query;
                        state = .Version;
                        begin = ctx.index + 1;
                    } else if (ctx.buf[begin] == '*') {
                        req.path = ctx.buf[begin .. begin + 1];
                        state = .AfterPath;
                    }
                },
                .AfterPath => {
                    if (ctx.buf[ctx.index] != ' ') {
                        return Error.InvalidChar;
                    }
                    state = .Version;
                    begin = ctx.index + 1;
                },
                .Version => {
                    // 8 for HTTP/X.X
                    if (ctx.index - begin < 7) {
                        continue;
                    }
                    if (!mem.eql(u8, ctx.buf[begin .. begin + 5], "HTTP/") or ctx.buf[begin + 6] != '.') {
                        return Error.InvalidVersion;
                    }
                    switch (ctx.buf[begin + 5]) {
                        '0' => req.version = .Http09,
                        '1' => req.version = .Http10,
                        '2' => req.version = .Http20,
                        '3' => req.version = .Http30,
                        else => return Error.InvalidVersion,
                    }
                    switch (ctx.buf[begin + 7]) {
                        '9' => if (req.version != .Http09) return Error.InvalidVersion,
                        '1' => if (req.version == .Http10) {
                            req.version = .Http11;
                        } else return Error.InvalidVersion,
                        '0' => {
                            if (req.version != .Http10 // or req.version != .Http20) {
                            ) {
                                //if (req.version != .Http20 and req.version != .Http30) return Error.InvalidVersion,
                                return Error.UnsupportedVersion;
                            }
                        },
                        else => return Error.InvalidVersion,
                    }
                    state = .Cr;
                },
                .Cr => {
                    if (ctx.buf[ctx.index] != '\r') {
                        return Error.Invalid;
                    }
                    state = .Lf;
                },
                .Lf => {
                    if (ctx.buf[ctx.index] != '\n') {
                        return Error.Invalid;
                    }
                    ctx.index += 1;
                    if (req.version == .Http09 and ctx.index == ctx.count) {
                        return;
                    }
                    try req.headers.parse(ctx);
                    if (ctx.index >= ctx.count) {
                        return;
                    }
                    if (ctx.buf[ctx.index] == '\r') {
                        state = .EmptyLine;
                    } else {
                        return Error.Invalid;
                    }
                },
                .EmptyLine => if (ctx.buf[ctx.index] == '\n') {
                    begin = ctx.index + 1;
                    state = .Body;
                } else {
                    return Error.Invalid;
                },
                else => unreachable,
            }
        }
    }
};

const alloc = std.heap.direct_allocator;

/// for testing, normally all memory is freed when the arena allocator is freed
fn deinit(req: *Request) void {
    req.headers.list.allocator.free(req.path);
    req.headers.deinit();
}

test "HTTP/0.9" {
    var b = try mem.dupe(alloc, u8, "GET / HTTP/0.9\r\n");
    defer alloc.free(b);
    var req: Request = undefined;
    req.headers = Headers.init(alloc);
    defer deinit(&req);
    var ctx = Context{
        .buf = b,
        .count = b.len,
        .stack = undefined,
        .socket = undefined,
        .server = undefined,
    };
    try noasync req.parse(&ctx);
    assert(mem.eql(u8, req.method, Method.Get));
    assert(mem.eql(u8, req.path, "/"));
    assert(req.version == .Http09);
}

test "HTTP/1.1" {
    var b = try mem.dupe(alloc, u8, "POST /about HTTP/1.1\r\n" ++
        "expires: Mon, 08 Jul 2019 11:49:03 GMT\r\n" ++
        "last-modified: Fri, 09 Nov 2018 06:15:00 GMT\r\n" ++
        "X-Test: test\r\n" ++
        " obs-fold\r\n" ++
        "\r\na body\n");
    defer alloc.free(b);
    var req: Request = undefined;
    req.headers =  Headers.init(alloc);
    defer deinit(&req);
    var ctx = Context{
        .buf = b,
        .count = b.len,
        .stack = undefined,
        .socket = undefined,
        .server = undefined,
    };
    try noasync req.parse(&ctx);
    assert(mem.eql(u8, req.method, Method.Post));
    assert(mem.eql(u8, req.path, "/about"));
    assert(req.version == .Http11);
    assert(mem.eql(u8, req.body, "a body\n"));
    assert(mem.eql(u8, (try req.headers.get(alloc, "expires")).?[0].value, "Mon, 08 Jul 2019 11:49:03 GMT"));
    assert(mem.eql(u8, (try req.headers.get(alloc, "last-modified")).?[0].value, "Fri, 09 Nov 2018 06:15:00 GMT"));
    const val = try req.headers.get(alloc, "x-test");
    assert(mem.eql(u8, (try req.headers.get(alloc, "x-test")).?[0].value, "test obs-fold"));
}

test "HTTP/3.0" {
    var b = try mem.dupe(alloc, u8, "POST /about HTTP/3.0\r\n\r\n");
    defer alloc.free(b);
    var req: Request = undefined;
    req.headers =  Headers.init(alloc);
    defer deinit(&req);
    var ctx = Context{
        .buf = b,
        .count = b.len,
        .stack = undefined,
        .socket = undefined,
        .server = undefined,
    };
    std.testing.expectError(error.UnsupportedVersion, noasync req.parse(&ctx));
}
