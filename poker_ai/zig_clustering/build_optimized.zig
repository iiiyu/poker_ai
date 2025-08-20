const std = @import("std");

pub fn build(b: *std.Build) void {
    // Target and optimization options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });

    // Main optimized executable
    const exe = b.addExecutable(.{
        .name = "poker_clustering_optimized",
        .root_source_file = b.path("src/optimized_main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Enable all CPU features for SIMD
    exe.target.cpu_arch = .native;
    exe.target.cpu_features_add = std.Target.x86.cpu.Feature.Set.init(.{
        .avx2 = true,
        .fma = true,
        .sse4_2 = true,
        .popcnt = true,
        .bmi = true,
        .bmi2 = true,
    });

    // Compiler flags for maximum optimization
    exe.addCSourceFlags(&[_][]const u8{
        "-march=native",
        "-mtune=native",
        "-O3",
        "-ffast-math",
        "-funroll-loops",
        "-ftree-vectorize",
        "-fomit-frame-pointer",
    });

    // Link-time optimization
    exe.want_lto = true;
    
    // SQLite dependency (assuming it's available)
    exe.linkLibC();
    exe.linkSystemLibrary("sqlite3");
    
    // Threading support
    exe.linkSystemLibrary("pthread");

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the optimized clustering");
    run_step.dependOn(&run_cmd.step);

    // Benchmark executable
    const bench = b.addExecutable(.{
        .name = "benchmark",
        .root_source_file = b.path("src/benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    bench.target.cpu_arch = .native;
    bench.want_lto = true;
    bench.linkLibC();
    bench.linkSystemLibrary("sqlite3");
    bench.linkSystemLibrary("pthread");
    
    b.installArtifact(bench);
    
    const bench_cmd = b.addRunArtifact(bench);
    bench_cmd.step.dependOn(b.getInstallStep());
    const bench_step = b.step("bench", "Run performance benchmarks");
    bench_step.dependOn(&bench_cmd.step);

    // Test command
    const test_exe = b.addTest(.{
        .root_source_file = b.path("src/optimized_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_exe.linkLibC();
    test_exe.linkSystemLibrary("sqlite3");
    
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_exe.step);

    // Profile-guided optimization build
    const pgo_step = b.step("pgo", "Build with profile-guided optimization");
    
    // Step 1: Build with profiling
    const pgo_gen = b.addExecutable(.{
        .name = "poker_clustering_pgo_gen",
        .root_source_file = b.path("src/optimized_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    pgo_gen.addCSourceFlags(&[_][]const u8{
        "-fprofile-generate",
    });
    pgo_gen.linkLibC();
    pgo_gen.linkSystemLibrary("sqlite3");
    pgo_gen.linkSystemLibrary("pthread");
    
    // Step 2: Run profiling workload
    const pgo_run = b.addRunArtifact(pgo_gen);
    pgo_run.addArg("--benchmark");
    
    // Step 3: Build with profile data
    const pgo_use = b.addExecutable(.{
        .name = "poker_clustering_pgo",
        .root_source_file = b.path("src/optimized_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    pgo_use.addCSourceFlags(&[_][]const u8{
        "-fprofile-use",
    });
    pgo_use.linkLibC();
    pgo_use.linkSystemLibrary("sqlite3");
    pgo_use.linkSystemLibrary("pthread");
    
    pgo_step.dependOn(&pgo_use.step);
    b.installArtifact(pgo_use);
}