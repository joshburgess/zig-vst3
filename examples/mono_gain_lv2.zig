const core = @import("zig-vst3-plugin-core");
const shared = @import("mono_gain_lv2_shared.zig");

pub const MonoGain = shared.MonoGain;
pub const uri = shared.uri;
pub const Adapter = shared.Adapter;

pub export fn lv2_descriptor(
    index: u32,
) callconv(.c) ?*const core.lv2.Descriptor {
    return Adapter.descriptorAt(index);
}

test "Mono Gain exports one LV2 descriptor" {
    const std = @import("std");
    const descriptor = lv2_descriptor(0) orelse
        return error.MissingDescriptor;
    try std.testing.expectEqualStrings(
        uri,
        std.mem.span(descriptor.URI),
    );
    try std.testing.expect(lv2_descriptor(1) == null);
    try std.testing.expectEqual(@as(usize, 6), Adapter.port_count);
}
