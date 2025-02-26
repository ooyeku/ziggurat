const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Modules can depend on one another using the `std.Build.Module.addImport` function.
    // This is what allows Zig source code to use `@import("foo")` where 'foo' is not a
    // file path. In this case, we set up `exe_mod` to import `lib_mod`.
    exe_mod.addImport("ziggurat_lib", lib_mod);

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.
    const lib = b.addStaticLibrary(.{
        .name = "ziggurat",
        .root_module = exe_mod,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "ziggurat",
        .root_module = exe_mod,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Example 1: Todo API
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

    // Example 2: Static File Server
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

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add the ziggurat_lib module to the test
    main_tests.root_module.addImport("ziggurat_lib", lib_mod);

    const run_main_tests = b.addRunArtifact(main_tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
