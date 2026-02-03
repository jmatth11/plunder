const std = @import("std");

/// Build the test program
fn build_test(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    path: []const u8,
    name: []const u8,
    lib_mod: *std.Build.Module,
) !void {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("plunder", lib_mod);
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = exe_mod,
    });
    b.installArtifact(exe);
}

/// build the C program (goes along with the test)
fn build_c_exe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    path: []const u8,
    name: []const u8,
) !void {
    const exe_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    exe_mod.addCSourceFiles(.{
        .language = .c,
        .files = &.{
            path,
        },
        .flags = &.{
            "-Wall",
            "-std=c11",
        },
    });
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = exe_mod,
    });
    b.installArtifact(exe);
}

pub fn release_builds(b: *std.Build) !void {
    const targets: []const std.Target.Query = &.{
        .{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
        },
        .{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
        },
        .{
            .cpu_arch = .aarch64,
            .os_tag = .macos,
        },
    };
    var alloc = std.heap.smp_allocator;
    for (targets) |t| {
        const resolve = b.resolveTargetQuery(t);
        // create plunder module
        const mod = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = resolve,
            .optimize = .ReleaseSafe,
        });

        // create executable
        const exe_version = try resolve.result.linuxTriple(alloc);
        defer alloc.free(exe_version);
        const exe_name = try std.fmt.allocPrint(
            alloc,
            "plunder-{s}",
            .{exe_version},
        );
        defer alloc.free(exe_name);
        const zigtui_dep = b.dependency("zigtui", .{
            .target = resolve,
            .optimize = .ReleaseSafe,
        });
        const tui = b.addExecutable(.{
            .name = exe_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tui.zig"),
                .target = resolve,
                .optimize = .ReleaseSafe,
                .imports = &.{
                    .{ .name = "plunder", .module = mod },
                    .{ .name = "zigtui", .module = zigtui_dep.module("zigtui") },
                },
            }),
        });
        b.installArtifact(tui);
    }
}

pub fn build(b: *std.Build) !void {
    const build_release = b.option(bool, "release", "Build release builds for all supported platforms.") orelse false;
    if (build_release) {
        try release_builds(b);
        return;
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // create plunder module
    const mod = b.addModule("plunder", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // create executable
    const example_exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "plunder", .module = mod },
            },
        }),
    });

    b.installArtifact(example_exe);

    // TUI app
    const zigtui_dep = b.dependency("zigtui", .{
        .target = target,
        .optimize = optimize,
    });
    const tui = b.addExecutable(.{
        .name = "plunder",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tui.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "plunder", .module = mod },
                .{ .name = "zigtui", .module = zigtui_dep.module("zigtui") },
            },
        }),
    });
    b.installArtifact(tui);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(tui);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // build test programs.
    try build_test(
        b,
        target,
        optimize,
        "test/heap_read.zig",
        "heap_read",
        mod,
    );
    try build_c_exe(
        b,
        target,
        optimize,
        "test/dummy.c",
        "dummy",
    );

    // test build
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mod_tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
