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
const InitializeProc =
    *const fn (*anyopaque) callconv(.c) au.OSStatus;
const RenderProc = *const fn (
    *anyopaque,
    ?*au.AudioUnitRenderActionFlags,
    ?*const au.AudioTimeStamp,
    u32,
    u32,
    *au.AudioBufferList,
) callconv(.c) au.OSStatus;

const StereoBufferList = extern struct {
    number_buffers: u32,
    buffers: [2]au.AudioBuffer,
};

const InputState = struct {
    calls: usize = 0,
};

fn pullInput(
    reference: ?*anyopaque,
    _: ?*au.AudioUnitRenderActionFlags,
    _: ?*const au.AudioTimeStamp,
    bus: u32,
    frame_count: u32,
    data: *au.AudioBufferList,
) callconv(.c) au.OSStatus {
    const state: *InputState = @ptrCast(@alignCast(
        reference orelse return au.status.invalid_property_value,
    ));
    if (bus != 0 or frame_count != 4 or data.number_buffers != 2)
        return au.status.invalid_element;
    const list: *StereoBufferList = @ptrCast(@alignCast(data));
    const expected = [_][4]f32{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
    };
    for (&list.buffers, expected) |*buffer, samples| {
        if (buffer.number_channels != 1 or
            buffer.data_byte_size < @sizeOf(@TypeOf(samples)))
            return au.status.format_not_supported;
        const destination = @as(
            [*]f32,
            @ptrCast(@alignCast(
                buffer.data orelse
                    return au.status.format_not_supported,
            )),
        )[0..samples.len];
        @memcpy(destination, &samples);
    }
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
        "ZigVst3AuxOutputSplitterFactory",
    ) orelse return error.MissingFactory;
    const description = au.AudioComponentDescription{
        .component_type = 0x61756678,
        .component_subtype = 0x5a417578,
        .component_manufacturer = 0x5a696733,
        .component_flags = 0,
        .component_flags_mask = 0,
    };
    const interface = factory(&description) orelse
        return error.FactoryCreationFailed;
    const opaque_interface: *anyopaque = @ptrCast(interface);
    if (interface.open(
        opaque_interface,
        @ptrFromInt(1),
    ) != au.status.success) return error.OpenFailed;
    errdefer _ = interface.close(opaque_interface);

    const set_property: SetPropertyProc = @ptrCast(@alignCast(
        interface.lookup(au.selector.set_property) orelse
            return error.MissingSetProperty,
    ));
    var input_state = InputState{};
    const callback = au.AURenderCallbackStruct{
        .input = pullInput,
        .reference = &input_state,
    };
    if (set_property(
        opaque_interface,
        au.property.set_render_callback,
        au.scope.input,
        0,
        &callback,
        @sizeOf(au.AURenderCallbackStruct),
    ) != au.status.success) return error.InputCallbackFailed;

    const initialize: InitializeProc = @ptrCast(@alignCast(
        interface.lookup(au.selector.initialize) orelse
            return error.MissingInitialize,
    ));
    if (initialize(opaque_interface) != au.status.success)
        return error.InitializeFailed;
    const render: RenderProc = @ptrCast(@alignCast(
        interface.lookup(au.selector.render) orelse
            return error.MissingRender,
    ));
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

    var auxiliary_left = [_]f32{ 0, 0, 0, 0 };
    var auxiliary_right = [_]f32{ 0, 0, 0, 0 };
    var auxiliary_stereo = StereoBufferList{
        .number_buffers = 2,
        .buffers = .{
            .{
                .number_channels = 1,
                .data_byte_size = @sizeOf(@TypeOf(auxiliary_left)),
                .data = &auxiliary_left,
            },
            .{
                .number_channels = 1,
                .data_byte_size = @sizeOf(@TypeOf(auxiliary_right)),
                .data = &auxiliary_right,
            },
        },
    };
    if (render(
        opaque_interface,
        &flags,
        &timestamp,
        2,
        4,
        @ptrCast(&auxiliary_stereo),
    ) != au.status.success) return error.AuxiliaryStereoRenderFailed;

    var main_left = [_]f32{ 0, 0, 0, 0 };
    var main_right = [_]f32{ 0, 0, 0, 0 };
    var main_output = StereoBufferList{
        .number_buffers = 2,
        .buffers = .{
            .{
                .number_channels = 1,
                .data_byte_size = @sizeOf(@TypeOf(main_left)),
                .data = &main_left,
            },
            .{
                .number_channels = 1,
                .data_byte_size = @sizeOf(@TypeOf(main_right)),
                .data = &main_right,
            },
        },
    };
    if (render(
        opaque_interface,
        &flags,
        &timestamp,
        0,
        4,
        @ptrCast(&main_output),
    ) != au.status.success) return error.MainRenderFailed;

    var auxiliary_mono = [_]f32{ 0, 0, 0, 0 };
    var mono = au.AudioBufferList{
        .number_buffers = 1,
        .buffers = .{.{
            .number_channels = 1,
            .data_byte_size = @sizeOf(@TypeOf(auxiliary_mono)),
            .data = &auxiliary_mono,
        }},
    };
    if (render(
        opaque_interface,
        &flags,
        &timestamp,
        1,
        4,
        &mono,
    ) != au.status.success) return error.AuxiliaryMonoRenderFailed;

    if (!std.mem.eql(f32, &main_left, &.{ 1, 2, 3, 4 }) or
        !std.mem.eql(f32, &main_right, &.{ 5, 6, 7, 8 }) or
        !std.mem.eql(f32, &auxiliary_mono, &.{ 3, 4, 5, 6 }) or
        !std.mem.eql(f32, &auxiliary_left, &.{ 1, 2, 3, 4 }) or
        !std.mem.eql(f32, &auxiliary_right, &.{ 5, 6, 7, 8 }))
        return error.InvalidOutput;
    if (input_state.calls != 1)
        return error.DuplicateBlockProcessing;
    if (flags & au.render_action.output_is_silence != 0)
        return error.UnexpectedSilence;
    if (interface.close(opaque_interface) != au.status.success)
        return error.CloseFailed;
}
