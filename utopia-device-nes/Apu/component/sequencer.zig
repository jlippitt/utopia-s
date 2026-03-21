const std = @import("std");

pub fn Sequencer(comptime T: type, comptime len: usize) type {
    return struct {
        const Self = @This();

        sequence: *const [len]T,
        index: std.math.IntFittingRange(0, len) = 0,

        pub fn init(sequence: *const [len]T) Self {
            return .{
                .sequence = sequence,
            };
        }

        pub fn sample(self: *const Self) T {
            return self.sequence[self.index];
        }

        pub fn setSequence(self: *Self, sequence: *const [len]T) void {
            self.sequence = sequence;
        }

        pub fn reset(self: *Self) void {
            self.index = 0;
        }

        pub fn step(self: *Self) void {
            self.index += 1;

            if (self.index == len) {
                self.index = 0;
            }
        }
    };
}
