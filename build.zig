const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Ziggurat is a library - no need for library artifact, just provide the module

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

    const run_step = b.step("run", "Run the todo-api example");
    run_step.dependOn(&run_ex1_cmd.step);

    const run_ex1_step = b.step("run-ex1", "Run the todo-api example");
    run_ex1_step.dependOn(&run_ex1_cmd.step);

    const run_ex2_step = b.step("run-ex2", "Run the static-server example");
    run_ex2_step.dependOn(&run_ex2_cmd.step);

    const test_step = b.step("test", "Run all tests");
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("ziggurat", lib_mod);

    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    // Also run tests from the library itself to ensure all test blocks are discovered
    const lib_test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_tests = b.addTest(.{
        .root_module = lib_test_mod,
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);
}
