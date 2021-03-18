const std = @import("std");
const expect = std.testing.expect;
usingnamespace @import("http.zig");
usingnamespace @import("router.zig");

pub fn all(path: []const u8, handler: anytype) Route {
    return createRoute(null, path, handler);
}

pub fn get(path: []const u8, handler: anytype) Route {
    return createRoute(Method.Get, path, handler);
}

pub fn head(path: []const u8, handler: anytype) Route {
    return createRoute(Method.Head, path, handler);
}

pub fn post(path: []const u8, handler: anytype) Route {
    return createRoute(Method.Post, path, handler);
}

pub fn put(path: []const u8, handler: anytype) Route {
    return createRoute(Method.Put, path, handler);
}

pub fn delete(path: []const u8, handler: anytype) Route {
    return createRoute(Method.Delete, path, handler);
}

pub fn connect(path: []const u8, handler: anytype) Route {
    return createRoute(Method.Connect, path, handler);
}

pub fn options(path: []const u8, handler: anytype) Route {
    return createRoute(Method.Options, path, handler);
}

pub fn trace(path: []const u8, handler: anytype) Route {
    return createRoute(Method.Trace, path, handler);
}

pub fn patch(path: []const u8, handler: anytype) Route {
    return createRoute(Method.Patch, path, handler);
}

pub fn custom(method: []const u8, path: []const u8, handler: anytype) Route {
    return createRoute(method, path, handler);
}

/// add route with given method
fn createRoute(method: ?[]const u8, path: []const u8, handler: anytype) Route {
    const t = @typeInfo(@TypeOf(handler));
    if (t != .Fn) {
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
        if (@typeInfo(arg_type) != .Pointer or blk: {
            const ptr = @typeInfo(arg_type).Pointer;
            break :blk !ptr.is_const or ptr.size != .One or @typeInfo(ptr.child) != .Struct;
        }) {
            @compileError("third argument of a handler must be a const pointer to a struct containing all path arguments it takes");
        }
    }

    const ret = f.return_type.?;
    if (ret != void and (@typeInfo(ret) != .ErrorUnion or @typeInfo(ret).ErrorUnion.payload != void)) {
        @compileError("handler must return void which may be in an error union");
    }

    return Route{
        .path = path,
        .method = method,
        .handler = handler,
    };
}

pub fn subRoute(route: []const u8, handlers: anytype) Route {
    const h = Router(handlers);
    const handler = struct {
        fn handle(req: Request, res: Response, args: *const struct {
            path: []const u8,
        }) !void {
            return h(req, res, args.path);
        }
    }.handle;

    const path = (if (route[route.len - 1] == '/') route[0 .. route.len - 2] else route) ++ "{path;}";
    return createRoute(Method.Get, path, handler);
}

// todo static cofig
// todo uri decode path
pub fn static(local_path: []const u8, remote_path: ?[]const u8) Route {
    const handler = struct {
        fn staticHandler(req: Request, res: Response, args: *const struct {
            path: []const u8,
        }) !void {
            const allocator = res.allocator;
            const path = if (local_path[local_path.len - 1] == '/') local_path else local_path ++ "/";
            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, args.path });

            try res.sendFile(full_path);
        }
    }.staticHandler;

    var path = if (remote_path) |r| if (r[r.len - 1] == '/') r ++ "{path;}" else r ++ "/{path;}" else "/{path;}";
    return createRoute(Method.Get, path, handler);
}

// for tests
const request = @import("http/request.zig").Request;
const response = @import("http/response.zig").Response;
const alloc = std.heap.page_allocator;

test "index" {
    const handler = comptime Router(.{get("/", indexHandler)});

    var req = request{
        .method = Method.Get,
        .headers = undefined,
        .path = "/",
        .query = undefined,
        .body = undefined,
        .version = .Http11,
    };
    var res: response = undefined;
    try nosuspend handler(&req, &res, req.path);
    expect(res.status_code.? == .Ok);
}

fn indexHandler(req: Request, res: Response) void {
    res.status_code = .Ok;
}

test "custom status code" {
    const handler = comptime Router(.{get("/", customStatusCode)});

    var req = request{
        .method = Method.Get,
        .headers = undefined,
        .path = "/",
        .query = undefined,
        .body = undefined,
        .version = .Http11,
    };
    var res: response = undefined;
    try nosuspend handler(&req, &res, req.path);
    expect(res.status_code.? == .BadRequest);
}

fn customStatusCode(req: Request, res: Response) void {
    res.status_code = .BadRequest;
}

test "args" {
    const handler = comptime Router(.{get("/a/{num}", argHandler)});

    var req = request{
        .method = Method.Get,
        .headers = undefined,
        .path = "/a/14",
        .query = undefined,
        .body = undefined,
        .version = .Http11,
    };
    var res: response = undefined;

    try nosuspend handler(&req, &res, req.path);
}

fn argHandler(req: Request, res: Response, args: *const struct {
    num: u32,
}) void {
    expect(args.num == 14);
}

test "delim string" {
    const handler = comptime Router(.{get("/{str;}", delimHandler)});

    var req = request{
        .method = Method.Get,
        .headers = undefined,
        .path = "/all/of/this.html",
        .query = undefined,
        .body = undefined,
        .version = .Http11,
    };
    var res: response = undefined;

    try nosuspend handler(&req, &res, req.path);
}

fn delimHandler(req: Request, res: Response, args: *const struct {
    str: []const u8,
}) void {
    expect(std.mem.eql(u8, args.str, "all/of/this.html"));
}

test "subRoute" {
    const handler = comptime Router(.{subRoute("/sub", .{get("/other", indexHandler)})});

    var req = request{
        .method = Method.Get,
        .path = "/sub/other",
        .query = undefined,
        .body = undefined,
        .version = .Http11,
        .headers = undefined,
    };
    var res: response = undefined;

    try nosuspend handler(&req, &res, req.path);
    expect(res.status_code.? == .Ok);
}

test "static files" {
    const handler = comptime Router(.{static(
        "assets",
        "/static",
    )});

    var req = request{
        .method = Method.Get,
        .path = "/static/example-file.txt",
        .query = undefined,
        .body = undefined,
        .version = .Http11,
        .headers = undefined,
    };
    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();
    var res = response{
        .status_code = .Processing,
        .headers = Headers.init(alloc),
        .body = .{ .context = &buf },
        .allocator = alloc,
    };

    // ignore file not found error
    nosuspend handler(&req, &res, req.path) catch |e| switch (e) {
        error.FileNotFound => return,
        else => return e,
    };
    expect(std.mem.eql(u8, (try res.headers.get(alloc, "content-type")).?[0].value, "text/plain;charset=UTF-8"));
    expect(std.mem.eql(u8, res.body.context.items, "Some text\n"));
}

test "optional char" {
    const handler = comptime Router(.{get("/about/?", indexHandler)});

    var req = request{
        .method = Method.Get,
        .headers = undefined,
        .path = "/about",
        .query = undefined,
        .body = undefined,
        .version = .Http11,
    };
    var res: response = undefined;
    try nosuspend handler(&req, &res, req.path);
    expect(res.status_code.? == .Ok);
}
