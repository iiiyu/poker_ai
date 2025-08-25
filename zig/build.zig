const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main library
    const lib = b.addLibrary(.{
        .name = "poker_ai",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link required libraries
    lib.linkLibC();
    lib.linkSystemLibrary("sqlite3");
    
    // Export symbols for C API
    lib.bundle_compiler_rt = true;
    
    b.installArtifact(lib);

    // Shared library for Python FFI
    const shared_lib = b.addLibrary(.{
        .name = "poker_ai",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    shared_lib.linkLibC();
    shared_lib.linkSystemLibrary("sqlite3");
    shared_lib.bundle_compiler_rt = true;
    
    b.installArtifact(shared_lib);

    // Example executable
    const exe = b.addExecutable(.{
        .name = "poker_ai_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
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

    // Clustering demo executable
    const clustering_demo = b.addExecutable(.{
        .name = "clustering_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/clustering_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    clustering_demo.root_module.addImport("poker_ai", lib.root_module);
    clustering_demo.linkLibC();
    clustering_demo.linkSystemLibrary("sqlite3");
    
    b.installArtifact(clustering_demo);
    
    const run_clustering = b.addRunArtifact(clustering_demo);
    run_clustering.step.dependOn(b.getInstallStep());
    
    const clustering_step = b.step("clustering", "Run the clustering demo");
    clustering_step.dependOn(&run_clustering.step);

    // Tournament demo executable
    const tournament_demo = b.addExecutable(.{
        .name = "tournament_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/tournament_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    tournament_demo.root_module.addImport("poker_ai", lib.root_module);
    tournament_demo.linkLibC();
    tournament_demo.linkSystemLibrary("sqlite3");
    
    b.installArtifact(tournament_demo);
    
    const run_tournament = b.addRunArtifact(tournament_demo);
    run_tournament.step.dependOn(b.getInstallStep());
    
    const tournament_step = b.step("tournament", "Run the tournament demo");
    tournament_step.dependOn(&run_tournament.step);

    // Interactive poker game executable
    const play_poker = b.addExecutable(.{
        .name = "play_poker",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/play_poker.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    play_poker.root_module.addImport("poker_ai", lib.root_module);
    play_poker.linkLibC();
    play_poker.linkSystemLibrary("sqlite3");
    
    b.installArtifact(play_poker);
    
    const run_play_poker = b.addRunArtifact(play_poker);
    run_play_poker.step.dependOn(b.getInstallStep());
    
    if (b.args) |args| {
        run_play_poker.addArgs(args);
    }
    
    const play_step = b.step("play", "Run the interactive poker game");
    play_step.dependOn(&run_play_poker.step);

    // Training executable
    const train_exe = b.addExecutable(.{
        .name = "train",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/train.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    train_exe.root_module.addImport("poker_ai", lib.root_module);
    train_exe.linkLibC();
    train_exe.linkSystemLibrary("sqlite3");
    
    b.installArtifact(train_exe);
    
    const run_train = b.addRunArtifact(train_exe);
    run_train.step.dependOn(b.getInstallStep());
    
    if (b.args) |args| {
        run_train.addArgs(args);
    }
    
    const train_step = b.step("train", "Run MCCFR training");
    train_step.dependOn(&run_train.step);

    // Unit tests
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
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
        "tests/test_mccfr_complete.zig",
        "tests/test_tournament.zig",
    };
    
    for (test_files) |test_file| {
        const test_exe = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
            }),
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
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/main.zig"),
            .target = target,
            .optimize = .ReleaseFast, // Always optimize benchmarks
        }),
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