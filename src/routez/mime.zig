const std = @import("std");
const mem = std.mem;
const hashString = std.hash_map.hashString;

/// Maps extensions to their mimetypes
pub const map = std.ComptimeStringMap([]const u8, .{
    .{ "js", js },
    .{ "json", json },
    .{ "css", css },
    .{ "html", html },
    .{ "png", png },
    .{ "jpeg", jpeg },
    .{ "gif", gif },
    .{ "webp", webp },
    .{ "svg", svg },
    .{ "ico", icon },
    .{ "txt", text },
    .{ "wav", wav },
    .{ "ogg", ogg },
    .{ "webm", webm },
    .{ "zig", text },
});

pub const js = "application/javascript;charset=UTF-8";
pub const css = "text/css;charset=UTF-8";
pub const html = "text/html;charset=UTF-8";
pub const json = "application/json";
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
