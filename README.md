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

pub fn main() !void {
    const router = comptime Router(&[]Route{
        all("/", indexHandler),
        get("/about", aboutHandler),
        get("/about/more", aboutHandler2),
        get("/post/{post_num}", postHandler),
        get("/post/{post_num}/", postHandler),
    }, defaultErrorHandler);

    var req = request{ .code = 2, .method = .Get, .path = "/post/1234" };
    var res = try std.debug.global_allocator.create(response);
    res.* = response{ .status_code = .InternalServerError };

    // start currently takes req and res for testing purposes
    router.start(Settings{
        .port = 8080,
    }, &req, res);
    assert(res.status_code == .Ok);
}

fn indexHandler(req: Request, res: Response) void {
    res.status_code = .Ok;
    warn("Hello from index\n");
}

fn aboutHandler(req: Request, res: Response) void {
    res.status_code = .Ok;
    warn("Hello from about\n");
}

fn aboutHandler2(req: Request, res: Response) void {
    res.status_code = .Ok;
    warn("Hello from about2\n");
}

fn postHandler(req: Request, res: Response, args: *const struct {
    post_num: []const u8,
}) void {
    res.status_code = .Ok;
    warn("Hello from post, post_num is {}\n", args.post_num);
}

```