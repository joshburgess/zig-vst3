const std = @import("std");
const units = @import("../units.zig");

const root_unit_id = units.root_unit_id;
const no_parent_unit_id = units.no_parent_unit_id;
const no_program_list_id = units.no_program_list_id;
const Unit = units.Unit;
const Program = units.Program;
const ProgramParameter = units.ProgramParameter;
const ProgramInfo = units.ProgramInfo;
const ProgramList = units.ProgramList;
const UnitSet = units.UnitSet;

test "default unit set exposes root unit only" {
    const Set = UnitSet(.{});
    const set = Set{};

    try std.testing.expectEqual(@as(usize, 1), set.unitCount());
    try std.testing.expect(!set.unitsEmpty());
    try std.testing.expect(set.hasUnits());
    try std.testing.expectEqual(@as(usize, 0), set.programListCount());
    try std.testing.expect(set.programListsEmpty());
    try std.testing.expect(!set.hasProgramLists());
    try std.testing.expectEqual(@as(?i32, null), set.duplicateUnitId());
    try std.testing.expectEqual(@as(?usize, null), set.duplicateUnitIdIndex());
    try std.testing.expect(!set.hasDuplicateUnitIds());
    try std.testing.expectEqual(@as(?[]const u8, null), set.duplicateUnitName());
    try std.testing.expectEqual(@as(?usize, null), set.duplicateUnitNameIndex());
    try std.testing.expect(!set.hasDuplicateUnitNames());
    try std.testing.expectEqual(@as(?usize, null), set.cyclicUnitParentIndex());
    try std.testing.expectEqual(@as(?i32, null), set.duplicateProgramListId());
    try std.testing.expectEqual(@as(?usize, null), set.duplicateProgramListIdIndex());
    try std.testing.expect(!set.hasDuplicateProgramListIds());
    try std.testing.expectEqual(@as(?[]const u8, null), set.duplicateProgramListName());
    try std.testing.expectEqual(@as(?usize, null), set.duplicateProgramListNameIndex());
    try std.testing.expect(!set.hasDuplicateProgramListNames());
    try std.testing.expectEqual(root_unit_id, set.rootUnit().id);
    try std.testing.expectEqual(root_unit_id, set.rootUnitId());
    try std.testing.expectEqual(no_parent_unit_id, set.rootUnit().parent_id);
    try std.testing.expectEqual(no_program_list_id, set.rootUnit().program_list_id);
    try std.testing.expectEqualStrings("Root", set.rootUnit().name);
    try std.testing.expectEqualStrings("Root", set.rootUnitName());
    try std.testing.expect(set.rootUnit().isRoot());
    try std.testing.expect(!set.rootUnit().hasParent());
    try std.testing.expect(!set.rootUnit().hasProgramList());
    try std.testing.expect(set.hasUnit(root_unit_id));
    try std.testing.expect(!set.hasUnit(99));
    try std.testing.expect(!set.hasProgramList(10));
    try std.testing.expectEqual(@as(?ProgramList, null), set.programListForUnit(root_unit_id));
    try std.testing.expectEqual(@as(?ProgramList, null), set.programListForUnitName("Root"));
    try std.testing.expectEqual(@as(?Unit, null), set.unit(1));
    try std.testing.expectEqual(@as(?ProgramList, null), set.programList(0));
}

test "unit set exposes custom units and programs" {
    const programs = [_]Program{
        .{
            .name = "Clean",
            .parameters = &.{.{ .parameter_id = 3, .normalized = 0.25 }},
            .info = &.{.{ .key = "category", .value = "Clean" }},
        },
        .{
            .name = "Drive",
            .parameters = &.{.{ .parameter_id = 3, .normalized = 0.75 }},
        },
    };
    const Set = UnitSet(.{
        .units = &.{
            Unit.root("Main"),
            .{ .id = 1, .name = "Oscillator", .parent_id = root_unit_id, .program_list_id = 10 },
        },
        .program_lists = &.{
            .{ .id = 10, .name = "Oscillator Presets", .programs = &programs },
        },
    });
    const set = Set{};

    try std.testing.expectEqual(@as(usize, 2), set.unitCount());
    try std.testing.expect(!set.unitsEmpty());
    try std.testing.expect(set.hasUnits());
    try std.testing.expectEqual(@as(usize, 1), set.programListCount());
    try std.testing.expect(!set.programListsEmpty());
    try std.testing.expect(set.hasProgramLists());
    try std.testing.expectEqual(@as(?i32, null), set.duplicateUnitId());
    try std.testing.expectEqual(@as(?usize, null), set.duplicateUnitIdIndex());
    try std.testing.expect(!set.hasDuplicateUnitIds());
    try std.testing.expectEqual(@as(?[]const u8, null), set.duplicateUnitName());
    try std.testing.expectEqual(@as(?usize, null), set.duplicateUnitNameIndex());
    try std.testing.expect(!set.hasDuplicateUnitNames());
    try std.testing.expectEqual(@as(?usize, null), set.cyclicUnitParentIndex());
    try std.testing.expectEqual(@as(?i32, null), set.duplicateProgramListId());
    try std.testing.expectEqual(@as(?usize, null), set.duplicateProgramListIdIndex());
    try std.testing.expect(!set.hasDuplicateProgramListIds());
    try std.testing.expectEqual(@as(?[]const u8, null), set.duplicateProgramListName());
    try std.testing.expectEqual(@as(?usize, null), set.duplicateProgramListNameIndex());
    try std.testing.expect(!set.hasDuplicateProgramListNames());
    try std.testing.expectEqual(@as(?usize, 1), set.unitIndexOfId(1));
    try std.testing.expectEqual(@as(?usize, null), set.unitIndexOfId(99));
    try std.testing.expectEqual(@as(?usize, 1), set.unitIndexOfName("Oscillator"));
    try std.testing.expectEqual(@as(?usize, null), set.unitIndexOfName("Missing"));
    try std.testing.expect(set.hasUnit(1));
    try std.testing.expect(!set.hasUnit(99));
    try std.testing.expect(set.hasUnitName("Oscillator"));
    try std.testing.expect(!set.hasUnitName("Missing"));
    try std.testing.expectEqualStrings("Oscillator", set.unitById(1).?.name);
    try std.testing.expectEqual(@as(i32, 1), set.unitByName("Oscillator").?.id);
    try std.testing.expectEqual(@as(?Unit, null), set.unitByName("Missing"));
    try std.testing.expectEqual(@as(i32, 10), set.unitById(1).?.program_list_id);
    try std.testing.expect(!set.unitById(1).?.isRoot());
    try std.testing.expect(set.unitById(1).?.hasParent());
    try std.testing.expect(set.unitById(1).?.hasProgramList());
    try std.testing.expectEqual(@as(?usize, 0), set.programListIndexOfId(10));
    try std.testing.expectEqual(@as(?usize, null), set.programListIndexOfId(99));
    try std.testing.expectEqual(@as(?usize, 0), set.programListIndexOfName("Oscillator Presets"));
    try std.testing.expectEqual(@as(?usize, null), set.programListIndexOfName("Missing"));
    try std.testing.expect(set.hasProgramList(10));
    try std.testing.expect(!set.hasProgramList(99));
    try std.testing.expect(set.hasProgramListName("Oscillator Presets"));
    try std.testing.expect(!set.hasProgramListName("Missing"));
    try std.testing.expectEqualStrings("Oscillator Presets", set.programListById(10).?.name);
    try std.testing.expectEqual(@as(i32, 10), set.programListByName("Oscillator Presets").?.id);
    try std.testing.expectEqual(@as(?ProgramList, null), set.programListByName("Missing"));
    try std.testing.expectEqual(@as(usize, 2), set.programListById(10).?.programCount());
    try std.testing.expect(!set.programListById(10).?.isEmpty());
    try std.testing.expect(set.programListById(10).?.hasPrograms());
    try std.testing.expectEqual(@as(?[]const u8, null), set.programListById(10).?.duplicateProgramName());
    try std.testing.expectEqual(@as(?usize, null), set.programListById(10).?.duplicateProgramNameIndex());
    try std.testing.expect(!set.programListById(10).?.hasDuplicateProgramNames());
    try std.testing.expectEqualStrings("Drive", set.programListById(10).?.program(1).?.name);
    try std.testing.expectEqual(@as(?Program, null), set.programListById(10).?.program(2));
    try std.testing.expectEqualStrings("Drive", set.programListById(10).?.programName(1).?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.programListById(10).?.programName(2));
    try std.testing.expectEqual(@as(?usize, 1), set.programListById(10).?.programIndexOfName("Drive"));
    try std.testing.expectEqual(@as(?usize, null), set.programListById(10).?.programIndexOfName("Missing"));
    try std.testing.expectEqualStrings("Drive", set.programListById(10).?.programByName("Drive").?.name);
    try std.testing.expectEqual(@as(?Program, null), set.programListById(10).?.programByName("Missing"));
    try std.testing.expect(set.programListById(10).?.hasProgramName("Drive"));
    try std.testing.expect(!set.programListById(10).?.hasProgramName("Missing"));
    try std.testing.expect(set.programListHasPrograms(10));
    try std.testing.expect(set.programListHasProgramsByName("Oscillator Presets"));
    try std.testing.expect(!set.programListHasPrograms(99));
    try std.testing.expect(!set.programListHasProgramsByName("Missing"));
    try std.testing.expect(!set.programListEmpty(10));
    try std.testing.expect(!set.programListEmptyByName("Oscillator Presets"));
    try std.testing.expect(set.programListEmpty(99));
    try std.testing.expect(set.programListEmptyByName("Missing"));
    try std.testing.expectEqualStrings("Oscillator Presets", set.programListForUnit(1).?.name);
    try std.testing.expectEqual(@as(?ProgramList, null), set.programListForUnit(root_unit_id));
    try std.testing.expectEqualStrings("Oscillator Presets", set.programListForUnitName("Oscillator").?.name);
    try std.testing.expectEqual(@as(?ProgramList, null), set.programListForUnitName("Main"));
    try std.testing.expectEqual(@as(?ProgramList, null), set.programListForUnitName("Missing"));
    try std.testing.expectEqual(@as(?i32, 10), set.programListIdForUnit(1));
    try std.testing.expectEqual(@as(?i32, 10), set.programListIdForUnitName("Oscillator"));
    try std.testing.expectEqual(@as(?i32, null), set.programListIdForUnit(root_unit_id));
    try std.testing.expectEqual(@as(?i32, null), set.programListIdForUnitName("Missing"));
    try std.testing.expectEqualStrings("Oscillator Presets", set.programListNameForUnit(1).?);
    try std.testing.expectEqualStrings("Oscillator Presets", set.programListNameForUnitName("Oscillator").?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.programListNameForUnit(root_unit_id));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programListNameForUnitName("Missing"));
    try std.testing.expectEqual(@as(?usize, 2), set.programCount(10));
    try std.testing.expectEqual(@as(?usize, 2), set.programCountByName("Oscillator Presets"));
    try std.testing.expectEqual(@as(?usize, null), set.programCount(99));
    try std.testing.expectEqual(@as(?usize, null), set.programCountByName("Missing"));
    try std.testing.expectEqualStrings("Drive", set.programName(10, 1).?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.programName(10, 2));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programName(99, 0));
    try std.testing.expectEqualStrings("Drive", set.programNameByListName("Oscillator Presets", 1).?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.programNameByListName("Oscillator Presets", 2));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programNameByListName("Missing", 0));
    try std.testing.expectEqualStrings("Drive", set.program(10, 1).?.name);
    try std.testing.expectEqual(@as(?Program, null), set.program(10, 2));
    try std.testing.expectEqual(@as(?Program, null), set.program(99, 0));
    try std.testing.expectEqualStrings("Drive", set.programByListName("Oscillator Presets", 1).?.name);
    try std.testing.expectEqual(@as(?Program, null), set.programByListName("Oscillator Presets", 2));
    try std.testing.expectEqual(@as(?Program, null), set.programByListName("Missing", 0));
    try std.testing.expectEqual(@as(usize, 1), set.program(10, 0).?.parameterCount());
    try std.testing.expectEqual(@as(usize, 1), set.program(10, 0).?.infoCount());
    try std.testing.expect(set.program(10, 0).?.hasParameters());
    try std.testing.expect(!set.program(10, 0).?.parametersEmpty());
    try std.testing.expect(set.program(10, 0).?.hasInfo());
    try std.testing.expect(!set.program(10, 0).?.infoEmpty());
    try std.testing.expectEqual(@as(?u32, null), set.program(10, 0).?.duplicateParameterId());
    try std.testing.expectEqual(@as(?usize, null), set.program(10, 0).?.duplicateParameterIdIndex());
    try std.testing.expect(!set.program(10, 0).?.hasDuplicateParameterIds());
    try std.testing.expectEqual(@as(?[]const u8, null), set.program(10, 0).?.duplicateInfoKey());
    try std.testing.expectEqual(@as(?usize, null), set.program(10, 0).?.duplicateInfoKeyIndex());
    try std.testing.expect(!set.program(10, 0).?.hasDuplicateInfoKeys());
    try std.testing.expectEqual(@as(u32, 3), set.program(10, 0).?.parameter(0).?.parameter_id);
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.program(10, 0).?.parameter(1));
    try std.testing.expectEqual(@as(?usize, 0), set.program(10, 0).?.parameterIndexOfId(3));
    try std.testing.expectEqual(@as(?usize, null), set.program(10, 0).?.parameterIndexOfId(99));
    try std.testing.expectEqual(@as(f64, 0.25), set.program(10, 0).?.parameterById(3).?.normalized);
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.program(10, 0).?.parameterById(99));
    try std.testing.expect(set.program(10, 0).?.hasParameter(3));
    try std.testing.expect(!set.program(10, 0).?.hasParameter(99));
    try std.testing.expectEqualStrings("category", set.program(10, 0).?.infoEntry(0).?.key);
    try std.testing.expectEqualStrings("Clean", set.program(10, 0).?.infoEntry(0).?.value);
    try std.testing.expectEqual(@as(?ProgramInfo, null), set.program(10, 0).?.infoEntry(1));
    try std.testing.expectEqual(@as(?usize, 0), set.program(10, 0).?.infoIndexOfKey("category"));
    try std.testing.expectEqual(@as(?usize, null), set.program(10, 0).?.infoIndexOfKey("missing"));
    try std.testing.expectEqualStrings("Clean", set.program(10, 0).?.infoValue("category").?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.program(10, 0).?.infoValue("missing"));
    try std.testing.expect(set.program(10, 0).?.hasInfoKey("category"));
    try std.testing.expect(!set.program(10, 0).?.hasInfoKey("missing"));
    try std.testing.expect(!set.program(10, 1).?.hasInfo());
    try std.testing.expect(set.program(10, 1).?.infoEmpty());
    try std.testing.expectEqualStrings("Drive", set.programByName(10, "Drive").?.name);
    try std.testing.expectEqual(@as(?Program, null), set.programByName(10, "Missing"));
    try std.testing.expectEqual(@as(?Program, null), set.programByName(99, "Drive"));
    try std.testing.expectEqual(@as(?usize, 1), set.programIndexOfName(10, "Drive"));
    try std.testing.expectEqual(@as(?usize, null), set.programIndexOfName(10, "Missing"));
    try std.testing.expectEqual(@as(?usize, null), set.programIndexOfName(99, "Drive"));
    try std.testing.expectEqual(@as(?usize, 1), set.programIndexOfNameByListName("Oscillator Presets", "Drive"));
    try std.testing.expectEqual(@as(?usize, null), set.programIndexOfNameByListName("Oscillator Presets", "Missing"));
    try std.testing.expectEqual(@as(?usize, null), set.programIndexOfNameByListName("Missing", "Drive"));
    try std.testing.expect(set.hasProgramName(10, "Drive"));
    try std.testing.expect(!set.hasProgramName(10, "Missing"));
    try std.testing.expect(!set.hasProgramName(99, "Drive"));
    try std.testing.expect(set.hasProgramNameByListName("Oscillator Presets", "Drive"));
    try std.testing.expect(!set.hasProgramNameByListName("Oscillator Presets", "Missing"));
    try std.testing.expect(!set.hasProgramNameByListName("Missing", "Drive"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.duplicateProgramName(10));
    try std.testing.expectEqual(@as(?usize, null), set.duplicateProgramNameIndex(10));
    try std.testing.expectEqual(@as(?[]const u8, null), set.duplicateProgramName(99));
    try std.testing.expectEqual(@as(?usize, null), set.duplicateProgramNameIndex(99));
    try std.testing.expect(!set.hasDuplicateProgramNames(10));
    try std.testing.expect(!set.hasDuplicateProgramNames(99));
    try std.testing.expectEqual(@as(?usize, 1), set.programParameterCount(10, 1));
    try std.testing.expectEqual(@as(?usize, null), set.programParameterCount(10, 2));
    try std.testing.expectEqual(@as(?usize, null), set.programParameterCount(99, 0));
    try std.testing.expectEqual(@as(?usize, 1), set.programParameterCountByName(10, "Drive"));
    try std.testing.expectEqual(@as(?usize, null), set.programParameterCountByName(10, "Missing"));
    try std.testing.expectEqual(@as(?usize, null), set.programParameterCountByName(99, "Drive"));
    try std.testing.expect(set.programHasParameters(10, 0));
    try std.testing.expect(set.programHasParametersByName(10, "Drive"));
    try std.testing.expect(!set.programHasParameters(10, 2));
    try std.testing.expect(!set.programHasParametersByName(10, "Missing"));
    try std.testing.expect(!set.programParametersEmpty(10, 0));
    try std.testing.expect(!set.programParametersEmptyByName(10, "Drive"));
    try std.testing.expect(set.programParametersEmpty(10, 2));
    try std.testing.expect(set.programParametersEmptyByName(10, "Missing"));
    try std.testing.expectEqual(@as(u32, 3), set.programParameter(10, 1, 0).?.parameter_id);
    try std.testing.expectEqual(@as(f64, 0.75), set.programParameter(10, 1, 0).?.normalized);
    try std.testing.expectEqual(@as(u32, 3), set.programParameterByName(10, "Drive", 0).?.parameter_id);
    try std.testing.expectEqual(@as(f64, 0.75), set.programParameterByName(10, "Drive", 0).?.normalized);
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameterByName(10, "Drive", 1));
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameterByName(10, "Missing", 0));
    try std.testing.expectEqual(@as(f64, 0.25), set.programParameterById(10, 0, 3).?.normalized);
    try std.testing.expectEqual(@as(?usize, 0), set.programParameterIndexOfId(10, 0, 3));
    try std.testing.expectEqual(@as(?usize, null), set.programParameterIndexOfId(10, 0, 99));
    try std.testing.expectEqual(@as(?usize, null), set.programParameterIndexOfId(10, 2, 3));
    try std.testing.expectEqual(@as(f64, 0.75), set.programParameterByNameAndId(10, "Drive", 3).?.normalized);
    try std.testing.expectEqual(@as(?usize, 0), set.programParameterIndexOfIdByName(10, "Drive", 3));
    try std.testing.expectEqual(@as(?usize, null), set.programParameterIndexOfIdByName(10, "Drive", 99));
    try std.testing.expectEqual(@as(?usize, null), set.programParameterIndexOfIdByName(10, "Missing", 3));
    try std.testing.expect(set.hasProgramParameter(10, 0, 3));
    try std.testing.expect(!set.hasProgramParameter(10, 0, 99));
    try std.testing.expect(!set.hasProgramParameter(99, 0, 3));
    try std.testing.expectEqual(@as(?u32, null), set.duplicateProgramParameterId(10, 0));
    try std.testing.expectEqual(@as(?usize, null), set.duplicateProgramParameterIdIndex(10, 0));
    try std.testing.expectEqual(@as(?u32, null), set.duplicateProgramParameterId(10, 2));
    try std.testing.expectEqual(@as(?usize, null), set.duplicateProgramParameterIdIndex(10, 2));
    try std.testing.expect(!set.hasDuplicateProgramParameterIds(10, 0));
    try std.testing.expect(!set.hasDuplicateProgramParameterIds(10, 2));
    try std.testing.expect(set.hasProgramParameterByName(10, "Drive", 3));
    try std.testing.expect(!set.hasProgramParameterByName(10, "Drive", 99));
    try std.testing.expect(!set.hasProgramParameterByName(10, "Missing", 3));
    try std.testing.expectEqual(@as(?u32, null), set.duplicateProgramParameterIdByName(10, "Drive"));
    try std.testing.expectEqual(@as(?usize, null), set.duplicateProgramParameterIdIndexByName(10, "Drive"));
    try std.testing.expectEqual(@as(?u32, null), set.duplicateProgramParameterIdByName(10, "Missing"));
    try std.testing.expectEqual(@as(?usize, null), set.duplicateProgramParameterIdIndexByName(10, "Missing"));
    try std.testing.expect(!set.hasDuplicateProgramParameterIdsByName(10, "Drive"));
    try std.testing.expect(!set.hasDuplicateProgramParameterIdsByName(10, "Missing"));
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameter(10, 1, 1));
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameterById(10, 1, 99));
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameterByNameAndId(10, "Drive", 99));
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameterByNameAndId(10, "Missing", 3));
    try std.testing.expectEqual(@as(?ProgramParameter, null), set.programParameterByNameAndId(99, "Drive", 3));
    try std.testing.expectEqualStrings("Clean", set.programInfo(10, 0, "category").?);
    try std.testing.expectEqualStrings("Clean", set.programInfoByName(10, "Clean", "category").?);
    try std.testing.expectEqualStrings("category", set.programInfoEntry(10, 0, 0).?.key);
    try std.testing.expectEqualStrings("Clean", set.programInfoEntry(10, 0, 0).?.value);
    try std.testing.expectEqual(@as(?ProgramInfo, null), set.programInfoEntry(10, 0, 1));
    try std.testing.expectEqual(@as(?ProgramInfo, null), set.programInfoEntry(10, 2, 0));
    try std.testing.expectEqual(@as(?usize, 0), set.programInfoIndexOfKey(10, 0, "category"));
    try std.testing.expectEqual(@as(?usize, null), set.programInfoIndexOfKey(10, 0, "missing"));
    try std.testing.expectEqual(@as(?usize, null), set.programInfoIndexOfKey(10, 2, "category"));
    try std.testing.expectEqualStrings("category", set.programInfoEntryByName(10, "Clean", 0).?.key);
    try std.testing.expectEqualStrings("Clean", set.programInfoEntryByName(10, "Clean", 0).?.value);
    try std.testing.expectEqual(@as(?ProgramInfo, null), set.programInfoEntryByName(10, "Clean", 1));
    try std.testing.expectEqual(@as(?ProgramInfo, null), set.programInfoEntryByName(10, "Missing", 0));
    try std.testing.expectEqual(@as(?usize, 0), set.programInfoIndexOfKeyByName(10, "Clean", "category"));
    try std.testing.expectEqual(@as(?usize, null), set.programInfoIndexOfKeyByName(10, "Clean", "missing"));
    try std.testing.expectEqual(@as(?usize, null), set.programInfoIndexOfKeyByName(10, "Missing", "category"));
    try std.testing.expectEqual(@as(?usize, 1), set.programInfoCount(10, 0));
    try std.testing.expectEqual(@as(?usize, 0), set.programInfoCountByName(10, "Drive"));
    try std.testing.expectEqual(@as(?usize, null), set.programInfoCount(10, 2));
    try std.testing.expectEqual(@as(?usize, null), set.programInfoCountByName(10, "Missing"));
    try std.testing.expect(set.programHasInfoEntries(10, 0));
    try std.testing.expect(set.programHasInfoEntriesByName(10, "Clean"));
    try std.testing.expect(!set.programHasInfoEntries(10, 1));
    try std.testing.expect(!set.programHasInfoEntriesByName(10, "Drive"));
    try std.testing.expect(!set.programInfoEmpty(10, 0));
    try std.testing.expect(set.programInfoEmpty(10, 1));
    try std.testing.expect(set.programInfoEmpty(10, 2));
    try std.testing.expect(set.programInfoEmptyByName(10, "Missing"));
    try std.testing.expect(set.hasProgramInfo(10, 0, "category"));
    try std.testing.expect(!set.hasProgramInfo(10, 0, "missing"));
    try std.testing.expect(!set.hasProgramInfo(10, 2, "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.duplicateProgramInfoKey(10, 0));
    try std.testing.expectEqual(@as(?usize, null), set.duplicateProgramInfoKeyIndex(10, 0));
    try std.testing.expectEqual(@as(?[]const u8, null), set.duplicateProgramInfoKey(10, 2));
    try std.testing.expectEqual(@as(?usize, null), set.duplicateProgramInfoKeyIndex(10, 2));
    try std.testing.expect(!set.hasDuplicateProgramInfoKeys(10, 0));
    try std.testing.expect(!set.hasDuplicateProgramInfoKeys(10, 2));
    try std.testing.expect(set.hasProgramInfoByName(10, "Clean", "category"));
    try std.testing.expect(!set.hasProgramInfoByName(10, "Clean", "missing"));
    try std.testing.expect(!set.hasProgramInfoByName(10, "Missing", "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.duplicateProgramInfoKeyByName(10, "Clean"));
    try std.testing.expectEqual(@as(?usize, null), set.duplicateProgramInfoKeyIndexByName(10, "Clean"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.duplicateProgramInfoKeyByName(10, "Missing"));
    try std.testing.expectEqual(@as(?usize, null), set.duplicateProgramInfoKeyIndexByName(10, "Missing"));
    try std.testing.expect(!set.hasDuplicateProgramInfoKeysByName(10, "Clean"));
    try std.testing.expect(!set.hasDuplicateProgramInfoKeysByName(10, "Missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programInfo(10, 0, "missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programInfo(10, 2, "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programInfo(99, 0, "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programInfoByName(10, "Missing", "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), set.programInfoByName(99, "Clean", "category"));
    try set.validate();
}

test "unit set program accessors stay symmetric across selector forms" {
    const programs = [_]Program{
        .{
            .name = "Init",
            .parameters = &.{
                .{ .parameter_id = 3, .normalized = 0.25 },
                .{ .parameter_id = 5, .normalized = 0.50 },
            },
            .info = &.{
                .{ .key = "category", .value = "Clean" },
                .{ .key = "author", .value = "Factory" },
            },
        },
        .{
            .name = "Drive",
            .parameters = &.{.{ .parameter_id = 3, .normalized = 0.75 }},
            .info = &.{.{ .key = "category", .value = "Distortion" }},
        },
    };
    const Set = UnitSet(.{
        .units = &.{
            Unit.root("Main"),
            .{ .id = 1, .name = "Oscillator", .parent_id = root_unit_id, .program_list_id = 10 },
        },
        .program_lists = &.{
            .{ .id = 10, .name = "Oscillator Presets", .programs = &programs },
        },
    });
    const set = Set{};
    const list_id: i32 = 10;
    const list_name = "Oscillator Presets";
    const unit_id: i32 = 1;
    const unit_name = "Oscillator";
    const program_names = [_][]const u8{ "Init", "Drive", "Missing" };
    const parameter_ids = [_]u32{ 3, 5, 99 };
    const info_keys = [_][]const u8{ "category", "author", "missing" };

    for (0..programs.len + 1) |program_index| {
        try std.testing.expectEqual(set.programCount(list_id), set.programCountByName(list_name));
        try std.testing.expectEqual(set.programCount(list_id), set.programCountForUnit(unit_id));
        try std.testing.expectEqual(set.programCount(list_id), set.programCountForUnitName(unit_name));
        try std.testing.expectEqual(set.programName(list_id, program_index), set.programNameByListName(list_name, program_index));
        try std.testing.expectEqual(set.programName(list_id, program_index), set.programNameForUnit(unit_id, program_index));
        try std.testing.expectEqual(set.programName(list_id, program_index), set.programNameForUnitName(unit_name, program_index));
        try std.testing.expectEqual(set.program(list_id, program_index), set.programByListName(list_name, program_index));
        try std.testing.expectEqual(set.program(list_id, program_index), set.programForUnit(unit_id, program_index));
        try std.testing.expectEqual(set.program(list_id, program_index), set.programForUnitName(unit_name, program_index));
        try std.testing.expectEqual(set.programParameterCount(list_id, program_index), set.programParameterCountByListName(list_name, program_index));
        try std.testing.expectEqual(set.programParameterCount(list_id, program_index), set.programParameterCountForUnit(unit_id, program_index));
        try std.testing.expectEqual(set.programParameterCount(list_id, program_index), set.programParameterCountForUnitName(unit_name, program_index));
        try std.testing.expectEqual(set.programHasParameters(list_id, program_index), set.programHasParametersByListName(list_name, program_index));
        try std.testing.expectEqual(set.programHasParameters(list_id, program_index), set.programHasParametersForUnit(unit_id, program_index));
        try std.testing.expectEqual(set.programHasParameters(list_id, program_index), set.programHasParametersForUnitName(unit_name, program_index));
        try std.testing.expectEqual(set.programParametersEmpty(list_id, program_index), set.programParametersEmptyByListName(list_name, program_index));
        try std.testing.expectEqual(set.programParametersEmpty(list_id, program_index), set.programParametersEmptyForUnit(unit_id, program_index));
        try std.testing.expectEqual(set.programParametersEmpty(list_id, program_index), set.programParametersEmptyForUnitName(unit_name, program_index));
        try std.testing.expectEqual(set.programInfoCount(list_id, program_index), set.programInfoCountByListName(list_name, program_index));
        try std.testing.expectEqual(set.programInfoCount(list_id, program_index), set.programInfoCountForUnit(unit_id, program_index));
        try std.testing.expectEqual(set.programInfoCount(list_id, program_index), set.programInfoCountForUnitName(unit_name, program_index));
        try std.testing.expectEqual(set.programHasInfoEntries(list_id, program_index), set.programHasInfoEntriesByListName(list_name, program_index));
        try std.testing.expectEqual(set.programHasInfoEntries(list_id, program_index), set.programHasInfoEntriesForUnit(unit_id, program_index));
        try std.testing.expectEqual(set.programHasInfoEntries(list_id, program_index), set.programHasInfoEntriesForUnitName(unit_name, program_index));
        try std.testing.expectEqual(set.programInfoEmpty(list_id, program_index), set.programInfoEmptyByListName(list_name, program_index));
        try std.testing.expectEqual(set.programInfoEmpty(list_id, program_index), set.programInfoEmptyForUnit(unit_id, program_index));
        try std.testing.expectEqual(set.programInfoEmpty(list_id, program_index), set.programInfoEmptyForUnitName(unit_name, program_index));

        for (0..3) |parameter_index| {
            try std.testing.expectEqual(set.programParameter(list_id, program_index, parameter_index), set.programParameterByListName(list_name, program_index, parameter_index));
            try std.testing.expectEqual(set.programParameter(list_id, program_index, parameter_index), set.programParameterForUnit(unit_id, program_index, parameter_index));
            try std.testing.expectEqual(set.programParameter(list_id, program_index, parameter_index), set.programParameterForUnitName(unit_name, program_index, parameter_index));
        }
        for (parameter_ids) |parameter_id| {
            try std.testing.expectEqual(set.programParameterById(list_id, program_index, parameter_id), set.programParameterByIdForListName(list_name, program_index, parameter_id));
            try std.testing.expectEqual(set.programParameterById(list_id, program_index, parameter_id), set.programParameterByIdForUnit(unit_id, program_index, parameter_id));
            try std.testing.expectEqual(set.programParameterById(list_id, program_index, parameter_id), set.programParameterByIdForUnitName(unit_name, program_index, parameter_id));
            try std.testing.expectEqual(set.programParameterIndexOfId(list_id, program_index, parameter_id), set.programParameterIndexOfIdByListName(list_name, program_index, parameter_id));
            try std.testing.expectEqual(set.programParameterIndexOfId(list_id, program_index, parameter_id), set.programParameterIndexOfIdForUnit(unit_id, program_index, parameter_id));
            try std.testing.expectEqual(set.programParameterIndexOfId(list_id, program_index, parameter_id), set.programParameterIndexOfIdForUnitName(unit_name, program_index, parameter_id));
            try std.testing.expectEqual(set.hasProgramParameter(list_id, program_index, parameter_id), set.hasProgramParameterByListName(list_name, program_index, parameter_id));
            try std.testing.expectEqual(set.hasProgramParameter(list_id, program_index, parameter_id), set.hasProgramParameterForUnit(unit_id, program_index, parameter_id));
            try std.testing.expectEqual(set.hasProgramParameter(list_id, program_index, parameter_id), set.hasProgramParameterForUnitName(unit_name, program_index, parameter_id));
        }
        for (0..3) |info_index| {
            try std.testing.expectEqual(set.programInfoEntry(list_id, program_index, info_index), set.programInfoEntryByListName(list_name, program_index, info_index));
            try std.testing.expectEqual(set.programInfoEntry(list_id, program_index, info_index), set.programInfoEntryForUnit(unit_id, program_index, info_index));
            try std.testing.expectEqual(set.programInfoEntry(list_id, program_index, info_index), set.programInfoEntryForUnitName(unit_name, program_index, info_index));
        }
        for (info_keys) |key| {
            try std.testing.expectEqual(set.programInfo(list_id, program_index, key), set.programInfoByListName(list_name, program_index, key));
            try std.testing.expectEqual(set.programInfo(list_id, program_index, key), set.programInfoForUnit(unit_id, program_index, key));
            try std.testing.expectEqual(set.programInfo(list_id, program_index, key), set.programInfoForUnitName(unit_name, program_index, key));
            try std.testing.expectEqual(set.programInfoEntryByKey(list_id, program_index, key), set.programInfoEntryByKeyByListName(list_name, program_index, key));
            try std.testing.expectEqual(set.programInfoEntryByKey(list_id, program_index, key), set.programInfoEntryByKeyForUnit(unit_id, program_index, key));
            try std.testing.expectEqual(set.programInfoEntryByKey(list_id, program_index, key), set.programInfoEntryByKeyForUnitName(unit_name, program_index, key));
            try std.testing.expectEqual(set.programInfoIndexOfKey(list_id, program_index, key), set.programInfoIndexOfKeyByListName(list_name, program_index, key));
            try std.testing.expectEqual(set.programInfoIndexOfKey(list_id, program_index, key), set.programInfoIndexOfKeyForUnit(unit_id, program_index, key));
            try std.testing.expectEqual(set.programInfoIndexOfKey(list_id, program_index, key), set.programInfoIndexOfKeyForUnitName(unit_name, program_index, key));
            try std.testing.expectEqual(set.hasProgramInfo(list_id, program_index, key), set.hasProgramInfoByListName(list_name, program_index, key));
            try std.testing.expectEqual(set.hasProgramInfo(list_id, program_index, key), set.hasProgramInfoForUnit(unit_id, program_index, key));
            try std.testing.expectEqual(set.hasProgramInfo(list_id, program_index, key), set.hasProgramInfoForUnitName(unit_name, program_index, key));
        }
    }

    for (program_names) |program_name| {
        try std.testing.expectEqual(set.programByName(list_id, program_name), set.programByNameForListName(list_name, program_name));
        try std.testing.expectEqual(set.programByName(list_id, program_name), set.programByNameForUnit(unit_id, program_name));
        try std.testing.expectEqual(set.programByName(list_id, program_name), set.programByNameForUnitName(unit_name, program_name));
        try std.testing.expectEqual(set.programIndexOfName(list_id, program_name), set.programIndexOfNameByListName(list_name, program_name));
        try std.testing.expectEqual(set.programIndexOfName(list_id, program_name), set.programIndexOfNameForUnit(unit_id, program_name));
        try std.testing.expectEqual(set.programIndexOfName(list_id, program_name), set.programIndexOfNameForUnitName(unit_name, program_name));
        try std.testing.expectEqual(set.hasProgramName(list_id, program_name), set.hasProgramNameByListName(list_name, program_name));
        try std.testing.expectEqual(set.hasProgramName(list_id, program_name), set.hasProgramNameForUnit(unit_id, program_name));
        try std.testing.expectEqual(set.hasProgramName(list_id, program_name), set.hasProgramNameForUnitName(unit_name, program_name));
        try std.testing.expectEqual(set.programParameterCountByName(list_id, program_name), set.programParameterCountByNameForListName(list_name, program_name));
        try std.testing.expectEqual(set.programParameterCountByName(list_id, program_name), set.programParameterCountByNameForUnit(unit_id, program_name));
        try std.testing.expectEqual(set.programParameterCountByName(list_id, program_name), set.programParameterCountByNameForUnitName(unit_name, program_name));
        try std.testing.expectEqual(set.programHasParametersByName(list_id, program_name), set.programHasParametersByNameForListName(list_name, program_name));
        try std.testing.expectEqual(set.programHasParametersByName(list_id, program_name), set.programHasParametersByNameForUnit(unit_id, program_name));
        try std.testing.expectEqual(set.programHasParametersByName(list_id, program_name), set.programHasParametersByNameForUnitName(unit_name, program_name));
        try std.testing.expectEqual(set.programParametersEmptyByName(list_id, program_name), set.programParametersEmptyByNameForListName(list_name, program_name));
        try std.testing.expectEqual(set.programParametersEmptyByName(list_id, program_name), set.programParametersEmptyByNameForUnit(unit_id, program_name));
        try std.testing.expectEqual(set.programParametersEmptyByName(list_id, program_name), set.programParametersEmptyByNameForUnitName(unit_name, program_name));
        try std.testing.expectEqual(set.programInfoCountByName(list_id, program_name), set.programInfoCountByNameForListName(list_name, program_name));
        try std.testing.expectEqual(set.programInfoCountByName(list_id, program_name), set.programInfoCountByNameForUnit(unit_id, program_name));
        try std.testing.expectEqual(set.programInfoCountByName(list_id, program_name), set.programInfoCountByNameForUnitName(unit_name, program_name));
        try std.testing.expectEqual(set.programHasInfoEntriesByName(list_id, program_name), set.programHasInfoEntriesByNameForListName(list_name, program_name));
        try std.testing.expectEqual(set.programHasInfoEntriesByName(list_id, program_name), set.programHasInfoEntriesByNameForUnit(unit_id, program_name));
        try std.testing.expectEqual(set.programHasInfoEntriesByName(list_id, program_name), set.programHasInfoEntriesByNameForUnitName(unit_name, program_name));
        try std.testing.expectEqual(set.programInfoEmptyByName(list_id, program_name), set.programInfoEmptyByNameForListName(list_name, program_name));
        try std.testing.expectEqual(set.programInfoEmptyByName(list_id, program_name), set.programInfoEmptyByNameForUnit(unit_id, program_name));
        try std.testing.expectEqual(set.programInfoEmptyByName(list_id, program_name), set.programInfoEmptyByNameForUnitName(unit_name, program_name));

        for (0..3) |parameter_index| {
            try std.testing.expectEqual(set.programParameterByName(list_id, program_name, parameter_index), set.programParameterByNameForListName(list_name, program_name, parameter_index));
            try std.testing.expectEqual(set.programParameterByName(list_id, program_name, parameter_index), set.programParameterByNameForUnit(unit_id, program_name, parameter_index));
            try std.testing.expectEqual(set.programParameterByName(list_id, program_name, parameter_index), set.programParameterByNameForUnitName(unit_name, program_name, parameter_index));
        }
        for (parameter_ids) |parameter_id| {
            try std.testing.expectEqual(set.programParameterByNameAndId(list_id, program_name, parameter_id), set.programParameterByNameAndIdForListName(list_name, program_name, parameter_id));
            try std.testing.expectEqual(set.programParameterByNameAndId(list_id, program_name, parameter_id), set.programParameterByNameAndIdForUnit(unit_id, program_name, parameter_id));
            try std.testing.expectEqual(set.programParameterByNameAndId(list_id, program_name, parameter_id), set.programParameterByNameAndIdForUnitName(unit_name, program_name, parameter_id));
            try std.testing.expectEqual(set.programParameterIndexOfIdByName(list_id, program_name, parameter_id), set.programParameterIndexOfIdByNameForListName(list_name, program_name, parameter_id));
            try std.testing.expectEqual(set.programParameterIndexOfIdByName(list_id, program_name, parameter_id), set.programParameterIndexOfIdByNameForUnit(unit_id, program_name, parameter_id));
            try std.testing.expectEqual(set.programParameterIndexOfIdByName(list_id, program_name, parameter_id), set.programParameterIndexOfIdByNameForUnitName(unit_name, program_name, parameter_id));
            try std.testing.expectEqual(set.hasProgramParameterByName(list_id, program_name, parameter_id), set.hasProgramParameterByNameForListName(list_name, program_name, parameter_id));
            try std.testing.expectEqual(set.hasProgramParameterByName(list_id, program_name, parameter_id), set.hasProgramParameterByNameForUnit(unit_id, program_name, parameter_id));
            try std.testing.expectEqual(set.hasProgramParameterByName(list_id, program_name, parameter_id), set.hasProgramParameterByNameForUnitName(unit_name, program_name, parameter_id));
        }
        for (0..3) |info_index| {
            try std.testing.expectEqual(set.programInfoEntryByName(list_id, program_name, info_index), set.programInfoEntryByNameForListName(list_name, program_name, info_index));
            try std.testing.expectEqual(set.programInfoEntryByName(list_id, program_name, info_index), set.programInfoEntryByNameForUnit(unit_id, program_name, info_index));
            try std.testing.expectEqual(set.programInfoEntryByName(list_id, program_name, info_index), set.programInfoEntryByNameForUnitName(unit_name, program_name, info_index));
        }
        for (info_keys) |key| {
            try std.testing.expectEqual(set.programInfoByName(list_id, program_name, key), set.programInfoByNameForListName(list_name, program_name, key));
            try std.testing.expectEqual(set.programInfoByName(list_id, program_name, key), set.programInfoByNameForUnit(unit_id, program_name, key));
            try std.testing.expectEqual(set.programInfoByName(list_id, program_name, key), set.programInfoByNameForUnitName(unit_name, program_name, key));
            try std.testing.expectEqual(set.programInfoEntryByNameAndKey(list_id, program_name, key), set.programInfoEntryByNameAndKeyForListName(list_name, program_name, key));
            try std.testing.expectEqual(set.programInfoEntryByNameAndKey(list_id, program_name, key), set.programInfoEntryByNameAndKeyForUnit(unit_id, program_name, key));
            try std.testing.expectEqual(set.programInfoEntryByNameAndKey(list_id, program_name, key), set.programInfoEntryByNameAndKeyForUnitName(unit_name, program_name, key));
            try std.testing.expectEqual(set.programInfoIndexOfKeyByName(list_id, program_name, key), set.programInfoIndexOfKeyByNameForListName(list_name, program_name, key));
            try std.testing.expectEqual(set.programInfoIndexOfKeyByName(list_id, program_name, key), set.programInfoIndexOfKeyByNameForUnit(unit_id, program_name, key));
            try std.testing.expectEqual(set.programInfoIndexOfKeyByName(list_id, program_name, key), set.programInfoIndexOfKeyByNameForUnitName(unit_name, program_name, key));
            try std.testing.expectEqual(set.hasProgramInfoByName(list_id, program_name, key), set.hasProgramInfoByNameForListName(list_name, program_name, key));
            try std.testing.expectEqual(set.hasProgramInfoByName(list_id, program_name, key), set.hasProgramInfoByNameForUnit(unit_id, program_name, key));
            try std.testing.expectEqual(set.hasProgramInfoByName(list_id, program_name, key), set.hasProgramInfoByNameForUnitName(unit_name, program_name, key));
        }
    }
}

test "unit set validates ids names and links" {
    const DuplicateUnits = UnitSet(.{
        .units = &.{ Unit.root("Root"), .{ .id = root_unit_id, .name = "Other" } },
    });
    const DuplicateUnitNames = UnitSet(.{
        .units = &.{ Unit.root("Root"), .{ .id = 1, .name = "Root", .parent_id = root_unit_id } },
    });
    const MissingRoot = UnitSet(.{
        .units = &.{.{ .id = 1, .name = "Oscillator", .parent_id = root_unit_id }},
    });
    const EmptyUnitName = UnitSet(.{
        .units = &.{Unit.root("")},
    });
    const InvalidUnitName = UnitSet(.{
        .units = &.{Unit.root("Ro\x00ot")},
    });
    const InvalidParent = UnitSet(.{
        .units = &.{ Unit.root("Root"), .{ .id = 1, .name = "Oscillator", .parent_id = 99 } },
    });
    const ReservedUnitId = UnitSet(.{
        .units = &.{ Unit.root("Root"), .{ .id = no_parent_unit_id, .name = "Reserved", .parent_id = root_unit_id } },
    });
    const CyclicParent = UnitSet(.{
        .units = &.{
            Unit.root("Root"),
            .{ .id = 1, .name = "Oscillator", .parent_id = 2 },
            .{ .id = 2, .name = "Filter", .parent_id = 1 },
        },
    });
    const InvalidProgramListLink = UnitSet(.{
        .units = &.{ Unit.root("Root"), .{ .id = 1, .name = "Oscillator", .program_list_id = 99 } },
    });
    const DuplicateProgramLists = UnitSet(.{
        .program_lists = &.{ .{ .id = 1, .name = "A" }, .{ .id = 1, .name = "B" } },
    });
    const DuplicateProgramListNames = UnitSet(.{
        .program_lists = &.{ .{ .id = 1, .name = "Programs" }, .{ .id = 2, .name = "Programs" } },
    });
    const ReservedProgramListId = UnitSet(.{
        .program_lists = &.{.{ .id = no_program_list_id, .name = "Reserved" }},
    });
    const EmptyProgramListName = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "" }},
    });
    const InvalidProgramListName = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Pro\x00grams" }},
    });
    const EmptyProgramName = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "" }} }},
    });
    const InvalidProgramName = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Cle\x00an" }} }},
    });
    const DuplicateProgramNames = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{ .{ .name = "Clean" }, .{ .name = "Clean" } } }},
    });
    const DuplicateProgramNamesForUnit = UnitSet(.{
        .units = &.{ Unit.root("Root"), .{ .id = 1, .name = "Oscillator", .parent_id = root_unit_id, .program_list_id = 1 } },
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{ .{ .name = "Clean" }, .{ .name = "Clean" } } }},
    });
    const DuplicateProgramParameters = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .parameters = &.{ .{ .parameter_id = 1, .normalized = 0.25 }, .{ .parameter_id = 1, .normalized = 0.75 } } }} }},
    });
    const InvalidProgramParameter = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .parameters = &.{.{ .parameter_id = 1, .normalized = 1.5 }} }} }},
    });
    const NanProgramParameter = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .parameters = &.{.{ .parameter_id = 1, .normalized = std.math.nan(f64) }} }} }},
    });
    const InfiniteProgramParameter = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .parameters = &.{.{ .parameter_id = 1, .normalized = std.math.inf(f64) }} }} }},
    });
    const EmptyProgramInfoKey = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .info = &.{.{ .key = "", .value = "x" }} }} }},
    });
    const InvalidProgramInfoKey = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .info = &.{.{ .key = "cat\x00egory", .value = "x" }} }} }},
    });
    const InvalidProgramInfoValue = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .info = &.{.{ .key = "category", .value = "cle\x00an" }} }} }},
    });
    const DuplicateProgramInfoKeys = UnitSet(.{
        .program_lists = &.{.{ .id = 1, .name = "Programs", .programs = &.{.{ .name = "Clean", .info = &.{ .{ .key = "category", .value = "clean" }, .{ .key = "category", .value = "lead" } } }} }},
    });

    const duplicate_program_names = ProgramList{ .id = 1, .name = "Programs", .programs = &.{ .{ .name = "Clean" }, .{ .name = "Clean" } } };
    const duplicate_program_parameters = Program{ .name = "Clean", .parameters = &.{ .{ .parameter_id = 1, .normalized = 0.25 }, .{ .parameter_id = 1, .normalized = 0.75 } } };
    const duplicate_program_info = Program{ .name = "Clean", .info = &.{ .{ .key = "category", .value = "clean" }, .{ .key = "category", .value = "lead" } } };
    try std.testing.expectEqualStrings("Clean", duplicate_program_names.duplicateProgramName().?);
    try std.testing.expectEqual(@as(?usize, 1), duplicate_program_names.duplicateProgramNameIndex());
    try std.testing.expect(duplicate_program_names.hasDuplicateProgramNames());
    try std.testing.expectEqual(@as(u32, 1), duplicate_program_parameters.duplicateParameterId().?);
    try std.testing.expectEqual(@as(?usize, 1), duplicate_program_parameters.duplicateParameterIdIndex());
    try std.testing.expect(duplicate_program_parameters.hasDuplicateParameterIds());
    try std.testing.expectEqualStrings("category", duplicate_program_info.duplicateInfoKey().?);
    try std.testing.expectEqual(@as(?usize, 1), duplicate_program_info.duplicateInfoKeyIndex());
    try std.testing.expect(duplicate_program_info.hasDuplicateInfoKeys());
    try std.testing.expectEqual(@as(?i32, root_unit_id), (DuplicateUnits{}).duplicateUnitId());
    try std.testing.expectEqual(@as(?usize, 1), (DuplicateUnits{}).duplicateUnitIdIndex());
    try std.testing.expect((DuplicateUnits{}).hasDuplicateUnitIds());
    try std.testing.expectEqualStrings("Root", (DuplicateUnitNames{}).duplicateUnitName().?);
    try std.testing.expectEqual(@as(?usize, 1), (DuplicateUnitNames{}).duplicateUnitNameIndex());
    try std.testing.expect((DuplicateUnitNames{}).hasDuplicateUnitNames());
    try std.testing.expectEqual(@as(?usize, 1), (CyclicParent{}).cyclicUnitParentIndex());
    try std.testing.expectEqual(@as(?i32, 1), (DuplicateProgramLists{}).duplicateProgramListId());
    try std.testing.expectEqual(@as(?usize, 1), (DuplicateProgramLists{}).duplicateProgramListIdIndex());
    try std.testing.expect((DuplicateProgramLists{}).hasDuplicateProgramListIds());
    try std.testing.expectEqualStrings("Programs", (DuplicateProgramListNames{}).duplicateProgramListName().?);
    try std.testing.expectEqual(@as(?usize, 1), (DuplicateProgramListNames{}).duplicateProgramListNameIndex());
    try std.testing.expect((DuplicateProgramListNames{}).hasDuplicateProgramListNames());
    try std.testing.expectEqualStrings("Clean", (DuplicateProgramNames{}).duplicateProgramName(1).?);
    try std.testing.expectEqual(@as(?usize, 1), (DuplicateProgramNames{}).duplicateProgramNameIndex(1));
    try std.testing.expect((DuplicateProgramNames{}).hasDuplicateProgramNames(1));
    try std.testing.expectEqualStrings("Clean", (DuplicateProgramNamesForUnit{}).duplicateProgramNameForUnit(1).?);
    try std.testing.expectEqualStrings("Clean", (DuplicateProgramNamesForUnit{}).duplicateProgramNameForUnitName("Oscillator").?);
    try std.testing.expectEqual(@as(?usize, 1), (DuplicateProgramNamesForUnit{}).duplicateProgramNameIndexForUnit(1));
    try std.testing.expectEqual(@as(?usize, 1), (DuplicateProgramNamesForUnit{}).duplicateProgramNameIndexForUnitName("Oscillator"));
    try std.testing.expect((DuplicateProgramNamesForUnit{}).hasDuplicateProgramNamesForUnit(1));
    try std.testing.expect((DuplicateProgramNamesForUnit{}).hasDuplicateProgramNamesForUnitName("Oscillator"));
    try std.testing.expectEqual(@as(u32, 1), (DuplicateProgramParameters{}).duplicateProgramParameterId(1, 0).?);
    try std.testing.expectEqual(@as(?usize, 1), (DuplicateProgramParameters{}).duplicateProgramParameterIdIndex(1, 0));
    try std.testing.expectEqual(@as(u32, 1), (DuplicateProgramParameters{}).duplicateProgramParameterIdByName(1, "Clean").?);
    try std.testing.expectEqual(@as(?usize, 1), (DuplicateProgramParameters{}).duplicateProgramParameterIdIndexByName(1, "Clean"));
    try std.testing.expect((DuplicateProgramParameters{}).hasDuplicateProgramParameterIds(1, 0));
    try std.testing.expect((DuplicateProgramParameters{}).hasDuplicateProgramParameterIdsByName(1, "Clean"));
    try std.testing.expectEqualStrings("category", (DuplicateProgramInfoKeys{}).duplicateProgramInfoKey(1, 0).?);
    try std.testing.expectEqual(@as(?usize, 1), (DuplicateProgramInfoKeys{}).duplicateProgramInfoKeyIndex(1, 0));
    try std.testing.expectEqualStrings("category", (DuplicateProgramInfoKeys{}).duplicateProgramInfoKeyByName(1, "Clean").?);
    try std.testing.expectEqual(@as(?usize, 1), (DuplicateProgramInfoKeys{}).duplicateProgramInfoKeyIndexByName(1, "Clean"));
    try std.testing.expect((DuplicateProgramInfoKeys{}).hasDuplicateProgramInfoKeys(1, 0));
    try std.testing.expect((DuplicateProgramInfoKeys{}).hasDuplicateProgramInfoKeysByName(1, "Clean"));

    try std.testing.expectError(error.DuplicateUnitId, (DuplicateUnits{}).validate());
    try std.testing.expectError(error.DuplicateUnitName, (DuplicateUnitNames{}).validate());
    try std.testing.expectError(error.MissingRootUnit, (MissingRoot{}).validate());
    try std.testing.expectError(error.EmptyUnitName, (EmptyUnitName{}).validate());
    try std.testing.expectError(error.InvalidUnitMetadata, (InvalidUnitName{}).validate());
    try std.testing.expectError(error.InvalidUnitParent, (InvalidParent{}).validate());
    try std.testing.expectError(error.ReservedUnitId, (ReservedUnitId{}).validate());
    try std.testing.expectError(error.CyclicUnitParent, (CyclicParent{}).validate());
    try std.testing.expectError(error.InvalidUnitProgramList, (InvalidProgramListLink{}).validate());
    try std.testing.expectError(error.DuplicateProgramListId, (DuplicateProgramLists{}).validate());
    try std.testing.expectError(error.DuplicateProgramListName, (DuplicateProgramListNames{}).validate());
    try std.testing.expectError(error.ReservedProgramListId, (ReservedProgramListId{}).validate());
    try std.testing.expectError(error.EmptyProgramListName, (EmptyProgramListName{}).validate());
    try std.testing.expectError(error.InvalidProgramListMetadata, (InvalidProgramListName{}).validate());
    try std.testing.expectError(error.EmptyProgramName, (EmptyProgramName{}).validate());
    try std.testing.expectError(error.InvalidProgramMetadata, (InvalidProgramName{}).validate());
    try std.testing.expectError(error.DuplicateProgramName, (DuplicateProgramNames{}).validate());
    try std.testing.expectError(error.DuplicateProgramParameter, (DuplicateProgramParameters{}).validate());
    try std.testing.expectError(error.ProgramParameterOutsideNormalizedRange, (InvalidProgramParameter{}).validate());
    try std.testing.expectError(error.ProgramParameterOutsideNormalizedRange, (NanProgramParameter{}).validate());
    try std.testing.expectError(error.ProgramParameterOutsideNormalizedRange, (InfiniteProgramParameter{}).validate());
    try std.testing.expectError(error.EmptyProgramInfoKey, (EmptyProgramInfoKey{}).validate());
    try std.testing.expectError(error.InvalidProgramInfoMetadata, (InvalidProgramInfoKey{}).validate());
    try std.testing.expectError(error.InvalidProgramInfoMetadata, (InvalidProgramInfoValue{}).validate());
    try std.testing.expectError(error.DuplicateProgramInfoKey, (DuplicateProgramInfoKeys{}).validate());
}

test "unit set reports cyclic parent indexes across graph shapes" {
    const DirectCycle = UnitSet(.{
        .units = &.{
            Unit.root("Root"),
            .{ .id = 1, .name = "Oscillator", .parent_id = 2 },
            .{ .id = 2, .name = "Filter", .parent_id = 1 },
        },
    });
    const NestedCycle = UnitSet(.{
        .units = &.{
            Unit.root("Root"),
            .{ .id = 1, .name = "Oscillator", .parent_id = root_unit_id },
            .{ .id = 2, .name = "Filter", .parent_id = 3 },
            .{ .id = 3, .name = "Envelope", .parent_id = 4 },
            .{ .id = 4, .name = "Modulator", .parent_id = 2 },
        },
    });
    const SelfCycle = UnitSet(.{
        .units = &.{
            Unit.root("Root"),
            .{ .id = 1, .name = "Oscillator", .parent_id = root_unit_id },
            .{ .id = 2, .name = "Filter", .parent_id = 2 },
        },
    });
    const LongCycle = UnitSet(.{
        .units = &.{
            Unit.root("Root"),
            .{ .id = 1, .name = "Oscillator", .parent_id = 2 },
            .{ .id = 2, .name = "Filter", .parent_id = 3 },
            .{ .id = 3, .name = "Envelope", .parent_id = 4 },
            .{ .id = 4, .name = "Modulator", .parent_id = 5 },
            .{ .id = 5, .name = "Output", .parent_id = 1 },
        },
    });
    const Acyclic = UnitSet(.{
        .units = &.{
            Unit.root("Root"),
            .{ .id = 1, .name = "Oscillator", .parent_id = root_unit_id },
            .{ .id = 2, .name = "Filter", .parent_id = 1 },
            .{ .id = 3, .name = "Envelope", .parent_id = 2 },
        },
    });

    try std.testing.expectEqual(@as(?usize, 1), (DirectCycle{}).cyclicUnitParentIndex());
    try std.testing.expectError(error.CyclicUnitParent, (DirectCycle{}).validate());
    try std.testing.expectEqual(@as(?usize, 2), (NestedCycle{}).cyclicUnitParentIndex());
    try std.testing.expectError(error.CyclicUnitParent, (NestedCycle{}).validate());
    try std.testing.expectEqual(@as(?usize, 2), (SelfCycle{}).cyclicUnitParentIndex());
    try std.testing.expectError(error.CyclicUnitParent, (SelfCycle{}).validate());
    try std.testing.expectEqual(@as(?usize, 1), (LongCycle{}).cyclicUnitParentIndex());
    try std.testing.expectError(error.CyclicUnitParent, (LongCycle{}).validate());
    try std.testing.expectEqual(@as(?usize, null), (Acyclic{}).cyclicUnitParentIndex());
    try (Acyclic{}).validate();
}
