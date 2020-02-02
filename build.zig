const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const tests = b.addTest("test.zig");
    tests.setBuildMode(mode);
    tests.addPackagePath("zuri", "zuri/src/zuri.zig");

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&tests.step);

    var basic = b.addExecutable("basic", "examples/basic.zig");
    basic.setBuildMode(mode);
    basic.addPackage(.{
        .name = "routez",
        .path = "src/routez.zig",
        .dependencies = &[_]std.build.Pkg{.{
            .name = "zuri",
            .path = "zuri/src/zuri.zig",
        }},
    });
    basic.setOutputDir("zig-cache");
    b.installArtifact(basic);
    const basic_step = b.step("basic", "Basic example");
    basic_step.dependOn(&basic.run().step);
}
