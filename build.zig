const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const tests = b.addTest("test.zig");
    tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&tests.step);
    b.default_step.dependOn(test_step);


    var basic = b.addExecutable("basic", "examples/basic.zig");
    basic.setBuildMode(mode);
    basic.addPackagePath("routez", "src/routez.zig");
    basic.setOutputDir("zig-cache");

    b.installArtifact(basic);

    const basic_step = b.step("basic", "Basic example");
    basic_step.dependOn(&basic.run().step);
}
