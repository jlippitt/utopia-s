const std = @import("std");
const fw = @import("framework");

pub const EventType = enum {
    cpu_interrupt,
    cpu_timer,
    rsp_run,
    ai_sample,
    vi_new_line,
};

const total_event_types = @typeInfo(EventType).@"enum".fields.len;

const Self = @This();

cycles: u64 = 0,
next_event_cycle: u64 = std.math.maxInt(u64),
next_event_type: ?EventType = null,
scheduled_events: [total_event_types]u64 = @splat(std.math.maxInt(u64)),

pub fn init() Self {
    return .{};
}

pub fn getCycles(self: *const Self) u64 {
    return self.cycles;
}

pub fn addCycles(self: *Self, cycles: u64) void {
    self.cycles += cycles;
}

pub fn schedule(self: *Self, event_type: EventType, delta: u64) void {
    if (self.scheduled_events[@intFromEnum(event_type)] != std.math.maxInt(u64)) {
        fw.log.panic("Event already scheduled: {t}", .{event_type});
    }

    self.reschedule(event_type, delta);
}

pub fn reschedule(self: *Self, event_type: EventType, delta: u64) void {
    const event_cycle = self.cycles + delta;

    self.scheduled_events[@intFromEnum(event_type)] = event_cycle;

    if (event_cycle < self.next_event_cycle or
        (event_cycle == self.next_event_cycle and
            @intFromEnum(event_type) < @intFromEnum(self.next_event_type.?)))
    {
        self.next_event_cycle = event_cycle;
        self.next_event_type = event_type;
    }

    fw.log.trace("Event Scheduled: {t} (+{d})", .{ event_type, delta });
}

pub fn nextEvent(self: *Self) ?EventType {
    if (self.cycles < self.next_event_cycle) {
        @branchHint(.likely);
        return null;
    }

    const event_type = self.next_event_type.?;
    fw.log.trace("Event Fired: {t}", .{event_type});

    self.scheduled_events[@intFromEnum(event_type)] = std.math.maxInt(u64);

    self.next_event_cycle = std.math.maxInt(u64);
    self.next_event_type = null;

    for (self.scheduled_events, 0..) |cycle, index| {
        if (cycle < self.next_event_cycle) {
            self.next_event_cycle = cycle;
            self.next_event_type = @enumFromInt(index);
        }
    }

    return event_type;
}
