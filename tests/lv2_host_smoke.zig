const core = @import("zig-vst3-plugin-core");
const std = @import("std");

const DescriptorFunction = *const fn (
    index: u32,
) callconv(.c) ?*const core.lv2.Descriptor;

const SequenceBuffer = extern struct {
    sequence: core.lv2.AtomSequence,
    storage: [64]u8,

    fn position(frame_offset: i64) SequenceBuffer {
        var result = std.mem.zeroes(SequenceBuffer);
        result.sequence = .{
            .atom = .{ .size = 56, .type = 29 },
            .body = .{ .unit = 0, .pad = 0 },
        };
        const bytes: [*]u8 = @ptrCast(&result.sequence.body);
        const event: *core.lv2.AtomEvent = @ptrCast(
            @alignCast(bytes + 8),
        );
        event.* = .{
            .time = .{ .frames = frame_offset },
            .body = .{ .size = 32, .type = 43 },
        };
        const object: *core.lv2.AtomObjectBody = @ptrCast(
            @alignCast(bytes + 24),
        );
        object.* = .{ .id = 0, .otype = 67 };
        const property: *core.lv2.AtomPropertyBody = @ptrCast(
            @alignCast(bytes + 32),
        );
        property.* = .{
            .key = 97,
            .context = 0,
            .value = .{ .size = 4, .type = 47 },
        };
        const bpm: *align(1) f32 = @ptrCast(bytes + 48);
        bpm.* = 120.0;
        return result;
    }

    fn midi(payload: []const u8) !SequenceBuffer {
        const event_size = std.mem.alignForward(
            usize,
            @sizeOf(core.lv2.AtomEvent) + payload.len,
            8,
        );
        if (event_size > 64) return error.MidiEventTooLarge;
        var result = std.mem.zeroes(SequenceBuffer);
        result.sequence = .{
            .atom = .{
                .size = @intCast(
                    @sizeOf(core.lv2.AtomSequenceBody) + event_size,
                ),
                .type = 29,
            },
            .body = .{ .unit = 0, .pad = 0 },
        };
        const bytes: [*]u8 = @ptrCast(&result.sequence.body);
        const event: *core.lv2.AtomEvent = @ptrCast(
            @alignCast(
                bytes + @sizeOf(core.lv2.AtomSequenceBody),
            ),
        );
        event.* = .{
            .time = .{ .frames = 0 },
            .body = .{
                .size = @intCast(payload.len),
                .type = 37,
            },
        };
        @memcpy(
            bytes[@sizeOf(core.lv2.AtomSequenceBody) + @sizeOf(core.lv2.AtomEvent) .. @sizeOf(core.lv2.AtomSequenceBody) + @sizeOf(core.lv2.AtomEvent) + payload.len],
            payload,
        );
        return result;
    }
};

const StateHost = struct {
    key: core.lv2.Urid = 0,
    value_type: core.lv2.Urid = 0,
    flags: u32 = 0,
    bytes: [4096]u8 = undefined,
    size: usize = 0,

    fn map(
        _: ?*anyopaque,
        URI: [*:0]const u8,
    ) callconv(.c) core.lv2.Urid {
        const uri = std.mem.span(URI);
        if (std.mem.eql(u8, uri, core.lv2.atom_chunk_uri))
            return 23;
        if (std.mem.eql(u8, uri, core.lv2.atom_sequence_uri))
            return 29;
        if (std.mem.eql(u8, uri, core.lv2.atom_frame_time_uri))
            return 31;
        if (std.mem.eql(u8, uri, core.lv2.midi_event_uri))
            return 37;
        if (std.mem.eql(u8, uri, core.lv2.atom_blank_uri))
            return 41;
        if (std.mem.eql(u8, uri, core.lv2.atom_object_uri))
            return 43;
        if (std.mem.eql(u8, uri, core.lv2.atom_float_uri))
            return 47;
        if (std.mem.eql(u8, uri, core.lv2.atom_double_uri))
            return 53;
        if (std.mem.eql(u8, uri, core.lv2.atom_int_uri))
            return 59;
        if (std.mem.eql(u8, uri, core.lv2.atom_long_uri))
            return 61;
        if (std.mem.eql(u8, uri, core.lv2.time_position_uri))
            return 67;
        if (std.mem.eql(u8, uri, core.lv2.time_bar_uri))
            return 71;
        if (std.mem.eql(u8, uri, core.lv2.time_bar_beat_uri))
            return 73;
        if (std.mem.eql(u8, uri, core.lv2.time_beat_uri))
            return 79;
        if (std.mem.eql(u8, uri, core.lv2.time_beat_unit_uri))
            return 83;
        if (std.mem.eql(u8, uri, core.lv2.time_beats_per_bar_uri))
            return 89;
        if (std.mem.eql(
            u8,
            uri,
            core.lv2.time_beats_per_minute_uri,
        )) return 97;
        if (std.mem.eql(u8, uri, core.lv2.time_frame_uri))
            return 101;
        if (std.mem.eql(
            u8,
            uri,
            core.lv2.time_frames_per_second_uri,
        )) return 103;
        if (std.mem.eql(u8, uri, core.lv2.time_speed_uri))
            return 107;
        if (std.mem.eql(
            u8,
            uri,
            core.lv2.buffer_minimum_block_length_uri,
        )) return 109;
        if (std.mem.eql(
            u8,
            uri,
            core.lv2.buffer_maximum_block_length_uri,
        )) return 113;
        if (std.mem.eql(
            u8,
            uri,
            core.lv2.buffer_nominal_block_length_uri,
        )) return 127;
        if (std.mem.eql(
            u8,
            uri,
            core.lv2.buffer_sequence_size_uri,
        )) return 131;
        if (std.mem.endsWith(u8, uri, "#parameterState"))
            return 17;
        return 0;
    }

    fn store(
        handle: core.lv2.StateHandle,
        key: core.lv2.Urid,
        value: *const anyopaque,
        size: usize,
        value_type: core.lv2.Urid,
        flags: u32,
    ) callconv(.c) core.lv2.StateStatus {
        const raw = handle orelse return .unknown;
        const self: *@This() = @ptrCast(@alignCast(raw));
        if (size > self.bytes.len) return .no_space;
        const source: [*]const u8 = @ptrCast(value);
        @memcpy(self.bytes[0..size], source[0..size]);
        self.key = key;
        self.value_type = value_type;
        self.flags = flags;
        self.size = size;
        return .success;
    }

    fn retrieve(
        handle: core.lv2.StateHandle,
        key: core.lv2.Urid,
        size: *usize,
        value_type: *core.lv2.Urid,
        flags: *u32,
    ) callconv(.c) ?*const anyopaque {
        const raw = handle orelse return null;
        const self: *@This() = @ptrCast(@alignCast(raw));
        if (key != self.key or self.size == 0) return null;
        size.* = self.size;
        value_type.* = self.value_type;
        flags.* = self.flags;
        return &self.bytes;
    }
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(
        init.arena.allocator(),
    );
    if (args.len != 2) return error.InvalidArguments;

    var library = try std.DynLib.open(args[1]);
    defer library.close();
    const descriptor_function = library.lookup(
        DescriptorFunction,
        "lv2_descriptor",
    ) orelse return error.MissingLv2Descriptor;
    const descriptor = descriptor_function(0) orelse
        return error.MissingPluginDescriptor;
    if (descriptor_function(1) != null)
        return error.UnexpectedPluginDescriptor;
    if (!std.mem.eql(
        u8,
        std.mem.span(descriptor.URI),
        "https://zig-vst3.dev/plugins/mono-gain",
    )) return error.InvalidPluginUri;

    var urid_map = core.lv2.UridMap{
        .handle = null,
        .map = StateHost.map,
    };
    var map_feature = core.lv2.Feature{
        .URI = core.lv2.urid_map_uri,
        .data = &urid_map,
    };
    const minimum_block_length: i32 = 1;
    const maximum_block_length: i32 = 4;
    const nominal_block_length: i32 = 4;
    const sequence_size: i32 = 1024;
    const options = [_]core.lv2.OptionsOption{
        .{
            .key = 109,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &minimum_block_length,
        },
        .{
            .key = 113,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &maximum_block_length,
        },
        .{
            .key = 127,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &nominal_block_length,
        },
        .{
            .key = 131,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &sequence_size,
        },
        .{},
    };
    var options_feature = core.lv2.Feature{
        .URI = core.lv2.options_options_uri,
        .data = @constCast(&options),
    };
    const features = [_:null]?*const core.lv2.Feature{
        &map_feature,
        &options_feature,
    };
    if (descriptor.instantiate(
        null,
        48_000.0,
        "/tmp/zig_vst3_mono_gain.lv2",
        features[0..].ptr,
    ) != null) return error.NullDescriptorAccepted;
    if (descriptor.instantiate(
        descriptor,
        48_000.0,
        null,
        features[0..].ptr,
    ) != null) return error.NullBundlePathAccepted;
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/zig_vst3_mono_gain.lv2",
        features[0..].ptr,
    ) orelse return error.InstantiateFailed;
    defer descriptor.cleanup(handle);

    if (descriptor.extension_data(null) != null)
        return error.NullExtensionUriAccepted;
    const raw_options = descriptor.extension_data(
        core.lv2.options_interface_uri,
    ) orelse return error.MissingOptionsInterface;
    const runtime_options: *const core.lv2.OptionsInterface =
        @ptrCast(@alignCast(raw_options));
    if (runtime_options.get(handle, null) !=
        core.lv2.options_status_unknown)
        return error.NullOptionsQueryAccepted;
    if (runtime_options.set(handle, null) !=
        core.lv2.options_status_unknown)
        return error.NullOptionsUpdateAccepted;
    var option_queries = [_]core.lv2.OptionsOption{
        .{ .key = 113 },
        .{ .key = 131 },
        .{},
    };
    if (runtime_options.get(handle, &option_queries) !=
        core.lv2.options_status_success)
        return error.OptionsGetFailed;
    const initial_maximum = @as(
        *align(1) const i32,
        @ptrCast(option_queries[0].value orelse
            return error.MissingMaximumOption),
    ).*;
    if (initial_maximum != 4)
        return error.InvalidMaximumOption;
    const initial_sequence_size = @as(
        *align(1) const i32,
        @ptrCast(option_queries[1].value orelse
            return error.MissingSequenceSizeOption),
    ).*;
    if (initial_sequence_size != 1024)
        return error.InvalidSequenceSizeOption;

    const reduced_maximum: i32 = 3;
    const reduced_nominal: i32 = 3;
    const reduced_options = [_]core.lv2.OptionsOption{
        .{
            .key = 113,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &reduced_maximum,
        },
        .{
            .key = 127,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &reduced_nominal,
        },
        .{},
    };
    if (runtime_options.set(handle, &reduced_options) !=
        core.lv2.options_status_success)
        return error.OptionsSetFailed;
    const restored_maximum: i32 = 4;
    const restored_nominal: i32 = 4;
    const restored_options = [_]core.lv2.OptionsOption{
        .{
            .key = 113,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &restored_maximum,
        },
        .{
            .key = 127,
            .size = @sizeOf(i32),
            .type = 59,
            .value = &restored_nominal,
        },
        .{},
    };
    if (runtime_options.set(handle, &restored_options) !=
        core.lv2.options_status_success)
        return error.OptionsSetFailed;

    const input = [_]f32{ 0.25, -0.5, 0.75, -1.0 };
    var output = [_]f32{0.0} ** input.len;
    var events = SequenceBuffer.position(0);
    var gain: f32 = 1.5;
    var freewheeling: f32 = 0.0;
    var latency: f32 = -1.0;
    descriptor.connect_port(handle, 0, @constCast(&input));
    descriptor.connect_port(handle, 1, &output);
    descriptor.connect_port(handle, 2, &events);
    descriptor.connect_port(handle, 3, &gain);
    descriptor.connect_port(handle, 4, &freewheeling);
    descriptor.connect_port(handle, 5, &latency);
    if (descriptor.activate) |activate| activate(handle);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.375, -0.75, 1.125, -1.5 },
        &output,
    );
    try std.testing.expectEqual(@as(f32, 0.0), latency);

    freewheeling = 1.0;
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.375, -0.75, 1.125, -1.5 },
        &output,
    );
    freewheeling = 0.0;

    events = SequenceBuffer.position(1);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.375, -0.75, 1.125, -1.5 },
        &output,
    );
    events = try SequenceBuffer.midi(
        &.{ 0xf0, 0x7d, 1, 2, 0xf7 },
    );
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.375, -0.75, 1.125, -1.5 },
        &output,
    );
    events = std.mem.zeroes(SequenceBuffer);
    events.sequence = .{
        .atom = .{
            .size = @sizeOf(core.lv2.AtomSequenceBody),
            .type = 29,
        },
        .body = .{ .unit = 0, .pad = 0 },
    };

    const raw_state = descriptor.extension_data(
        core.lv2.state_interface_uri,
    ) orelse return error.MissingStateInterface;
    const state: *const core.lv2.StateInterface =
        @ptrCast(@alignCast(raw_state));
    var saved = StateHost{};
    if (state.save(
        handle,
        StateHost.store,
        &saved,
        0,
        null,
    ) != .success) return error.StateSaveFailed;
    gain = 0.5;
    descriptor.run(handle, input.len);
    if (state.restore(
        handle,
        StateHost.retrieve,
        &saved,
        0,
        null,
    ) != .success) return error.StateRestoreFailed;
    var restored = StateHost{};
    if (state.save(
        handle,
        StateHost.store,
        &restored,
        0,
        null,
    ) != .success) return error.StateSaveFailed;
    if (saved.key != restored.key or
        saved.value_type != restored.value_type or
        saved.flags != restored.flags or
        saved.size != restored.size or
        !std.mem.eql(
            u8,
            saved.bytes[0..saved.size],
            restored.bytes[0..restored.size],
        ))
        return error.StateRoundTripMismatch;

    if (descriptor.deactivate) |deactivate| deactivate(handle);
}
