const std = @import("std");
const mem = std.mem;

const Mime = struct {
    extension: []const u8,
    mime: []const u8,
};

const mimes = []Mime{
    Mime{ .extension = "js", .mime = js },
    Mime{ .extension = "css", .mime = css },
    Mime{ .extension = "html", .mime = html },
    Mime{ .extension = "png", .mime = png },
    Mime{ .extension = "jpeg", .mime = jpeg },
    Mime{ .extension = "gif", .mime = gif },
    Mime{ .extension = "webp", .mime = webp },
    Mime{ .extension = "svg", .mime = svg },
    Mime{ .extension = "ico", .mime = icon },
    Mime{ .extension = "txt", .mime = text },
    Mime{ .extension = "wav", .mime = wav },
    Mime{ .extension = "ogg", .mime = ogg },
    Mime{ .extension = "webm", .mime = webm },
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

/// changes mime if better alternative found
pub fn fromExtension(extension: []const u8) ?[]const u8 {
    for (mimes) |m| {
        if (mem.eql(u8, m.extension, extension)) {
            return m.mime;
        }
    }
    return null;
}
