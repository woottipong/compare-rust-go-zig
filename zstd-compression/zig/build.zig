const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zstd-compression",
        .root_module = exe_mod,
    });

    exe.linkSystemLibrary("zstd");
    exe.linkLibC();

    b.installArtifact(exe);
}
