const core = @import("zig-vst3-plugin-core");
const std = @import("std");

const au = core.audio_unit_v2;
const FactoryFunction = *const fn (
    ?*const au.AudioComponentDescription,
) callconv(.c) ?*au.AudioComponentPlugInInterface;
const SetPropertyProc = *const fn (
    *anyopaque,
    au.AudioUnitPropertyID,
    au.AudioUnitScope,
    au.AudioUnitElement,
    ?*const anyopaque,
    u32,
) callconv(.c) au.OSStatus;
const GetPropertyProc = *const fn (
    *anyopaque,
    au.AudioUnitPropertyID,
    au.AudioUnitScope,
    au.AudioUnitElement,
    ?*anyopaque,
    ?*u32,
) callconv(.c) au.OSStatus;
const GetParameterProc = *const fn (
    *anyopaque,
    au.AudioUnitParameterID,
    au.AudioUnitScope,
    au.AudioUnitElement,
    ?*au.AudioUnitParameterValue,
) callconv(.c) au.OSStatus;
const SetParameterProc = *const fn (
    *anyopaque,
    au.AudioUnitParameterID,
    au.AudioUnitScope,
    au.AudioUnitElement,
    au.AudioUnitParameterValue,
    u32,
) callconv(.c) au.OSStatus;
const InitializeProc = *const fn (
    *anyopaque,
) callconv(.c) au.OSStatus;
const ScheduleParametersProc = *const fn (
    *anyopaque,
    ?[*]const au.AudioUnitParameterEvent,
    u32,
) callconv(.c) au.OSStatus;
const RenderProc = *const fn (
    *anyopaque,
    ?*au.AudioUnitRenderActionFlags,
    ?*const au.AudioTimeStamp,
    u32,
    u32,
    *au.AudioBufferList,
) callconv(.c) au.OSStatus;
const AddPropertyListenerProc = *const fn (
    *anyopaque,
    au.AudioUnitPropertyID,
    au.AudioUnitPropertyListenerProc,
    ?*anyopaque,
) callconv(.c) au.OSStatus;
const RemovePropertyListenerProc = *const fn (
    *anyopaque,
    au.AudioUnitPropertyID,
    au.AudioUnitPropertyListenerProc,
    ?*anyopaque,
) callconv(.c) au.OSStatus;
const RenderNotifyProc = *const fn (
    *anyopaque,
    au.AURenderCallback,
    ?*anyopaque,
) callconv(.c) au.OSStatus;

const PropertyListenerState = struct {
    calls: usize = 0,
    last_property: au.AudioUnitPropertyID = 0,
};

const RenderNotifyState = struct {
    calls: usize = 0,
    flags: [2]au.AudioUnitRenderActionFlags = .{ 0, 0 },
};

extern fn CFRelease(value: *const anyopaque) void;
extern fn CFDictionaryGetCount(dictionary: *const anyopaque) isize;
extern fn CFDictionaryContainsKey(
    dictionary: *const anyopaque,
    key: *const anyopaque,
) u8;
extern fn CFStringCreateWithBytes(
    allocator: ?*const anyopaque,
    bytes: [*]const u8,
    byte_count: isize,
    encoding: u32,
    external_representation: u8,
) ?*anyopaque;

fn requireClassInfoKey(
    class_info: *const anyopaque,
    key_name: []const u8,
) !void {
    const key = CFStringCreateWithBytes(
        null,
        key_name.ptr,
        @intCast(key_name.len),
        0x0800_0100,
        0,
    ) orelse return error.ClassInfoKeyCreationFailed;
    defer CFRelease(key);
    if (CFDictionaryContainsKey(class_info, key) == 0)
        return error.MissingClassInfoKey;
}

fn pullInput(
    _: ?*anyopaque,
    _: ?*au.AudioUnitRenderActionFlags,
    _: ?*const au.AudioTimeStamp,
    bus: u32,
    frame_count: u32,
    data: *au.AudioBufferList,
) callconv(.c) au.OSStatus {
    if (bus != 0 or frame_count != 4 or data.number_buffers != 1)
        return au.status.invalid_element;
    const buffer = &data.buffers[0];
    if (buffer.number_channels != 1 or
        buffer.data_byte_size < 4 * @sizeOf(f32))
        return au.status.format_not_supported;
    const pointer = buffer.data orelse
        return au.status.format_not_supported;
    const samples = @as(
        [*]f32,
        @ptrCast(@alignCast(pointer)),
    )[0..4];
    @memcpy(samples, &[_]f32{ 1, 2, 3, 4 });
    return au.status.success;
}

fn propertyChanged(
    reference: ?*anyopaque,
    _: au.AudioComponentInstance,
    property_id: au.AudioUnitPropertyID,
    _: au.AudioUnitScope,
    _: au.AudioUnitElement,
) callconv(.c) void {
    const state: *PropertyListenerState = @ptrCast(@alignCast(
        reference orelse return,
    ));
    state.calls += 1;
    state.last_property = property_id;
}

fn renderNotified(
    reference: ?*anyopaque,
    action_flags: ?*au.AudioUnitRenderActionFlags,
    _: ?*const au.AudioTimeStamp,
    _: u32,
    _: u32,
    _: *au.AudioBufferList,
) callconv(.c) au.OSStatus {
    const state: *RenderNotifyState = @ptrCast(@alignCast(
        reference orelse return au.status.invalid_property_value,
    ));
    if (state.calls < state.flags.len)
        state.flags[state.calls] =
            if (action_flags) |value| value.* else 0;
    state.calls += 1;
    return au.status.success;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(
        init.arena.allocator(),
    );
    if (args.len != 2) return error.InvalidArguments;

    var library = try std.DynLib.open(args[1]);
    defer library.close();
    const factory = library.lookup(
        FactoryFunction,
        "ZigVst3MonoGainFactory",
    ) orelse return error.MissingFactory;
    const description = au.AudioComponentDescription{
        .component_type = 0x61756678,
        .component_subtype = 0x5a4d476e,
        .component_manufacturer = 0x5a696733,
        .component_flags = 0,
        .component_flags_mask = 0,
    };
    const interface = factory(&description) orelse
        return error.FactoryCreationFailed;
    const opaque_interface: *anyopaque = @ptrCast(interface);
    const instance: au.AudioComponentInstance = @ptrFromInt(1);
    if (interface.open(opaque_interface, instance) != au.status.success)
        return error.OpenFailed;
    errdefer _ = interface.close(opaque_interface);

    const set_property: SetPropertyProc = @ptrCast(@alignCast(
        interface.lookup(au.selector.set_property) orelse
            return error.MissingSetProperty,
    ));
    const add_property_listener: AddPropertyListenerProc =
        @ptrCast(@alignCast(
            interface.lookup(au.selector.add_property_listener) orelse
                return error.MissingAddPropertyListener,
        ));
    const remove_property_listener: RemovePropertyListenerProc =
        @ptrCast(@alignCast(
            interface.lookup(
                au.selector.remove_property_listener_with_user_data,
            ) orelse
                return error.MissingRemovePropertyListener,
        ));
    var property_listener = PropertyListenerState{};
    if (add_property_listener(
        opaque_interface,
        au.property.set_render_callback,
        propertyChanged,
        &property_listener,
    ) != au.status.success) return error.PropertyListenerRegistrationFailed;
    const callback = au.AURenderCallbackStruct{
        .input = pullInput,
        .reference = null,
    };
    if (set_property(
        opaque_interface,
        au.property.set_render_callback,
        au.scope.input,
        0,
        &callback,
        @sizeOf(au.AURenderCallbackStruct),
    ) != au.status.success) return error.InputCallbackFailed;
    if (property_listener.calls != 1 or
        property_listener.last_property !=
            au.property.set_render_callback)
        return error.PropertyListenerNotCalled;
    if (remove_property_listener(
        opaque_interface,
        au.property.set_render_callback,
        propertyChanged,
        &property_listener,
    ) != au.status.success) return error.PropertyListenerRemovalFailed;

    const initialize: InitializeProc = @ptrCast(@alignCast(
        interface.lookup(au.selector.initialize) orelse
            return error.MissingInitialize,
    ));
    if (initialize(opaque_interface) != au.status.success)
        return error.InitializeFailed;

    const schedule: ScheduleParametersProc = @ptrCast(@alignCast(
        interface.lookup(au.selector.schedule_parameters) orelse
            return error.MissingScheduleParameters,
    ));
    var event = au.AudioUnitParameterEvent{
        .parameter_scope = au.scope.global,
        .element = 0,
        .parameter = 0,
        .event_type = au.parameter_event_type.ramped,
        .event_values = .{ .ramp = .{
            .start_buffer_offset = 0,
            .duration_in_frames = 4,
            .start_value = 1.0,
            .end_value = 2.0,
        } },
    };
    if (schedule(
        opaque_interface,
        @ptrCast(&event),
        1,
    ) != au.status.success) return error.ScheduleFailed;

    var output = [_]f32{ 0, 0, 0, 0 };
    var output_list = au.AudioBufferList{
        .number_buffers = 1,
        .buffers = .{.{
            .number_channels = 1,
            .data_byte_size = @sizeOf(@TypeOf(output)),
            .data = &output,
        }},
    };
    var timestamp = au.AudioTimeStamp{
        .sample_time = 0,
        .host_time = 0,
        .rate_scalar = 0,
        .word_clock_time = 0,
        .smpte_time = std.mem.zeroes(au.SMPTETime),
        .flags = au.timestamp_flag.sample_time_valid,
        .reserved = 0,
    };
    var flags: au.AudioUnitRenderActionFlags = 0;
    const render: RenderProc = @ptrCast(@alignCast(
        interface.lookup(au.selector.render) orelse
            return error.MissingRender,
    ));
    const add_render_notify: RenderNotifyProc = @ptrCast(@alignCast(
        interface.lookup(au.selector.add_render_notify) orelse
            return error.MissingAddRenderNotify,
    ));
    const remove_render_notify: RenderNotifyProc = @ptrCast(@alignCast(
        interface.lookup(au.selector.remove_render_notify) orelse
            return error.MissingRemoveRenderNotify,
    ));
    var render_notify = RenderNotifyState{};
    if (add_render_notify(
        opaque_interface,
        renderNotified,
        &render_notify,
    ) != au.status.success) return error.RenderNotifyRegistrationFailed;
    if (render(
        opaque_interface,
        &flags,
        &timestamp,
        0,
        4,
        &output_list,
    ) != au.status.success) return error.RenderFailed;
    if (!std.mem.eql(f32, &output, &[_]f32{ 1, 2.5, 4.5, 7 }))
        return error.InvalidOutput;
    if (flags & au.render_action.output_is_silence != 0)
        return error.UnexpectedSilence;
    if (render_notify.calls != 2 or
        render_notify.flags[0] & au.render_action.pre_render == 0 or
        render_notify.flags[1] & au.render_action.post_render == 0 or
        render_notify.flags[1] &
            au.render_action.post_render_error != 0)
        return error.InvalidRenderNotifications;
    if (remove_render_notify(
        opaque_interface,
        renderNotified,
        &render_notify,
    ) != au.status.success) return error.RenderNotifyRemovalFailed;

    const get_property: GetPropertyProc = @ptrCast(@alignCast(
        interface.lookup(au.selector.get_property) orelse
            return error.MissingGetProperty,
    ));
    var class_info: ?*anyopaque = null;
    var class_info_size: u32 = @sizeOf(?*anyopaque);
    if (get_property(
        opaque_interface,
        au.property.class_info,
        au.scope.global,
        0,
        @ptrCast(&class_info),
        &class_info_size,
    ) != au.status.success) return error.ClassInfoReadFailed;
    const retained_class_info = class_info orelse
        return error.MissingClassInfo;
    defer CFRelease(retained_class_info);
    if (CFDictionaryGetCount(retained_class_info) != 7)
        return error.InvalidClassInfoShape;
    for ([_][]const u8{
        "type",
        "subtype",
        "manufacturer",
        "version",
        "name",
        "preset-number",
        "data",
    }) |key_name| {
        try requireClassInfoKey(retained_class_info, key_name);
    }

    const set_parameter: SetParameterProc = @ptrCast(@alignCast(
        interface.lookup(au.selector.set_parameter) orelse
            return error.MissingSetParameter,
    ));
    if (set_parameter(
        opaque_interface,
        0,
        au.scope.global,
        0,
        0.25,
        0,
    ) != au.status.success) return error.ParameterMutationFailed;
    if (set_property(
        opaque_interface,
        au.property.class_info,
        au.scope.global,
        0,
        @ptrCast(&class_info),
        @sizeOf(?*anyopaque),
    ) != au.status.success) return error.ClassInfoRestoreFailed;

    const get_parameter: GetParameterProc = @ptrCast(@alignCast(
        interface.lookup(au.selector.get_parameter) orelse
            return error.MissingGetParameter,
    ));
    var restored_gain: au.AudioUnitParameterValue = 0;
    if (get_parameter(
        opaque_interface,
        0,
        au.scope.global,
        0,
        &restored_gain,
    ) != au.status.success) return error.ParameterReadFailed;
    if (@abs(restored_gain - 2.0) > 0.000_001)
        return error.InvalidRestoredParameter;

    if (interface.close(opaque_interface) != au.status.success)
        return error.CloseFailed;
}
