const std = @import("std");
const Address = std.net.Address;
const r = @import("routez");
const allocator = std.heap.page_allocator;

pub const io_mode = .evented;

pub fn main() !void {
    var server = r.Server.init(
        allocator,
        .{},
        .{
            r.all("/", indexHandler),
            r.get("/about", aboutHandler),
            r.get("/about/more", aboutHandler2),
            r.get("/post/{post_num}/?", postHandler),
            r.static("./", "/static"),
            r.all("/counter", counterHandler),
        },
    );
    var addr = try Address.parseIp("127.0.0.1", 8080);
    try server.listen(addr);
}

fn indexHandler(_: r.Request, res: r.Response) !void {
    try res.sendFile("examples/index.html");
}

fn aboutHandler(_: r.Request, res: r.Response) !void {
    try res.write("Hello from about\n");
}

fn aboutHandler2(_: r.Request, res: r.Response) !void {
    try res.write("Hello from about2\n");
}

fn postHandler(_: r.Request, res: r.Response, args: *const struct {
    post_num: []const u8,
}) !void {
    try res.print("Hello from post, post_num is {s}\n", .{args.post_num});
}

var counter = std.atomic.Atomic(usize).init(0);
fn counterHandler(_: r.Request, res: r.Response) !void {
    try res.print("Page loaded {d} times\n", .{counter.fetchAdd(1, .SeqCst)});
}
