const std = @import("std");

pub const maximum_steps = 32;
pub const no_playhead: ?u5 = null;

pub fn Sequencer(comptime capacity: usize) type {
    if (capacity == 0 or capacity > maximum_steps) {
        @compileError("step sequencer capacity must be between 1 and 32 steps");
    }

    return struct {
        const Self = @This();

        step_count: u6,
        active: u32,
        selection: u32,
        cursor: u5,
        anchor: u5,
        playhead: ?u5 = no_playhead,

        pub fn init(step_count: u6, active: u32, selection: u32) !Self {
            if (step_count == 0 or step_count > capacity) return error.InvalidStepCount;
            const valid = maskFor(step_count);
            if (active & ~valid != 0 or selection & ~valid != 0) return error.StepOutsideRange;
            const cursor: u5 = if (selection == 0) 0 else @intCast(@ctz(selection));
            return .{
                .step_count = step_count,
                .active = active,
                .selection = selection,
                .cursor = cursor,
                .anchor = cursor,
            };
        }

        pub fn isActive(self: Self, step: u5) bool {
            return self.contains(step) and self.active & bit(step) != 0;
        }

        pub fn isSelected(self: Self, step: u5) bool {
            return self.contains(step) and self.selection & bit(step) != 0;
        }

        pub fn select(self: *Self, step: u5, mode: enum { replace, toggle, extend }) !void {
            if (!self.contains(step)) return error.StepOutsideRange;
            switch (mode) {
                .replace => {
                    self.selection = bit(step);
                    self.anchor = step;
                },
                .toggle => {
                    self.selection ^= bit(step);
                    self.anchor = step;
                },
                .extend => self.selection = rangeMask(self.anchor, step),
            }
            self.cursor = step;
        }

        pub fn selectAll(self: *Self) void {
            self.selection = maskFor(self.step_count);
        }

        pub fn clearSelection(self: *Self) void {
            self.selection = 0;
            self.anchor = self.cursor;
        }

        pub fn moveCursor(self: *Self, direction: enum { previous, next }, extend: bool) bool {
            const previous = self.cursor;
            self.cursor = switch (direction) {
                .previous => if (self.cursor == 0) @intCast(self.step_count - 1) else self.cursor - 1,
                .next => if (@as(u6, self.cursor) + 1 == self.step_count) 0 else self.cursor + 1,
            };
            self.selection = if (extend) rangeMask(self.anchor, self.cursor) else bit(self.cursor);
            if (!extend) self.anchor = self.cursor;
            return previous != self.cursor;
        }

        pub fn toggleSelection(self: *Self) u32 {
            const affected = if (self.selection == 0) bit(self.cursor) else self.selection;
            const enable = self.active & affected != affected;
            if (enable) self.active |= affected else self.active &= ~affected;
            return affected;
        }

        pub fn paint(self: *Self, step: u5, enabled: bool) !bool {
            if (!self.contains(step)) return error.StepOutsideRange;
            const mask = bit(step);
            const changed = (self.active & mask != 0) != enabled;
            if (enabled) self.active |= mask else self.active &= ~mask;
            self.selection = mask;
            self.cursor = step;
            self.anchor = step;
            return changed;
        }

        pub fn setPlayhead(self: *Self, step: ?u5) !bool {
            if (step) |value| if (!self.contains(value)) return error.StepOutsideRange;
            const changed = self.playhead != step;
            self.playhead = step;
            return changed;
        }

        fn contains(self: Self, step: u5) bool {
            return step < self.step_count;
        }
    };
}

fn bit(step: u5) u32 {
    return @as(u32, 1) << step;
}

fn maskFor(step_count: u6) u32 {
    return if (step_count == maximum_steps) std.math.maxInt(u32) else (@as(u32, 1) << @intCast(step_count)) - 1;
}

fn rangeMask(first: u5, last: u5) u32 {
    const low = @min(first, last);
    const high = @max(first, last);
    const upper = if (high == 31) std.math.maxInt(u32) else (@as(u32, 1) << (high + 1)) - 1;
    const lower = if (low == 0) 0 else (@as(u32, 1) << low) - 1;
    return upper & ~lower;
}

test "sequencer keeps activity selection cursor and playhead independent" {
    const Model = Sequencer(16);
    var model = try Model.init(8, 0b0101, 0);

    try model.select(2, .replace);
    try model.select(5, .extend);
    try std.testing.expectEqual(@as(u32, 0b00111100), model.selection);
    try std.testing.expectEqual(@as(u32, 0b00111100), model.toggleSelection());
    try std.testing.expectEqual(@as(u32, 0b00111101), model.active);
    try std.testing.expect(try model.setPlayhead(3));
    try std.testing.expectEqual(@as(?u5, 3), model.playhead);
    try std.testing.expectEqual(@as(u32, 0b00111100), model.selection);
}

test "sequencer wraps navigation and supports additive selection" {
    const Model = Sequencer(8);
    var model = try Model.init(4, 0, 1);

    try std.testing.expect(model.moveCursor(.previous, false));
    try std.testing.expectEqual(@as(u5, 3), model.cursor);
    try model.select(1, .toggle);
    try std.testing.expectEqual(@as(u32, 0b1010), model.selection);
    model.selectAll();
    try std.testing.expectEqual(@as(u32, 0b1111), model.selection);
    model.clearSelection();
    try std.testing.expectEqual(@as(u32, 0), model.selection);
}

test "sequencer validates bounded state and painting" {
    const Model = Sequencer(8);
    try std.testing.expectError(error.InvalidStepCount, Model.init(0, 0, 0));
    try std.testing.expectError(error.StepOutsideRange, Model.init(4, 0b10000, 0));
    var model = try Model.init(4, 0, 0);
    try std.testing.expect(try model.paint(2, true));
    try std.testing.expect(!try model.paint(2, true));
    try std.testing.expectError(error.StepOutsideRange, model.setPlayhead(4));
}
