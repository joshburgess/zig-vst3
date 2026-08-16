const std = @import("std");
const plug = @import("zig-vst3-plugin");
const core = @import("zig-vst3-plugin-core");
const vst3 = @import("zig-vst3");

const component_cid = vst3.tuid.inlineUid(0x57B0E4A1, 0xA130416D, 0xBB84B987, 0x33C839A2);
const controller_cid = vst3.tuid.inlineUid(0x8CB9E501, 0x11994947, 0xA3C6E453, 0x5BA0CF82);

const LegacyParams = struct {
    amount: core.parameters.FloatParam = .{ .id = 1, .name = "Amount", .min = 0.0, .max = 1.0, .default = 0.0 },
    retired: core.parameters.FloatParam = .{ .id = 99, .name = "Retired", .min = 0.0, .max = 1.0, .default = 0.0 },
};

const CurrentDefinition = struct {
    pub const name = "Downstream Saturator";
    pub const vendor = "Downstream Fixture";
    pub const Params = struct {
        drive: core.parameters.FloatParam = .{ .id = 10, .name = "Drive", .min = 0.0, .max = 24.0, .default = 0.0 },
        mix: core.parameters.FloatParam = .{ .id = 20, .name = "Mix", .min = 0.0, .max = 100.0, .default = 100.0 },
    };
};

test "pre-candidate source paths have documented RC1 replacements" {
    try std.testing.expectEqualStrings("0.3.0", plug.version);
    try std.testing.expect(@hasDecl(core.lv2.metadata, "Metadata"));
    try std.testing.expect(!@hasDecl(plug, "backendVersion"));
    try std.testing.expect(!@hasDecl(core, "lv2_metadata"));
}

test "upgrade preserves class ids and migrates retained state" {
    try std.testing.expectEqual(
        component_cid,
        vst3.tuid.inlineUid(0x57B0E4A1, 0xA130416D, 0xBB84B987, 0x33C839A2),
    );
    try std.testing.expectEqual(
        controller_cid,
        vst3.tuid.inlineUid(0x8CB9E501, 0x11994947, 0xA3C6E453, 0x5BA0CF82),
    );

    const LegacySet = core.parameters.ParameterSet(LegacyParams);
    const LegacyValues = core.parameters.ParameterValues(LegacyParams);
    const legacy_set = LegacySet.init(.{});
    var legacy_values = LegacyValues.init(&legacy_set);
    try std.testing.expect(legacy_values.storeField(&legacy_set, "amount", 0.5));
    try std.testing.expect(legacy_values.storeField(&legacy_set, "retired", 0.25));
    var encoded: [core.state.encodedSize(LegacyParams)]u8 = undefined;
    var writer = std.Io.Writer.fixed(&encoded);
    try core.state.writeParameterState(LegacyParams, &legacy_set, &legacy_values, &writer);

    const CurrentInstance = core.plugin.PluginInstance(CurrentDefinition);
    var current = try CurrentInstance.init(std.testing.allocator, .{});
    var reader = std.Io.Reader.fixed(writer.buffered());
    const report = try current.readParameterStateWithMigrationsReport(
        &reader,
        &.{.{ .old_id = 1, .new_id = 10 }},
    );
    try std.testing.expectEqual(@as(usize, 2), report.entry_count);
    try std.testing.expectEqual(@as(usize, 1), report.restored_count);
    try std.testing.expectEqual(@as(usize, 1), report.ignored_count);
    try std.testing.expect(report.isRestoredAndIgnoredClassification());
    try std.testing.expectEqual(@as(f64, 0.5), current.loadParameterById(10).?);
    try std.testing.expectEqual(@as(f64, 1.0), current.loadParameterById(20).?);
}
