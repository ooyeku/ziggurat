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

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

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

    const run_ex1_step = b.step("run-ex1", "Run the Todo API example");
    run_ex1_step.dependOn(&run_ex1_cmd.step);

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

    const run_ex2_step = b.step("run-ex2", "Run the Static File Server example");
    run_ex2_step.dependOn(&run_ex2_cmd.step);

    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    main_tests.root_module.addImport("ziggurat_lib", lib_mod);

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
