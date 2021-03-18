const std = @import("std");
const Address = std.net.Address;
usingnamespace @import("routez");
const allocator = std.heap.page_allocator;

pub const io_mode = .evented;

pub fn main() !void {
    var server = Server.init(
        allocator,
        .{},
        .{
            all("/", indexHandler),
            get("/about", aboutHandler),
            get("/about/more", aboutHandler2),
            get("/post/{post_num}/?", postHandler),
            static("./", "/static"),
            all("/counter", counterHandler),
        },
    );
    var addr = try Address.parseIp("127.0.0.1", 8080);
    try server.listen(addr);
}

fn indexHandler(req: Request, res: Response) !void {
    try res.sendFile("examples/index.html");
}

fn aboutHandler(req: Request, res: Response) !void {
    try res.write("Hello from about\n");
}

fn aboutHandler2(req: Request, res: Response) !void {
    try res.write("Hello from about2\n");
}

fn postHandler(req: Request, res: Response, args: *const struct {
    post_num: []const u8,
}) !void {
    try res.print("Hello from post, post_num is {s}\n", .{args.post_num});
}

var counter = std.atomic.Int(usize).init(0);
fn counterHandler(req: Request, res: Response) !void {
    try res.print("Page loaded {d} times\n", .{counter.fetchAdd(1)});
}
