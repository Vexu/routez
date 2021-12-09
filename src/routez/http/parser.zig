const std = @import("std");
const mem = std.mem;
const zuri = @import("zuri");
const Uri = zuri.Uri;
const Headers = @import("headers.zig").Headers;
const Request = @import("request.zig").Request;
const Version = @import("common.zig").Version;
const Context = @import("../server.zig").Server.Context;
const Method = @import("../http.zig").Method;
const t = std.testing;

pub fn parse(req: *Request, ctx: *Context) !void {
    var cur = ctx.index;

    // method
    if (!seek(ctx, ' ')) {
        return error.NoMethod;
    }
    req.method = ctx.buf[cur .. ctx.index - 1];
    cur = ctx.index;

    // path
    if (!seek(ctx, ' ')) {
        return error.NoPath;
    }
    const uri = try Uri.parse(ctx.buf[cur .. ctx.index - 1], true);
    req.path = try Uri.resolvePath(req.headers.list.allocator, uri.path);
    req.query = uri.query;
    cur = ctx.index;

    // version
    if (!seek(ctx, '\r')) {
        return error.NoVersion;
    }
    req.version = try Version.fromString(ctx.buf[cur .. ctx.index - 1]);

    if (req.version == .Http30) {
        return error.UnsupportedVersion;
    }

    try expect(ctx, '\n');

    // HTTP/0.9 allows request with no headers to end after "METHOD PATH HTTP/0.9\r\n"
    if (req.version == .Http09 and ctx.index == ctx.count) {
        return;
    }
    try parseHeaders(&req.headers, ctx);
    try expect(ctx, '\r');
    try expect(ctx, '\n');

    req.body = ctx.buf[ctx.index..ctx.count];
}

fn parseHeaders(h: *Headers, ctx: *Context) !void {
    var name: []u8 = "";
    var cur = ctx.index;

    while (ctx.buf[cur] != '\r') {
        if (!seek(ctx, ':')) {
            return error.NoName;
        }
        name = ctx.buf[cur .. ctx.index - 1];
        cur = ctx.index;

        if (!seek(ctx, '\r')) {
            return error.NoValue;
        }
        try expect(ctx, '\n');

        switch (ctx.buf[ctx.index]) {
            '\t', ' ' => { // obs-fold
                if (!seek(ctx, '\r')) {
                    return error.InvalidObsFold;
                }
                try expect(ctx, '\n');
            },
            else => {},
        }
        try h.put(name, ctx.buf[cur .. ctx.index - 2]);
        cur = ctx.index;
    }
}

// index is after first `c`
fn seek(ctx: *Context, c: u8) bool {
    while (true) {
        if (ctx.index >= ctx.count) {
            return false;
        } else if (ctx.buf[ctx.index] == c) {
            ctx.index += 1;
            return true;
        } else {
            ctx.index += 1;
        }
    }
}

// index is after `c`
fn expect(ctx: *Context, c: u8) !void {
    if (ctx.count < ctx.index + 1) {
        return error.UnexpectedEof;
    }
    if (ctx.buf[ctx.index] == c) {
        ctx.index += 1;
    } else {
        return error.InvalidChar;
    }
}

const alloc = std.heap.page_allocator;

test "parse headers" {
    var b = try alloc.dupe(u8, "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:67.0) Gecko/20100101 Firefox/67.0\r\n" ++
        "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n" ++
        "Accept-Language: en-US,en;q=0.5\r\n" ++
        "Accept-Encoding: gzip, deflate\r\n" ++
        "DNT: 1\r\n" ++
        "Connection: keep-alive\r\n" ++
        "Upgrade-Insecure-Requests: 1\r\n\r\n");
    defer alloc.free(b);
    var h = Headers.init(alloc);
    defer h.list.deinit();
    var ctx = Context{
        .buf = b,
        .count = b.len,
        .stack = undefined,
        .writer = undefined,
        .server = undefined,
        .stream = undefined,
        .frame = undefined,
        .node = undefined,
    };
    try parseHeaders(&h, &ctx);

    var slice = h.list.items;
    try t.expect(mem.eql(u8, slice[0].name, "user-agent"));
    try t.expect(mem.eql(u8, slice[0].value, "Mozilla/5.0 (X11; Linux x86_64; rv:67.0) Gecko/20100101 Firefox/67.0"));
    try t.expect(mem.eql(u8, slice[1].name, "accept"));
    try t.expect(mem.eql(u8, slice[1].value, "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"));
    try t.expect(mem.eql(u8, slice[2].name, "accept-language"));
    try t.expect(mem.eql(u8, slice[2].value, "en-US,en;q=0.5"));
    try t.expect(mem.eql(u8, slice[3].name, "accept-encoding"));
    try t.expect(mem.eql(u8, slice[3].value, "gzip, deflate"));
    try t.expect(mem.eql(u8, slice[4].name, "dnt"));
    try t.expect(mem.eql(u8, slice[4].value, "1"));
    try t.expect(mem.eql(u8, slice[5].name, "connection"));
    try t.expect(mem.eql(u8, slice[5].value, "keep-alive"));
    try t.expect(mem.eql(u8, slice[6].name, "upgrade-insecure-requests"));
    try t.expect(mem.eql(u8, slice[6].value, "1"));
}

test "HTTP/0.9" {
    var b = try alloc.dupe(u8, "GET / HTTP/0.9\r\n");
    defer alloc.free(b);
    var req: Request = undefined;
    req.headers = Headers.init(alloc);
    defer req.headers.deinit();
    var ctx = Context{
        .buf = b,
        .count = b.len,
        .stack = undefined,
        .writer = undefined,
        .server = undefined,
        .stream = undefined,
        .frame = undefined,
        .node = undefined,
    };
    try parse(&req, &ctx);
    try t.expect(mem.eql(u8, req.method, Method.Get));
    try t.expect(mem.eql(u8, req.path, "/"));
    try t.expect(req.version == .Http09);
}

test "HTTP/1.1" {
    var b = try alloc.dupe(u8, "POST /about HTTP/1.1\r\n" ++
        "expires: Mon, 08 Jul 2019 11:49:03 GMT\r\n" ++
        "last-modified: Fri, 09 Nov 2018 06:15:00 GMT\r\n" ++
        "X-Test: test\r\n" ++
        " obs-fold\r\n" ++
        "\r\na body\n");
    defer alloc.free(b);
    var req: Request = undefined;
    req.headers = Headers.init(alloc);
    defer req.headers.deinit();
    var ctx = Context{
        .buf = b,
        .count = b.len,
        .stack = undefined,
        .writer = undefined,
        .server = undefined,
        .stream = undefined,
        .frame = undefined,
        .node = undefined,
    };
    try parse(&req, &ctx);
    try t.expect(mem.eql(u8, req.method, Method.Post));
    try t.expect(mem.eql(u8, req.path, "/about"));
    try t.expect(req.version == .Http11);
    try t.expect(mem.eql(u8, req.body, "a body\n"));
    try t.expect(mem.eql(u8, (try req.headers.get(alloc, "expires")).?[0].value, "Mon, 08 Jul 2019 11:49:03 GMT"));
    try t.expect(mem.eql(u8, (try req.headers.get(alloc, "last-modified")).?[0].value, "Fri, 09 Nov 2018 06:15:00 GMT"));
    const val = try req.headers.get(alloc, "x-test");
    _ = val;
    try t.expect(mem.eql(u8, (try req.headers.get(alloc, "x-test")).?[0].value, "test obs-fold"));
}

test "HTTP/3.0" {
    var b = try alloc.dupe(u8, "POST /about HTTP/3.0\r\n\r\n");
    defer alloc.free(b);
    var req: Request = undefined;
    req.headers = Headers.init(alloc);
    defer req.headers.deinit();
    var ctx = Context{
        .buf = b,
        .count = b.len,
        .stack = undefined,
        .writer = undefined,
        .server = undefined,
        .stream = undefined,
        .frame = undefined,
        .node = undefined,
    };
    try t.expectError(error.UnsupportedVersion, parse(&req, &ctx));
}
