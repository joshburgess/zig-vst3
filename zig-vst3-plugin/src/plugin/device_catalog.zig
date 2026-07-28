const std = @import("std");

pub const maximum_device_identifier_bytes = 128;
pub const maximum_device_name_bytes = 128;

pub const DeviceKind = enum(u8) {
    audio,
    midi_input,
    midi_output,
    audio_input,
    audio_output,
};

pub const DeviceIdentifier = struct {
    storage: [maximum_device_identifier_bytes]u8 = undefined,
    length: u8 = 0,

    pub fn init(value: []const u8) !DeviceIdentifier {
        if (value.len == 0)
            return error.EmptyDeviceIdentifier;
        if (value.len > maximum_device_identifier_bytes)
            return error.DeviceIdentifierTooLong;
        if (!std.unicode.utf8ValidateSlice(value) or
            std.mem.indexOfScalar(u8, value, 0) != null)
            return error.InvalidDeviceIdentifier;
        var identifier = DeviceIdentifier{};
        @memcpy(identifier.storage[0..value.len], value);
        identifier.length = @intCast(value.len);
        return identifier;
    }

    pub fn slice(self: *const DeviceIdentifier) []const u8 {
        return self.storage[0..self.length];
    }

    pub fn eql(
        self: *const DeviceIdentifier,
        other: *const DeviceIdentifier,
    ) bool {
        return std.mem.eql(u8, self.slice(), other.slice());
    }

    pub fn valid(self: *const DeviceIdentifier) bool {
        if (self.length == 0 or
            self.length > maximum_device_identifier_bytes)
            return false;
        const value = self.slice();
        return std.unicode.utf8ValidateSlice(value) and
            std.mem.indexOfScalar(u8, value, 0) == null;
    }
};

pub const DeviceDescriptor = struct {
    kind: DeviceKind,
    identifier: DeviceIdentifier,
    name_storage: [maximum_device_name_bytes]u8 = undefined,
    name_length: u8,
    input_channel_count: u8 = 0,
    output_channel_count: u8 = 0,
    is_default: bool = false,

    pub fn init(
        kind: DeviceKind,
        identifier: []const u8,
        display_name: []const u8,
        input_channel_count: u8,
        output_channel_count: u8,
        is_default: bool,
    ) !DeviceDescriptor {
        if (display_name.len == 0) return error.EmptyDeviceName;
        if (display_name.len > maximum_device_name_bytes)
            return error.DeviceNameTooLong;
        if (!std.unicode.utf8ValidateSlice(display_name) or
            std.mem.indexOfScalar(u8, display_name, 0) != null)
            return error.InvalidDeviceName;
        switch (kind) {
            .audio => if (input_channel_count == 0 and
                output_channel_count == 0)
                return error.AudioDeviceHasNoChannels,
            .audio_input => if (input_channel_count == 0 or
                output_channel_count != 0)
                return error.InvalidAudioInputDeviceChannels,
            .audio_output => if (input_channel_count != 0 or
                output_channel_count == 0)
                return error.InvalidAudioOutputDeviceChannels,
            .midi_input, .midi_output => if (input_channel_count != 0 or
                output_channel_count != 0)
                return error.InvalidMidiDeviceChannels,
        }

        var descriptor = DeviceDescriptor{
            .kind = kind,
            .identifier = try DeviceIdentifier.init(identifier),
            .name_length = @intCast(display_name.len),
            .input_channel_count = input_channel_count,
            .output_channel_count = output_channel_count,
            .is_default = is_default,
        };
        @memcpy(
            descriptor.name_storage[0..display_name.len],
            display_name,
        );
        return descriptor;
    }

    pub fn name(self: *const DeviceDescriptor) []const u8 {
        return self.name_storage[0..self.name_length];
    }

    pub fn valid(self: *const DeviceDescriptor) bool {
        if (!self.identifier.valid() or
            self.name_length == 0 or
            self.name_length > maximum_device_name_bytes)
            return false;
        const device_name = self.name();
        if (!std.unicode.utf8ValidateSlice(device_name) or
            std.mem.indexOfScalar(u8, device_name, 0) != null)
            return false;
        return switch (self.kind) {
            .audio => self.input_channel_count != 0 or
                self.output_channel_count != 0,
            .audio_input => self.input_channel_count != 0 and
                self.output_channel_count == 0,
            .audio_output => self.input_channel_count == 0 and
                self.output_channel_count != 0,
            .midi_input, .midi_output => self.input_channel_count == 0 and
                self.output_channel_count == 0,
        };
    }
};

pub fn DeviceCatalog(comptime capacity: usize) type {
    if (capacity == 0)
        @compileError("DeviceCatalog capacity must be positive");

    return struct {
        descriptors: [capacity]DeviceDescriptor = undefined,
        count: usize = 0,
        current_generation: u64 = 0,

        pub fn replace(
            self: *@This(),
            descriptors: []const DeviceDescriptor,
        ) !void {
            if (descriptors.len > capacity)
                return error.DeviceCatalogCapacityExceeded;
            try validateDescriptors(descriptors);

            var next: [capacity]DeviceDescriptor = undefined;
            @memcpy(next[0..descriptors.len], descriptors);
            self.descriptors = next;
            self.count = descriptors.len;
            self.current_generation +%= 1;
            if (self.current_generation == 0)
                self.current_generation = 1;
        }

        pub fn generation(self: *const @This()) u64 {
            return self.current_generation;
        }

        pub fn valid(self: *const @This()) bool {
            if (self.count > capacity) return false;
            validateDescriptors(self.descriptors[0..self.count]) catch return false;
            return true;
        }

        pub fn items(self: *const @This()) []const DeviceDescriptor {
            return self.descriptors[0..@min(self.count, capacity)];
        }

        pub fn find(
            self: *const @This(),
            kind: DeviceKind,
            identifier: DeviceIdentifier,
        ) ?*const DeviceDescriptor {
            if (!self.valid() or !identifier.valid()) return null;
            for (self.items()) |*descriptor| {
                if (descriptor.kind == kind and
                    descriptor.identifier.eql(&identifier))
                    return descriptor;
            }
            return null;
        }

        pub fn resolve(
            self: *const @This(),
            kind: DeviceKind,
            requested: ?DeviceIdentifier,
        ) ?*const DeviceDescriptor {
            if (!self.valid()) return null;
            if (requested) |identifier| {
                if (self.find(kind, identifier)) |descriptor|
                    return descriptor;
            }
            for (self.items()) |*descriptor| {
                if (descriptor.kind == kind and
                    descriptor.is_default)
                    return descriptor;
            }
            for (self.items()) |*descriptor| {
                if (descriptor.kind == kind) return descriptor;
            }
            return null;
        }
    };
}

pub const DeviceSelection = struct {
    pub const maximum_encoded_size =
        4 + 2 + 5 * (2 + maximum_device_identifier_bytes);

    audio: ?DeviceIdentifier = null,
    audio_input: ?DeviceIdentifier = null,
    audio_output: ?DeviceIdentifier = null,
    midi_input: ?DeviceIdentifier = null,
    midi_output: ?DeviceIdentifier = null,

    pub fn valid(self: *const DeviceSelection) bool {
        return optionalIdentifierValid(self.audio) and
            optionalIdentifierValid(self.audio_input) and
            optionalIdentifierValid(self.audio_output) and
            optionalIdentifierValid(self.midi_input) and
            optionalIdentifierValid(self.midi_output);
    }

    pub fn writeTo(
        self: *const DeviceSelection,
        writer: anytype,
    ) !void {
        try writer.writeAll("DVSL");
        try writer.writeInt(u16, 2, .little);
        try writeOptionalIdentifier(writer, self.audio);
        try writeOptionalIdentifier(writer, self.audio_input);
        try writeOptionalIdentifier(writer, self.audio_output);
        try writeOptionalIdentifier(writer, self.midi_input);
        try writeOptionalIdentifier(writer, self.midi_output);
    }

    pub fn readFrom(
        self: *DeviceSelection,
        reader: anytype,
    ) !void {
        var magic: [4]u8 = undefined;
        try reader.readSliceAll(&magic);
        if (!std.mem.eql(u8, &magic, "DVSL"))
            return error.InvalidDeviceSelection;
        const version = try reader.takeInt(u16, .little);
        const next = switch (version) {
            1 => DeviceSelection{
                .audio = try readOptionalIdentifier(reader),
                .midi_input = try readOptionalIdentifier(reader),
                .midi_output = try readOptionalIdentifier(reader),
            },
            2 => DeviceSelection{
                .audio = try readOptionalIdentifier(reader),
                .audio_input = try readOptionalIdentifier(reader),
                .audio_output = try readOptionalIdentifier(reader),
                .midi_input = try readOptionalIdentifier(reader),
                .midi_output = try readOptionalIdentifier(reader),
            },
            else => return error.UnsupportedDeviceSelection,
        };
        if (reader.seek != reader.end)
            return error.InvalidDeviceSelection;
        self.* = next;
    }
};

pub const DeviceSelectionResolution = struct {
    catalog_generation: u64,
    audio_changed: bool,
    audio_input_changed: bool,
    audio_output_changed: bool,
    midi_input_changed: bool,
    midi_output_changed: bool,
    audio_uses_fallback: bool,
    audio_input_uses_fallback: bool,
    audio_output_uses_fallback: bool,
    midi_input_uses_fallback: bool,
    midi_output_uses_fallback: bool,

    pub fn changed(self: *const DeviceSelectionResolution) bool {
        return self.audio_changed or
            self.audio_input_changed or
            self.audio_output_changed or
            self.midi_input_changed or
            self.midi_output_changed;
    }
};

pub const DeviceSelectionTracker = struct {
    requested: DeviceSelection,
    active: DeviceSelection = .{},
    catalog_generation: u64 = 0,

    pub fn init(
        requested: DeviceSelection,
    ) !DeviceSelectionTracker {
        if (!requested.valid())
            return error.InvalidDeviceSelection;
        return .{ .requested = requested };
    }

    pub fn setRequested(
        self: *DeviceSelectionTracker,
        requested: DeviceSelection,
    ) !void {
        if (!requested.valid())
            return error.InvalidDeviceSelection;
        self.requested = requested;
        self.catalog_generation = 0;
    }

    pub fn reconcile(
        self: *DeviceSelectionTracker,
        catalog: anytype,
    ) !DeviceSelectionResolution {
        if (!self.requested.valid() or
            !self.active.valid() or
            !catalog.valid())
            return error.InvalidDeviceSelectionState;

        const next = DeviceSelection{
            .audio = resolvedIdentifier(
                catalog,
                .audio,
                self.requested.audio,
            ),
            .audio_input = resolvedIdentifier(
                catalog,
                .audio_input,
                self.requested.audio_input,
            ),
            .audio_output = resolvedIdentifier(
                catalog,
                .audio_output,
                self.requested.audio_output,
            ),
            .midi_input = resolvedIdentifier(
                catalog,
                .midi_input,
                self.requested.midi_input,
            ),
            .midi_output = resolvedIdentifier(
                catalog,
                .midi_output,
                self.requested.midi_output,
            ),
        };
        const report = DeviceSelectionResolution{
            .catalog_generation = catalog.generation(),
            .audio_changed = !optionalIdentifiersEqual(
                self.active.audio,
                next.audio,
            ),
            .audio_input_changed = !optionalIdentifiersEqual(
                self.active.audio_input,
                next.audio_input,
            ),
            .audio_output_changed = !optionalIdentifiersEqual(
                self.active.audio_output,
                next.audio_output,
            ),
            .midi_input_changed = !optionalIdentifiersEqual(
                self.active.midi_input,
                next.midi_input,
            ),
            .midi_output_changed = !optionalIdentifiersEqual(
                self.active.midi_output,
                next.midi_output,
            ),
            .audio_uses_fallback = usesFallback(
                self.requested.audio,
                next.audio,
            ),
            .audio_input_uses_fallback = usesFallback(
                self.requested.audio_input,
                next.audio_input,
            ),
            .audio_output_uses_fallback = usesFallback(
                self.requested.audio_output,
                next.audio_output,
            ),
            .midi_input_uses_fallback = usesFallback(
                self.requested.midi_input,
                next.midi_input,
            ),
            .midi_output_uses_fallback = usesFallback(
                self.requested.midi_output,
                next.midi_output,
            ),
        };
        self.active = next;
        self.catalog_generation = report.catalog_generation;
        return report;
    }
};

pub const DeviceRecoveryReason = struct {
    initial_start: bool,
    selection_changed: bool,
    retry_requested: bool,
};

pub const DeviceRecoveryCallback = struct {
    context: *anyopaque,
    apply_recovery: *const fn (
        *anyopaque,
        DeviceSelection,
        DeviceSelectionResolution,
        DeviceRecoveryReason,
    ) anyerror!void,

    pub fn apply(
        self: DeviceRecoveryCallback,
        selection: DeviceSelection,
        resolution: DeviceSelectionResolution,
        reason: DeviceRecoveryReason,
    ) !void {
        try self.apply_recovery(
            self.context,
            selection,
            resolution,
            reason,
        );
    }
};

pub const DeviceRecoveryResult = enum {
    unchanged,
    applied,
};

pub const DeviceFailureSnapshot = struct {
    audio: u64 = 0,
    audio_input: u64 = 0,
    audio_output: u64 = 0,
    midi_input: u64 = 0,
    midi_output: u64 = 0,
};

pub const DeviceFailureReport = struct {
    audio: bool = false,
    audio_input: bool = false,
    audio_output: bool = false,
    midi_input: bool = false,
    midi_output: bool = false,

    pub fn any(self: DeviceFailureReport) bool {
        return self.audio or
            self.audio_input or
            self.audio_output or
            self.midi_input or
            self.midi_output;
    }

    pub fn merge(
        self: *DeviceFailureReport,
        other: DeviceFailureReport,
    ) void {
        self.audio = self.audio or other.audio;
        self.audio_input =
            self.audio_input or other.audio_input;
        self.audio_output =
            self.audio_output or other.audio_output;
        self.midi_input =
            self.midi_input or other.midi_input;
        self.midi_output =
            self.midi_output or other.midi_output;
    }
};

pub const DeviceFailureSource = struct {
    context: *anyopaque,
    read_snapshot: *const fn (
        *anyopaque,
    ) anyerror!DeviceFailureSnapshot,

    pub fn snapshot(
        self: DeviceFailureSource,
    ) !DeviceFailureSnapshot {
        return self.read_snapshot(self.context);
    }
};

pub const DeviceFailureMonitor = struct {
    source: DeviceFailureSource,
    previous: DeviceFailureSnapshot,

    pub fn init(
        source: DeviceFailureSource,
    ) !DeviceFailureMonitor {
        return .{
            .source = source,
            .previous = try source.snapshot(),
        };
    }

    pub fn poll(
        self: *DeviceFailureMonitor,
    ) !DeviceFailureReport {
        const current = try self.source.snapshot();
        const report = failureIncrease(self.previous, current);
        self.previous = current;
        return report;
    }
};

pub fn DeviceFailureMonitorSet(comptime capacity: usize) type {
    if (capacity == 0)
        @compileError("DeviceFailureMonitorSet capacity must be positive");

    return struct {
        monitors: [capacity]DeviceFailureMonitor = undefined,
        count: usize = 0,

        pub fn add(
            self: *@This(),
            source: DeviceFailureSource,
        ) !void {
            if (self.count == capacity)
                return error.DeviceFailureSourceCapacityExceeded;
            const monitor = try DeviceFailureMonitor.init(source);
            self.monitors[self.count] = monitor;
            self.count += 1;
        }

        pub fn replace(
            self: *@This(),
            source: DeviceFailureSource,
        ) !void {
            const monitor = try DeviceFailureMonitor.init(source);
            self.monitors[0] = monitor;
            self.count = 1;
        }

        pub fn clear(self: *@This()) void {
            self.count = 0;
        }

        pub fn poll(
            self: *@This(),
        ) !DeviceFailureReport {
            var snapshots: [capacity]DeviceFailureSnapshot = undefined;
            var report = DeviceFailureReport{};
            for (self.monitors[0..self.count], 0..) |monitor, index| {
                const current = try monitor.source.snapshot();
                snapshots[index] = current;
                report.merge(failureIncrease(
                    monitor.previous,
                    current,
                ));
            }
            for (self.monitors[0..self.count], 0..) |*monitor, index| {
                monitor.previous = snapshots[index];
            }
            return report;
        }
    };
}

fn failureIncrease(
    previous: DeviceFailureSnapshot,
    current: DeviceFailureSnapshot,
) DeviceFailureReport {
    return .{
        .audio = current.audio > previous.audio,
        .audio_input = current.audio_input > previous.audio_input,
        .audio_output = current.audio_output > previous.audio_output,
        .midi_input = current.midi_input > previous.midi_input,
        .midi_output = current.midi_output > previous.midi_output,
    };
}

pub const DeviceRecoveryController = struct {
    tracker: DeviceSelectionTracker,
    initial_start_pending: bool = true,
    retry_requested: bool = false,
    attempt_count: usize = 0,
    success_count: usize = 0,
    failure_count: usize = 0,

    pub fn init(
        preferred_selection: DeviceSelection,
    ) !DeviceRecoveryController {
        return .{
            .tracker = try DeviceSelectionTracker.init(
                preferred_selection,
            ),
        };
    }

    pub fn setRequested(
        self: *DeviceRecoveryController,
        preferred_selection: DeviceSelection,
    ) !void {
        try self.tracker.setRequested(preferred_selection);
        self.retry_requested = true;
    }

    pub fn requestRecovery(
        self: *DeviceRecoveryController,
    ) void {
        self.retry_requested = true;
    }

    pub fn requested(
        self: *const DeviceRecoveryController,
    ) DeviceSelection {
        return self.tracker.requested;
    }

    pub fn active(
        self: *const DeviceRecoveryController,
    ) DeviceSelection {
        return self.tracker.active;
    }

    /// Call from a control thread. The callback must stop affected devices,
    /// apply the candidate selection, and restart them before returning.
    pub fn reconcileAndApply(
        self: *DeviceRecoveryController,
        catalog: anytype,
        callback: DeviceRecoveryCallback,
    ) !DeviceRecoveryResult {
        var candidate = self.tracker;
        const resolution = try candidate.reconcile(catalog);
        const reason = DeviceRecoveryReason{
            .initial_start = self.initial_start_pending,
            .selection_changed = resolution.changed(),
            .retry_requested = self.retry_requested,
        };
        if (!reason.initial_start and
            !reason.selection_changed and
            !reason.retry_requested)
            return .unchanged;

        self.attempt_count +|= 1;
        callback.apply(
            candidate.active,
            resolution,
            reason,
        ) catch |apply_error| {
            self.failure_count +|= 1;
            self.retry_requested = true;
            return apply_error;
        };

        self.tracker = candidate;
        self.initial_start_pending = false;
        self.retry_requested = false;
        self.success_count +|= 1;
        return .applied;
    }
};

fn validateDescriptors(
    descriptors: []const DeviceDescriptor,
) !void {
    var default_seen: [5]bool = @splat(false);
    for (descriptors, 0..) |descriptor, index| {
        if (!descriptor.valid())
            return error.InvalidDeviceDescriptor;
        if (descriptor.is_default) {
            const kind_index = @intFromEnum(descriptor.kind);
            if (default_seen[kind_index])
                return error.MultipleDefaultDevices;
            default_seen[kind_index] = true;
        }
        for (descriptors[0..index]) |previous| {
            if (previous.kind == descriptor.kind and
                previous.identifier.eql(&descriptor.identifier))
                return error.DuplicateDeviceIdentifier;
        }
    }
}

fn optionalIdentifierValid(
    identifier: ?DeviceIdentifier,
) bool {
    if (identifier) |value| return value.valid();
    return true;
}

fn optionalIdentifiersEqual(
    left: ?DeviceIdentifier,
    right: ?DeviceIdentifier,
) bool {
    if (left) |left_value| {
        const right_value = right orelse return false;
        return left_value.eql(&right_value);
    }
    return right == null;
}

fn resolvedIdentifier(
    catalog: anytype,
    kind: DeviceKind,
    requested: ?DeviceIdentifier,
) ?DeviceIdentifier {
    const descriptor = catalog.resolve(kind, requested) orelse
        return null;
    return descriptor.identifier;
}

fn usesFallback(
    requested: ?DeviceIdentifier,
    active: ?DeviceIdentifier,
) bool {
    const preferred = requested orelse return false;
    const resolved = active orelse return true;
    return !preferred.eql(&resolved);
}

fn writeOptionalIdentifier(
    writer: anytype,
    identifier: ?DeviceIdentifier,
) !void {
    const value = identifier orelse {
        try writer.writeByte(0);
        return;
    };
    if (!value.valid()) return error.InvalidDeviceIdentifier;
    try writer.writeByte(1);
    try writer.writeByte(value.length);
    try writer.writeAll(value.slice());
}

fn readOptionalIdentifier(reader: anytype) !?DeviceIdentifier {
    const present = try reader.takeByte();
    if (present == 0) return null;
    if (present != 1) return error.InvalidDeviceSelection;
    const length = try reader.takeByte();
    if (length == 0 or
        length > maximum_device_identifier_bytes)
        return error.InvalidDeviceSelection;
    var identifier = DeviceIdentifier{};
    identifier.length = length;
    try reader.readSliceAll(identifier.storage[0..length]);
    if (!identifier.valid()) return error.InvalidDeviceSelection;
    return identifier;
}

test "device catalog refresh is transactional and generation tracked" {
    const built_in = try DeviceDescriptor.init(
        .audio,
        "coreaudio:built-in",
        "Built-in Output",
        2,
        2,
        true,
    );
    const interface = try DeviceDescriptor.init(
        .audio,
        "coreaudio:interface",
        "Studio Interface",
        8,
        8,
        false,
    );
    var catalog = DeviceCatalog(2){};
    try catalog.replace(&.{ built_in, interface });
    try std.testing.expectEqual(@as(u64, 1), catalog.generation());
    try std.testing.expectEqual(@as(usize, 2), catalog.items().len);
    try std.testing.expectEqualStrings(
        "Studio Interface",
        catalog.resolve(
            .audio,
            try DeviceIdentifier.init("coreaudio:interface"),
        ).?.name(),
    );
    try std.testing.expectEqualStrings(
        "Built-in Output",
        catalog.resolve(.audio, null).?.name(),
    );

    var duplicate = interface;
    duplicate.is_default = true;
    try std.testing.expectError(
        error.DuplicateDeviceIdentifier,
        catalog.replace(&.{ interface, duplicate }),
    );
    try std.testing.expectEqual(@as(u64, 1), catalog.generation());
    try std.testing.expectEqualStrings(
        "Built-in Output",
        catalog.items()[0].name(),
    );
}

test "device catalog rejects excess capacity and duplicate defaults" {
    const first = try DeviceDescriptor.init(
        .midi_input,
        "midi:first",
        "First",
        0,
        0,
        true,
    );
    const second = try DeviceDescriptor.init(
        .midi_input,
        "midi:second",
        "Second",
        0,
        0,
        true,
    );
    var catalog = DeviceCatalog(1){};
    try std.testing.expectError(
        error.DeviceCatalogCapacityExceeded,
        catalog.replace(&.{ first, second }),
    );
    var larger = DeviceCatalog(2){};
    try std.testing.expectError(
        error.MultipleDefaultDevices,
        larger.replace(&.{ first, second }),
    );
}

test "device descriptors validate bounded text channels and generation rollover" {
    try std.testing.expectError(
        error.EmptyDeviceIdentifier,
        DeviceIdentifier.init(""),
    );
    try std.testing.expectError(
        error.InvalidDeviceIdentifier,
        DeviceIdentifier.init("audio:\x00invalid"),
    );
    try std.testing.expectError(
        error.InvalidDeviceIdentifier,
        DeviceIdentifier.init(&.{0xff}),
    );
    const oversized =
        [_]u8{'a'} ** (maximum_device_identifier_bytes + 1);
    try std.testing.expectError(
        error.DeviceIdentifierTooLong,
        DeviceIdentifier.init(&oversized),
    );
    try std.testing.expectError(
        error.InvalidMidiDeviceChannels,
        DeviceDescriptor.init(
            .midi_output,
            "midi:invalid",
            "Invalid MIDI",
            0,
            1,
            false,
        ),
    );
    try std.testing.expectError(
        error.AudioDeviceHasNoChannels,
        DeviceDescriptor.init(
            .audio,
            "audio:invalid",
            "Invalid Audio",
            0,
            0,
            false,
        ),
    );
    try std.testing.expectError(
        error.InvalidAudioInputDeviceChannels,
        DeviceDescriptor.init(
            .audio_input,
            "audio-input:invalid",
            "Invalid Input",
            0,
            0,
            false,
        ),
    );
    try std.testing.expectError(
        error.InvalidAudioOutputDeviceChannels,
        DeviceDescriptor.init(
            .audio_output,
            "audio-output:invalid",
            "Invalid Output",
            1,
            2,
            false,
        ),
    );

    const audio = try DeviceDescriptor.init(
        .audio,
        "audio:valid",
        "Valid Audio",
        2,
        2,
        true,
    );
    var catalog = DeviceCatalog(1){
        .current_generation = std.math.maxInt(u64),
    };
    try catalog.replace(&.{audio});
    try std.testing.expectEqual(@as(u64, 1), catalog.generation());
}

test "device selection round trips and rejects malformed state transactionally" {
    const original = DeviceSelection{
        .audio = try DeviceIdentifier.init("audio:studio"),
        .audio_input = try DeviceIdentifier.init("audio-input:mic"),
        .audio_output = try DeviceIdentifier.init("audio-output:monitors"),
        .midi_input = try DeviceIdentifier.init("midi:keyboard"),
        .midi_output = null,
    };
    var bytes: [DeviceSelection.maximum_encoded_size]u8 =
        undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try original.writeTo(&writer);

    var restored = DeviceSelection{};
    var reader = std.Io.Reader.fixed(bytes[0..writer.end]);
    try restored.readFrom(&reader);
    try std.testing.expect(restored.audio.?.eql(&original.audio.?));
    try std.testing.expect(
        restored.audio_input.?.eql(&original.audio_input.?),
    );
    try std.testing.expect(
        restored.audio_output.?.eql(&original.audio_output.?),
    );
    try std.testing.expect(
        restored.midi_input.?.eql(&original.midi_input.?),
    );
    try std.testing.expect(restored.midi_output == null);

    var malformed = bytes;
    malformed[0] = 'X';
    var malformed_reader =
        std.Io.Reader.fixed(malformed[0..writer.end]);
    try std.testing.expectError(
        error.InvalidDeviceSelection,
        restored.readFrom(&malformed_reader),
    );
    try std.testing.expect(restored.audio.?.eql(&original.audio.?));
}

test "device selection restores version one records" {
    const audio = try DeviceIdentifier.init("audio:legacy");
    const midi_output = try DeviceIdentifier.init("midi:legacy");
    var bytes: [DeviceSelection.maximum_encoded_size]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try writer.writeAll("DVSL");
    try writer.writeInt(u16, 1, .little);
    try writeOptionalIdentifier(&writer, audio);
    try writeOptionalIdentifier(&writer, null);
    try writeOptionalIdentifier(&writer, midi_output);

    var restored = DeviceSelection{
        .audio_input = try DeviceIdentifier.init("audio-input:old"),
    };
    var reader = std.Io.Reader.fixed(bytes[0..writer.end]);
    try restored.readFrom(&reader);
    try std.testing.expect(restored.audio.?.eql(&audio));
    try std.testing.expect(restored.audio_input == null);
    try std.testing.expect(restored.audio_output == null);
    try std.testing.expect(restored.midi_input == null);
    try std.testing.expect(restored.midi_output.?.eql(&midi_output));
}

test "directional audio selections reconcile independently" {
    const built_in_input = try DeviceDescriptor.init(
        .audio_input,
        "wasapi-input:built-in",
        "Built-in Microphone",
        2,
        0,
        true,
    );
    const interface_input = try DeviceDescriptor.init(
        .audio_input,
        "wasapi-input:interface",
        "Interface Input",
        8,
        0,
        false,
    );
    const built_in_output = try DeviceDescriptor.init(
        .audio_output,
        "wasapi-output:built-in",
        "Built-in Output",
        0,
        2,
        true,
    );
    const interface_output = try DeviceDescriptor.init(
        .audio_output,
        "wasapi-output:interface",
        "Interface Output",
        0,
        8,
        false,
    );
    var catalog = DeviceCatalog(4){};
    try catalog.replace(&.{
        built_in_input,
        interface_input,
        built_in_output,
        interface_output,
    });
    var tracker = try DeviceSelectionTracker.init(.{
        .audio_input = interface_input.identifier,
        .audio_output = interface_output.identifier,
    });
    const initial = try tracker.reconcile(&catalog);
    try std.testing.expect(initial.audio_input_changed);
    try std.testing.expect(initial.audio_output_changed);
    try std.testing.expect(!initial.audio_input_uses_fallback);
    try std.testing.expect(!initial.audio_output_uses_fallback);

    try catalog.replace(&.{
        built_in_input,
        built_in_output,
    });
    const removed = try tracker.reconcile(&catalog);
    try std.testing.expect(removed.audio_input_uses_fallback);
    try std.testing.expect(removed.audio_output_uses_fallback);
    try std.testing.expect(
        tracker.active.audio_input.?.eql(
            &built_in_input.identifier,
        ),
    );
    try std.testing.expect(
        tracker.active.audio_output.?.eql(
            &built_in_output.identifier,
        ),
    );

    try catalog.replace(&.{
        built_in_input,
        interface_input,
        built_in_output,
        interface_output,
    });
    const restored = try tracker.reconcile(&catalog);
    try std.testing.expect(restored.audio_input_changed);
    try std.testing.expect(restored.audio_output_changed);
    try std.testing.expect(!restored.audio_input_uses_fallback);
    try std.testing.expect(!restored.audio_output_uses_fallback);
}

test "device selection tracker restores preferred devices after hot plug" {
    const built_in = try DeviceDescriptor.init(
        .audio,
        "audio:built-in",
        "Built-in Audio",
        2,
        2,
        true,
    );
    const studio = try DeviceDescriptor.init(
        .audio,
        "audio:studio",
        "Studio Interface",
        8,
        8,
        false,
    );
    var catalog = DeviceCatalog(2){};
    try catalog.replace(&.{ built_in, studio });
    var tracker = try DeviceSelectionTracker.init(.{
        .audio = studio.identifier,
    });

    const initial = try tracker.reconcile(&catalog);
    try std.testing.expect(initial.audio_changed);
    try std.testing.expect(!initial.audio_uses_fallback);
    try std.testing.expect(
        tracker.active.audio.?.eql(&studio.identifier),
    );

    try catalog.replace(&.{built_in});
    const removed = try tracker.reconcile(&catalog);
    try std.testing.expect(removed.changed());
    try std.testing.expect(removed.audio_uses_fallback);
    try std.testing.expect(
        tracker.active.audio.?.eql(&built_in.identifier),
    );

    try catalog.replace(&.{ built_in, studio });
    const restored = try tracker.reconcile(&catalog);
    try std.testing.expect(restored.audio_changed);
    try std.testing.expect(!restored.audio_uses_fallback);
    try std.testing.expect(
        tracker.active.audio.?.eql(&studio.identifier),
    );
}

test "device failure monitor detects increases and absorbs resets" {
    const Probe = struct {
        snapshot: DeviceFailureSnapshot = .{},
        fail_read: bool = false,

        fn read(context: *anyopaque) !DeviceFailureSnapshot {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (self.fail_read) return error.FailureSnapshotUnavailable;
            return self.snapshot;
        }

        fn source(self: *@This()) DeviceFailureSource {
            return .{
                .context = self,
                .read_snapshot = read,
            };
        }
    };

    var probe = Probe{
        .snapshot = .{
            .audio_input = 3,
            .midi_input = 8,
        },
    };
    var monitor = try DeviceFailureMonitor.init(probe.source());
    try std.testing.expect(!(try monitor.poll()).any());

    probe.snapshot.audio_input = 4;
    probe.snapshot.midi_output = 1;
    const increased = try monitor.poll();
    try std.testing.expect(increased.any());
    try std.testing.expect(increased.audio_input);
    try std.testing.expect(increased.midi_output);
    try std.testing.expect(!increased.midi_input);

    probe.snapshot.audio_input = 0;
    probe.snapshot.midi_output = 0;
    try std.testing.expect(!(try monitor.poll()).any());

    probe.fail_read = true;
    try std.testing.expectError(
        error.FailureSnapshotUnavailable,
        monitor.poll(),
    );
    probe.fail_read = false;
    probe.snapshot.audio = 1;
    const after_error = try monitor.poll();
    try std.testing.expect(after_error.audio);
}

test "device failure monitor set aggregates transactionally" {
    const Probe = struct {
        snapshot: DeviceFailureSnapshot = .{},
        fail_read: bool = false,

        fn read(context: *anyopaque) !DeviceFailureSnapshot {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (self.fail_read) return error.FailureSnapshotUnavailable;
            return self.snapshot;
        }

        fn source(self: *@This()) DeviceFailureSource {
            return .{
                .context = self,
                .read_snapshot = read,
            };
        }
    };

    var audio = Probe{};
    var midi = Probe{};
    var monitors = DeviceFailureMonitorSet(2){};
    try monitors.add(audio.source());
    try monitors.add(midi.source());
    audio.snapshot.audio_output = 1;
    midi.snapshot.midi_input = 1;
    const combined = try monitors.poll();
    try std.testing.expect(combined.audio_output);
    try std.testing.expect(combined.midi_input);

    audio.snapshot.audio_output = 2;
    midi.fail_read = true;
    try std.testing.expectError(
        error.FailureSnapshotUnavailable,
        monitors.poll(),
    );
    midi.fail_read = false;
    const retried = try monitors.poll();
    try std.testing.expect(retried.audio_output);
    try std.testing.expect(!retried.midi_input);

    var full = DeviceFailureMonitorSet(1){};
    try full.add(audio.source());
    try std.testing.expectError(
        error.DeviceFailureSourceCapacityExceeded,
        full.add(midi.source()),
    );
}

test "device recovery publishes changed selections only after success" {
    const built_in = try DeviceDescriptor.init(
        .audio,
        "audio:built-in",
        "Built-in Audio",
        2,
        2,
        true,
    );
    const studio = try DeviceDescriptor.init(
        .audio,
        "audio:studio",
        "Studio Interface",
        8,
        8,
        false,
    );
    const Probe = struct {
        fail_next: bool = false,
        apply_count: usize = 0,
        last_selection: DeviceSelection = .{},
        last_reason: DeviceRecoveryReason = undefined,

        fn apply(
            context: *anyopaque,
            selection: DeviceSelection,
            _: DeviceSelectionResolution,
            reason: DeviceRecoveryReason,
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.apply_count += 1;
            if (self.fail_next) {
                self.fail_next = false;
                return error.DeviceRestartFailed;
            }
            self.last_selection = selection;
            self.last_reason = reason;
        }
    };

    var catalog = DeviceCatalog(2){};
    try catalog.replace(&.{ built_in, studio });
    var controller = try DeviceRecoveryController.init(.{
        .audio = studio.identifier,
    });
    var probe = Probe{};
    const callback = DeviceRecoveryCallback{
        .context = &probe,
        .apply_recovery = Probe.apply,
    };

    try std.testing.expectEqual(
        DeviceRecoveryResult.applied,
        try controller.reconcileAndApply(&catalog, callback),
    );
    try std.testing.expect(probe.last_reason.initial_start);
    try std.testing.expect(
        controller.active().audio.?.eql(&studio.identifier),
    );
    try std.testing.expectEqual(
        DeviceRecoveryResult.unchanged,
        try controller.reconcileAndApply(&catalog, callback),
    );

    try catalog.replace(&.{built_in});
    probe.fail_next = true;
    try std.testing.expectError(
        error.DeviceRestartFailed,
        controller.reconcileAndApply(&catalog, callback),
    );
    try std.testing.expect(
        controller.active().audio.?.eql(&studio.identifier),
    );

    try std.testing.expectEqual(
        DeviceRecoveryResult.applied,
        try controller.reconcileAndApply(&catalog, callback),
    );
    try std.testing.expect(
        controller.active().audio.?.eql(&built_in.identifier),
    );
    try std.testing.expectEqual(@as(usize, 3), controller.attempt_count);
    try std.testing.expectEqual(@as(usize, 2), controller.success_count);
    try std.testing.expectEqual(@as(usize, 1), controller.failure_count);

    try catalog.replace(&.{ built_in, studio });
    try std.testing.expectEqual(
        DeviceRecoveryResult.applied,
        try controller.reconcileAndApply(&catalog, callback),
    );
    try std.testing.expect(
        controller.active().audio.?.eql(&studio.identifier),
    );
}

test "device recovery supports an explicit same-selection restart" {
    const audio = try DeviceDescriptor.init(
        .audio,
        "audio:default",
        "Default Audio",
        2,
        2,
        true,
    );
    const Probe = struct {
        reason: DeviceRecoveryReason = undefined,
        apply_count: usize = 0,

        fn apply(
            context: *anyopaque,
            _: DeviceSelection,
            _: DeviceSelectionResolution,
            reason: DeviceRecoveryReason,
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.reason = reason;
            self.apply_count += 1;
        }
    };

    var catalog = DeviceCatalog(1){};
    try catalog.replace(&.{audio});
    var controller = try DeviceRecoveryController.init(.{});
    var probe = Probe{};
    const callback = DeviceRecoveryCallback{
        .context = &probe,
        .apply_recovery = Probe.apply,
    };
    _ = try controller.reconcileAndApply(&catalog, callback);
    controller.requestRecovery();
    try std.testing.expectEqual(
        DeviceRecoveryResult.applied,
        try controller.reconcileAndApply(&catalog, callback),
    );
    try std.testing.expect(probe.reason.retry_requested);
    try std.testing.expect(!probe.reason.selection_changed);
    try std.testing.expectEqual(@as(usize, 2), probe.apply_count);
}

test "device selection reconciliation rejects malformed state transactionally" {
    const audio = try DeviceDescriptor.init(
        .audio,
        "audio:valid",
        "Valid Audio",
        2,
        2,
        true,
    );
    var catalog = DeviceCatalog(1){};
    try catalog.replace(&.{audio});
    var tracker = try DeviceSelectionTracker.init(.{});
    _ = try tracker.reconcile(&catalog);
    const previous = tracker;

    catalog.count = 2;
    try std.testing.expectError(
        error.InvalidDeviceSelectionState,
        tracker.reconcile(&catalog),
    );
    try std.testing.expectEqualDeep(previous, tracker);
}
