const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const builtin = @import("builtin");

const http = @import("http.zig");

pub const Router = struct {
    routes: [100]Route,
    count: u32,
    error_handler: ?ErrorHandler,

    const ErrorHandler = fn(anyerror, http.Request) http.Response;

    fn defaultErrorHandler(err: anyerror, req: http.Request) http.Response {
        return http.Response{
            .code = 502,
        };
    }

    const Route = struct {
        path: []const u8,
        method: Method,
        handler: *const void,
        handler_type: builtin.TypeInfo,
    };

    pub fn init() Router {
        return Router {
            .routes = undefined,
            .count = 0,
            .error_handler = defaultErrorHandler,
        };
    }

    const Method = enum {
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

    pub fn all(comptime r: *Router, path: []const u8, handler: var) void {
        r.addRoute(.All, path, handler);
    }

    pub fn get(comptime r: *Router, comptime path: []const u8, handler: var) void {
        r.addRoute(.Get, path, handler);
    }

    pub fn head(comptime r: *Router, path: []const u8, handler: var) void {
        r.addRoute(.Head, path, handler);
    }

    pub fn post(comptime r: *Router, path: []const u8, handler: var) void {
        r.addRoute(.Post, path, handler);
    }

    pub fn put(comptime r: *Router, path: []const u8, handler: var) void {
        r.addRoute(.Put, path, handler);
    }

    pub fn delete(comptime r: *Router, path: []const u8, handler: var) void {
        r.addRoute(.Delete, path, handler);
    }

    pub fn connect(comptime r: *Router, path: []const u8, handler: var) void {
        r.addRoute(.Connect, path, handler);
    }

    pub fn options(comptime r: *Router, path: []const u8, handler: var) void {
        r.addRoute(.Options, path, handler);
    }

    pub fn trace(comptime r: *Router, path: []const u8, handler: var) void {
        r.addRoute(.Trace, path, handler);
    }

    pub fn patch(comptime r: *Router, path: []const u8, handler: var) void {
        r.addRoute(.Patch, path, handler);
    }

    /// add route with given method
    fn addRoute(comptime r: *Router, comptime method: Method, comptime path: []const u8, handler: var) void {
        if (r.count >= 100) {
            @compileError("too many routes, TODO better comptime");
        }
        comptime {
            const t = @typeInfo(@typeOf(handler));
            if (t != builtin.TypeId.Fn) {
                @compileError("handler must be a function");
            }
            const f = t.Fn;

            if (f.return_type) |ret| {
                if (ret != http.Response and (@typeInfo(ret) != builtin.TypeId.ErrorUnion or @typeInfo(ret).ErrorUnion.payload != http.Response)) {
                    @compileError("handler must return a http response");
                }
            } else {
                @compileError("handler must return a value");
            }
            r.routes[r.count] = Route {
                .path = path,
                .method = method,
                .handler = @ptrCast(*const void, handler),
                .handler_type = t,
            };
            r.count += 1;
        }
    }

};

fn index(req: http.Request) http.Response {
    return http.Response {
        .code = 200,
    };
}

test "wut" {
    comptime  var r = Router.init();
    r.get("/", index);
}