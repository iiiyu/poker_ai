const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main library
    const lib = b.addStaticLibrary(.{
        .name = "poker_ai",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link required libraries
    lib.linkLibC();
    lib.linkSystemLibrary("sqlite3");
    
    // Export symbols for C API
    lib.bundle_compiler_rt = true;
    
    b.installArtifact(lib);

    // Shared library for Python FFI
    const shared_lib = b.addSharedLibrary(.{
        .name = "poker_ai",
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    shared_lib.linkLibC();
    shared_lib.linkSystemLibrary("sqlite3");
    shared_lib.bundle_compiler_rt = true;
    
    b.installArtifact(shared_lib);

    // Example executable
    const exe = b.addExecutable(.{
        .name = "poker_ai_demo",
        .root_source_file = b.path("src/demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    exe.root_module.addImport("poker_ai", lib.root_module);
    exe.linkLibC();
    exe.linkSystemLibrary("sqlite3");
    
    b.installArtifact(exe);

    // Run command for demo
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the demo application");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    lib_unit_tests.linkLibC();
    lib_unit_tests.linkSystemLibrary("sqlite3");

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Individual test modules
    const test_files = [_][]const u8{
        "tests/test_hand_eval.zig",
        "tests/test_game_state.zig", 
        "tests/test_cfr.zig",
        "tests/test_ffi.zig",
        "tests/test_game_engine_integration.zig",
    };
    
    for (test_files) |test_file| {
        const test_exe = b.addTest(.{
            .root_source_file = b.path(test_file),
            .target = target,
            .optimize = optimize,
        });
        
        test_exe.root_module.addImport("poker_ai", lib.root_module);
        test_exe.linkLibC();
        test_exe.linkSystemLibrary("sqlite3");
        
        const run_test = b.addRunArtifact(test_exe);
        test_step.dependOn(&run_test.step);
    }

    // Benchmarks
    const bench = b.addExecutable(.{
        .name = "poker_ai_bench",
        .root_source_file = b.path("bench/main.zig"),
        .target = target,
        .optimize = .ReleaseFast, // Always optimize benchmarks
    });
    
    bench.root_module.addImport("poker_ai", lib.root_module);
    bench.linkLibC();
    bench.linkSystemLibrary("sqlite3");
    
    b.installArtifact(bench);

    const run_bench = b.addRunArtifact(bench);
    run_bench.step.dependOn(b.getInstallStep());
    
    const bench_step = b.step("bench", "Run performance benchmarks");
    bench_step.dependOn(&run_bench.step);

    // Check step for code quality
    const check_step = b.step("check", "Check code without building");
    check_step.dependOn(&lib.step);
    
    // Install step for documentation
    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&lib.step);
}