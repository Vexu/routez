const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const assert = std.debug.assert;
use @import("headers.zig");
use @import("version.zig");
use @import("zuri");

pub const Request = struct {
    method: Method,
    headers: Headers,
    path: []const u8,
    body: []const u8,
    version: Version,

    pub const Error = error{
        InvalidMethod,
        TooShort,
        InvalidPath,
        InvalidVersion,
        UnsupportedVersion,
    } || Uri.Error || Headers.Error;

    //todo use instream?
    pub fn parse(allocator: *Allocator, buffer: []const u8) Error!Request {
        if (buffer.len < 15) {
            return Error.TooShort;
        }
        var req = Request{
            .method = undefined,
            .headers = Headers.init(allocator),
            .path = undefined,
            .body = "",
            .version = undefined,
        };
        var index: usize = 0;

        switch (buffer[0]) {
            'G' => {
                index += 3;
                if (!mem.eql(u8, buffer[0..index], "GET")) {
                    return Error.InvalidMethod;
                }
                req.method = .Get;
            },
            'H' => {
                index += 4;
                if (!mem.eql(u8, buffer[0..index], "HEAD")) {
                    return Error.InvalidMethod;
                }
                req.method = .Head;
            },
            'P' => {
                switch (buffer[1]) {
                    'A' => {
                        index += 5;
                        if (!mem.eql(u8, buffer[0..index], "PATCH")) {
                            return Error.InvalidMethod;
                        }
                        req.method = .Patch;
                    },
                    'O' => {
                        index += 4;
                        if (!mem.eql(u8, buffer[0..index], "POST")) {
                            return Error.InvalidMethod;
                        }
                        req.method = .Post;
                    },
                    'U' => {
                        index += 3;
                        if (!mem.eql(u8, buffer[0..index], "PUT")) {
                            return Error.InvalidMethod;
                        }
                        req.method = .Put;
                    },
                    else => return Error.InvalidMethod,
                }
            },
            'D' => {
                index += 6;
                if (!mem.eql(u8, buffer[0..index], "DELETE")) {
                    return Error.InvalidMethod;
                }
                req.method = .Delete;
            },
            'C' => {
                index += 7;
                if (!mem.eql(u8, buffer[0..index], "CONNECT")) {
                    return Error.InvalidMethod;
                }
                req.method = .Connect;
            },
            'O' => {
                index += 7;
                if (!mem.eql(u8, buffer[0..index], "OPTIONS")) {
                    return Error.InvalidMethod;
                }
                req.method = .Options;
            },
            'T' => {
                index += 5;
                if (!mem.eql(u8, buffer[0..index], "TRACE")) {
                    return Error.InvalidMethod;
                }
                req.method = .Trace;
            },
            else => return Error.InvalidMethod,
        }
        if (buffer[index] != ' ') {
            return Error.InvalidChar;
        }
        index += 1;

        const uri = try Uri.parse(buffer[index..]);
        if (uri.path[0] != '/') {
            return Error.InvalidPath;
        }
        req.path = uri.path;
        index += uri.len;

        if (buffer[index..].len < 11) {
            return Error.TooShort;
        }

        if (buffer[index] != ' ') {
            return Error.InvalidChar;
        }
        index += 1;

        if (!mem.eql(u8, buffer[index .. index + 5], "HTTP/")) {
            return Error.InvalidChar;
        }
        index += 5;

        switch (buffer[index]) {
            '0' => {
                if (buffer[index + 2] == '9') {
                    req.version = .Http09;
                } else {
                    return Error.InvalidVersion;
                }
            },
            '1' => {
                if (buffer[index + 2] == '0') {
                    req.version = .Http10;
                } else if (buffer[index + 2] == '1') {
                    req.version = .Http11;
                } else {
                    return Error.InvalidVersion;
                }
            },
            '2' => {
                if (buffer[index + 2] == '0') {
                    req.version = .Http20;
                } else {
                    return Error.InvalidVersion;
                }
            },
            '3' => return Error.UnsupportedVersion,
            else => return Error.InvalidVersion,
        }
        index += 3;

        if (buffer[index] != '\r' or buffer[index + 1] != '\n') {
            return Error.InvalidChar;
        }

        index += 2;

        if (req.version != .Http09) {
            if (buffer[index..].len < 2) {
                return Error.TooShort;
            }
        } else if (buffer[index..].len == 0) {
            return req;
        }

        index += try Headers.parse(&req.headers, buffer[index..]);

        if (buffer[index] != '\r' or buffer[index + 1] != '\n') {
            return Error.InvalidChar;
        }
        index += 2;

        req.body = buffer[index..];

        return req;
    }
};

pub const Method = enum {
    All,
    Get,
    Head,
    Post,
    Put,
    Delete,
    Connect,
    Options,
    Trace,
    Patch,
};

test "HTTP/0.9" {
    const req = try Request.parse(std.debug.global_allocator, "GET / HTTP/0.9\r\n");
    assert(req.method == .Get);
    assert(mem.eql(u8, req.path, "/"));
    assert(req.version == .Http09);
}

test "HTTP/1.1" {
    const req = try Request.parse(std.debug.global_allocator, "POST /about HTTP/1.1\r\n" ++
        "expires: Mon, 08 Jul 2019 11:49:03 GMT\r\n" ++
        "last-modified: Fri, 09 Nov 2018 06:15:00 GMT\r\n" ++
        "\r\na body\n");
    assert(req.method == .Post);
    assert(mem.eql(u8, req.path, "/about"));
    assert(req.version == .Http11);
    assert(mem.eql(u8, req.body, "a body\n"));
    assert(mem.eql(u8, req.headers.map.get("expires").?.value, "Mon, 08 Jul 2019 11:49:03 GMT"));
    assert(mem.eql(u8, req.headers.map.get("last-modified").?.value, "Fri, 09 Nov 2018 06:15:00 GMT"));
}

test "HTTP/3.0" {
    _ = Request.parse(std.debug.global_allocator, "POST /about HTTP/3.0\r\n\r\n") catch |e| {
        assert(e == Request.Error.UnsupportedVersion);
        return;
    };
}
