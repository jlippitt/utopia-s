const std = @import("std");
const sdl3 = @import("sdl3");
const utopia = @import("utopia");

const format: sdl3.audio.Format = .signed_16_bit_little_endian;
const num_channels = 2;

const silence: utopia.Sample = .{ 0, 0 };

const Self = @This();

stream: sdl3.audio.Stream,
sample_rate: u32,
last_sample: utopia.Sample = silence,

pub fn init(sample_rate: u32) error{SdlError}!Self {
    const device = sdl3.audio.Device.default_playback;

    const spec: sdl3.audio.Spec = .{
        .format = format,
        .num_channels = num_channels,
        .sample_rate = sample_rate,
    };

    const stream = try device.openStream(spec, void, null, null);
    errdefer stream.deinit();

    // Add approx 50ms of silence at the start of the queue to help reduce popping
    for (0..(sample_rate / 20)) |_| {
        try stream.putData(@ptrCast(&silence));
    }

    return .{
        .stream = stream,
        .sample_rate = sample_rate,
    };
}

pub fn deinit(self: *Self) void {
    self.stream.deinit();
}

pub fn play(self: *Self) error{SdlError}!void {
    self.stream.setGetCallback(utopia.Sample, getCallback, &self.last_sample);
    try self.stream.resumeDevice();
}

pub fn pause(self: *Self) error{SdlError}!void {
    try self.stream.pauseDevice();
    self.stream.setGetCallback(void, null, null);
}

pub fn setSampleRate(self: *Self, sample_rate: u32) error{SdlError}!void {
    if (sample_rate == self.sample_rate) {
        return;
    }

    const spec: sdl3.audio.Spec = .{
        .format = format,
        .num_channels = num_channels,
        .sample_rate = sample_rate,
    };

    try self.stream.setFormat(spec, null);

    self.sample_rate = sample_rate;
}

pub fn queueAudioData(self: *Self, sample_data: []const [2]i16) error{SdlError}!void {
    if (sample_data.len == 0) {
        return;
    }

    try self.stream.putData(std.mem.sliceAsBytes(sample_data));
    self.last_sample = sample_data[sample_data.len - 1];
}

fn getCallback(
    last_sample: ?*utopia.Sample,
    stream: sdl3.audio.Stream,
    additional_amount: usize,
    total_amount: usize,
) void {
    _ = total_amount;

    std.debug.assert((additional_amount % 4) == 0);

    for (0..(additional_amount / 4)) |_| {
        stream.putData(@ptrCast(&last_sample.?.*)) catch |err| {
            std.debug.panic("Failed to queue audio data in callback: {t}", .{err});
        };
    }
}
