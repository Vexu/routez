const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const TypeInfo = builtin.TypeInfo;
const TypeId = builtin.TypeId;
use @import("route/parse.zig");

use @import("http.zig");

pub const Settings = struct {
    port: u16,
};

pub const ErrorHandler = fn (anyerror, Request, Response) bool;

fn defaultErrorHandler(err: anyerror, req: Request, res: Response) bool {
    res.status_code = 500;
    return false;
}

// todo include error handlers and other mixins in routes
pub fn build(comptime routes: []Route, comptime error_handler: ErrorHandler) type {
    return struct {
        fn handle(req: Request, res: Response) void {
            inline for (routes) |route| {
                comptime var type_info = @typeInfo(route.handler_type).Fn;
                comptime var err = switch (@typeId(type_info.return_type.?)) {
                    TypeId.ErrorUnion => type_info.return_type.?.ErrorUnion.error_set,
                    else => null,
                };
                var method = route.method;

                // try matching if method is correct or handler accepts all
                if (method == .All or req.method == method) {
                    if (err == null) {
                        match(@ptrCast(route.handler_type, route.handler), err, route.path, req, res);
                    } else {
                        match(@ptrCast(route.handler_type, route.handler), err, route.path, req, res) catch |e| error_handler(req, res);
                    }
                }
            }
        }

        pub fn start(settings: Settings, req: Request, res: Response) void {
            handle(req, res);
        }
    };
}

const Route = struct {
    path: []const u8,
    method: Method,
    handler: fn () void,
    handler_type: type,

    pub fn all(path: []const u8, handler: var) Route {
        return addRoute(.All, path, handler);
    }

    pub fn get(path: []const u8, handler: var) Route {
        return addRoute(.Get, path, handler);
    }

    pub fn head(path: []const u8, handler: var) Route {
        return addRoute(.Head, path, handler);
    }

    pub fn post(path: []const u8, handler: var) Route {
        return addRoute(.Post, path, handler);
    }

    pub fn put(path: []const u8, handler: var) Route {
        return addRoute(.Put, path, handler);
    }

    pub fn delete(path: []const u8, handler: var) Route {
        return addRoute(.Delete, path, handler);
    }

    pub fn connect(path: []const u8, handler: var) Route {
        return addRoute(.Connect, path, handler);
    }

    pub fn options(path: []const u8, handler: var) Route {
        return addRoute(.Options, path, handler);
    }

    pub fn trace(path: []const u8, handler: var) Route {
        return addRoute(.Trace, path, handler);
    }

    pub fn patch(path: []const u8, handler: var) Route {
        return addRoute(.Patch, path, handler);
    }

    /// add route with given method
    fn addRoute(method: Method, path: []const u8, handler: var) Route {
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
};

test "index" {
    const router = comptime build(&[]Route{Route.get("/", index)}, defaultErrorHandler);

    var req = request{ .code = 2, .method = .Get, .path = "/" };
    var res = try std.debug.global_allocator.create(response);
    res.* = response{ .status_code = 500 };

    router.start(Settings{
        .port = 8080,
    }, &req, res);
    assert(res.status_code == 200);
}

fn index(req: Request, res: Response) void {
    res.status_code = 200;
    return;
}

test "args" {
    const router = comptime build(&[]Route{Route.get("/a/{num}", a)}, defaultErrorHandler);

    var req = request{ .code = 2, .method = .Get, .path = "/a/14" };
    var res = try std.debug.global_allocator.create(response);
    res.* = response{ .status_code = 500 };

    router.start(Settings{
        .port = 8080,
    }, &req, res);
    assert(res.status_code == 200);
}

fn a(req: Request, res: Response, args: *const struct {
    num: u32,
}) void {
    res.status_code = 200;
    assert(args.num == 14);
    return;
}
