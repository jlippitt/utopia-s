const std = @import("std");
const sdl3 = @import("sdl3");
const utopia = @import("utopia");
const cli = @import("./cli.zig");
const VideoDevice = @import("./VideoDevice.zig");
const AudioDevice = @import("./AudioDevice.zig");
const FpsCounter = @import("./FpsCounter.zig");
const logger = @import("./logger.zig");

pub const panic = std.debug.FullPanic(panicHandler);

pub const utopia_logger: utopia.log.Interface = .{
    .enabled = logger.enabled,
    .record = logger.record,
    .pushContext = logger.pushContext,
    .popContext = logger.popContext,
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    logger.init(allocator) catch |err| {
        std.debug.panic("Failed to initialize logger: {t}", .{err});
    };
    defer logger.deinit();

    const app_args, const device_args = try cli.parse(allocator) orelse return;

    sdl3.errors.error_callback = sdlError;

    try sdl3.init(.everything);
    defer sdl3.quit(.everything);

    var device = try device_args.initDevice(allocator);
    defer device.deinit();

    var video = try VideoDevice.init(device.getVideoState().resolution);
    defer video.deinit();

    var maybe_audio: ?AudioDevice = if (!app_args.no_fps_limit)
        try AudioDevice.init(device.getAudioState().sample_rate)
    else
        null;

    defer if (maybe_audio) |*audio| audio.deinit();

    const gamepad_ids = try sdl3.gamepad.getGamepads();

    const gamepad: ?sdl3.gamepad.Gamepad = if (gamepad_ids.len > 0)
        try sdl3.gamepad.Gamepad.init(gamepad_ids[0])
    else
        null;

    defer if (gamepad) |pad| pad.deinit();

    var controller_state: utopia.ControllerState = .{};

    if (maybe_audio) |*audio| {
        try audio.play();
    }

    var fps_counter = try FpsCounter.init();
    var timer = try std.time.Timer.start();
    var delay_time: i64 = 0;

    outer: while (true) {
        while (sdl3.events.poll()) |event| {
            switch (event) {
                .quit => break :outer,
                .window_display_changed => try video.onWindowDisplayChanged(),
                .key_down => |key| if (key.scancode) |scancode| {
                    switch (scancode) {
                        .escape => break :outer,
                        else => {},
                    }
                },
                .gamepad_button_down => |button| switch (button.button) {
                    inline else => |field| @field(controller_state.button, @tagName(field)) = true,
                },
                .gamepad_button_up => |button| switch (button.button) {
                    inline else => |field| @field(controller_state.button, @tagName(field)) = false,
                },
                .gamepad_axis_motion => |axis| switch (axis.axis) {
                    inline else => |field| @field(controller_state.axis, @tagName(field)) =
                        @as(f32, @floatFromInt(axis.value)) /
                        (std.math.maxInt(@TypeOf(axis.value)) + 1),
                },
                else => {},
            }
        }

        device.updateControllerState(&controller_state);

        try device.runFrame();

        {
            const video_state = device.getVideoState();
            try video.setResolution(video_state.resolution);
            try video.update(video_state.pixel_data);
        }

        if (maybe_audio) |*audio| {
            const audio_state = device.getAudioState();

            try audio.setSampleRate(audio_state.sample_rate);
            try audio.queueAudioData(audio_state.sample_data);

            const expected_duration = (@as(u64, audio_state.sample_data.len) * std.time.ns_per_s) /
                (audio_state.sample_rate);
            const actual_duration = timer.lap();
            delay_time += @intCast(expected_duration);
            delay_time -= @intCast(actual_duration);

            if (delay_time > 0) {
                sdl3.timer.delayNanoseconds(@intCast(delay_time));
            }
        }

        try video.setFps(fps_counter.update());
    }
}

fn panicHandler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    logger.deinit();
    std.debug.defaultPanic(msg, first_trace_addr);
}

fn sdlError(err: ?[:0]const u8) void {
    if (err) |err_string| {
        std.debug.print("SDL Error: {s}\n", .{err_string});
    } else {
        std.debug.print("SDL Error: Unknown\n", .{});
    }
}
