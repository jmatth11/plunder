const std = @import("std");

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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // create plunder module
    const mod = b.addModule("plunder", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const dvui_dep = b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3,
    });

    const gui = b.addExecutable(.{
        .name = "plunder-gui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/gui.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "plunder", .module = mod },
                .{ .name = "dvui", .module = dvui_dep.module("dvui_sdl3") },
            },
        }),
    });
    b.installArtifact(gui);

    // create executable
    const exe = b.addExecutable(.{
        .name = "plunder",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "plunder", .module = mod },
                .{ .name = "dvui", .module = dvui_dep.module("dvui_sdl3") },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
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
