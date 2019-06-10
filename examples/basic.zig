const std = @import("std");
use @import("routez");

pub fn main() !void {
    var server = try Server.init(
        std.debug.global_allocator,
        Server.Properties{ .multithreaded = true },
        &[]Route{
            all("/", indexHandler),
            get("/about", aboutHandler),
            get("/about/more", aboutHandler2),
            get("/post/{post_num}/?", postHandler),
            static(std.debug.global_allocator, "/public/static", "/static"),
        },
        null,
    );

    try server.listen(&Address.initIp4(try std.net.parseIp4("127.0.0.1"), 8080));
}

fn indexHandler(req: Request, res: Response) void {
    res.status_code = .Ok;
    res.body.write("Hello from index\n");
}

fn aboutHandler(req: Request, res: Response) void {
    res.status_code = .Ok;
    res.body.write("Hello from about\n");
}

fn aboutHandler2(req: Request, res: Response) void {
    res.status_code = .Ok;
    res.body.write("Hello from about2\n");
}

fn postHandler(req: Request, res: Response, args: *const struct {
    post_num: []const u8,
}) void {
    res.status_code = .Ok;
    res.body.print("Hello from post, post_num is {}\n", args.post_num);
}
