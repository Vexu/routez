const std = @import("std");
const Allocator = std.mem.Allocator;
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;
const meta = std.meta;
usingnamespace @import("http.zig");

pub const HandlerFn = fn handle(Request, Response, []const u8) callconv(.Async) anyerror!void;

pub const ErrorHandler = struct {
    handler: fn (Request, Response) void,
    err: anyerror,
};

pub fn Router(comptime handlers: anytype) HandlerFn {
    comptime var routes: []const Route = &[_]Route{};
    comptime var err_handlers: []const ErrorHandler = &[_]ErrorHandler{};
    inline for (handlers) |handler| {
        switch (@TypeOf(handler)) {
            ErrorHandler => {
                err_handlers = (err_handlers ++ &[_]ErrorHandler{handler});
            },
            Route => {
                routes = (routes ++ &[_]Route{handler});
            },
            else => |f_type| @compileError("unsupported handler type " ++ @typeName(f_type)),
        }
    }
    if (routes.len == 0) {
        @compileError("Router must have at least one route");
    }
    return struct {
        fn handle(req: Request, res: Response, path: []const u8) callconv(.Async) !void {
            if (req.path[0] == '*') {
                @panic("Todo server request");
            }
            inline for (routes) |route| {
                comptime var type_info = @typeInfo(@TypeOf(route.handler)).Fn;
                comptime var err: ?type = switch (@typeInfo(type_info.return_type.?)) {
                    .ErrorUnion => @typeInfo(type_info.return_type.?).ErrorUnion.error_set,
                    else => null,
                };

                // try matching path to route
                if (err == null) {
                    if (match(route, err, req, res, path)) {
                        if (res.status_code == null)
                            res.status_code = .Ok;
                        return;
                    }
                } else {
                    if (match(route, err, req, res, path) catch |e| {
                        if (err_handlers.len == 0) {
                            return e;
                        } else {
                            return handleError(e, req, res);
                        }
                    }) {
                        if (res.status_code == null)
                            res.status_code = .Ok;
                        return;
                    }
                }
            }
            // not found
            return if (err_handlers.len == 0) error.FileNotFound else handleError(error.FileNotFound, req, res);
        }

        fn handleError(err: anyerror, req: Request, res: Response) !void {
            inline for (err_handlers) |e| {
                if (err == e.err) {
                    return e.handler(req, res);
                }
            }
            return err;
        }
    }.handle;
}

pub const Route = struct {
    path: []const u8,
    method: ?[]const u8,
    handler: anytype,
};

/// returns true if request matched route
pub fn match(
    comptime route: Route,
    comptime Errs: ?type,
    req: Request,
    res: Response,
    path: []const u8,
) if (Errs != null) Errs.?!bool else bool { // TODO this can be improved
    const handler = route.handler;
    const has_args = @typeInfo(@TypeOf(handler)).Fn.args.len == 3;
    const Args = if (has_args) @typeInfo(@typeInfo(@TypeOf(handler)).Fn.args[2].arg_type.?).Pointer.child else void;

    var args: Args = undefined;

    comptime var used: if (has_args) [@typeInfo(Args).Struct.fields.len]bool else void = undefined;

    if (has_args) {
        comptime mem.set(bool, &used, false);
    }

    const State = enum {
        Start,
        Path,
        AmperStart,
        AmperFirst,
        Format,
    };

    comptime var state = State.Start;
    comptime var index = 0;
    comptime var begin = 0;
    comptime var fmt_begin = 0;
    // worst-case scenario every byte in route needs to be percentage encoded
    comptime var pathbuf: [route.path.len * 3]u8 = undefined;
    comptime var optional = false;
    var path_index: usize = 0;
    var len: usize = undefined;

    inline for (route.path) |c, i| {
        switch (state) {
            .Start => comptime switch (c) {
                '/' => {
                    pathbuf[index] = '/';
                    state = .Path;
                    index += 1;
                },
                '*' => {
                    state = .Path;
                    break;
                },
                else => @compileError("route must begin with a '/'"),
            },
            .Path => switch (c) {
                '?' => {
                    if (!optional) {
                        @compileError("previous character is not optional");
                    } else {
                        optional = false;
                        index -= 1;
                        const r = pathbuf[begin..index];
                        begin = index;
                        if (path.len < r.len or !mem.eql(u8, r, path[path_index .. path_index + r.len])) {
                            return false;
                        }
                        path_index += r.len;
                        if (path.len > path_index and path[path_index] == pathbuf[begin]) {
                            path_index += 1;
                        }
                    }
                },
                'a'...'z', 'A'...'Z', '0'...'9', '-', '.', '_', '~', '!', '$', '&', '\'', '(', ')', '*', '+', ',', ';', '=', ':', '@', '%', '/' => comptime {
                    pathbuf[index] = c;
                    index += 1;
                    if (c == '%') {
                        state = .AmperStart;
                    }
                    optional = true;
                },
                '{' => {
                    if (!has_args) {
                        @compileError("handler does not take path arguments");
                    }
                    optional = false;
                    state = .Format;
                    fmt_begin = i + 1;
                    const r = pathbuf[begin..index];
                    begin = index;
                    if (path.len < r.len or !mem.eql(u8, r, path[path_index .. path_index + r.len])) {
                        return false;
                    }
                    path_index += r.len;
                },
                else => comptime {
                    const hex_digits = "0123456789ABCDEF";
                    pathbuf[index] = '%';
                    pathbuf[index + 1] = hex_digits[(c & 0xF0) >> 4];
                    pathbuf[index + 2] = hex_digits[c & 0x0F];
                    index += 3;
                    optional = true;
                },
            },
            .AmperStart, .AmperFirst => comptime switch (c) {
                '0'...'9', 'a'...'f', 'A'...'F' => {
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
                    comptime var radix = 10;
                    comptime var number = true;
                    comptime var field_name: []const u8 = undefined;
                    comptime var field_type: type = undefined;
                    comptime var delim: []const u8 = "/.";

                    comptime {
                        const Fstate = enum {
                            Name,
                            Radix,
                            Done,
                            Fmt,
                        };
                        var fstate = .Name;
                        var fmt = route.path[fmt_begin..i];
                        if (fmt.len == 0) {
                            @compileError("path argument's name must at least one character");
                        }
                        for (fmt) |fc, fi| {
                            switch (fstate) {
                                .Name => switch (fc) {
                                    ';' => {
                                        if (fi == 0) {
                                            @compileError("path argument's name must at least one character");
                                        }
                                        field_name = fmt[0..fi];

                                        canUse(Args, field_name, &used);
                                        field_type = @TypeOf(@field(args, field_name));
                                        verifyField(field_type, &number);

                                        if (number) {
                                            fstate = .Fmt;
                                        } else {
                                            delim = fmt[fi + 1 ..];
                                            fstate = .Done;
                                            break;
                                        }
                                    },
                                    else => {},
                                },
                                .Radix => switch (fc) {
                                    '0'...'9' => {
                                        radix *= 10;
                                        radix += fc - '0';
                                    },
                                    else => @compileError("radix must be a number"),
                                },
                                .Fmt => switch (fc) {
                                    'r', 'R' => {
                                        radix = 0;
                                        fstate = .Radix;
                                    },
                                    'x', 'X' => {
                                        radix = 16;
                                        fstate = .Done;
                                    },
                                    else => @compileError("invalid format character"),
                                },
                                .Done => @compileError("unexpected character after format '" ++ fmt[fi .. fi + 1] ++ "'"),
                                else => unreachable,
                            }
                        }
                        if (fstate == .Name) {
                            field_name = fmt[0..];

                            canUse(Args, field_name, &used);
                            field_type = @TypeOf(@field(args, field_name));
                            verifyField(field_type, &number);
                        }
                        if (radix < 2 or radix > 36) {
                            @compileError("radix must be in range [2,36]");
                        }
                    }
                    len = 0;

                    if (number) {
                        @field(args, field_name) = getNum(field_type, path[path_index..], radix, &len);
                    } else {
                        if (delim.len != 0) {
                            @field(args, field_name) = getString(path[path_index..], delim, &len);
                        } else {
                            @field(args, field_name) = path[path_index..];
                            len += path[path_index..].len;
                        }
                    }
                    // route is incorrect if the argument given is zero sized
                    if (len == 0) {
                        return false;
                    }
                    path_index += len;

                    state = .Path;
                },
                else => {},
            },
        }
    }
    if (state != .Path) {
        @compileError("Invalid route");
    }
    comptime if (has_args) {
        for (used) |u, i| {
            if (!u) {
                @compileError("handler argument '" ++ @typeInfo(Args).Struct.fields[i].name ++ "' is not given in the path");
            }
        }
    };
    const r = pathbuf[begin..index];
    if (route.path[0] != '*' and !mem.eql(u8, r, path[path_index..])) {
        return false;
    }
    if (route.method) |m| {
        if (!mem.eql(u8, req.method, m)) {
            res.status_code = .MethodNotAllowed;
            // routing was successful but method was not allowed
            return true; // todo return false and try to find a route with correct method
        }
    }

    if (has_args) {
        if (Errs != null) {
            try handler(req, res, &args);
        } else {
            handler(req, res, &args);
        }
    } else {
        if (Errs != null) {
            try handler(req, res);
        } else {
            handler(req, res);
        }
    }
    return true;
}

fn canUse(comptime Args: type, comptime field_name: []const u8, used: []bool) void {
    const index = meta.fieldIndex(Args, field_name) orelse {
        @compileError("handler does not take argument '" ++ field_name ++ "'");
    };
    if (used[index]) {
        @compileError("argument '" ++ field_name ++ "' already used");
    } else {
        used[index] = true;
    }
}

fn verifyField(comptime field: type, number: *bool) void {
    number.* = @typeInfo(field) == .Int;
    if (!number.*) {
        assert(@typeInfo(field) == .Pointer);
        const ptr = @typeInfo(field).Pointer;
        assert(ptr.is_const and ptr.size == .Slice and ptr.child == u8);
    }
}

fn getNum(comptime T: type, path: []const u8, radix: u8, len: *usize) T {
    const signed = @typeInfo(T).Int.signedness == .signed;
    var sign = if (signed) false;
    var res: T = 0;
    for (path) |c, i| {
        if (signed and c == '-' and i == 1) {
            sign = true;
        }
        const value = switch (c) {
            '0'...'9' => c - '0',
            'A'...'Z' => c - 'A' + 10,
            'a'...'z' => c - 'a' + 10,
            else => break,
        };

        if (value >= radix) break;

        if (res != 0) res = math.mul(T, res, @intCast(T, radix)) catch break;
        res = math.add(T, res, @intCast(T, value)) catch break;
        len.* += 1;
    }
    if (signed and sign) {
        res = -res;
    }
    return res;
}

fn getString(path: []const u8, delim: []const u8, len: *usize) []const u8 {
    for (path) |c, i| {
        var done = false;

        for (delim) |d| {
            done = done or c == d;
        }

        if (done) {
            len.* = i;
            return path[0..i];
        }
    }
    len.* = path.len;
    return path;
}
