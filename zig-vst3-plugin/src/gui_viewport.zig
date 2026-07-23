const std = @import("std");

pub const Axes = enum {
    horizontal,
    vertical,
    both,

    pub fn includesHorizontal(self: Axes) bool {
        return self != .vertical;
    }

    pub fn includesVertical(self: Axes) bool {
        return self != .horizontal;
    }
};

pub const Config = struct {
    axes: Axes = .horizontal,
    minimum_zoom: f64 = 1.0,
    maximum_zoom: f64 = 32.0,
    initial_zoom: f64 = 1.0,
    initial_x_offset: f64 = 0.0,
    initial_y_offset: f64 = 0.0,
    zoom_step: f64 = 1.25,
    scroll_step: f64 = 0.1,

    pub fn validate(self: Config) !void {
        if (!std.math.isFinite(self.minimum_zoom) or !std.math.isFinite(self.maximum_zoom) or
            self.minimum_zoom < 1.0 or self.maximum_zoom < self.minimum_zoom or self.maximum_zoom > 128.0)
        {
            return error.InvalidZoomRange;
        }
        if (!std.math.isFinite(self.initial_zoom) or
            self.initial_zoom < self.minimum_zoom or self.initial_zoom > self.maximum_zoom)
        {
            return error.InvalidInitialZoom;
        }
        if (!std.math.isFinite(self.zoom_step) or self.zoom_step <= 1.0 or self.zoom_step > 4.0) {
            return error.InvalidZoomStep;
        }
        if (!std.math.isFinite(self.scroll_step) or self.scroll_step <= 0.0 or self.scroll_step > 1.0) {
            return error.InvalidScrollStep;
        }
        try validateOffset(self.initial_x_offset, self.axes.includesHorizontal(), self.initial_zoom);
        try validateOffset(self.initial_y_offset, self.axes.includesVertical(), self.initial_zoom);
    }
};

pub const State = struct {
    zoom: f64,
    x_offset: f64,
    y_offset: f64,

    pub fn init(config: Config) !State {
        try config.validate();
        return .{
            .zoom = config.initial_zoom,
            .x_offset = config.initial_x_offset,
            .y_offset = config.initial_y_offset,
        };
    }

    pub fn visibleSpan(self: State, active: bool) f64 {
        return if (active) 1.0 / self.zoom else 1.0;
    }

    pub fn project(self: State, config: Config, normalized: f64, horizontal: bool) f64 {
        const active = if (horizontal) config.axes.includesHorizontal() else config.axes.includesVertical();
        const offset = if (horizontal) self.x_offset else self.y_offset;
        return (normalized - offset) / self.visibleSpan(active);
    }

    pub fn unproject(self: State, config: Config, visible: f64, horizontal: bool) f64 {
        const active = if (horizontal) config.axes.includesHorizontal() else config.axes.includesVertical();
        const offset = if (horizontal) self.x_offset else self.y_offset;
        return offset + visible * self.visibleSpan(active);
    }

    pub fn setZoom(self: *State, config: Config, requested: f64, anchor_x: f64, anchor_y: f64) bool {
        config.validate() catch return false;
        const next = std.math.clamp(requested, config.minimum_zoom, config.maximum_zoom);
        if (!std.math.isFinite(next) or next == self.zoom) return false;
        if (config.axes.includesHorizontal() and !std.math.isFinite(anchor_x)) return false;
        if (config.axes.includesVertical() and !std.math.isFinite(anchor_y)) return false;
        const old_span = 1.0 / self.zoom;
        const new_span = 1.0 / next;
        if (config.axes.includesHorizontal()) {
            const anchor = std.math.clamp(anchor_x, 0.0, 1.0);
            const content_anchor = self.x_offset + anchor * old_span;
            self.x_offset = std.math.clamp(content_anchor - anchor * new_span, 0.0, 1.0 - new_span);
        }
        if (config.axes.includesVertical()) {
            const anchor = std.math.clamp(anchor_y, 0.0, 1.0);
            const content_anchor = self.y_offset + anchor * old_span;
            self.y_offset = std.math.clamp(content_anchor - anchor * new_span, 0.0, 1.0 - new_span);
        }
        self.zoom = next;
        return true;
    }

    pub fn zoomIn(self: *State, config: Config, anchor_x: f64, anchor_y: f64) bool {
        return self.setZoom(config, self.zoom * config.zoom_step, anchor_x, anchor_y);
    }

    pub fn zoomOut(self: *State, config: Config, anchor_x: f64, anchor_y: f64) bool {
        return self.setZoom(config, self.zoom / config.zoom_step, anchor_x, anchor_y);
    }

    pub fn pan(self: *State, config: Config, x_steps: f64, y_steps: f64) bool {
        config.validate() catch return false;
        var changed = false;
        const span = 1.0 / self.zoom;
        if (config.axes.includesHorizontal() and std.math.isFinite(x_steps)) {
            const next = std.math.clamp(self.x_offset + x_steps * span * config.scroll_step, 0.0, 1.0 - span);
            changed = next != self.x_offset;
            self.x_offset = next;
        }
        if (config.axes.includesVertical() and std.math.isFinite(y_steps)) {
            const next = std.math.clamp(self.y_offset + y_steps * span * config.scroll_step, 0.0, 1.0 - span);
            changed = changed or next != self.y_offset;
            self.y_offset = next;
        }
        return changed;
    }

    pub fn reset(self: *State, config: Config) bool {
        const next = State.init(config) catch return false;
        if (std.meta.eql(self.*, next)) return false;
        self.* = next;
        return true;
    }
};

fn validateOffset(offset: f64, active: bool, zoom: f64) !void {
    if (!std.math.isFinite(offset)) return error.InvalidInitialOffset;
    if (!active and offset != 0.0) return error.InvalidInitialOffset;
    if (active and (offset < 0.0 or offset > 1.0 - 1.0 / zoom)) return error.InvalidInitialOffset;
}

test "viewport zoom preserves its anchor and bounds offsets" {
    const config = Config{ .initial_zoom = 2.0, .initial_x_offset = 0.25 };
    var state = try State.init(config);
    const anchored = state.x_offset + 0.75 / state.zoom;
    try std.testing.expect(state.zoomIn(config, 0.75, 0.5));
    try std.testing.expectApproxEqAbs(anchored, state.x_offset + 0.75 / state.zoom, 1e-12);
    while (state.zoomIn(config, 0.5, 0.5)) {}
    try std.testing.expectEqual(config.maximum_zoom, state.zoom);
    try std.testing.expect(state.x_offset >= 0.0 and state.x_offset <= 1.0 - 1.0 / state.zoom);
}

test "viewport panning is axis aware and bounded" {
    const config = Config{ .axes = .horizontal, .initial_zoom = 4.0 };
    var state = try State.init(config);
    try std.testing.expect(state.pan(config, 100.0, 100.0));
    try std.testing.expectEqual(0.75, state.x_offset);
    try std.testing.expectEqual(0.0, state.y_offset);
    try std.testing.expect(state.pan(config, -100.0, 0.0));
    try std.testing.expectEqual(0.0, state.x_offset);
}

test "viewport declarations reject ambiguous bounds" {
    try std.testing.expectError(error.InvalidZoomRange, (Config{ .minimum_zoom = 0.5 }).validate());
    try std.testing.expectError(error.InvalidInitialZoom, (Config{ .initial_zoom = 64.0, .maximum_zoom = 32.0 }).validate());
    try std.testing.expectError(error.InvalidZoomStep, (Config{ .zoom_step = 1.0 }).validate());
    try std.testing.expectError(error.InvalidScrollStep, (Config{ .scroll_step = 0.0 }).validate());
    try std.testing.expectError(error.InvalidInitialOffset, (Config{ .axes = .horizontal, .initial_y_offset = 0.1 }).validate());
}

test "viewport rejects non-finite active anchors without changing state" {
    const config = Config{ .axes = .both, .initial_zoom = 2.0, .initial_x_offset = 0.25, .initial_y_offset = 0.25 };
    var state = try State.init(config);
    const initial = state;
    try std.testing.expect(!state.setZoom(config, 4.0, std.math.nan(f64), 0.5));
    try std.testing.expectEqual(initial, state);
    try std.testing.expect(!state.setZoom(config, 4.0, 0.5, std.math.inf(f64)));
    try std.testing.expectEqual(initial, state);
}

test "viewport mutations reject invalid replacement configurations" {
    const config = Config{ .axes = .both, .initial_zoom = 2.0, .initial_x_offset = 0.25, .initial_y_offset = 0.25 };
    var state = try State.init(config);
    const initial = state;

    try std.testing.expect(!state.setZoom(.{ .minimum_zoom = 4.0, .maximum_zoom = 2.0 }, 3.0, 0.5, 0.5));
    try std.testing.expectEqual(initial, state);
    try std.testing.expect(!state.zoomIn(.{ .zoom_step = std.math.nan(f64) }, 0.5, 0.5));
    try std.testing.expectEqual(initial, state);
    try std.testing.expect(!state.pan(.{ .scroll_step = std.math.inf(f64) }, 1.0, 1.0));
    try std.testing.expectEqual(initial, state);
}

test "viewport generated transitions preserve finite bounded state" {
    const seed = 0x71e4_90a2_2026_0721;
    var random_state = std.Random.DefaultPrng.init(seed);
    const random = random_state.random();
    const config = Config{ .axes = .both, .minimum_zoom = 1.0, .maximum_zoom = 128.0 };

    for (0..128) |case_index| {
        var state = try State.init(config);
        for (0..256) |operation_index| {
            const inject_non_finite = operation_index % 43 == 0;
            const anchor_x = if (inject_non_finite) std.math.nan(f64) else random.float(f64) * 3.0 - 1.0;
            const anchor_y = if (inject_non_finite) std.math.inf(f64) else random.float(f64) * 3.0 - 1.0;
            switch (random.uintLessThan(u8, 6)) {
                0 => _ = state.setZoom(config, random.float(f64) * 192.0 - 32.0, anchor_x, anchor_y),
                1 => _ = state.zoomIn(config, anchor_x, anchor_y),
                2 => _ = state.zoomOut(config, anchor_x, anchor_y),
                3 => _ = state.pan(config, random.float(f64) * 20.0 - 10.0, random.float(f64) * 20.0 - 10.0),
                4 => _ = state.pan(config, std.math.nan(f64), std.math.inf(f64)),
                else => _ = state.reset(config),
            }
            const span = 1.0 / state.zoom;
            const valid = std.math.isFinite(state.zoom) and
                state.zoom >= config.minimum_zoom and state.zoom <= config.maximum_zoom and
                std.math.isFinite(state.x_offset) and state.x_offset >= 0.0 and state.x_offset <= 1.0 - span and
                std.math.isFinite(state.y_offset) and state.y_offset >= 0.0 and state.y_offset <= 1.0 - span;
            if (!valid) {
                std.debug.print("viewport seed={x} case={} operation={}\n", .{ seed, case_index, operation_index });
                return error.GeneratedViewportInvariantFailed;
            }
        }
    }
}
