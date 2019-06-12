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

// todo include error handlers and other middleware in routes
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
                        return match(@ptrCast(route.handler_type, route.handler), err, route.path, req, res, null) catch |e| {
                            if (err_handlers == null) {
                                return error.Notfound;
                            } else {
                                return handleError(e, req, res);
                            }
                        };
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
