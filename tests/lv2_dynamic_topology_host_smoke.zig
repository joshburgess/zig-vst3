const core = @import("zig-vst3-plugin-core");
const std = @import("std");

const DescriptorFunction = *const fn (
    index: u32,
) callconv(.c) ?*const core.lv2.Descriptor;

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
        "https://zig-vst3.dev/tests/lv2-dynamic-topology",
    )) return error.InvalidPluginUri;

    const empty_features = [_:null]?*const core.lv2.Feature{};
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/lv2-dynamic-topology.lv2",
        &empty_features,
    ) orelse return error.InstantiateFailed;
    defer descriptor.cleanup(handle);

    const input_left = [_]f32{ 0.25, -0.5, 0.75, -1.0 };
    const input_right = [_]f32{ 1.0, -0.75, 0.5, -0.25 };
    const auxiliary_input_left = [_]f32{ 0.1, 0.2, 0.3, 0.4 };
    const auxiliary_input_right = [_]f32{ -0.4, -0.3, -0.2, -0.1 };
    var output_left = [_]f32{0.0} ** 4;
    var output_right = [_]f32{0.0} ** 4;
    var auxiliary_output_left = [_]f32{0.0} ** 4;
    var auxiliary_output_right = [_]f32{0.0} ** 4;
    var latency: f32 = -1.0;

    descriptor.connect_port(handle, 0, @constCast(&input_left));
    descriptor.connect_port(handle, 1, @constCast(&input_right));
    descriptor.connect_port(handle, 2, null);
    descriptor.connect_port(handle, 3, null);
    descriptor.connect_port(handle, 4, &output_left);
    descriptor.connect_port(handle, 5, &output_right);
    descriptor.connect_port(handle, 6, null);
    descriptor.connect_port(handle, 7, null);
    descriptor.connect_port(handle, 8, &latency);

    if (descriptor.activate) |activate| activate(handle);
    descriptor.run(handle, input_left.len);
    try requireSamples(&input_left, &output_left);
    try requireSamples(&input_right, &output_right);
    if (latency != 0.0) return error.InvalidLatency;

    descriptor.connect_port(
        handle,
        2,
        @constCast(&auxiliary_input_left),
    );
    descriptor.connect_port(
        handle,
        3,
        @constCast(&auxiliary_input_right),
    );
    descriptor.connect_port(handle, 6, &auxiliary_output_left);
    descriptor.connect_port(handle, 7, &auxiliary_output_right);
    descriptor.run(handle, input_left.len);
    try requireSamples(
        &[_]f32{ 0.35, -0.3, 1.05, -0.6 },
        &output_left,
    );
    try requireSamples(
        &[_]f32{ 0.6, -1.05, 0.3, -0.35 },
        &output_right,
    );
    try requireSamples(
        &[_]f32{ 0.5, -1.0, 1.5, -2.0 },
        &auxiliary_output_left,
    );
    try requireSamples(
        &[_]f32{ 2.0, -1.5, 1.0, -0.5 },
        &auxiliary_output_right,
    );

    descriptor.connect_port(handle, 2, null);
    descriptor.connect_port(handle, 3, null);
    descriptor.connect_port(handle, 6, null);
    descriptor.connect_port(handle, 7, null);
    output_left = @splat(0.0);
    output_right = @splat(0.0);
    descriptor.run(handle, input_left.len);
    try requireSamples(&input_left, &output_left);
    try requireSamples(&input_right, &output_right);

    descriptor.connect_port(
        handle,
        2,
        @constCast(&auxiliary_input_left),
    );
    output_left = @splat(1.0);
    output_right = @splat(1.0);
    descriptor.run(handle, input_left.len);
    try requireSilence(&output_left);
    try requireSilence(&output_right);

    descriptor.connect_port(
        handle,
        3,
        @constCast(&auxiliary_input_right),
    );
    descriptor.connect_port(handle, 6, &auxiliary_output_left);
    descriptor.connect_port(handle, 7, null);
    output_left = @splat(1.0);
    output_right = @splat(1.0);
    auxiliary_output_left = @splat(1.0);
    auxiliary_output_right = @splat(1.0);
    descriptor.run(handle, input_left.len);
    try requireSilence(&output_left);
    try requireSilence(&output_right);
    try requireSilence(&auxiliary_output_left);
    try requireSamples(
        &[_]f32{ 1.0, 1.0, 1.0, 1.0 },
        &auxiliary_output_right,
    );

    descriptor.connect_port(handle, 7, &auxiliary_output_right);
    descriptor.run(handle, input_left.len);
    try requireSamples(
        &[_]f32{ 0.35, -0.3, 1.05, -0.6 },
        &output_left,
    );
    try requireSamples(
        &[_]f32{ 2.0, -1.5, 1.0, -0.5 },
        &auxiliary_output_right,
    );

    if (descriptor.deactivate) |deactivate| deactivate(handle);
}

fn requireSamples(
    expected: []const f32,
    actual: []const f32,
) !void {
    if (!std.mem.eql(f32, expected, actual))
        return error.UnexpectedSamples;
}

fn requireSilence(samples: []const f32) !void {
    for (samples) |sample|
        if (sample != 0.0) return error.ExpectedSilence;
}
