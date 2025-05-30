const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("ziggurat_lib", lib_mod);

    const lib = b.addStaticLibrary(.{
        .name = "ziggurat",
        .root_module = exe_mod,
    });

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "ziggurat",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const ex1_mod = b.createModule(.{
        .root_source_file = b.path("examples/ex1/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    ex1_mod.addImport("ziggurat", lib_mod);

    const ex1_exe = b.addExecutable(.{
        .name = "todo-api",
        .root_module = ex1_mod,
    });
    b.installArtifact(ex1_exe);

    const run_ex1_cmd = b.addRunArtifact(ex1_exe);
    run_ex1_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_ex1_cmd.addArgs(args);
    }

    const ex2_mod = b.createModule(.{
        .root_source_file = b.path("examples/ex2/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    ex2_mod.addImport("ziggurat", lib_mod);

    const ex2_exe = b.addExecutable(.{
        .name = "static-server",
        .root_module = ex2_mod,
    });
    b.installArtifact(ex2_exe);

    const run_ex2_cmd = b.addRunArtifact(ex2_exe);
    run_ex2_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_ex2_cmd.addArgs(args);
    }

    const test_step = b.step("test", "Run all tests");
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/test_main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);
}
