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

    const utopia_processor = b.addModule("utopia-processor", .{
        .root_source_file = b.path("utopia-processor/lib.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "framework", .module = utopia_framework },
        },
    });

    const utopia_device_gb = b.addModule("utopia-device-gb", .{
        .root_source_file = b.path("utopia-device-gb/Device.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "framework", .module = utopia_framework },
            .{ .name = "processor", .module = utopia_processor },
        },
    });

    const utopia_device_n64 = b.addModule("utopia-device-n64", .{
        .root_source_file = b.path("utopia-device-n64/Device.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "framework", .module = utopia_framework },
            .{ .name = "sdl3", .module = sdl3.module("sdl3") },
            shaderImport(b, "rdp.vert", "utopia-device-n64/Rdp/shader.vert"),
            shaderImport(b, "rdp.frag", "utopia-device-n64/Rdp/shader.frag"),
        },
    });

    const utopia_device_nes = b.addModule("utopia-device-nes", .{
        .root_source_file = b.path("utopia-device-nes/Device.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "framework", .module = utopia_framework },
            .{ .name = "processor", .module = utopia_processor },
        },
    });

    const utopia_device_sms = b.addModule("utopia-device-sms", .{
        .root_source_file = b.path("utopia-device-sms/Device.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "framework", .module = utopia_framework },
            .{ .name = "processor", .module = utopia_processor },
        },
    });

    const utopia = b.addModule("utopia", .{
        .root_source_file = b.path("utopia/lib.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "framework", .module = utopia_framework },
            .{ .name = "device-gb", .module = utopia_device_gb },
            .{ .name = "device-n64", .module = utopia_device_n64 },
            .{ .name = "device-nes", .module = utopia_device_nes },
            .{ .name = "device-sms", .module = utopia_device_sms },
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

fn shaderImport(b: *std.Build, name: []const u8, path: []const u8) std.Build.Module.Import {
    const cmd = b.addSystemCommand(&.{
        "glslangValidator",
        "-V",
        "--quiet",
        "-o",
    });

    const output_path = b.fmt("{s}.spv", .{
        std.fmt.hex(std.hash.Fnv1a_128.hash(path)),
    });

    const spv = cmd.addOutputFileArg(output_path);
    cmd.addFileArg(b.path(path));
    cmd.stdio = .inherit;

    const module = b.createModule(.{
        .root_source_file = spv,
    });

    return .{
        .name = name,
        .module = module,
    };
}
