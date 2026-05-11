const std = @import("std");
const plug = @import("zig-vst3-plugin");

const voice_unit_id: i32 = 1;
const voice_program_list_id: i32 = 7;

pub const VoiceMix = struct {
    pub const name = "zig-vst3-plugin Core Voice Mix";
    pub const vendor = "zig-vst3";
    pub const units = plug.units.Config{
        .units = &.{
            plug.units.Unit.root("Main"),
            .{
                .id = voice_unit_id,
                .name = "Voices",
                .parent_id = plug.units.root_unit_id,
                .program_list_id = voice_program_list_id,
            },
        },
        .program_lists = &.{
            .{
                .id = voice_program_list_id,
                .name = "Voice Presets",
                .programs = &.{
                    .{
                        .name = "Single",
                        .parameters = &.{.{ .parameter_id = 0, .normalized = 0.0 }},
                        .info = &.{.{ .key = "voices", .value = "1" }},
                    },
                    .{
                        .name = "Quad",
                        .parameters = &.{.{ .parameter_id = 0, .normalized = 1.0 }},
                        .info = &.{.{ .key = "voices", .value = "4" }},
                    },
                },
            },
        },
    };
    pub const Params = struct {
        voices: plug.parameters.IntParam = .{ .id = 0, .name = "Voices", .min = 1, .max = 4, .default = 1, .unit_id = voice_unit_id },
    };

    pub fn processWithParameterView(
        _: *VoiceMix,
        context: *plug.process.ProcessContext(f32),
        params: plug.parameters.ParameterView(Params),
    ) void {
        const gain: f32 = @floatFromInt(params.load("voices"));
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample] * gain;
            }
        }
    }
};

pub const Spec = plug.plugin.PluginSpec(VoiceMix);
pub const Instance = plug.plugin.PluginInstance(VoiceMix);
pub const parameter_set = Spec.ParameterSet.init(.{});

test "voice mix core example declares reflected int parameter" {
    const spec = Spec.init(.{});

    try std.testing.expectEqualStrings("zig-vst3-plugin Core Voice Mix", Spec.name);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(usize, 1), parameter_set.parameterCount());
    try std.testing.expectEqual(@as(?i32, voice_unit_id), parameter_set.unitId(0));
    try std.testing.expectEqual(@as(i64, 1), spec.values.view(&parameter_set).load("voices"));
    plug.plugin.validateLifecycle(VoiceMix);
}

test "voice mix core example declares reflected unit and program metadata" {
    var instance = try Instance.init(std.testing.allocator, .{});
    var buffer: [16]u8 = undefined;

    try std.testing.expectEqual(@as(usize, 2), instance.unitCount());
    try std.testing.expect(!instance.unitsEmpty());
    try std.testing.expect(instance.hasUnits());
    const units = instance.unitSet();
    try std.testing.expectEqual(@as(usize, 2), units.unitCount());
    try std.testing.expect(!units.unitsEmpty());
    try std.testing.expect(units.hasUnits());
    try std.testing.expectEqualStrings("Main", units.rootUnitName());
    try std.testing.expectEqual(@as(i32, plug.units.root_unit_id), units.rootUnitId());
    try std.testing.expectEqualStrings("Main", units.rootUnit().name);
    try std.testing.expectEqualStrings("Main", units.unit(0).?.name);
    try std.testing.expectEqualStrings("Voices", units.unitById(voice_unit_id).?.name);
    try std.testing.expectEqual(@as(i32, voice_unit_id), units.unitByName("Voices").?.id);
    try std.testing.expectEqual(@as(?usize, 1), units.unitIndexOfId(voice_unit_id));
    try std.testing.expectEqual(@as(?usize, 1), units.unitIndexOfName("Voices"));
    try std.testing.expect(units.hasUnit(voice_unit_id));
    try std.testing.expect(units.hasUnitName("Voices"));
    try std.testing.expectEqual(@as(?i32, null), units.duplicateUnitId());
    try std.testing.expectEqual(@as(?usize, null), units.duplicateUnitIdIndex());
    try std.testing.expect(!units.hasDuplicateUnitIds());
    try std.testing.expectEqual(@as(?[]const u8, null), units.duplicateUnitName());
    try std.testing.expectEqual(@as(?usize, null), units.duplicateUnitNameIndex());
    try std.testing.expect(!units.hasDuplicateUnitNames());
    try std.testing.expectEqual(@as(usize, 1), units.programListCount());
    try std.testing.expect(!units.programListsEmpty());
    try std.testing.expect(units.hasProgramLists());
    try std.testing.expectEqualStrings("Voice Presets", units.programList(0).?.name);
    try std.testing.expectEqualStrings("Voice Presets", units.programListById(voice_program_list_id).?.name);
    try std.testing.expectEqual(@as(i32, voice_program_list_id), units.programListByName("Voice Presets").?.id);
    try std.testing.expectEqual(@as(?usize, 0), units.programListIndexOfId(voice_program_list_id));
    try std.testing.expectEqual(@as(?usize, 0), units.programListIndexOfName("Voice Presets"));
    try std.testing.expect(units.hasProgramList(voice_program_list_id));
    try std.testing.expect(units.hasProgramListName("Voice Presets"));
    try std.testing.expectEqual(@as(?i32, null), units.duplicateProgramListId());
    try std.testing.expectEqual(@as(?usize, null), units.duplicateProgramListIdIndex());
    try std.testing.expect(!units.hasDuplicateProgramListIds());
    try std.testing.expectEqual(@as(?[]const u8, null), units.duplicateProgramListName());
    try std.testing.expectEqual(@as(?usize, null), units.duplicateProgramListNameIndex());
    try std.testing.expect(!units.hasDuplicateProgramListNames());
    try std.testing.expectEqualStrings("Voice Presets", units.programListForUnitName("Voices").?.name);
    try std.testing.expectEqualStrings("Voice Presets", units.programListForUnit(voice_unit_id).?.name);
    try std.testing.expectEqual(@as(?i32, voice_program_list_id), units.programListIdForUnit(voice_unit_id));
    try std.testing.expectEqual(@as(?i32, voice_program_list_id), units.programListIdForUnitName("Voices"));
    try std.testing.expectEqualStrings("Voice Presets", units.programListNameForUnit(voice_unit_id).?);
    try std.testing.expectEqualStrings("Voice Presets", units.programListNameForUnitName("Voices").?);
    try std.testing.expect(units.programListHasPrograms(voice_program_list_id));
    try std.testing.expect(units.programListHasProgramsByName("Voice Presets"));
    try std.testing.expect(!units.programListEmpty(voice_program_list_id));
    try std.testing.expect(!units.programListEmptyByName("Voice Presets"));
    try std.testing.expectEqual(@as(?usize, 2), units.programCount(voice_program_list_id));
    try std.testing.expectEqualStrings("Quad", units.programName(voice_program_list_id, 1).?);
    try std.testing.expectEqualStrings("Quad", units.program(voice_program_list_id, 1).?.name);
    try std.testing.expectEqualStrings("Quad", units.programByName(voice_program_list_id, "Quad").?.name);
    try std.testing.expectEqual(@as(?usize, 1), units.programIndexOfName(voice_program_list_id, "Quad"));
    try std.testing.expect(units.hasProgramName(voice_program_list_id, "Quad"));
    try std.testing.expectEqual(@as(?[]const u8, null), units.duplicateProgramName(voice_program_list_id));
    try std.testing.expectEqual(@as(?usize, null), units.duplicateProgramNameIndex(voice_program_list_id));
    try std.testing.expect(!units.hasDuplicateProgramNames(voice_program_list_id));
    try std.testing.expectEqual(@as(?usize, 1), units.programParameterCount(voice_program_list_id, 1));
    try std.testing.expectEqual(@as(?usize, 1), units.programParameterCountByName(voice_program_list_id, "Quad"));
    try std.testing.expect(units.programHasParameters(voice_program_list_id, 1));
    try std.testing.expect(units.programHasParametersByName(voice_program_list_id, "Quad"));
    try std.testing.expect(!units.programParametersEmpty(voice_program_list_id, 1));
    try std.testing.expect(!units.programParametersEmptyByName(voice_program_list_id, "Quad"));
    try std.testing.expectEqual(@as(f64, 1.0), units.programParameter(voice_program_list_id, 1, 0).?.normalized);
    try std.testing.expectEqual(@as(f64, 1.0), units.programParameterByName(voice_program_list_id, "Quad", 0).?.normalized);
    try std.testing.expectEqual(@as(f64, 1.0), units.programParameterById(voice_program_list_id, 1, 0).?.normalized);
    try std.testing.expectEqual(@as(?usize, 0), units.programParameterIndexOfId(voice_program_list_id, 1, 0));
    try std.testing.expect(units.hasProgramParameter(voice_program_list_id, 1, 0));
    try std.testing.expectEqual(@as(?u32, null), units.duplicateProgramParameterId(voice_program_list_id, 1));
    try std.testing.expectEqual(@as(?usize, null), units.duplicateProgramParameterIdIndex(voice_program_list_id, 1));
    try std.testing.expect(!units.hasDuplicateProgramParameterIds(voice_program_list_id, 1));
    try std.testing.expectEqual(@as(f64, 1.0), units.programParameterByNameAndId(voice_program_list_id, "Quad", 0).?.normalized);
    try std.testing.expectEqual(@as(?usize, 0), units.programParameterIndexOfIdByName(voice_program_list_id, "Quad", 0));
    try std.testing.expect(units.hasProgramParameterByName(voice_program_list_id, "Quad", 0));
    try std.testing.expectEqual(@as(?u32, null), units.duplicateProgramParameterIdByName(voice_program_list_id, "Quad"));
    try std.testing.expectEqual(@as(?usize, null), units.duplicateProgramParameterIdIndexByName(voice_program_list_id, "Quad"));
    try std.testing.expect(!units.hasDuplicateProgramParameterIdsByName(voice_program_list_id, "Quad"));
    try std.testing.expectEqual(@as(?usize, 1), units.programInfoCount(voice_program_list_id, 1));
    try std.testing.expectEqual(@as(?usize, 1), units.programInfoCountByName(voice_program_list_id, "Quad"));
    try std.testing.expect(units.programHasInfoEntries(voice_program_list_id, 1));
    try std.testing.expect(units.programHasInfoEntriesByName(voice_program_list_id, "Quad"));
    try std.testing.expect(!units.programInfoEmpty(voice_program_list_id, 1));
    try std.testing.expect(!units.programInfoEmptyByName(voice_program_list_id, "Quad"));
    try std.testing.expectEqualStrings("4", units.programInfo(voice_program_list_id, 1, "voices").?);
    try std.testing.expectEqualStrings("voices", units.programInfoEntry(voice_program_list_id, 1, 0).?.key);
    try std.testing.expectEqual(@as(?usize, 0), units.programInfoIndexOfKey(voice_program_list_id, 1, "voices"));
    try std.testing.expect(units.hasProgramInfo(voice_program_list_id, 1, "voices"));
    try std.testing.expectEqual(@as(?[]const u8, null), units.duplicateProgramInfoKey(voice_program_list_id, 1));
    try std.testing.expectEqual(@as(?usize, null), units.duplicateProgramInfoKeyIndex(voice_program_list_id, 1));
    try std.testing.expect(!units.hasDuplicateProgramInfoKeys(voice_program_list_id, 1));
    try std.testing.expectEqualStrings("4", units.programInfoByName(voice_program_list_id, "Quad", "voices").?);
    try std.testing.expectEqualStrings("voices", units.programInfoEntryByName(voice_program_list_id, "Quad", 0).?.key);
    try std.testing.expectEqual(@as(?usize, 0), units.programInfoIndexOfKeyByName(voice_program_list_id, "Quad", "voices"));
    try std.testing.expect(units.hasProgramInfoByName(voice_program_list_id, "Quad", "voices"));
    try std.testing.expectEqual(@as(?[]const u8, null), units.duplicateProgramInfoKeyByName(voice_program_list_id, "Quad"));
    try std.testing.expectEqual(@as(?usize, null), units.duplicateProgramInfoKeyIndexByName(voice_program_list_id, "Quad"));
    try std.testing.expect(!units.hasDuplicateProgramInfoKeysByName(voice_program_list_id, "Quad"));
    try std.testing.expectEqual(@as(i32, plug.units.root_unit_id), instance.rootUnitId());
    try std.testing.expectEqualStrings("Main", instance.rootUnitName());
    const root_unit = instance.rootUnit();
    try std.testing.expect(root_unit.isRoot());
    try std.testing.expect(!root_unit.hasParent());
    try std.testing.expect(!root_unit.hasProgramList());
    const voice_unit = instance.unitById(voice_unit_id).?;
    try std.testing.expectEqualStrings("Voices", instance.unit(1).?.name);
    try std.testing.expect(!voice_unit.isRoot());
    try std.testing.expect(voice_unit.hasParent());
    try std.testing.expect(voice_unit.hasProgramList());
    try std.testing.expectEqualStrings("Voices", instance.unitById(voice_unit_id).?.name);
    try std.testing.expectEqual(@as(i32, voice_unit_id), instance.unitByName("Voices").?.id);
    try std.testing.expectEqual(@as(?usize, 1), instance.unitIndexOfId(voice_unit_id));
    try std.testing.expectEqual(@as(?usize, 1), instance.unitIndexOfName("Voices"));
    try std.testing.expect(instance.hasUnit(voice_unit_id));
    try std.testing.expect(instance.hasUnitName("Voices"));
    const descriptor = instance.parameterFieldDescriptor("voices");
    try std.testing.expect(descriptor.containsPlain(4));
    try std.testing.expect(!descriptor.containsPlain(0));
    try std.testing.expectEqual(@as(i64, 1), descriptor.clampPlain(0));
    try std.testing.expectEqual(@as(i64, 4), descriptor.clampPlain(9));
    try std.testing.expectEqual(@as(f64, 1.0), descriptor.normalize(4));
    try std.testing.expectEqual(@as(i64, 3), descriptor.denormalize(0.5));
    try std.testing.expectEqual(@as(f64, 0.0), descriptor.defaultNormalized());
    try std.testing.expectEqualStrings("4", try descriptor.formatPlain(1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 4.0), descriptor.plainFromNormalized(1.0));
    try std.testing.expectEqual(@as(f64, 1.0), descriptor.normalizedFromPlain(4.0));
    try std.testing.expectEqual(@as(f64, 1.0), try descriptor.parsePlain("4"));
    try std.testing.expectEqual(@as(?i32, null), instance.duplicateUnitId());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateUnitIdIndex());
    try std.testing.expect(!instance.hasDuplicateUnitIds());
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateUnitName());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateUnitNameIndex());
    try std.testing.expect(!instance.hasDuplicateUnitNames());
    try std.testing.expect(instance.unitIsRootByName("Main"));
    try std.testing.expect(!instance.unitIsRoot(voice_unit_id));
    try std.testing.expect(instance.unitHasParent(voice_unit_id));
    try std.testing.expectEqual(@as(?i32, plug.units.root_unit_id), instance.unitParentIdByName("Voices"));
    try std.testing.expect(instance.unitHasProgramList(voice_unit_id));
    try std.testing.expect(instance.unitHasProgramListByName("Voices"));
    try std.testing.expect(!instance.unitHasProgramListByName("Main"));
    try std.testing.expect(instance.unitHasParentByName("Voices"));
    try std.testing.expect(!instance.unitHasParentByName("Main"));
    try std.testing.expectEqual(@as(?i32, plug.units.root_unit_id), instance.unitParentId(voice_unit_id));
    try std.testing.expectEqual(@as(?i32, null), instance.unitParentId(plug.units.root_unit_id));
    try std.testing.expectEqualStrings("Voice Presets", instance.programListForUnit(voice_unit_id).?.name);
    try std.testing.expectEqual(@as(i32, voice_program_list_id), instance.programListForUnitName("Voices").?.id);
    try std.testing.expectEqual(@as(?i32, voice_program_list_id), instance.programListIdForUnit(voice_unit_id));
    try std.testing.expectEqual(@as(?i32, voice_program_list_id), instance.programListIdForUnitName("Voices"));
    try std.testing.expectEqualStrings("Voice Presets", instance.programListNameForUnit(voice_unit_id).?);
    try std.testing.expectEqualStrings("Voice Presets", instance.programListNameForUnitName("Voices").?);
    try std.testing.expectEqual(@as(usize, 1), instance.programListCount());
    try std.testing.expect(!instance.programListsEmpty());
    try std.testing.expect(instance.hasProgramLists());
    try std.testing.expectEqualStrings("Voice Presets", instance.programList(0).?.name);
    try std.testing.expectEqualStrings("Voice Presets", instance.programListById(voice_program_list_id).?.name);
    try std.testing.expectEqual(@as(i32, voice_program_list_id), instance.programListByName("Voice Presets").?.id);
    try std.testing.expectEqual(@as(?usize, 0), instance.programListIndexOfId(voice_program_list_id));
    try std.testing.expectEqual(@as(?usize, 0), instance.programListIndexOfName("Voice Presets"));
    try std.testing.expect(instance.hasProgramList(voice_program_list_id));
    try std.testing.expect(instance.hasProgramListName("Voice Presets"));
    const program_list = instance.programListByName("Voice Presets").?;
    try std.testing.expectEqual(@as(usize, 2), program_list.programCount());
    try std.testing.expect(!program_list.isEmpty());
    try std.testing.expect(program_list.hasPrograms());
    try std.testing.expectEqualStrings("Single", program_list.program(0).?.name);
    try std.testing.expectEqual(@as(?usize, 1), program_list.programIndexOfName("Quad"));
    try std.testing.expectEqualStrings("Quad", program_list.programByName("Quad").?.name);
    try std.testing.expect(program_list.hasProgramName("Single"));
    try std.testing.expect(program_list.programByName("Missing") == null);
    try std.testing.expectEqual(@as(?[]const u8, null), program_list.duplicateProgramName());
    try std.testing.expectEqual(@as(?usize, null), program_list.duplicateProgramNameIndex());
    try std.testing.expect(!program_list.hasDuplicateProgramNames());
    try std.testing.expectEqual(@as(?i32, null), instance.duplicateProgramListId());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramListIdIndex());
    try std.testing.expect(!instance.hasDuplicateProgramListIds());
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramListName());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramListNameIndex());
    try std.testing.expect(!instance.hasDuplicateProgramListNames());
    try std.testing.expect(instance.programListHasPrograms(voice_program_list_id));
    try std.testing.expect(instance.programListHasProgramsByName("Voice Presets"));
    try std.testing.expect(!instance.programListEmpty(voice_program_list_id));
    try std.testing.expect(!instance.programListEmptyByName("Voice Presets"));
    try std.testing.expectEqual(@as(?usize, 2), instance.programCount(voice_program_list_id));
    try std.testing.expectEqualStrings("Quad", instance.programName(voice_program_list_id, 1).?);
    try std.testing.expectEqualStrings("Quad", instance.program(voice_program_list_id, 1).?.name);
    try std.testing.expectEqualStrings("Quad", instance.programByName(voice_program_list_id, "Quad").?.name);
    try std.testing.expectEqual(@as(?usize, 1), instance.programIndexOfName(voice_program_list_id, "Quad"));
    try std.testing.expect(instance.hasProgramName(voice_program_list_id, "Quad"));
    const quad_program = instance.programByName(voice_program_list_id, "Quad").?;
    try std.testing.expectEqual(@as(usize, 1), quad_program.parameterCount());
    try std.testing.expectEqual(@as(usize, 1), quad_program.infoCount());
    try std.testing.expect(quad_program.hasParameters());
    try std.testing.expect(!quad_program.parametersEmpty());
    try std.testing.expect(quad_program.hasInfo());
    try std.testing.expect(!quad_program.infoEmpty());
    try std.testing.expectEqual(@as(u32, 0), quad_program.parameter(0).?.parameter_id);
    try std.testing.expect(quad_program.hasParameter(0));
    try std.testing.expectEqual(@as(?usize, 0), quad_program.parameterIndexOfId(0));
    try std.testing.expectEqual(@as(f64, 1.0), quad_program.parameterById(0).?.normalized);
    try std.testing.expectEqualStrings("4", quad_program.infoEntry(0).?.value);
    try std.testing.expect(quad_program.hasInfoKey("voices"));
    try std.testing.expectEqual(@as(?usize, 0), quad_program.infoIndexOfKey("voices"));
    try std.testing.expectEqualStrings("4", quad_program.infoValue("voices").?);
    try std.testing.expectEqual(@as(?u32, null), quad_program.duplicateParameterId());
    try std.testing.expectEqual(@as(?usize, null), quad_program.duplicateParameterIdIndex());
    try std.testing.expect(!quad_program.hasDuplicateParameterIds());
    try std.testing.expectEqual(@as(?[]const u8, null), quad_program.duplicateInfoKey());
    try std.testing.expectEqual(@as(?usize, null), quad_program.duplicateInfoKeyIndex());
    try std.testing.expect(!quad_program.hasDuplicateInfoKeys());
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramName(voice_program_list_id));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramNameIndex(voice_program_list_id));
    try std.testing.expect(!instance.hasDuplicateProgramNames(voice_program_list_id));
    try std.testing.expectEqual(@as(?usize, 1), instance.programParameterCount(voice_program_list_id, 1));
    try std.testing.expectEqual(@as(?usize, 1), instance.programParameterCountByName(voice_program_list_id, "Quad"));
    try std.testing.expect(instance.programHasParameters(voice_program_list_id, 1));
    try std.testing.expect(instance.programHasParametersByName(voice_program_list_id, "Quad"));
    try std.testing.expect(!instance.programParametersEmpty(voice_program_list_id, 1));
    try std.testing.expect(!instance.programParametersEmptyByName(voice_program_list_id, "Quad"));
    try std.testing.expectEqual(@as(f64, 1.0), instance.programParameter(voice_program_list_id, 1, 0).?.normalized);
    try std.testing.expectEqual(@as(f64, 1.0), instance.programParameterByName(voice_program_list_id, "Quad", 0).?.normalized);
    try std.testing.expectEqual(@as(f64, 1.0), instance.programParameterById(voice_program_list_id, 1, 0).?.normalized);
    try std.testing.expectEqual(@as(?usize, 0), instance.programParameterIndexOfId(voice_program_list_id, 1, 0));
    try std.testing.expect(instance.hasProgramParameter(voice_program_list_id, 1, 0));
    try std.testing.expectEqual(@as(?u32, null), instance.duplicateProgramParameterId(voice_program_list_id, 1));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramParameterIdIndex(voice_program_list_id, 1));
    try std.testing.expect(!instance.hasDuplicateProgramParameterIds(voice_program_list_id, 1));
    try std.testing.expectEqual(@as(f64, 1.0), instance.programParameterByNameAndId(voice_program_list_id, "Quad", 0).?.normalized);
    try std.testing.expectEqual(@as(?usize, 0), instance.programParameterIndexOfIdByName(voice_program_list_id, "Quad", 0));
    try std.testing.expect(instance.hasProgramParameterByName(voice_program_list_id, "Quad", 0));
    try std.testing.expectEqual(@as(?u32, null), instance.duplicateProgramParameterIdByName(voice_program_list_id, "Quad"));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramParameterIdIndexByName(voice_program_list_id, "Quad"));
    try std.testing.expect(!instance.hasDuplicateProgramParameterIdsByName(voice_program_list_id, "Quad"));
    try std.testing.expectEqual(@as(?usize, 1), instance.programInfoCount(voice_program_list_id, 1));
    try std.testing.expectEqual(@as(?usize, 1), instance.programInfoCountByName(voice_program_list_id, "Quad"));
    try std.testing.expect(instance.programHasInfoEntries(voice_program_list_id, 1));
    try std.testing.expect(instance.programHasInfoEntriesByName(voice_program_list_id, "Quad"));
    try std.testing.expect(!instance.programInfoEmpty(voice_program_list_id, 1));
    try std.testing.expect(!instance.programInfoEmptyByName(voice_program_list_id, "Quad"));
    try std.testing.expectEqualStrings("voices", instance.programInfoEntry(voice_program_list_id, 1, 0).?.key);
    try std.testing.expectEqual(@as(?usize, 0), instance.programInfoIndexOfKey(voice_program_list_id, 1, "voices"));
    try std.testing.expect(instance.hasProgramInfo(voice_program_list_id, 1, "voices"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramInfoKey(voice_program_list_id, 1));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramInfoKeyIndex(voice_program_list_id, 1));
    try std.testing.expect(!instance.hasDuplicateProgramInfoKeys(voice_program_list_id, 1));
    try std.testing.expectEqualStrings("4", instance.programInfoByName(voice_program_list_id, "Quad", "voices").?);
    try std.testing.expectEqualStrings("voices", instance.programInfoEntryByName(voice_program_list_id, "Quad", 0).?.key);
    try std.testing.expectEqual(@as(?usize, 0), instance.programInfoIndexOfKeyByName(voice_program_list_id, "Quad", "voices"));
    try std.testing.expect(instance.hasProgramInfoByName(voice_program_list_id, "Quad", "voices"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramInfoKeyByName(voice_program_list_id, "Quad"));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramInfoKeyIndexByName(voice_program_list_id, "Quad"));
    try std.testing.expect(!instance.hasDuplicateProgramInfoKeysByName(voice_program_list_id, "Quad"));
}

test "voice mix core example applies reflected program snapshots" {
    var instance = try Instance.init(std.testing.allocator, .{});

    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramCount(voice_program_list_id, 1));
    try std.testing.expectEqual(@as(i64, 4), instance.loadParameter("voices"));
    try std.testing.expectEqual(@as(?usize, 0), try instance.applyProgramCount(voice_program_list_id, 1));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramByNameCount(voice_program_list_id, "Single"));
    try std.testing.expectEqual(@as(i64, 1), instance.loadParameter("voices"));
    try std.testing.expect(try instance.applyProgram(voice_program_list_id, 1));
    try std.testing.expectEqual(@as(i64, 4), instance.loadParameter("voices"));
    try std.testing.expect(try instance.applyProgramByName(voice_program_list_id, "Single"));
    try std.testing.expectEqual(@as(i64, 1), instance.loadParameter("voices"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramByNameForUnitCount(voice_unit_id, "Quad"));
    try std.testing.expectEqual(@as(i64, 4), instance.loadParameter("voices"));
    try std.testing.expect(try instance.applyProgramByNameForUnit(voice_unit_id, "Quad"));
    try std.testing.expectEqual(@as(i64, 4), instance.loadParameter("voices"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramByNameForUnitNameCount("Voices", "Single"));
    try std.testing.expectEqual(@as(i64, 1), instance.loadParameter("voices"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramForUnitCount(voice_unit_id, 1));
    try std.testing.expectEqual(@as(i64, 4), instance.loadParameter("voices"));
    try std.testing.expect(try instance.applyProgramForUnit(voice_unit_id, 1));
    try std.testing.expectEqual(@as(i64, 4), instance.loadParameter("voices"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramForUnitNameCount("Voices", 0));
    try std.testing.expectEqual(@as(i64, 1), instance.loadParameter("voices"));
    try std.testing.expect(try instance.applyProgramForUnitName("Voices", 1));
    try std.testing.expectEqual(@as(i64, 4), instance.loadParameter("voices"));
    try std.testing.expect(try instance.applyProgramByNameForUnitName("Voices", "Quad"));
    try std.testing.expectEqual(@as(i64, 4), instance.loadParameter("voices"));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramCount(voice_program_list_id, 99));
    try std.testing.expect(!try instance.applyProgramByNameForUnit(voice_unit_id, "Missing"));
    try std.testing.expect(!try instance.applyProgramByNameForUnitName("Missing", "Quad"));
}

test "voice mix core example formats and parses int parameters" {
    var instance = try Instance.init(std.testing.allocator, .{});
    var buffer: [16]u8 = undefined;

    try std.testing.expectEqual(@as(?u32, 0), instance.parameterIdByName("Voices"));
    try std.testing.expectEqual(@as(?usize, 0), instance.parameterIndexOfName("Voices"));
    try std.testing.expectEqual(@as(?i32, voice_unit_id), instance.parameterUnitIdByName("Voices"));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultNormalizedByName("Voices"));
    try std.testing.expectEqual(@as(?i32, 3), instance.parameterStepCountByName("Voices"));

    try std.testing.expectEqualStrings("3", try instance.formatParameterPlainByName("Voices", 2.0 / 3.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try instance.parseParameterPlainByName("Voices", "4"));
    try std.testing.expect(instance.storeParameterPlainByName("Voices", 4.0));
    try std.testing.expectEqual(@as(i64, 4), instance.loadParameter("voices"));
    try std.testing.expect(instance.resetParameterToDefaultByName("Voices"));
    try std.testing.expectEqual(@as(i64, 1), instance.loadParameter("voices"));
}

test "voice mix core example applies int parameter changes" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5, 1.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        instance.parameterChange("voices", 0, 4),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
    });

    instance.process(&context);

    try std.testing.expectEqual(@as(f32, 1.0), output[0]);
    try std.testing.expectEqual(@as(f32, 2.0), output[1]);
    try std.testing.expectEqual(@as(f32, 4.0), output[2]);
}

test "voice mix core example can run through plugin instance" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        instance.parameterChange("voices", 0, 4),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
    });

    instance.process(&context);

    try std.testing.expectEqual(@as(i64, 4), instance.loadParameter("voices"));
    try std.testing.expectEqual(@as(f32, 1.0), output[0]);
    try std.testing.expectEqual(@as(f32, 2.0), output[1]);
}
