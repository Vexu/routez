const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const assert = std.debug.assert;
const Stream = std.event.net.InStream.Stream;
usingnamespace @import("headers.zig");
usingnamespace @import("common.zig");
usingnamespace @import("zuri");

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
    pub fn parse(req: *Request, s: *Session) Error!void {
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

        while (true) : (s.index += 1) {
            if (s.index >= s.count) {
                if (s.count < s.buf.len) {
                    // message has been read in its entirety
                    if (state != .Body) {
                        // message did not end properly
                        return Error.TooShort; // todo this is incorrectly being returned
                    }
                    req.body = s.buf[begin..s.index];
                    return;
                } else
                    suspend;
            }
            if (state == .Body) {
                s.index = s.count - 1;
                continue;
            }

            switch (state) {
                .Method => {
                    // todo should probably validate given chars
                    if (s.buf[s.index] == ' ') { // Conditional jump or move depends on uninitialised value(s), possible problem
                        if (s.index == 0) {
                            return Error.InvalidMethod;
                        }
                        req.method = s.buf[0..s.index];
                        begin = s.index + 1;
                        state = .Path;
                    }
                },
                .Path => {
                    if (s.buf[s.index] == ' ') {
                        const uri = try Uri.parse(s.buf[begin..s.index], true);
                        req.path = try Uri.collapsePath(req.headers.list.allocator, uri.path);
                        req.query = uri.query;
                        state = .Version;
                        begin = s.index + 1;
                    } else if (s.buf[begin] == '*') {
                        req.path = s.buf[begin .. begin + 1];
                        state = .AfterPath;
                    }
                },
                .AfterPath => {
                    if (s.buf[s.index] != ' ') {
                        return Error.InvalidChar;
                    }
                    state = .Version;
                    begin = s.index + 1;
                },
                .Version => {
                    // 8 for HTTP/X.X
                    if (s.index - begin < 7) {
                        continue;
                    }
                    if (!mem.eql(u8, s.buf[begin .. begin + 5], "HTTP/") or s.buf[begin + 6] != '.') {
                        return Error.InvalidVersion;
                    }
                    switch (s.buf[begin + 5]) {
                        '0' => req.version = .Http09,
                        '1' => req.version = .Http10,
                        '2' => req.version = .Http20,
                        '3' => req.version = .Http30,
                        else => return Error.InvalidVersion,
                    }
                    switch (s.buf[begin + 7]) {
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
                    if (s.buf[s.index] != '\r') {
                        return Error.Invalid;
                    }
                    state = .Lf;
                },
                .Lf => {
                    if (s.buf[s.index] != '\n') {
                        return Error.Invalid;
                    }
                    s.index += 1;
                    try await (try async req.headers.parse(s));
                    if (s.index >= s.count) {
                        return;
                    }
                    if (s.buf[s.index] == '\r') {
                        state = .EmptyLine;
                    } else {
                        return Error.Invalid;
                    }
                },
                .EmptyLine => if (s.buf[s.index] == '\n') {
                    begin = s.index + 1;
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
pub fn deinit(req: *Request) void {
    req.headers.list.allocator.free(req.path);
    req.headers.deinit();
}

test "HTTP/0.9" {
    var b = try mem.dupe(alloc, u8, "GET / HTTP/0.9\r\n");
    defer alloc.free(b);
    var req = Request{
        .method = undefined,
        .headers = Headers.init(alloc),
        .path = undefined,
        .query = undefined,
        .body = undefined,
        .version = .Http11,
    };
    defer deinit(&req);
    // try req.parse(&sess);
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
    var req = Request{
        .method = undefined,
        .headers = Headers.init(alloc),
        .path = undefined,
        .query = undefined,
        .body = undefined,
        .version = .Http11,
    };
    // try req.parse(&sess);
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
    var req = Request{
        .method = undefined,
        .headers = Headers.init(alloc),
        .path = undefined,
        .query = undefined,
        .body = undefined,
        .version = .Http11,
    };
    defer deinit(&req);
    // std.testing.expectError(error.UnsupportedVersion, req.parse(&sess));
}
