const std = @import("std");
const mem = std.mem;
const hashString = std.hash_map.hashString;

const Mime = struct {
    extension: []const u8,
    mime: []const u8,
    hash: u32,

    fn init(extension: []const u8, mime: []const u8) Mime {
        return .{
            .extension = extension,
            .hash = hashString(extension),
            .mime = mime,
        };
    }
};

const mimes = [_]Mime{
    Mime.init("js", js),
    Mime.init("css", css),
    Mime.init("html", html),
    Mime.init("png", png),
    Mime.init("jpeg", jpeg),
    Mime.init("gif", gif),
    Mime.init("webp", webp),
    Mime.init("svg", svg),
    Mime.init("ico", icon),
    Mime.init("txt", text),
    Mime.init("wav", wav),
    Mime.init("ogg", ogg),
    Mime.init("webm", webm),
    Mime.init("zig", text),
};

pub const js = "application/javascript;charset=UTF-8";
pub const css = "text/css;charset=UTF-8";
pub const html = "text/html;charset=UTF-8";
pub const png = "image/png";
pub const jpeg = "image/jpeg";
pub const gif = "image/gif";
pub const webp = "image/webp";
pub const svg = "image/svg+xml;charset=UTF-8";
pub const icon = "image/x-icon";
pub const text = "text/plain;charset=UTF-8";
pub const wav = "audio/wav";
pub const ogg = "audio/ogg";
pub const webm = "video/webm";
pub const default = "application/octet-stream";

/// return mime type of extension if found
pub fn fromExtension(extension: []const u8) ?[]const u8 {
    var hash = hashString(extension);
    for (mimes) |m| {
        if (m.hash == hash and mem.eql(u8, m.extension, extension)) {
            return m.mime;
        }
    }
    return null;
}
