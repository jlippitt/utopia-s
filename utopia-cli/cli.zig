const std = @import("std");
const clap = @import("clap");
const utopia = @import("utopia");

const default_save_interval = 30;

const AppArgs = struct {
    rom_path: []const u8,
    bios_path: ?[]const u8,
    save_path: ?[]const u8,
    save_interval: u32,
    full_screen: bool,
    no_fps_limit: bool,
};

pub fn parse(allocator: std.mem.Allocator) !?struct { AppArgs, utopia.DeviceArgs } {
    const parsers = .{
        .device = clap.parsers.enumeration(utopia.DeviceType),
        .path = clap.parsers.string,
        .seconds = clap.parsers.int(u32, 10),
    };

    const params = comptime clap.parseParamsComptime(
        \\-b, --bios-path <path>        Path to BIOS files
        \\-s, --save-path <path>        Path to save files
        \\-i, --save-interval <seconds> How often save data is synced to filesystem
        \\-f, --full-screen             Start in full screen mode
        \\-n, --no-fps-limit            Disable FPS limiter (also disables audio)
        \\-h, --help                    Display this help and exit
        \\<device>
        \\
    );

    var iter = try std.process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    _ = iter.next();

    var diag: clap.Diagnostic = .{};

    var res = clap.parseEx(clap.Help, &params, parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
        .terminating_positional = 0,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };

    defer res.deinit();

    if (res.args.help != 0) {
        try clap.helpToFile(.stderr(), clap.Help, &params, .{});
        return null;
    }

    const command = res.positionals[0] orelse {
        try clap.helpToFile(.stderr(), clap.Help, &params, .{});
        return error.MissingDeviceType;
    };

    const device_args, const rom_path = switch (command) {
        inline else => |device_type| try parseDeviceArgs(
            device_type,
            allocator,
            &iter,
        ) orelse return null,
    };

    const app_args: AppArgs = .{
        .rom_path = rom_path,
        .bios_path = res.args.@"bios-path",
        .save_path = res.args.@"save-path",
        .save_interval = res.args.@"save-interval" orelse default_save_interval,
        .full_screen = res.args.@"full-screen" != 0,
        .no_fps_limit = res.args.@"no-fps-limit" != 0,
    };

    return .{ app_args, device_args };
}

fn parseDeviceArgs(
    comptime device_type: utopia.DeviceType,
    allocator: std.mem.Allocator,
    iter: *std.process.ArgIterator,
) !?struct { utopia.DeviceArgs, []const u8 } {
    const parsers = .{
        .string = clap.parsers.string,
        .@"rom-path" = clap.parsers.string,
    };

    const params = comptime buildParams(device_type);

    var diag: clap.Diagnostic = .{};

    var res = clap.parseEx(clap.Help, params, parsers, iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
        .terminating_positional = 0,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };

    defer res.deinit();

    if (res.args.help != 0) {
        try clap.helpToFile(.stderr(), clap.Help, params, .{});
        return null;
    }

    const device_args = try translateArgs(device_type, &res.args);
    const rom_path = res.positionals[0] orelse return error.NoRomPath;

    return .{ device_args, rom_path };
}

fn buildParams(comptime device_type: utopia.DeviceType) []const clap.Param(clap.Help) {
    const DeviceArgs = @FieldType(utopia.DeviceArgs, @tagName(device_type));

    var params: []const clap.Param(clap.Help) = &.{};

    params = params ++ .{
        clap.Param(clap.Help){
            .id = .{
                .desc = "Display this help and exit",
            },
            .names = .{
                .short = 'h',
                .long = "help",
            },
            .takes_value = .none,
        },
    };

    for (std.meta.fields(DeviceArgs)) |field| {
        const long_name = replaceUnderscores(field.name);

        const cli = DeviceArgs.cli.get(long_name) orelse continue;

        const param: clap.Param(clap.Help) = .{
            .id = .{
                .desc = cli.desc,
                .val = switch (field.type) {
                    []const u8 => "string",
                    ?[]const u8 => "string",
                    bool => "",
                    else => long_name,
                },
            },
            .names = .{
                .short = cli.short_name,
                .long = long_name,
            },
            .takes_value = switch (field.type) {
                bool => .none,
                else => .one,
            },
        };

        params = params ++ .{param};
    }

    params = params ++ .{
        clap.Param(clap.Help){
            .id = .{
                .desc = "Path to ROM/ISO file",
                .val = "rom-path",
            },
            .takes_value = .one,
        },
    };

    return params;
}

fn translateArgs(comptime device_type: utopia.DeviceType, flags: anytype) !utopia.DeviceArgs {
    const DeviceArgs = @FieldType(utopia.DeviceArgs, @tagName(device_type));

    var device_args: DeviceArgs = undefined;

    inline for (std.meta.fields(DeviceArgs)) |field| {
        const long_name = comptime replaceUnderscores(field.name);

        const field_value = blk: {
            const value = @field(flags, long_name);
            break :blk if (field.type == bool) value != 0 else value;
        };

        @field(device_args, field.name) = field_value;
    }

    return @unionInit(utopia.DeviceArgs, @tagName(device_type), device_args);
}

fn replaceUnderscores(in_string: []const u8) []const u8 {
    var out_string: []const u8 = &.{};

    for (in_string) |char| {
        if (char == '_') {
            out_string = out_string ++ .{'-'};
        } else {
            out_string = out_string ++ .{char};
        }
    }

    return out_string;
}
