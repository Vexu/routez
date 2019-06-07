# routez
WIP

http server with router

## goals
offer functionality similar to express.js and the like

## example
```Zig
const std = @import("std");
const warn = std.debug.warn;
const assert = std.debug.assert;
use @import("routez");
use Http;

pub fn main() !void {
    const router = comptime build(&[]Route{
        Route.all("/", index),
        Route.get("/about", about),
        Route.get("/post/{post_num}/", post),
    }, defaultErrorHandler);

    var req = request{ .code = 2, .method = .Get, .path = "/post/12345/" };
    var res = try std.debug.global_allocator.create(response);
    res.* = response{ .status_code = 500 };

    // start currently takes req and res for testing purposes
    router.start(Settings{
        .port = 8080,
    }, &req, res);
    assert(res.status_code == 200);
}

fn index(req: Request, res: Response) void {
    res.status_code = 200;
    warn("Hello from index\n");
    return;
}

fn about(req: Request, res: Response) void {
    res.status_code = 200;
    warn("Hello from about\n");
    return;
}

fn post(req: Request, res: Response, args: *const struct {
    post_num: []const u8,
}) void {
    res.status_code = 200;
    warn("Hello from post, post_num is {}\n", args.post_num);
    return;
}

```