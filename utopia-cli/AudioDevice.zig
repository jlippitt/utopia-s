const std = @import("std");
const sdl3 = @import("sdl3");

const format: sdl3.audio.Format = .signed_16_bit_little_endian;
const num_channels = 2;

const Self = @This();

stream: sdl3.audio.Stream,
sample_rate: u32,

pub fn init(sample_rate: u32) error{SdlError}!Self {
    const device = sdl3.audio.Device.default_playback;

    const spec: sdl3.audio.Spec = .{
        .format = format,
        .num_channels = num_channels,
        .sample_rate = sample_rate,
    };

    const stream = try device.openStream(spec, void, null, null);
    errdefer stream.deinit();

    return .{
        .stream = stream,
        .sample_rate = sample_rate,
    };
}

pub fn deinit(self: *Self) void {
    self.stream.deinit();
}

pub fn play(self: *Self) error{SdlError}!void {
    try self.stream.resumeDevice();
}

pub fn pause(self: *Self) error{SdlError}!void {
    try self.stream.pauseDevice();
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

pub fn queueAudioData(self: *Self, sample_data: []const i16) error{SdlError}!void {
    try self.stream.putData(std.mem.sliceAsBytes(sample_data));
}
