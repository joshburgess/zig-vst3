const std = @import("std");

pub const Handle = enum {
    start,
    end,
};

pub const Config = struct {
    minimum: f64,
    maximum: f64,
    initial_start: f64,
    initial_end: f64,
    minimum_span: f64 = 0.0,
    step: f64,

    pub fn validate(self: Config) !void {
        const values = [_]f64{
            self.minimum,
            self.maximum,
            self.initial_start,
            self.initial_end,
            self.minimum_span,
            self.step,
        };
        for (values) |value| {
            if (!std.math.isFinite(value)) return error.NonFiniteRangeSelectionValue;
        }
        const span = self.maximum - self.minimum;
        if (span <= 0.0) return error.InvalidRangeSelectionBounds;
        if (self.initial_start < self.minimum or self.initial_end > self.maximum or
            self.initial_end < self.initial_start) return error.InvalidInitialRangeSelection;
        if (self.minimum_span < 0.0 or self.minimum_span > span or
            self.initial_end - self.initial_start < self.minimum_span) return error.InvalidRangeSelectionSpan;
        if (self.step <= 0.0 or self.step > span) return error.InvalidRangeSelectionStep;
    }
};

pub const State = struct {
    start: f64,
    end: f64,
    active: Handle = .start,

    pub fn init(config: Config) !State {
        try config.validate();
        return .{ .start = config.initial_start, .end = config.initial_end };
    }

    pub fn selectHandle(self: *State, handle: Handle) void {
        self.active = handle;
    }

    pub fn set(self: *State, config: Config, handle: Handle, target: f64) bool {
        if (!std.math.isFinite(target)) return false;
        const previous = self.*;
        switch (handle) {
            .start => self.start = std.math.clamp(target, config.minimum, self.end - config.minimum_span),
            .end => self.end = std.math.clamp(target, self.start + config.minimum_span, config.maximum),
        }
        self.active = handle;
        return self.start != previous.start or self.end != previous.end or self.active != previous.active;
    }

    pub fn adjust(self: *State, config: Config, delta: f64) bool {
        return self.set(config, self.active, self.value(self.active) + delta);
    }

    pub fn replace(self: *State, config: Config, first: f64, second: f64) bool {
        if (!std.math.isFinite(first) or !std.math.isFinite(second)) return false;
        const low = std.math.clamp(@min(first, second), config.minimum, config.maximum);
        const high = std.math.clamp(@max(first, second), config.minimum, config.maximum);
        const previous = self.*;
        if (high - low >= config.minimum_span) {
            self.start = low;
            self.end = high;
        } else if (second >= first) {
            self.start = low;
            self.end = @min(config.maximum, low + config.minimum_span);
            if (self.end - self.start < config.minimum_span) self.start = self.end - config.minimum_span;
        } else {
            self.end = high;
            self.start = @max(config.minimum, high - config.minimum_span);
            if (self.end - self.start < config.minimum_span) self.end = self.start + config.minimum_span;
        }
        self.active = if (second >= first) .end else .start;
        return self.start != previous.start or self.end != previous.end or self.active != previous.active;
    }

    pub fn value(self: State, handle: Handle) f64 {
        return switch (handle) {
            .start => self.start,
            .end => self.end,
        };
    }
};

test "range selection validates bounds span and step" {
    try (Config{
        .minimum = 0.0,
        .maximum = 1.0,
        .initial_start = 0.25,
        .initial_end = 0.75,
        .minimum_span = 0.1,
        .step = 0.01,
    }).validate();
    try std.testing.expectError(error.InvalidRangeSelectionSpan, (Config{
        .minimum = 0.0,
        .maximum = 1.0,
        .initial_start = 0.25,
        .initial_end = 0.3,
        .minimum_span = 0.1,
        .step = 0.01,
    }).validate());
}

test "range selection clamps handles without crossing" {
    const config = Config{
        .minimum = 0.0,
        .maximum = 1.0,
        .initial_start = 0.2,
        .initial_end = 0.8,
        .minimum_span = 0.1,
        .step = 0.01,
    };
    var state = try State.init(config);
    try std.testing.expect(state.set(config, .start, 0.9));
    try std.testing.expectApproxEqAbs(0.7, state.start, 1e-12);
    try std.testing.expect(state.set(config, .end, -1.0));
    try std.testing.expectApproxEqAbs(0.8, state.end, 1e-12);
}

test "range selection replacement preserves direction and minimum span" {
    const config = Config{
        .minimum = 0.0,
        .maximum = 1.0,
        .initial_start = 0.0,
        .initial_end = 1.0,
        .minimum_span = 0.2,
        .step = 0.01,
    };
    var state = try State.init(config);
    try std.testing.expect(state.replace(config, 0.6, 0.65));
    try std.testing.expectApproxEqAbs(0.6, state.start, 1e-12);
    try std.testing.expectApproxEqAbs(0.8, state.end, 1e-12);
    try std.testing.expectEqual(Handle.end, state.active);
    try std.testing.expect(state.replace(config, 0.7, 0.4));
    try std.testing.expectApproxEqAbs(0.4, state.start, 1e-12);
    try std.testing.expectApproxEqAbs(0.7, state.end, 1e-12);
    try std.testing.expectEqual(Handle.start, state.active);
}
