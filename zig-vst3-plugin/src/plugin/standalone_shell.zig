const std = @import("std");
const gui = @import("../gui.zig");
const device_catalog = @import("device_catalog.zig");

pub const maximum_device_failure_sources = 8;

pub const WindowEvent = union(enum) {
    none,
    close_requested,
    resized: gui.Size,
    scale_changed: gui.Scale,
    focus_changed: bool,
};

pub const WindowBackend = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        open: *const fn (
            *anyopaque,
            gui.Size,
            gui.Scale,
        ) anyerror!gui.NativeParent,
        close: *const fn (*anyopaque) void,
        show: *const fn (*anyopaque) anyerror!void,
        hide: *const fn (*anyopaque) anyerror!void,
        request_resize: *const fn (
            *anyopaque,
            gui.Size,
        ) anyerror!gui.Size,
        poll_event: *const fn (*anyopaque) anyerror!WindowEvent,
        destroy: *const fn (*anyopaque) void,
    };
};

pub const EventPumpReport = struct {
    processed: usize = 0,
    quit_requested: bool = false,
    resize_count: usize = 0,
    scale_count: usize = 0,
    focus_count: usize = 0,
};

pub const StandaloneWindow = struct {
    editor: gui.Editor,
    backend: WindowBackend,
    opened: bool = false,
    visible: bool = false,
    focused: bool = false,
    quit_requested: bool = false,
    destroyed: bool = false,

    pub fn init(
        editor: gui.Editor,
        backend: WindowBackend,
    ) StandaloneWindow {
        return .{
            .editor = editor,
            .backend = backend,
        };
    }

    /// Keep the window at a stable address from `open` through `deinit`
    pub fn open(self: *StandaloneWindow) !void {
        if (self.destroyed) return error.WindowDestroyed;
        if (self.opened) return error.WindowAlreadyOpen;
        try validateSize(self.editor.size);
        if (!self.editor.scale.valid()) return error.InvalidWindowScale;

        const parent = try self.backend.vtable.open(
            self.backend.context,
            self.editor.size,
            self.editor.scale,
        );
        self.editor.attach(parent) catch |attach_error| {
            self.backend.vtable.close(self.backend.context);
            return attach_error;
        };
        self.opened = true;
        self.quit_requested = false;
    }

    pub fn close(self: *StandaloneWindow) void {
        if (!self.opened) return;
        self.editor.setFocus(false);
        self.editor.detach();
        self.backend.vtable.close(self.backend.context);
        self.opened = false;
        self.visible = false;
        self.focused = false;
    }

    pub fn show(self: *StandaloneWindow) !void {
        try self.requireOpen();
        if (self.visible) return;
        try self.backend.vtable.show(self.backend.context);
        self.visible = true;
    }

    pub fn hide(self: *StandaloneWindow) !void {
        try self.requireOpen();
        if (!self.visible) return;
        try self.backend.vtable.hide(self.backend.context);
        self.visible = false;
    }

    pub fn requestResize(
        self: *StandaloneWindow,
        requested: gui.Size,
    ) !gui.Size {
        try self.requireOpen();
        try validateSize(requested);
        const accepted = try self.backend.vtable.request_resize(
            self.backend.context,
            gui.constrained(self.editor.resize_policy, requested),
        );
        try validateSize(accepted);
        try self.editor.hostResize(accepted);
        return accepted;
    }

    pub fn pump(
        self: *StandaloneWindow,
        maximum_events: usize,
    ) !EventPumpReport {
        try self.requireOpen();
        if (maximum_events == 0) return error.InvalidWindowEventBudget;

        var report = EventPumpReport{
            .quit_requested = self.quit_requested,
        };
        if (report.quit_requested) return report;
        while (report.processed < maximum_events) {
            const event = try self.backend.vtable.poll_event(
                self.backend.context,
            );
            switch (event) {
                .none => return report,
                .close_requested => {
                    report.processed += 1;
                    report.quit_requested = true;
                    self.quit_requested = true;
                    return report;
                },
                .resized => |size| {
                    try validateSize(size);
                    try self.editor.hostResize(size);
                    report.resize_count += 1;
                },
                .scale_changed => |scale| {
                    if (!scale.valid()) return error.InvalidWindowScale;
                    try self.editor.setScale(scale);
                    report.scale_count += 1;
                },
                .focus_changed => |focused| {
                    self.editor.setFocus(focused);
                    self.focused = focused;
                    report.focus_count += 1;
                },
            }
            report.processed += 1;
        }
        return report;
    }

    pub fn deinit(self: *StandaloneWindow) void {
        if (self.destroyed) return;
        self.close();
        self.editor.deinit();
        self.backend.vtable.destroy(self.backend.context);
        self.destroyed = true;
    }

    fn requireOpen(self: *const StandaloneWindow) !void {
        if (self.destroyed) return error.WindowDestroyed;
        if (!self.opened) return error.WindowNotOpen;
    }
};

pub const ControlCycleReport = struct {
    window: EventPumpReport,
    device_failures: device_catalog.DeviceFailureReport,
    recovery: device_catalog.DeviceRecoveryResult,
};

pub fn StandaloneShell(comptime catalog_capacity: usize) type {
    if (catalog_capacity == 0)
        @compileError("StandaloneShell requires a device catalog capacity");

    return struct {
        window: StandaloneWindow,
        recovery: device_catalog.DeviceRecoveryController,
        failure_monitors: device_catalog.DeviceFailureMonitorSet(
            maximum_device_failure_sources,
        ) = .{},

        pub fn init(
            editor: gui.Editor,
            backend: WindowBackend,
            requested_devices: device_catalog.DeviceSelection,
        ) !@This() {
            return .{
                .window = StandaloneWindow.init(editor, backend),
                .recovery = try device_catalog.DeviceRecoveryController.init(
                    requested_devices,
                ),
            };
        }

        pub fn pumpControlCycle(
            self: *@This(),
            catalog: *const device_catalog.DeviceCatalog(catalog_capacity),
            recovery_callback: device_catalog.DeviceRecoveryCallback,
            maximum_events: usize,
        ) !ControlCycleReport {
            const window_report = try self.window.pump(maximum_events);
            if (window_report.quit_requested) {
                return .{
                    .window = window_report,
                    .device_failures = .{},
                    .recovery = .unchanged,
                };
            }
            const device_failures =
                try self.failure_monitors.poll();
            if (device_failures.any())
                self.recovery.requestRecovery();
            return .{
                .window = window_report,
                .device_failures = device_failures,
                .recovery = try self.recovery.reconcileAndApply(
                    catalog,
                    recovery_callback,
                ),
            };
        }

        pub fn setRequestedDevices(
            self: *@This(),
            selection: device_catalog.DeviceSelection,
        ) !void {
            try self.recovery.setRequested(selection);
        }

        pub fn requestDeviceRecovery(self: *@This()) void {
            self.recovery.requestRecovery();
        }

        pub fn setDeviceFailureSource(
            self: *@This(),
            source: device_catalog.DeviceFailureSource,
        ) !void {
            try self.failure_monitors.replace(source);
        }

        pub fn addDeviceFailureSource(
            self: *@This(),
            source: device_catalog.DeviceFailureSource,
        ) !void {
            try self.failure_monitors.add(source);
        }

        pub fn clearDeviceFailureSources(self: *@This()) void {
            self.failure_monitors.clear();
        }

        pub fn deinit(self: *@This()) void {
            self.window.deinit();
        }
    };
}

fn validateSize(size: gui.Size) !void {
    if (size.width == 0 or size.height == 0)
        return error.InvalidWindowSize;
}

const TestState = struct {
    const maximum_events = 8;

    attach_fails: bool = false,
    resize_fails: bool = false,
    open_count: usize = 0,
    close_count: usize = 0,
    show_count: usize = 0,
    hide_count: usize = 0,
    attach_count: usize = 0,
    detach_count: usize = 0,
    editor_destroy_count: usize = 0,
    backend_destroy_count: usize = 0,
    resize_count: usize = 0,
    scale_count: usize = 0,
    focus_count: usize = 0,
    last_size: gui.Size = .{ .width = 0, .height = 0 },
    last_scale: gui.Scale = .{},
    last_focus: bool = false,
    events: [maximum_events]WindowEvent = undefined,
    event_count: usize = 0,
    event_index: usize = 0,

    fn context(self: *TestState) gui.Context {
        return .{
            .userdata = self,
            .vtable = &context_vtable,
        };
    }

    fn adapter(self: *TestState) gui.Adapter {
        return .{
            .userdata = self,
            .vtable = &adapter_vtable,
        };
    }

    fn backend(self: *TestState) WindowBackend {
        return .{
            .context = self,
            .vtable = &window_vtable,
        };
    }

    fn editor(self: *TestState) gui.Editor {
        return .{
            .context = self.context(),
            .adapter = self.adapter(),
            .size = .{ .width = 640, .height = 480 },
            .resize_policy = .{
                .resizable = .{
                    .minimum = .{ .width = 320, .height = 240 },
                    .maximum = .{ .width = 1280, .height = 960 },
                },
            },
        };
    }

    fn queue(self: *TestState, event: WindowEvent) !void {
        if (self.event_count == self.events.len)
            return error.TestEventCapacityExceeded;
        self.events[self.event_count] = event;
        self.event_count += 1;
    }

    fn beginEdit(_: *anyopaque, _: gui.ParameterId) gui.Error!void {}

    fn performEdit(
        _: *anyopaque,
        _: gui.ParameterId,
        _: gui.NormalizedValue,
    ) gui.Error!void {}

    fn endEdit(_: *anyopaque, _: gui.ParameterId) void {}

    fn value(_: *anyopaque, _: gui.ParameterId) ?gui.NormalizedValue {
        return 0.5;
    }

    fn metadata(_: *anyopaque, id: gui.ParameterId) ?gui.ParameterMetadata {
        return .{
            .id = id,
            .name = "Value",
            .short_name = "Value",
            .units = "",
            .default_normalized = 0.5,
            .step_count = 0,
        };
    }

    fn format(
        _: *anyopaque,
        _: gui.ParameterId,
        _: gui.NormalizedValue,
        output: []u8,
    ) gui.Error!usize {
        if (output.len == 0) return error.Rejected;
        output[0] = '0';
        return 1;
    }

    fn parse(
        _: *anyopaque,
        _: gui.ParameterId,
        _: []const u8,
    ) gui.Error!gui.NormalizedValue {
        return 0.5;
    }

    fn contextResize(
        _: *anyopaque,
        size: gui.Size,
    ) gui.Error!gui.Size {
        return size;
    }

    fn repaint(_: *anyopaque) void {}

    fn contextMenu(
        _: *anyopaque,
        _: gui.ParameterId,
        _: i32,
        _: i32,
    ) gui.Error!void {}

    fn attach(
        raw: *anyopaque,
        _: gui.NativeParent,
        size: gui.Size,
        initial_scale: gui.Scale,
    ) gui.Error!void {
        const self: *TestState = @ptrCast(@alignCast(raw));
        if (self.attach_fails) return error.Rejected;
        self.attach_count += 1;
        self.last_size = size;
        self.last_scale = initial_scale;
    }

    fn detach(raw: *anyopaque) void {
        const self: *TestState = @ptrCast(@alignCast(raw));
        self.detach_count += 1;
    }

    fn resize(raw: *anyopaque, size: gui.Size) gui.Error!void {
        const self: *TestState = @ptrCast(@alignCast(raw));
        if (self.resize_fails) return error.Rejected;
        self.resize_count += 1;
        self.last_size = size;
    }

    fn scale(raw: *anyopaque, value_to_set: gui.Scale) gui.Error!void {
        const self: *TestState = @ptrCast(@alignCast(raw));
        self.scale_count += 1;
        self.last_scale = value_to_set;
    }

    fn focus(raw: *anyopaque, focused: bool) void {
        const self: *TestState = @ptrCast(@alignCast(raw));
        self.focus_count += 1;
        self.last_focus = focused;
    }

    fn parameterChanged(
        _: *anyopaque,
        _: gui.ParameterId,
        _: gui.NormalizedValue,
    ) void {}

    fn destroyEditor(raw: *anyopaque) void {
        const self: *TestState = @ptrCast(@alignCast(raw));
        self.editor_destroy_count += 1;
    }

    fn openWindow(
        raw: *anyopaque,
        size: gui.Size,
        scale_value: gui.Scale,
    ) !gui.NativeParent {
        const self: *TestState = @ptrCast(@alignCast(raw));
        self.open_count += 1;
        self.last_size = size;
        self.last_scale = scale_value;
        return .{ .platform = .x11, .handle = self };
    }

    fn closeWindow(raw: *anyopaque) void {
        const self: *TestState = @ptrCast(@alignCast(raw));
        self.close_count += 1;
    }

    fn showWindow(raw: *anyopaque) !void {
        const self: *TestState = @ptrCast(@alignCast(raw));
        self.show_count += 1;
    }

    fn hideWindow(raw: *anyopaque) !void {
        const self: *TestState = @ptrCast(@alignCast(raw));
        self.hide_count += 1;
    }

    fn requestWindowResize(
        _: *anyopaque,
        size: gui.Size,
    ) !gui.Size {
        return size;
    }

    fn pollEvent(raw: *anyopaque) !WindowEvent {
        const self: *TestState = @ptrCast(@alignCast(raw));
        if (self.event_index == self.event_count) return .none;
        const event = self.events[self.event_index];
        self.event_index += 1;
        return event;
    }

    fn destroyBackend(raw: *anyopaque) void {
        const self: *TestState = @ptrCast(@alignCast(raw));
        self.backend_destroy_count += 1;
    }

    const context_vtable = gui.Context.VTable{
        .begin_edit = beginEdit,
        .perform_edit = performEdit,
        .end_edit = endEdit,
        .value = value,
        .metadata = metadata,
        .format = format,
        .parse = parse,
        .request_resize = contextResize,
        .request_repaint = repaint,
        .open_context_menu = contextMenu,
    };

    const adapter_vtable = gui.Adapter.VTable{
        .attach = attach,
        .detach = detach,
        .resize = resize,
        .scale = scale,
        .focus = focus,
        .parameter_changed = parameterChanged,
        .destroy = destroyEditor,
    };

    const window_vtable = WindowBackend.VTable{
        .open = openWindow,
        .close = closeWindow,
        .show = showWindow,
        .hide = hideWindow,
        .request_resize = requestWindowResize,
        .poll_event = pollEvent,
        .destroy = destroyBackend,
    };
};

test "standalone window owns attach visibility events and teardown" {
    var state = TestState{};
    var window = StandaloneWindow.init(
        state.editor(),
        state.backend(),
    );
    try window.open();
    try window.show();
    try window.show();
    try std.testing.expectEqual(
        gui.Size{ .width = 1280, .height = 240 },
        try window.requestResize(.{
            .width = 2000,
            .height = 100,
        }),
    );
    try state.queue(.{
        .resized = .{ .width = 800, .height = 600 },
    });
    try state.queue(.{
        .scale_changed = .{ .x = 2.0, .y = 2.0 },
    });
    try state.queue(.{ .focus_changed = true });
    const report = try window.pump(8);
    try std.testing.expectEqual(@as(usize, 3), report.processed);
    try std.testing.expectEqual(@as(usize, 1), report.resize_count);
    try std.testing.expectEqual(@as(usize, 1), report.scale_count);
    try std.testing.expectEqual(@as(usize, 1), report.focus_count);
    try std.testing.expect(window.focused);
    try window.hide();
    try window.hide();
    window.deinit();
    window.deinit();

    try std.testing.expectEqual(@as(usize, 1), state.open_count);
    try std.testing.expectEqual(@as(usize, 1), state.close_count);
    try std.testing.expectEqual(@as(usize, 1), state.show_count);
    try std.testing.expectEqual(@as(usize, 1), state.hide_count);
    try std.testing.expectEqual(@as(usize, 1), state.attach_count);
    try std.testing.expectEqual(@as(usize, 1), state.detach_count);
    try std.testing.expectEqual(@as(usize, 1), state.editor_destroy_count);
    try std.testing.expectEqual(@as(usize, 1), state.backend_destroy_count);
}

test "standalone window rolls back failed attachment and event updates" {
    var state = TestState{ .attach_fails = true };
    var window = StandaloneWindow.init(
        state.editor(),
        state.backend(),
    );
    defer window.deinit();
    try std.testing.expectError(error.Rejected, window.open());
    try std.testing.expect(!window.opened);
    try std.testing.expectEqual(@as(usize, 1), state.close_count);

    state.attach_fails = false;
    try window.open();
    const previous_size = window.editor.size;
    state.resize_fails = true;
    try state.queue(.{
        .resized = .{ .width = 900, .height = 700 },
    });
    try std.testing.expectError(error.Rejected, window.pump(1));
    try std.testing.expectEqual(previous_size, window.editor.size);
    try std.testing.expectError(
        error.InvalidWindowEventBudget,
        window.pump(0),
    );
}

test "standalone shell coordinates recovery and close requests" {
    const fallback = try device_catalog.DeviceDescriptor.init(
        .audio,
        "audio:fallback",
        "Fallback",
        2,
        2,
        true,
    );
    const preferred = try device_catalog.DeviceDescriptor.init(
        .audio,
        "audio:preferred",
        "Preferred",
        2,
        2,
        false,
    );
    const RecoveryProbe = struct {
        count: usize = 0,
        last: device_catalog.DeviceSelection = .{},

        fn apply(
            raw: *anyopaque,
            selection: device_catalog.DeviceSelection,
            _: device_catalog.DeviceSelectionResolution,
            _: device_catalog.DeviceRecoveryReason,
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.count += 1;
            self.last = selection;
        }
    };
    const FailureProbe = struct {
        snapshot: device_catalog.DeviceFailureSnapshot = .{},

        fn read(
            raw: *anyopaque,
        ) !device_catalog.DeviceFailureSnapshot {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return self.snapshot;
        }

        fn source(self: *@This()) device_catalog.DeviceFailureSource {
            return .{
                .context = self,
                .read_snapshot = read,
            };
        }
    };

    var state = TestState{};
    const Shell = StandaloneShell(2);
    var shell = try Shell.init(
        state.editor(),
        state.backend(),
        .{ .audio = preferred.identifier },
    );
    defer shell.deinit();
    try shell.window.open();

    var catalog = device_catalog.DeviceCatalog(2){};
    try catalog.replace(&.{ fallback, preferred });
    var recovery_probe = RecoveryProbe{};
    const recovery_callback = device_catalog.DeviceRecoveryCallback{
        .context = &recovery_probe,
        .apply_recovery = RecoveryProbe.apply,
    };
    const initial = try shell.pumpControlCycle(
        &catalog,
        recovery_callback,
        4,
    );
    try std.testing.expectEqual(
        device_catalog.DeviceRecoveryResult.applied,
        initial.recovery,
    );
    try std.testing.expect(
        recovery_probe.last.audio.?.eql(&preferred.identifier),
    );

    var failure_probe = FailureProbe{};
    try shell.setDeviceFailureSource(failure_probe.source());
    failure_probe.snapshot.audio = 1;
    const failed = try shell.pumpControlCycle(
        &catalog,
        recovery_callback,
        4,
    );
    try std.testing.expect(failed.device_failures.audio);
    try std.testing.expectEqual(
        device_catalog.DeviceRecoveryResult.applied,
        failed.recovery,
    );

    var midi_failure_probe = FailureProbe{};
    try shell.addDeviceFailureSource(
        midi_failure_probe.source(),
    );
    midi_failure_probe.snapshot.midi_input = 1;
    const midi_failed = try shell.pumpControlCycle(
        &catalog,
        recovery_callback,
        4,
    );
    try std.testing.expect(midi_failed.device_failures.midi_input);
    try std.testing.expectEqual(
        device_catalog.DeviceRecoveryResult.applied,
        midi_failed.recovery,
    );

    shell.clearDeviceFailureSources();
    failure_probe.snapshot.audio = 2;
    midi_failure_probe.snapshot.midi_input = 2;
    const cleared = try shell.pumpControlCycle(
        &catalog,
        recovery_callback,
        4,
    );
    try std.testing.expect(!cleared.device_failures.any());
    try std.testing.expectEqual(
        device_catalog.DeviceRecoveryResult.unchanged,
        cleared.recovery,
    );

    try catalog.replace(&.{fallback});
    const changed = try shell.pumpControlCycle(
        &catalog,
        recovery_callback,
        4,
    );
    try std.testing.expectEqual(
        device_catalog.DeviceRecoveryResult.applied,
        changed.recovery,
    );
    try std.testing.expect(
        recovery_probe.last.audio.?.eql(&fallback.identifier),
    );

    try state.queue(.close_requested);
    const closing = try shell.pumpControlCycle(
        &catalog,
        recovery_callback,
        4,
    );
    try std.testing.expect(closing.window.quit_requested);
    try std.testing.expectEqual(
        device_catalog.DeviceRecoveryResult.unchanged,
        closing.recovery,
    );
    try std.testing.expectEqual(@as(usize, 4), recovery_probe.count);
}
