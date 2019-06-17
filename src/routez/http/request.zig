const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const assert = std.debug.assert;
const Stream = std.event.net.InStream.Stream;
use @import("headers.zig");
use @import("common.zig");
use @import("zuri");

pub const Request = struct {
    buf: []u8,
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

    //todo use instream?
    pub async fn parse(allocator: *Allocator, stream: *Stream) Error!Request {
        var req = Request{
            .buf = undefined,
            .method = undefined,
            .headers = Headers.init(allocator),
            .path = undefined,
            .query = "",
            .body = "",
            .version = .Http11,
        };

        const State = enum {
            Method,
            Path,
            AfterPath,
            Version,
            Cr,
            Lf,
            Headers,
            Body,
        };

        // initial buffer size is 512 bytes wich should fit most bodyless requests
        var buffer = try allocator.alloc(u8, 512);
        errdefer allocator.free(buffer);
        var count: usize = 0;

        var state = State.Method;
        var i: usize = 0;
        var begin: usize = 0;

        var header_handle: ?promise = null;
        var headers_done = false;

        while (true) : (i += 1) {
            if (i >= count) {
                if (count != 0 and count < buffer.len) {
                    // message has been read in its entirety
                    if (state != .Body and state != .Headers and !headers_done) {
                        // message did not end properly
                        return Error.TooShort; // todo this is incorrectly being returned
                    }
                    req.buf = allocator.realloc(buffer, i) catch buffer[0..i];
                    req.body = buffer[begin..i];
                    return req;
                } else if (count == buffer.len) {
                    buffer = try allocator.realloc(buffer, buffer.len * 4);
                }
                count += await (try async stream.read(buffer[count..])) catch {
                    // todo probably incorrect way to handle this
                    return Error.OutOfMemory;
                };
            }
            if (state == .Body) {
                i = count - 1;
                continue;
            }

            switch (state) {
                .Method => {
                    // todo should probably validate given chars
                    if (buffer[i] == ' ') { // Conditional jump or move depends on uninitialised value(s), possible problem
                        if (i == 0) {
                            return Error.InvalidMethod;
                        }
                        req.method = buffer[0..i];
                        begin = i + 1;
                        state = .Path;
                    }
                },
                .Path => {
                    if (buffer[i] == ' ') {
                        const uri = try Uri.parse(buffer[begin..i], true);
                        req.path = uri.path;
                        req.query = uri.query;
                        state = .Version;
                        begin = i + 1;
                    } else if (buffer[begin] == '*') {
                        req.path = buffer[begin .. begin + 1];
                        state = .AfterPath;
                    }
                },
                .AfterPath => {
                    if (buffer[i] != ' ') {
                        return Error.InvalidChar;
                    }
                    state = .Version;
                    begin = i + 1;
                },
                .Version => {
                    // 8 for HTTP/X.X
                    if (i - begin < 7) {
                        continue;
                    }
                    if (!mem.eql(u8, buffer[begin .. begin + 5], "HTTP/") or buffer[begin + 6] != '.') {
                        return Error.InvalidVersion;
                    }
                    switch (buffer[begin + 5]) {
                        '0' => req.version = .Http09,
                        '1' => req.version = .Http10,
                        '2' => req.version = .Http20,
                        '3' => req.version = .Http30,
                        else => return Error.InvalidVersion,
                    }
                    switch (buffer[begin + 7]) {
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
                    if (buffer[i] != '\r') {
                        return Error.Invalid;
                    }
                    state = .Lf;
                },
                .Lf => {
                    if (buffer[i] != '\n') {
                        return Error.Invalid;
                    }
                    state = .Headers;
                },
                .Headers => {
                    // this is probably correct?
                    if (headers_done) {
                        cancel header_handle.?;

                        if (buffer[i] == '\n') {
                            begin = i + 1;
                            state = .Body;
                        } else {
                            return Error.Invalid;
                        }
                    }
                    if (header_handle) |h| {
                        resume h;
                    } else {
                        errdefer req.headers.deinit();
                        header_handle = try async req.headers.parse(buffer, &i, &count, &headers_done);
                        errdefer cancel header_handle;
                    }
                },
                else => unreachable,
            }
        }
    }

    pub fn deinit(req: Request) void {
        req.headers.list.allocator.free(req.buf);
        req.headers.deinit();
    }
};

pub const TestStream = struct {
    buf: []const u8,
    stream: S,

    pub const Error = std.event.net.ReadError;
    pub const S = std.event.io.InStream(Error);

    pub fn init(buf: []const u8) TestStream {
        return TestStream{
            .buf = buf,
            .stream = S{ .readFn = readFn },
        };
    }

    async<*mem.Allocator> fn readFn(in_stream: *S, bytes: []u8) Error!usize {
        const buf = @fieldParentPtr(TestStream, "stream", in_stream).buf;
        mem.copy(u8, bytes, buf);
        return buf.len;
    }
};

test "HTTP/0.9" {
    var h = try async<std.debug.global_allocator> http09();
    resume h;
    cancel h;
}

async fn http09() !void {
    suspend;
    var stream = TestStream.init("GET / HTTP/0.9\r\n");
    const req = try await (try async Request.parse(std.debug.global_allocator, &stream.stream));
    defer req.deinit();
    assert(mem.eql(u8, req.method, Method.Get));
    assert(mem.eql(u8, req.path, "/"));
    assert(req.version == .Http09);
}

test "HTTP/1.1" {
    var h = try async<std.debug.global_allocator> http11();
    resume h;
    cancel h;
}

async fn http11() !void {
    suspend;
    var a = std.debug.global_allocator;
    var stream = TestStream.init("POST /about HTTP/1.1\r\n" ++
        "expires: Mon, 08 Jul 2019 11:49:03 GMT\r\n" ++
        "last-modified: Fri, 09 Nov 2018 06:15:00 GMT\r\n" ++
        "X-Test: test\r\n" ++
        " obs-fold\r\n" ++
        "\r\na body\n");
    const req = try await (try async Request.parse(a, &stream.stream));
    defer req.deinit();
    assert(mem.eql(u8, req.method, Method.Post));
    assert(mem.eql(u8, req.path, "/about"));
    assert(req.version == .Http11);
    assert(mem.eql(u8, req.body, "a body\n"));
    assert(mem.eql(u8, (try req.headers.get(a, "expires")).?[0].value, "Mon, 08 Jul 2019 11:49:03 GMT"));
    assert(mem.eql(u8, (try req.headers.get(a, "last-modified")).?[0].value, "Fri, 09 Nov 2018 06:15:00 GMT"));
    const val = try req.headers.get(a, "x-test");
    assert(mem.eql(u8, (try req.headers.get(a, "x-test")).?[0].value, "test obs-fold"));
}

test "HTTP/3.0" {
    var h = try async<std.debug.global_allocator> http30();
    resume h;
    cancel h;
}

async fn http30() !void {
    suspend;
    var a = std.debug.global_allocator;
    var stream = TestStream.init("POST /about HTTP/3.0\r\n\r\n");
    _ = await (try async<a> Request.parse(a, &stream.stream)) catch |e| {
        assert(e == Request.Error.UnsupportedVersion);
        return;
    };
}
