const std = @import("std");
const clap = @import("clap");
const utopia = @import("utopia");

const AppArgs = struct {};

pub fn parse(allocator: std.mem.Allocator) !?struct { AppArgs, utopia.DeviceArgs } {
    var iter = try std.process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    _ = iter.next();

    const app_args, const command = try parseAppArgs(allocator, &iter) orelse return null;

    const device_args = switch (command) {
        inline else => |device_type| try parseDeviceArgs(
            device_type,
            allocator,
            &iter,
        ) orelse return null,
    };

    return .{ app_args, device_args };
}

fn parseAppArgs(
    allocator: std.mem.Allocator,
    iter: *std.process.ArgIterator,
) !?struct { AppArgs, utopia.DeviceType } {
    const parsers = .{
        .device = clap.parsers.enumeration(utopia.DeviceType),
    };

    const params = comptime clap.parseParamsComptime(
        \\-h, --help    Display this help and exit
        \\<device>
        \\
    );

    var diag: clap.Diagnostic = .{};

    var res = clap.parseEx(clap.Help, &params, parsers, iter, .{
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

    const app_args: AppArgs = .{};

    const device_type = res.positionals[0] orelse {
        try clap.helpToFile(.stderr(), clap.Help, &params, .{});
        return error.MissingCommand;
    };

    return .{ app_args, device_type };
}

fn parseDeviceArgs(
    comptime device_type: utopia.DeviceType,
    allocator: std.mem.Allocator,
    iter: *std.process.ArgIterator,
) !?utopia.DeviceArgs {
    const parsers = .{
        .string = clap.parsers.string,
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

    const device_args = try translateArgs(device_type, &res.args, &res.positionals);

    return device_args;
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

        const param: clap.Param(clap.Help) = switch (cli.type) {
            .positional => .{
                .id = .{
                    .desc = cli.desc,
                    .val = "string",
                },
                .takes_value = .one,
            },
            .flag => |short_name| .{
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
                    .short = short_name,
                    .long = long_name,
                },
                .takes_value = switch (field.type) {
                    bool => .none,
                    else => .one,
                },
            },
        };

        params = params ++ .{param};
    }

    return params;
}

fn translateArgs(
    comptime device_type: utopia.DeviceType,
    flags: anytype,
    positionals: anytype,
) !utopia.DeviceArgs {
    const DeviceArgs = @FieldType(utopia.DeviceArgs, @tagName(device_type));

    var device_args: DeviceArgs = undefined;
    comptime var positional_index: usize = 0;

    inline for (std.meta.fields(DeviceArgs)) |field| {
        const long_name = comptime replaceUnderscores(field.name);

        const cli = comptime DeviceArgs.cli.get(long_name) orelse continue;

        const field_value = switch (cli.type) {
            .positional => blk: {
                const value = positionals[positional_index] orelse return error.MissingPositional;
                positional_index += 1;
                break :blk value;
            },
            .flag => |_| blk: {
                const value = @field(flags, long_name);
                break :blk if (field.type == bool) value != 0 else value;
            },
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
