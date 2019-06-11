const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const TypeInfo = builtin.TypeInfo;
const TypeId = builtin.TypeId;
use @import("route/parse.zig");
use @import("http.zig");

pub const HandlerFn = fn handle(Request, Response) anyerror!void;

pub const ErrorHandler = struct {
    handler: fn (Request, Response) void,
    err: anyerror,
};

// todo include error handlers and other mixins in routes
pub fn Router(comptime routes: []Route, comptime err_handlers: ?[]ErrorHandler) HandlerFn {
    if (routes.len == 0) {
        @compileError("Router must have at least one route");
    }
    return struct {
        fn handle(req: Request, res: Response) !void {
            inline for (routes) |route| {
                comptime var type_info = @typeInfo(route.handler_type).Fn;
                comptime var err: ?type = switch (@typeId(type_info.return_type.?)) {
                    TypeId.ErrorUnion => @typeInfo(type_info.return_type.?).ErrorUnion.error_set,
                    else => null,
                };
                var method = route.method;

                // try matching if method is correct or handler accepts all
                if (method == null or req.method == method.?) {
                    if (err == null) {
                        return match(@ptrCast(route.handler_type, route.handler), err, route.path, req, res, null);
                    } else {
                        return match(@ptrCast(route.handler_type, route.handler), err, route.path, req, res, null) catch |e| if (err_handlers == null) error.HandleFailed else return handleError(e, req, res);
                    }
                }
            }
            // not found
            return if (err_handlers == null) error.HandleFailed else return handleError(error.Notfound, req, res);
        }

        fn handleError(err: anyerror, req: Request, res: Response) error{HandleFailed}!void {
            inline for (err_handlers) |e| {
                if (err == e.err) {
                    return e.handler(req, res);
                }
            }
            return error.HandleFailed;
        }
    }.handle;
}

pub const Route = struct {
    path: []const u8,
    method: ?Method,
    handler: fn () void,
    handler_type: type,
};

pub fn all(path: []const u8, handler: var) Route {
    return createRoute(null, path, handler);
}

pub fn get(path: []const u8, handler: var) Route {
    return createRoute(Method.Get, path, handler);
}

pub fn head(path: []const u8, handler: var) Route {
    return createRoute(Method.Head, path, handler);
}

pub fn post(path: []const u8, handler: var) Route {
    return createRoute(Method.Post, path, handler);
}

pub fn put(path: []const u8, handler: var) Route {
    return createRoute(Method.Put, path, handler);
}

pub fn delete(path: []const u8, handler: var) Route {
    return createRoute(Method.Delete, path, handler);
}

pub fn connect(path: []const u8, handler: var) Route {
    return createRoute(Method.Connect, path, handler);
}

pub fn options(path: []const u8, handler: var) Route {
    return createRoute(Method.Options, path, handler);
}

pub fn trace(path: []const u8, handler: var) Route {
    return createRoute(Method.Trace, path, handler);
}

pub fn patch(path: []const u8, handler: var) Route {
    return createRoute(Method.Patch, path, handler);
}

/// add route with given method
fn createRoute(method: ?Method, path: []const u8, handler: var) Route {
    const t = @typeInfo(@typeOf(handler));
    if (t != builtin.TypeId.Fn) {
        @compileError("handler must be a function");
    }
    const f = t.Fn;
    if (f.args.len != 2 and f.args.len != 3) {
        @compileError("handler must take 2 or 3 arguments");
    }

    if (f.args[0].arg_type orelse void != Request) {
        @compileError("first argument of a handler must be a HTTP Request");
    }

    if (f.args[1].arg_type orelse void != Response) {
        @compileError("second argument of a handler must be a HTTP Response");
    }

    if (f.args.len == 3) {
        const arg_type = f.args[2].arg_type orelse void;
        if (@typeId(arg_type) != TypeId.Pointer or blk: {
            const ptr = @typeInfo(arg_type).Pointer;
            break :blk !ptr.is_const or ptr.size != .One or @typeId(ptr.child) != TypeId.Struct;
        }) {
            @compileError("third argument of a handler must be a const pointer to a struct containing all path arguments it takes");
        }
    }

    const ret = f.return_type orelse undefined;
    if (ret != void and (@typeInfo(ret) != builtin.TypeId.ErrorUnion or @typeInfo(ret).ErrorUnion.payload != void)) {
        @compileError("handler must return void which may be in an error union");
    }

    return Route{
        .path = path,
        .method = method,
        .handler = @ptrCast(fn () void, handler),
        .handler_type = @typeOf(handler),
    };
}

pub fn subRoute(allocator: *std.mem.Allocator, route: []const u8, comptime routes: []Route, comptime err_handlers: ?[]ErrorHandler) Route {
    if (routes.len == 0) {
        @compileError("Router must have at least one route");
    }
    const handler = struct {
        fn handle(req: Request, res: Response, args: *const struct {
            path: []const u8,
        }) !void {
            inline for (routes) |r| {
                comptime var type_info = @typeInfo(r.handler_type).Fn;
                comptime var err: ?type = switch (@typeId(type_info.return_type.?)) {
                    TypeId.ErrorUnion => @typeInfo(type_info.return_type.?).ErrorUnion.error_set,
                    else => null,
                };
                var method = r.method;

                // try matching if method is correct or handler accepts all
                if (method == null or req.method == method.?) {
                    if (err == null) {
                        return match(@ptrCast(r.handler_type, r.handler), err, r.path, req, res, args.path);
                    } else {
                        return match(@ptrCast(r.handler_type, r.handler), err, route.path, req, res, args.path) catch |e| if (err_handlers == null) error.HandleFailed else return handleError(e, req, res);
                    }
                }
            }
            // not found
            return if (err_handlers == null) error.HandleFailed else return handleError(error.Notfound, req, res);
        }

        fn handleError(err: anyerror, req: Request, res: Response) error{HandleFailed}!void {
            inline for (err_handlers) |e| {
                if (err == e.err) {
                    return e.handler(req, res);
                }
            }
            return error.HandleFailed;
        }
    }.handle;

    const path = if (route[route.len - 1] == '/') route[0 .. route.len - 2] ++ "{path;}" else route ++ "{path;}";
    return createRoute(Method.Get, path, handler);
}

pub fn static(allocator: *std.mem.Allocator, local_path: []const u8, remote_path: ?[]const u8) Route {
    const handler = struct {
        fn staticHandler(req: Request, res: Response, args: *const struct {
            path: []const u8,
        }) !void {
            const path = if (local_path[local_path.len - 1] == '/') local_path else local_path ++ "/";
            const full_path = try std.os.path.join(allocator, [][]const u8{ path, args.path });
            defer allocator.free(full_path);

            try res.sendFile(full_path);
            res.status_code = .Ok;
        }
    }.staticHandler;

    var path = if (remote_path) |r| if (r[r.len - 1] == '/') r ++ "{path;}" else r ++ "/{path;}" else "/{path;}";
    return createRoute(Method.Get, path, handler);
}

// for tests
const request = @import("http/request.zig").Request;
const response = @import("http/response.zig").Response;

test "index" {
    const handler = comptime Router(&[]Route{get("/", indexHandler)}, null);

    var req = request{
        .method = .Get,
        .headers = undefined,
        .path = "/",
        .query = undefined,
        .body = undefined,
        .version = .Http11,
    };
    var res = try std.debug.global_allocator.create(response);
    res.* = response{
        .status_code = .InternalServerError,
        .headers = undefined,
        .body = undefined,
    };
    try handler(&req, res);
    assert(res.status_code == .Ok);
}

fn indexHandler(req: Request, res: Response) void {
    res.status_code = .Ok;
}

test "args" {
    const handler = comptime Router(&[]Route{get("/a/{num}", argHandler)}, null);

    var req = request{
        .method = .Get,
        .headers = undefined,
        .path = "/a/14",
        .query = undefined,
        .body = undefined,
        .version = .Http11,
    };
    var res = try std.debug.global_allocator.create(response);
    res.* = response{
        .status_code = .InternalServerError,
        .headers = undefined,
        .body = undefined,
    };

    try handler(&req, res);
}

fn argHandler(req: Request, res: Response, args: *const struct {
    num: u32,
}) void {
    assert(args.num == 14);
}

test "delim string" {
    const handler = comptime Router(&[]Route{get("/{str;}", delimHandler)}, null);

    var req = request{
        .method = .Get,
        .headers = undefined,
        .path = "/all/of/this.html",
        .query = undefined,
        .body = undefined,
        .version = .Http11,
    };
    var res = try std.debug.global_allocator.create(response);
    res.* = response{
        .status_code = .Processing,
        .headers = undefined,
        .body = undefined,
    };

    try handler(&req, res);
}

fn delimHandler(req: Request, res: Response, args: *const struct {
    str: []const u8,
}) void {
    assert(std.mem.eql(u8, args.str, "all/of/this.html"));
}

test "subRoute" {
    const handler = comptime Router(&[]Route{subRoute(std.debug.global_allocator, "/sub", &[]Route{get("/other", subRouteHandler)}, null)}, null);

    var req = request{
        .method = .Get,
        .path = "/sub/other",
        .query = undefined,
        .body = undefined,
        .version = .Http11,
        .headers = undefined,
    };
    var res = try std.debug.global_allocator.create(response);
    res.* = response{
        .status_code = .Processing,
        .headers = undefined,
        .body = undefined,
    };

    try handler(&req, res);
    assert(res.status_code == .Ok);
}

fn subRouteHandler(req: Request, res: Response) void {
    res.status_code = .Ok;
}

test "static files" {
    const handler = comptime Router(&[]Route{static(
        std.debug.global_allocator,
        "assets",
        "/static",
    )}, null);

    var req = request{
        .method = .Get,
        .path = "/static/example-file.txt",
        .query = undefined,
        .body = undefined,
        .version = .Http11,
        .headers = undefined,
    };
    var res = try std.debug.global_allocator.create(response);
    res.* = response{
        .status_code = .Processing,
        .headers = Headers.init(std.debug.global_allocator),
        .body = @import("http/response.zig").OutStream.init(std.debug.global_allocator),
    };

    try handler(&req, res);
    assert(std.mem.eql(u8, (try res.headers.get(std.debug.global_allocator, "content-type")).?[0].value, "text/plain;charset=UTF-8"));
    assert(std.mem.eql(u8, res.body.buf.toSlice(), "Some text\n"));
}
