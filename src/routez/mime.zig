const std = @import("std");
const mem = std.mem;

pub fn fromExtension(extension: []const u8) []const u8 {
    if (mem.eql(u8, extension, "js")) {
        return "application/javascript;charset=UTF-8";
    } else if (mem.eql(u8, extension, "css")) {
        return "text/css;charset=UTF-8";
    } else if (mem.eql(u8, extension, "html")) {
        return "text/html;charset=UTF-8";
    } else if (mem.eql(u8, extension, "png")) {
        return "image/png";
    } else if (mem.eql(u8, extension, "jpeg")) {
        return "image/jpeg";
    } else if (mem.eql(u8, extension, "gif")) {
        return "image/gif";
    } else if (mem.eql(u8, extension, "webp")) {
        return "image/webp";
    } else if (mem.eql(u8, extension, "svg")) {
        return "image/svg+xml;charset=UTF-8";
    } else if (mem.eql(u8, extension, "ico")) {
        return "image/x-icon";
    } else if (mem.eql(u8, extension, "txt")) {
        return "text/plain;charset=UTF-8";
    } else if (mem.eql(u8, extension, "wav")) {
        return "audio/wav";
    } else if (mem.eql(u8, extension, "ogg")) {
        return "audio/ogg";
    } else if (mem.eql(u8, extension, "webm")) {
        return "video/webm";
    } else {
        return default;
    }
}

pub const default = "application/octet-stream";