const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clap = b.dependency("clap", .{});
    const sdl3 = b.dependency("sdl3", .{});

    const log_level = b.option([]const u8, "log-level", "Maximum log level");

    const options = b.addOptions();
    options.addOption(?[]const u8, "log_level", log_level);

    const utopia_framework = b.addModule("utopia", .{
        .root_source_file = b.path("utopia-framework/lib.zig"),
        .target = target,
    });

    const utopia_device_n64 = b.addModule("utopia-device-n64", .{
        .root_source_file = b.path("utopia-device-n64/Device.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "framework", .module = utopia_framework },
            .{ .name = "sdl3", .module = sdl3.module("sdl3") },
        },
    });

    const utopia = b.addModule("utopia", .{
        .root_source_file = b.path("utopia/lib.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "framework", .module = utopia_framework },
            .{ .name = "device-n64", .module = utopia_device_n64 },
        },
    });

    const utopia_cli = b.addExecutable(.{
        .name = "utopia-cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("utopia-cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "options", .module = options.createModule() },
                .{ .name = "sdl3", .module = sdl3.module("sdl3") },
                .{ .name = "utopia", .module = utopia },
                .{ .name = "clap", .module = clap.module("clap") },
            },
        }),
    });

    b.installArtifact(utopia_cli);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(utopia_cli);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
