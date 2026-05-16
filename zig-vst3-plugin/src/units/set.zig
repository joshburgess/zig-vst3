const std = @import("std");
const common = @import("../common.zig");
const descriptors = @import("descriptors.zig");

pub const root_unit_id = descriptors.root_unit_id;
pub const no_parent_unit_id = descriptors.no_parent_unit_id;
pub const no_program_list_id = descriptors.no_program_list_id;
pub const Unit = descriptors.Unit;
pub const Program = descriptors.Program;
pub const ProgramParameter = descriptors.ProgramParameter;
pub const ProgramInfo = descriptors.ProgramInfo;
pub const ProgramList = descriptors.ProgramList;
pub const Config = descriptors.Config;

pub fn UnitSet(comptime config: Config) type {
    return struct {
        const Self = @This();

        pub const unit_count = config.units.len;
        pub const program_list_count = config.program_lists.len;

        pub fn unitCount(_: Self) usize {
            return unit_count;
        }

        pub fn unitsEmpty(_: Self) bool {
            return unit_count == 0;
        }

        pub fn hasUnits(_: Self) bool {
            return unit_count != 0;
        }

        pub fn programListCount(_: Self) usize {
            return program_list_count;
        }

        pub fn programListsEmpty(_: Self) bool {
            return program_list_count == 0;
        }

        pub fn hasProgramLists(_: Self) bool {
            return program_list_count != 0;
        }

        pub fn duplicateUnitId(_: Self) ?i32 {
            for (config.units, 0..) |left, left_index| {
                for (config.units[left_index + 1 ..]) |right| {
                    if (right.id == left.id) return left.id;
                }
            }
            return null;
        }

        pub fn duplicateUnitIdIndex(_: Self) ?usize {
            for (config.units, 0..) |left, left_index| {
                for (config.units[left_index + 1 ..], left_index + 1..) |right, right_index| {
                    if (right.id == left.id) return right_index;
                }
            }
            return null;
        }

        pub fn hasDuplicateUnitIds(self: Self) bool {
            return self.duplicateUnitId() != null;
        }

        pub fn duplicateUnitName(_: Self) ?[]const u8 {
            for (config.units, 0..) |left, left_index| {
                for (config.units[left_index + 1 ..]) |right| {
                    if (std.mem.eql(u8, right.name, left.name)) return left.name;
                }
            }
            return null;
        }

        pub fn duplicateUnitNameIndex(_: Self) ?usize {
            for (config.units, 0..) |left, left_index| {
                for (config.units[left_index + 1 ..], left_index + 1..) |right, right_index| {
                    if (std.mem.eql(u8, right.name, left.name)) return right_index;
                }
            }
            return null;
        }

        pub fn hasDuplicateUnitNames(self: Self) bool {
            return self.duplicateUnitName() != null;
        }

        pub fn cyclicUnitParentIndex(self: Self) ?usize {
            for (config.units, 0..) |item, index| {
                if (self.unitParentIsCyclic(item)) return index;
            }
            return null;
        }

        pub fn duplicateProgramListId(_: Self) ?i32 {
            for (config.program_lists, 0..) |left, left_index| {
                for (config.program_lists[left_index + 1 ..]) |right| {
                    if (right.id == left.id) return left.id;
                }
            }
            return null;
        }

        pub fn duplicateProgramListIdIndex(_: Self) ?usize {
            for (config.program_lists, 0..) |left, left_index| {
                for (config.program_lists[left_index + 1 ..], left_index + 1..) |right, right_index| {
                    if (right.id == left.id) return right_index;
                }
            }
            return null;
        }

        pub fn hasDuplicateProgramListIds(self: Self) bool {
            return self.duplicateProgramListId() != null;
        }

        pub fn duplicateProgramListName(_: Self) ?[]const u8 {
            for (config.program_lists, 0..) |left, left_index| {
                for (config.program_lists[left_index + 1 ..]) |right| {
                    if (std.mem.eql(u8, right.name, left.name)) return left.name;
                }
            }
            return null;
        }

        pub fn duplicateProgramListNameIndex(_: Self) ?usize {
            for (config.program_lists, 0..) |left, left_index| {
                for (config.program_lists[left_index + 1 ..], left_index + 1..) |right, right_index| {
                    if (std.mem.eql(u8, right.name, left.name)) return right_index;
                }
            }
            return null;
        }

        pub fn hasDuplicateProgramListNames(self: Self) bool {
            return self.duplicateProgramListName() != null;
        }

        pub fn duplicateProgramName(self: Self, list_id: i32) ?[]const u8 {
            const list = self.programListById(list_id) orelse return null;
            return list.duplicateProgramName();
        }

        pub fn duplicateProgramNameByListName(self: Self, list_name: []const u8) ?[]const u8 {
            const list = self.programListByName(list_name) orelse return null;
            return list.duplicateProgramName();
        }

        pub fn duplicateProgramNameForUnit(self: Self, unit_id: i32) ?[]const u8 {
            const list = self.programListForUnit(unit_id) orelse return null;
            return list.duplicateProgramName();
        }

        pub fn duplicateProgramNameForUnitName(self: Self, unit_name: []const u8) ?[]const u8 {
            const list = self.programListForUnitName(unit_name) orelse return null;
            return list.duplicateProgramName();
        }

        pub fn duplicateProgramNameIndex(self: Self, list_id: i32) ?usize {
            const list = self.programListById(list_id) orelse return null;
            return list.duplicateProgramNameIndex();
        }

        pub fn duplicateProgramNameIndexByListName(self: Self, list_name: []const u8) ?usize {
            const list = self.programListByName(list_name) orelse return null;
            return list.duplicateProgramNameIndex();
        }

        pub fn duplicateProgramNameIndexForUnit(self: Self, unit_id: i32) ?usize {
            const list = self.programListForUnit(unit_id) orelse return null;
            return list.duplicateProgramNameIndex();
        }

        pub fn duplicateProgramNameIndexForUnitName(self: Self, unit_name: []const u8) ?usize {
            const list = self.programListForUnitName(unit_name) orelse return null;
            return list.duplicateProgramNameIndex();
        }

        pub fn duplicateProgramParameterId(self: Self, list_id: i32, program_index: usize) ?u32 {
            const item = self.program(list_id, program_index) orelse return null;
            return item.duplicateParameterId();
        }

        pub fn duplicateProgramParameterIdByListName(self: Self, list_name: []const u8, program_index: usize) ?u32 {
            const item = self.programByListName(list_name, program_index) orelse return null;
            return item.duplicateParameterId();
        }

        pub fn duplicateProgramParameterIdForUnit(self: Self, unit_id: i32, program_index: usize) ?u32 {
            const item = self.programForUnit(unit_id, program_index) orelse return null;
            return item.duplicateParameterId();
        }

        pub fn duplicateProgramParameterIdForUnitName(self: Self, unit_name: []const u8, program_index: usize) ?u32 {
            const item = self.programForUnitName(unit_name, program_index) orelse return null;
            return item.duplicateParameterId();
        }

        pub fn duplicateProgramParameterIdIndex(self: Self, list_id: i32, program_index: usize) ?usize {
            const item = self.program(list_id, program_index) orelse return null;
            return item.duplicateParameterIdIndex();
        }

        pub fn duplicateProgramParameterIdIndexByListName(self: Self, list_name: []const u8, program_index: usize) ?usize {
            const item = self.programByListName(list_name, program_index) orelse return null;
            return item.duplicateParameterIdIndex();
        }

        pub fn duplicateProgramParameterIdIndexForUnit(self: Self, unit_id: i32, program_index: usize) ?usize {
            const item = self.programForUnit(unit_id, program_index) orelse return null;
            return item.duplicateParameterIdIndex();
        }

        pub fn duplicateProgramParameterIdIndexForUnitName(self: Self, unit_name: []const u8, program_index: usize) ?usize {
            const item = self.programForUnitName(unit_name, program_index) orelse return null;
            return item.duplicateParameterIdIndex();
        }

        pub fn duplicateProgramParameterIdByName(self: Self, list_id: i32, program_name: []const u8) ?u32 {
            const index = self.programIndexOfName(list_id, program_name) orelse return null;
            return self.duplicateProgramParameterId(list_id, index);
        }

        pub fn duplicateProgramParameterIdByNameForListName(self: Self, list_name: []const u8, program_name: []const u8) ?u32 {
            const item = self.programByNameForListName(list_name, program_name) orelse return null;
            return item.duplicateParameterId();
        }

        pub fn duplicateProgramParameterIdByNameForUnit(self: Self, unit_id: i32, program_name: []const u8) ?u32 {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return null;
            return item.duplicateParameterId();
        }

        pub fn duplicateProgramParameterIdByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8) ?u32 {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return null;
            return item.duplicateParameterId();
        }

        pub fn duplicateProgramParameterIdIndexByName(self: Self, list_id: i32, program_name: []const u8) ?usize {
            const index = self.programIndexOfName(list_id, program_name) orelse return null;
            return self.duplicateProgramParameterIdIndex(list_id, index);
        }

        pub fn duplicateProgramParameterIdIndexByNameForListName(self: Self, list_name: []const u8, program_name: []const u8) ?usize {
            const item = self.programByNameForListName(list_name, program_name) orelse return null;
            return item.duplicateParameterIdIndex();
        }

        pub fn duplicateProgramParameterIdIndexByNameForUnit(self: Self, unit_id: i32, program_name: []const u8) ?usize {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return null;
            return item.duplicateParameterIdIndex();
        }

        pub fn duplicateProgramParameterIdIndexByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8) ?usize {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return null;
            return item.duplicateParameterIdIndex();
        }

        pub fn duplicateProgramInfoKey(self: Self, list_id: i32, program_index: usize) ?[]const u8 {
            const item = self.program(list_id, program_index) orelse return null;
            return item.duplicateInfoKey();
        }

        pub fn duplicateProgramInfoKeyByListName(self: Self, list_name: []const u8, program_index: usize) ?[]const u8 {
            const item = self.programByListName(list_name, program_index) orelse return null;
            return item.duplicateInfoKey();
        }

        pub fn duplicateProgramInfoKeyForUnit(self: Self, unit_id: i32, program_index: usize) ?[]const u8 {
            const item = self.programForUnit(unit_id, program_index) orelse return null;
            return item.duplicateInfoKey();
        }

        pub fn duplicateProgramInfoKeyForUnitName(self: Self, unit_name: []const u8, program_index: usize) ?[]const u8 {
            const item = self.programForUnitName(unit_name, program_index) orelse return null;
            return item.duplicateInfoKey();
        }

        pub fn duplicateProgramInfoKeyIndex(self: Self, list_id: i32, program_index: usize) ?usize {
            const item = self.program(list_id, program_index) orelse return null;
            return item.duplicateInfoKeyIndex();
        }

        pub fn duplicateProgramInfoKeyIndexByListName(self: Self, list_name: []const u8, program_index: usize) ?usize {
            const item = self.programByListName(list_name, program_index) orelse return null;
            return item.duplicateInfoKeyIndex();
        }

        pub fn duplicateProgramInfoKeyIndexForUnit(self: Self, unit_id: i32, program_index: usize) ?usize {
            const item = self.programForUnit(unit_id, program_index) orelse return null;
            return item.duplicateInfoKeyIndex();
        }

        pub fn duplicateProgramInfoKeyIndexForUnitName(self: Self, unit_name: []const u8, program_index: usize) ?usize {
            const item = self.programForUnitName(unit_name, program_index) orelse return null;
            return item.duplicateInfoKeyIndex();
        }

        pub fn duplicateProgramInfoKeyByName(self: Self, list_id: i32, program_name: []const u8) ?[]const u8 {
            const index = self.programIndexOfName(list_id, program_name) orelse return null;
            return self.duplicateProgramInfoKey(list_id, index);
        }

        pub fn duplicateProgramInfoKeyByNameForListName(self: Self, list_name: []const u8, program_name: []const u8) ?[]const u8 {
            const item = self.programByNameForListName(list_name, program_name) orelse return null;
            return item.duplicateInfoKey();
        }

        pub fn duplicateProgramInfoKeyByNameForUnit(self: Self, unit_id: i32, program_name: []const u8) ?[]const u8 {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return null;
            return item.duplicateInfoKey();
        }

        pub fn duplicateProgramInfoKeyByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8) ?[]const u8 {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return null;
            return item.duplicateInfoKey();
        }

        pub fn duplicateProgramInfoKeyIndexByName(self: Self, list_id: i32, program_name: []const u8) ?usize {
            const index = self.programIndexOfName(list_id, program_name) orelse return null;
            return self.duplicateProgramInfoKeyIndex(list_id, index);
        }

        pub fn duplicateProgramInfoKeyIndexByNameForListName(self: Self, list_name: []const u8, program_name: []const u8) ?usize {
            const item = self.programByNameForListName(list_name, program_name) orelse return null;
            return item.duplicateInfoKeyIndex();
        }

        pub fn duplicateProgramInfoKeyIndexByNameForUnit(self: Self, unit_id: i32, program_name: []const u8) ?usize {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return null;
            return item.duplicateInfoKeyIndex();
        }

        pub fn duplicateProgramInfoKeyIndexByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8) ?usize {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return null;
            return item.duplicateInfoKeyIndex();
        }

        pub fn unit(_: Self, index: usize) ?Unit {
            if (index >= config.units.len) return null;
            return config.units[index];
        }

        pub fn unitById(_: Self, id: i32) ?Unit {
            for (config.units) |item| {
                if (item.id == id) return item;
            }
            return null;
        }

        pub fn unitByName(self: Self, name: []const u8) ?Unit {
            const index = self.unitIndexOfName(name) orelse return null;
            return self.unit(index);
        }

        pub fn hasUnit(self: Self, id: i32) bool {
            return self.unitById(id) != null;
        }

        pub fn hasUnitName(self: Self, name: []const u8) bool {
            return self.unitByName(name) != null;
        }

        pub fn unitIndexOfId(_: Self, id: i32) ?usize {
            for (config.units, 0..) |item, index| {
                if (item.id == id) return index;
            }
            return null;
        }

        pub fn unitIndexOfName(_: Self, name: []const u8) ?usize {
            for (config.units, 0..) |item, index| {
                if (std.mem.eql(u8, item.name, name)) return index;
            }
            return null;
        }

        pub fn programList(_: Self, index: usize) ?ProgramList {
            if (index >= config.program_lists.len) return null;
            return config.program_lists[index];
        }

        pub fn programListById(_: Self, id: i32) ?ProgramList {
            for (config.program_lists) |item| {
                if (item.id == id) return item;
            }
            return null;
        }

        pub fn programListByName(self: Self, name: []const u8) ?ProgramList {
            const index = self.programListIndexOfName(name) orelse return null;
            return self.programList(index);
        }

        pub fn hasProgramList(self: Self, id: i32) bool {
            return self.programListById(id) != null;
        }

        pub fn hasProgramListName(self: Self, name: []const u8) bool {
            return self.programListByName(name) != null;
        }

        pub fn programListHasPrograms(self: Self, id: i32) bool {
            const list = self.programListById(id) orelse return false;
            return list.hasPrograms();
        }

        pub fn programListHasProgramsByName(self: Self, name: []const u8) bool {
            const list = self.programListByName(name) orelse return false;
            return list.hasPrograms();
        }

        pub fn programListEmpty(self: Self, id: i32) bool {
            const list = self.programListById(id) orelse return true;
            return list.isEmpty();
        }

        pub fn programListEmptyByName(self: Self, name: []const u8) bool {
            const list = self.programListByName(name) orelse return true;
            return list.isEmpty();
        }

        pub fn programListForUnit(self: Self, unit_id: i32) ?ProgramList {
            const item = self.unitById(unit_id) orelse return null;
            if (item.program_list_id == no_program_list_id) return null;
            return self.programListById(item.program_list_id);
        }

        pub fn programListForUnitName(self: Self, unit_name: []const u8) ?ProgramList {
            const item = self.unitByName(unit_name) orelse return null;
            if (item.program_list_id == no_program_list_id) return null;
            return self.programListById(item.program_list_id);
        }

        pub fn programListIdForUnit(self: Self, unit_id: i32) ?i32 {
            const list = self.programListForUnit(unit_id) orelse return null;
            return list.id;
        }

        pub fn programListIdForUnitName(self: Self, unit_name: []const u8) ?i32 {
            const list = self.programListForUnitName(unit_name) orelse return null;
            return list.id;
        }

        pub fn programListNameForUnit(self: Self, unit_id: i32) ?[]const u8 {
            const list = self.programListForUnit(unit_id) orelse return null;
            return list.name;
        }

        pub fn programListNameForUnitName(self: Self, unit_name: []const u8) ?[]const u8 {
            const list = self.programListForUnitName(unit_name) orelse return null;
            return list.name;
        }

        pub fn programListIndexOfId(_: Self, id: i32) ?usize {
            for (config.program_lists, 0..) |item, index| {
                if (item.id == id) return index;
            }
            return null;
        }

        pub fn programListIndexOfName(_: Self, name: []const u8) ?usize {
            for (config.program_lists, 0..) |item, index| {
                if (std.mem.eql(u8, item.name, name)) return index;
            }
            return null;
        }

        pub fn programCount(self: Self, list_id: i32) ?usize {
            const list = self.programListById(list_id) orelse return null;
            return list.programs.len;
        }

        pub fn programCountByName(self: Self, list_name: []const u8) ?usize {
            const list = self.programListByName(list_name) orelse return null;
            return list.programs.len;
        }

        pub fn programCountForUnit(self: Self, unit_id: i32) ?usize {
            const list = self.programListForUnit(unit_id) orelse return null;
            return list.programCount();
        }

        pub fn programCountForUnitName(self: Self, unit_name: []const u8) ?usize {
            const list = self.programListForUnitName(unit_name) orelse return null;
            return list.programCount();
        }

        pub fn programName(self: Self, list_id: i32, program_index: usize) ?[]const u8 {
            const list = self.programListById(list_id) orelse return null;
            return list.programName(program_index);
        }

        pub fn programNameByListName(self: Self, list_name: []const u8, program_index: usize) ?[]const u8 {
            const list = self.programListByName(list_name) orelse return null;
            return list.programName(program_index);
        }

        pub fn programNameForUnit(self: Self, unit_id: i32, program_index: usize) ?[]const u8 {
            const list = self.programListForUnit(unit_id) orelse return null;
            return list.programName(program_index);
        }

        pub fn programNameForUnitName(self: Self, unit_name: []const u8, program_index: usize) ?[]const u8 {
            const list = self.programListForUnitName(unit_name) orelse return null;
            return list.programName(program_index);
        }

        pub fn program(self: Self, list_id: i32, program_index: usize) ?Program {
            const list = self.programListById(list_id) orelse return null;
            return list.program(program_index);
        }

        pub fn programByListName(self: Self, list_name: []const u8, program_index: usize) ?Program {
            const list = self.programListByName(list_name) orelse return null;
            return list.program(program_index);
        }

        pub fn programForUnit(self: Self, unit_id: i32, program_index: usize) ?Program {
            const list = self.programListForUnit(unit_id) orelse return null;
            return list.program(program_index);
        }

        pub fn programForUnitName(self: Self, unit_name: []const u8, program_index: usize) ?Program {
            const list = self.programListForUnitName(unit_name) orelse return null;
            return list.program(program_index);
        }

        pub fn programByName(self: Self, list_id: i32, name: []const u8) ?Program {
            const list = self.programListById(list_id) orelse return null;
            return list.programByName(name);
        }

        pub fn programByNameForListName(self: Self, list_name: []const u8, name: []const u8) ?Program {
            const list = self.programListByName(list_name) orelse return null;
            return list.programByName(name);
        }

        pub fn programByNameForUnit(self: Self, unit_id: i32, name: []const u8) ?Program {
            const list = self.programListForUnit(unit_id) orelse return null;
            return list.programByName(name);
        }

        pub fn programByNameForUnitName(self: Self, unit_name: []const u8, name: []const u8) ?Program {
            const list = self.programListForUnitName(unit_name) orelse return null;
            return list.programByName(name);
        }

        pub fn programIndexOfName(self: Self, list_id: i32, name: []const u8) ?usize {
            const list = self.programListById(list_id) orelse return null;
            return list.programIndexOfName(name);
        }

        pub fn programIndexOfNameByListName(self: Self, list_name: []const u8, name: []const u8) ?usize {
            const list = self.programListByName(list_name) orelse return null;
            return list.programIndexOfName(name);
        }

        pub fn programIndexOfNameForUnit(self: Self, unit_id: i32, name: []const u8) ?usize {
            const list = self.programListForUnit(unit_id) orelse return null;
            return list.programIndexOfName(name);
        }

        pub fn programIndexOfNameForUnitName(self: Self, unit_name: []const u8, name: []const u8) ?usize {
            const list = self.programListForUnitName(unit_name) orelse return null;
            return list.programIndexOfName(name);
        }

        pub fn hasProgramName(self: Self, list_id: i32, name: []const u8) bool {
            return self.programIndexOfName(list_id, name) != null;
        }

        pub fn hasProgramNameByListName(self: Self, list_name: []const u8, name: []const u8) bool {
            return self.programIndexOfNameByListName(list_name, name) != null;
        }

        pub fn hasProgramNameForUnit(self: Self, unit_id: i32, name: []const u8) bool {
            return self.programIndexOfNameForUnit(unit_id, name) != null;
        }

        pub fn hasProgramNameForUnitName(self: Self, unit_name: []const u8, name: []const u8) bool {
            return self.programIndexOfNameForUnitName(unit_name, name) != null;
        }

        pub fn hasDuplicateProgramNames(self: Self, list_id: i32) bool {
            return self.duplicateProgramName(list_id) != null;
        }

        pub fn hasDuplicateProgramNamesByListName(self: Self, list_name: []const u8) bool {
            return self.duplicateProgramNameByListName(list_name) != null;
        }

        pub fn hasDuplicateProgramNamesForUnit(self: Self, unit_id: i32) bool {
            return self.duplicateProgramNameForUnit(unit_id) != null;
        }

        pub fn hasDuplicateProgramNamesForUnitName(self: Self, unit_name: []const u8) bool {
            return self.duplicateProgramNameForUnitName(unit_name) != null;
        }

        pub fn programParameterCount(self: Self, list_id: i32, program_index: usize) ?usize {
            const item = self.program(list_id, program_index) orelse return null;
            return item.parameters.len;
        }

        pub fn programParameterCountByListName(self: Self, list_name: []const u8, program_index: usize) ?usize {
            const item = self.programByListName(list_name, program_index) orelse return null;
            return item.parameters.len;
        }

        pub fn programParameterCountForUnit(self: Self, unit_id: i32, program_index: usize) ?usize {
            const item = self.programForUnit(unit_id, program_index) orelse return null;
            return item.parameters.len;
        }

        pub fn programParameterCountForUnitName(self: Self, unit_name: []const u8, program_index: usize) ?usize {
            const item = self.programForUnitName(unit_name, program_index) orelse return null;
            return item.parameters.len;
        }

        pub fn programParameterCountByName(self: Self, list_id: i32, program_name: []const u8) ?usize {
            const item = self.programByName(list_id, program_name) orelse return null;
            return item.parameters.len;
        }

        pub fn programParameterCountByNameForListName(self: Self, list_name: []const u8, program_name: []const u8) ?usize {
            const item = self.programByNameForListName(list_name, program_name) orelse return null;
            return item.parameters.len;
        }

        pub fn programParameterCountByNameForUnit(self: Self, unit_id: i32, program_name: []const u8) ?usize {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return null;
            return item.parameters.len;
        }

        pub fn programParameterCountByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8) ?usize {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return null;
            return item.parameters.len;
        }

        pub fn programHasParameters(self: Self, list_id: i32, program_index: usize) bool {
            const item = self.program(list_id, program_index) orelse return false;
            return item.hasParameters();
        }

        pub fn programHasParametersByListName(self: Self, list_name: []const u8, program_index: usize) bool {
            const item = self.programByListName(list_name, program_index) orelse return false;
            return item.hasParameters();
        }

        pub fn programHasParametersForUnit(self: Self, unit_id: i32, program_index: usize) bool {
            const item = self.programForUnit(unit_id, program_index) orelse return false;
            return item.hasParameters();
        }

        pub fn programHasParametersForUnitName(self: Self, unit_name: []const u8, program_index: usize) bool {
            const item = self.programForUnitName(unit_name, program_index) orelse return false;
            return item.hasParameters();
        }

        pub fn programHasParametersByName(self: Self, list_id: i32, program_name: []const u8) bool {
            const item = self.programByName(list_id, program_name) orelse return false;
            return item.hasParameters();
        }

        pub fn programHasParametersByNameForListName(self: Self, list_name: []const u8, program_name: []const u8) bool {
            const item = self.programByNameForListName(list_name, program_name) orelse return false;
            return item.hasParameters();
        }

        pub fn programHasParametersByNameForUnit(self: Self, unit_id: i32, program_name: []const u8) bool {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return false;
            return item.hasParameters();
        }

        pub fn programHasParametersByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8) bool {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return false;
            return item.hasParameters();
        }

        pub fn programParametersEmpty(self: Self, list_id: i32, program_index: usize) bool {
            const item = self.program(list_id, program_index) orelse return true;
            return item.parametersEmpty();
        }

        pub fn programParametersEmptyByListName(self: Self, list_name: []const u8, program_index: usize) bool {
            const item = self.programByListName(list_name, program_index) orelse return true;
            return item.parametersEmpty();
        }

        pub fn programParametersEmptyForUnit(self: Self, unit_id: i32, program_index: usize) bool {
            const item = self.programForUnit(unit_id, program_index) orelse return true;
            return item.parametersEmpty();
        }

        pub fn programParametersEmptyForUnitName(self: Self, unit_name: []const u8, program_index: usize) bool {
            const item = self.programForUnitName(unit_name, program_index) orelse return true;
            return item.parametersEmpty();
        }

        pub fn programParametersEmptyByName(self: Self, list_id: i32, program_name: []const u8) bool {
            const item = self.programByName(list_id, program_name) orelse return true;
            return item.parametersEmpty();
        }

        pub fn programParametersEmptyByNameForListName(self: Self, list_name: []const u8, program_name: []const u8) bool {
            const item = self.programByNameForListName(list_name, program_name) orelse return true;
            return item.parametersEmpty();
        }

        pub fn programParametersEmptyByNameForUnit(self: Self, unit_id: i32, program_name: []const u8) bool {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return true;
            return item.parametersEmpty();
        }

        pub fn programParametersEmptyByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8) bool {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return true;
            return item.parametersEmpty();
        }

        pub fn programParameter(self: Self, list_id: i32, program_index: usize, parameter_index: usize) ?ProgramParameter {
            const item = self.program(list_id, program_index) orelse return null;
            return item.parameter(parameter_index);
        }

        pub fn programParameterByListName(self: Self, list_name: []const u8, program_index: usize, parameter_index: usize) ?ProgramParameter {
            const item = self.programByListName(list_name, program_index) orelse return null;
            return item.parameter(parameter_index);
        }

        pub fn programParameterForUnit(self: Self, unit_id: i32, program_index: usize, parameter_index: usize) ?ProgramParameter {
            const item = self.programForUnit(unit_id, program_index) orelse return null;
            return item.parameter(parameter_index);
        }

        pub fn programParameterForUnitName(self: Self, unit_name: []const u8, program_index: usize, parameter_index: usize) ?ProgramParameter {
            const item = self.programForUnitName(unit_name, program_index) orelse return null;
            return item.parameter(parameter_index);
        }

        pub fn programParameterByName(self: Self, list_id: i32, program_name: []const u8, parameter_index: usize) ?ProgramParameter {
            const item = self.programByName(list_id, program_name) orelse return null;
            return item.parameter(parameter_index);
        }

        pub fn programParameterByNameForListName(self: Self, list_name: []const u8, program_name: []const u8, parameter_index: usize) ?ProgramParameter {
            const item = self.programByNameForListName(list_name, program_name) orelse return null;
            return item.parameter(parameter_index);
        }

        pub fn programParameterByNameForUnit(self: Self, unit_id: i32, program_name: []const u8, parameter_index: usize) ?ProgramParameter {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return null;
            return item.parameter(parameter_index);
        }

        pub fn programParameterByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8, parameter_index: usize) ?ProgramParameter {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return null;
            return item.parameter(parameter_index);
        }

        pub fn programParameterById(self: Self, list_id: i32, program_index: usize, parameter_id: u32) ?ProgramParameter {
            const item = self.program(list_id, program_index) orelse return null;
            return item.parameterById(parameter_id);
        }

        pub fn programParameterByIdForListName(self: Self, list_name: []const u8, program_index: usize, parameter_id: u32) ?ProgramParameter {
            const item = self.programByListName(list_name, program_index) orelse return null;
            return item.parameterById(parameter_id);
        }

        pub fn programParameterByIdForUnit(self: Self, unit_id: i32, program_index: usize, parameter_id: u32) ?ProgramParameter {
            const item = self.programForUnit(unit_id, program_index) orelse return null;
            return item.parameterById(parameter_id);
        }

        pub fn programParameterByIdForUnitName(self: Self, unit_name: []const u8, program_index: usize, parameter_id: u32) ?ProgramParameter {
            const item = self.programForUnitName(unit_name, program_index) orelse return null;
            return item.parameterById(parameter_id);
        }

        pub fn programParameterIndexOfId(self: Self, list_id: i32, program_index: usize, parameter_id: u32) ?usize {
            const item = self.program(list_id, program_index) orelse return null;
            return item.parameterIndexOfId(parameter_id);
        }

        pub fn programParameterIndexOfIdByListName(self: Self, list_name: []const u8, program_index: usize, parameter_id: u32) ?usize {
            const item = self.programByListName(list_name, program_index) orelse return null;
            return item.parameterIndexOfId(parameter_id);
        }

        pub fn programParameterIndexOfIdForUnit(self: Self, unit_id: i32, program_index: usize, parameter_id: u32) ?usize {
            const item = self.programForUnit(unit_id, program_index) orelse return null;
            return item.parameterIndexOfId(parameter_id);
        }

        pub fn programParameterIndexOfIdForUnitName(self: Self, unit_name: []const u8, program_index: usize, parameter_id: u32) ?usize {
            const item = self.programForUnitName(unit_name, program_index) orelse return null;
            return item.parameterIndexOfId(parameter_id);
        }

        pub fn hasProgramParameter(self: Self, list_id: i32, program_index: usize, parameter_id: u32) bool {
            return self.programParameterIndexOfId(list_id, program_index, parameter_id) != null;
        }

        pub fn hasProgramParameterByListName(self: Self, list_name: []const u8, program_index: usize, parameter_id: u32) bool {
            return self.programParameterIndexOfIdByListName(list_name, program_index, parameter_id) != null;
        }

        pub fn hasProgramParameterForUnit(self: Self, unit_id: i32, program_index: usize, parameter_id: u32) bool {
            return self.programParameterIndexOfIdForUnit(unit_id, program_index, parameter_id) != null;
        }

        pub fn hasProgramParameterForUnitName(self: Self, unit_name: []const u8, program_index: usize, parameter_id: u32) bool {
            return self.programParameterIndexOfIdForUnitName(unit_name, program_index, parameter_id) != null;
        }

        pub fn hasDuplicateProgramParameterIds(self: Self, list_id: i32, program_index: usize) bool {
            return self.duplicateProgramParameterId(list_id, program_index) != null;
        }

        pub fn hasDuplicateProgramParameterIdsByListName(self: Self, list_name: []const u8, program_index: usize) bool {
            return self.duplicateProgramParameterIdByListName(list_name, program_index) != null;
        }

        pub fn hasDuplicateProgramParameterIdsForUnit(self: Self, unit_id: i32, program_index: usize) bool {
            return self.duplicateProgramParameterIdForUnit(unit_id, program_index) != null;
        }

        pub fn hasDuplicateProgramParameterIdsForUnitName(self: Self, unit_name: []const u8, program_index: usize) bool {
            return self.duplicateProgramParameterIdForUnitName(unit_name, program_index) != null;
        }

        pub fn programParameterByNameAndId(self: Self, list_id: i32, program_name: []const u8, parameter_id: u32) ?ProgramParameter {
            const item = self.programByName(list_id, program_name) orelse return null;
            return item.parameterById(parameter_id);
        }

        pub fn programParameterByNameAndIdForListName(self: Self, list_name: []const u8, program_name: []const u8, parameter_id: u32) ?ProgramParameter {
            const item = self.programByNameForListName(list_name, program_name) orelse return null;
            return item.parameterById(parameter_id);
        }

        pub fn programParameterByNameAndIdForUnit(self: Self, unit_id: i32, program_name: []const u8, parameter_id: u32) ?ProgramParameter {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return null;
            return item.parameterById(parameter_id);
        }

        pub fn programParameterByNameAndIdForUnitName(self: Self, unit_name: []const u8, program_name: []const u8, parameter_id: u32) ?ProgramParameter {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return null;
            return item.parameterById(parameter_id);
        }

        pub fn programParameterIndexOfIdByName(self: Self, list_id: i32, program_name: []const u8, parameter_id: u32) ?usize {
            const item = self.programByName(list_id, program_name) orelse return null;
            return item.parameterIndexOfId(parameter_id);
        }

        pub fn programParameterIndexOfIdByNameForListName(self: Self, list_name: []const u8, program_name: []const u8, parameter_id: u32) ?usize {
            const item = self.programByNameForListName(list_name, program_name) orelse return null;
            return item.parameterIndexOfId(parameter_id);
        }

        pub fn programParameterIndexOfIdByNameForUnit(self: Self, unit_id: i32, program_name: []const u8, parameter_id: u32) ?usize {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return null;
            return item.parameterIndexOfId(parameter_id);
        }

        pub fn programParameterIndexOfIdByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8, parameter_id: u32) ?usize {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return null;
            return item.parameterIndexOfId(parameter_id);
        }

        pub fn hasProgramParameterByName(self: Self, list_id: i32, program_name: []const u8, parameter_id: u32) bool {
            return self.programParameterIndexOfIdByName(list_id, program_name, parameter_id) != null;
        }

        pub fn hasProgramParameterByNameForListName(self: Self, list_name: []const u8, program_name: []const u8, parameter_id: u32) bool {
            return self.programParameterIndexOfIdByNameForListName(list_name, program_name, parameter_id) != null;
        }

        pub fn hasProgramParameterByNameForUnit(self: Self, unit_id: i32, program_name: []const u8, parameter_id: u32) bool {
            return self.programParameterIndexOfIdByNameForUnit(unit_id, program_name, parameter_id) != null;
        }

        pub fn hasProgramParameterByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8, parameter_id: u32) bool {
            return self.programParameterIndexOfIdByNameForUnitName(unit_name, program_name, parameter_id) != null;
        }

        pub fn hasDuplicateProgramParameterIdsByName(self: Self, list_id: i32, program_name: []const u8) bool {
            return self.duplicateProgramParameterIdByName(list_id, program_name) != null;
        }

        pub fn hasDuplicateProgramParameterIdsByNameForListName(self: Self, list_name: []const u8, program_name: []const u8) bool {
            return self.duplicateProgramParameterIdByNameForListName(list_name, program_name) != null;
        }

        pub fn hasDuplicateProgramParameterIdsByNameForUnit(self: Self, unit_id: i32, program_name: []const u8) bool {
            return self.duplicateProgramParameterIdByNameForUnit(unit_id, program_name) != null;
        }

        pub fn hasDuplicateProgramParameterIdsByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8) bool {
            return self.duplicateProgramParameterIdByNameForUnitName(unit_name, program_name) != null;
        }

        pub fn programInfo(self: Self, list_id: i32, program_index: usize, key: []const u8) ?[]const u8 {
            const list = self.programListById(list_id) orelse return null;
            const item = list.program(program_index) orelse return null;
            return item.infoValue(key);
        }

        pub fn programInfoByListName(self: Self, list_name: []const u8, program_index: usize, key: []const u8) ?[]const u8 {
            const item = self.programByListName(list_name, program_index) orelse return null;
            return item.infoValue(key);
        }

        pub fn programInfoForUnit(self: Self, unit_id: i32, program_index: usize, key: []const u8) ?[]const u8 {
            const item = self.programForUnit(unit_id, program_index) orelse return null;
            return item.infoValue(key);
        }

        pub fn programInfoForUnitName(self: Self, unit_name: []const u8, program_index: usize, key: []const u8) ?[]const u8 {
            const item = self.programForUnitName(unit_name, program_index) orelse return null;
            return item.infoValue(key);
        }

        pub fn programInfoEntry(self: Self, list_id: i32, program_index: usize, info_index: usize) ?ProgramInfo {
            const item = self.program(list_id, program_index) orelse return null;
            return item.infoEntry(info_index);
        }

        pub fn programInfoEntryByListName(self: Self, list_name: []const u8, program_index: usize, info_index: usize) ?ProgramInfo {
            const item = self.programByListName(list_name, program_index) orelse return null;
            return item.infoEntry(info_index);
        }

        pub fn programInfoEntryForUnit(self: Self, unit_id: i32, program_index: usize, info_index: usize) ?ProgramInfo {
            const item = self.programForUnit(unit_id, program_index) orelse return null;
            return item.infoEntry(info_index);
        }

        pub fn programInfoEntryForUnitName(self: Self, unit_name: []const u8, program_index: usize, info_index: usize) ?ProgramInfo {
            const item = self.programForUnitName(unit_name, program_index) orelse return null;
            return item.infoEntry(info_index);
        }

        pub fn programInfoEntryByKey(self: Self, list_id: i32, program_index: usize, key: []const u8) ?ProgramInfo {
            const item = self.program(list_id, program_index) orelse return null;
            return item.infoEntryByKey(key);
        }

        pub fn programInfoEntryByKeyByListName(self: Self, list_name: []const u8, program_index: usize, key: []const u8) ?ProgramInfo {
            const item = self.programByListName(list_name, program_index) orelse return null;
            return item.infoEntryByKey(key);
        }

        pub fn programInfoEntryByKeyForUnit(self: Self, unit_id: i32, program_index: usize, key: []const u8) ?ProgramInfo {
            const item = self.programForUnit(unit_id, program_index) orelse return null;
            return item.infoEntryByKey(key);
        }

        pub fn programInfoEntryByKeyForUnitName(self: Self, unit_name: []const u8, program_index: usize, key: []const u8) ?ProgramInfo {
            const item = self.programForUnitName(unit_name, program_index) orelse return null;
            return item.infoEntryByKey(key);
        }

        pub fn programInfoIndexOfKey(self: Self, list_id: i32, program_index: usize, key: []const u8) ?usize {
            const item = self.program(list_id, program_index) orelse return null;
            return item.infoIndexOfKey(key);
        }

        pub fn programInfoIndexOfKeyByListName(self: Self, list_name: []const u8, program_index: usize, key: []const u8) ?usize {
            const item = self.programByListName(list_name, program_index) orelse return null;
            return item.infoIndexOfKey(key);
        }

        pub fn programInfoIndexOfKeyForUnit(self: Self, unit_id: i32, program_index: usize, key: []const u8) ?usize {
            const item = self.programForUnit(unit_id, program_index) orelse return null;
            return item.infoIndexOfKey(key);
        }

        pub fn programInfoIndexOfKeyForUnitName(self: Self, unit_name: []const u8, program_index: usize, key: []const u8) ?usize {
            const item = self.programForUnitName(unit_name, program_index) orelse return null;
            return item.infoIndexOfKey(key);
        }

        pub fn hasProgramInfo(self: Self, list_id: i32, program_index: usize, key: []const u8) bool {
            return self.programInfoIndexOfKey(list_id, program_index, key) != null;
        }

        pub fn hasProgramInfoByListName(self: Self, list_name: []const u8, program_index: usize, key: []const u8) bool {
            return self.programInfoIndexOfKeyByListName(list_name, program_index, key) != null;
        }

        pub fn hasProgramInfoForUnit(self: Self, unit_id: i32, program_index: usize, key: []const u8) bool {
            return self.programInfoIndexOfKeyForUnit(unit_id, program_index, key) != null;
        }

        pub fn hasProgramInfoForUnitName(self: Self, unit_name: []const u8, program_index: usize, key: []const u8) bool {
            return self.programInfoIndexOfKeyForUnitName(unit_name, program_index, key) != null;
        }

        pub fn hasDuplicateProgramInfoKeys(self: Self, list_id: i32, program_index: usize) bool {
            return self.duplicateProgramInfoKey(list_id, program_index) != null;
        }

        pub fn hasDuplicateProgramInfoKeysByListName(self: Self, list_name: []const u8, program_index: usize) bool {
            return self.duplicateProgramInfoKeyByListName(list_name, program_index) != null;
        }

        pub fn hasDuplicateProgramInfoKeysForUnit(self: Self, unit_id: i32, program_index: usize) bool {
            return self.duplicateProgramInfoKeyForUnit(unit_id, program_index) != null;
        }

        pub fn hasDuplicateProgramInfoKeysForUnitName(self: Self, unit_name: []const u8, program_index: usize) bool {
            return self.duplicateProgramInfoKeyForUnitName(unit_name, program_index) != null;
        }

        pub fn programInfoByName(self: Self, list_id: i32, program_name: []const u8, key: []const u8) ?[]const u8 {
            const index = self.programIndexOfName(list_id, program_name) orelse return null;
            return self.programInfo(list_id, index, key);
        }

        pub fn programInfoByNameForListName(self: Self, list_name: []const u8, program_name: []const u8, key: []const u8) ?[]const u8 {
            const item = self.programByNameForListName(list_name, program_name) orelse return null;
            return item.infoValue(key);
        }

        pub fn programInfoByNameForUnit(self: Self, unit_id: i32, program_name: []const u8, key: []const u8) ?[]const u8 {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return null;
            return item.infoValue(key);
        }

        pub fn programInfoByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8, key: []const u8) ?[]const u8 {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return null;
            return item.infoValue(key);
        }

        pub fn programInfoEntryByName(self: Self, list_id: i32, program_name: []const u8, info_index: usize) ?ProgramInfo {
            const item = self.programByName(list_id, program_name) orelse return null;
            return item.infoEntry(info_index);
        }

        pub fn programInfoEntryByNameForListName(self: Self, list_name: []const u8, program_name: []const u8, info_index: usize) ?ProgramInfo {
            const item = self.programByNameForListName(list_name, program_name) orelse return null;
            return item.infoEntry(info_index);
        }

        pub fn programInfoEntryByNameForUnit(self: Self, unit_id: i32, program_name: []const u8, info_index: usize) ?ProgramInfo {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return null;
            return item.infoEntry(info_index);
        }

        pub fn programInfoEntryByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8, info_index: usize) ?ProgramInfo {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return null;
            return item.infoEntry(info_index);
        }

        pub fn programInfoEntryByNameAndKey(self: Self, list_id: i32, program_name: []const u8, key: []const u8) ?ProgramInfo {
            const item = self.programByName(list_id, program_name) orelse return null;
            return item.infoEntryByKey(key);
        }

        pub fn programInfoEntryByNameAndKeyForListName(self: Self, list_name: []const u8, program_name: []const u8, key: []const u8) ?ProgramInfo {
            const item = self.programByNameForListName(list_name, program_name) orelse return null;
            return item.infoEntryByKey(key);
        }

        pub fn programInfoEntryByNameAndKeyForUnit(self: Self, unit_id: i32, program_name: []const u8, key: []const u8) ?ProgramInfo {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return null;
            return item.infoEntryByKey(key);
        }

        pub fn programInfoEntryByNameAndKeyForUnitName(self: Self, unit_name: []const u8, program_name: []const u8, key: []const u8) ?ProgramInfo {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return null;
            return item.infoEntryByKey(key);
        }

        pub fn programInfoIndexOfKeyByName(self: Self, list_id: i32, program_name: []const u8, key: []const u8) ?usize {
            const item = self.programByName(list_id, program_name) orelse return null;
            return item.infoIndexOfKey(key);
        }

        pub fn programInfoIndexOfKeyByNameForListName(self: Self, list_name: []const u8, program_name: []const u8, key: []const u8) ?usize {
            const item = self.programByNameForListName(list_name, program_name) orelse return null;
            return item.infoIndexOfKey(key);
        }

        pub fn programInfoIndexOfKeyByNameForUnit(self: Self, unit_id: i32, program_name: []const u8, key: []const u8) ?usize {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return null;
            return item.infoIndexOfKey(key);
        }

        pub fn programInfoIndexOfKeyByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8, key: []const u8) ?usize {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return null;
            return item.infoIndexOfKey(key);
        }

        pub fn hasProgramInfoByName(self: Self, list_id: i32, program_name: []const u8, key: []const u8) bool {
            return self.programInfoIndexOfKeyByName(list_id, program_name, key) != null;
        }

        pub fn hasProgramInfoByNameForListName(self: Self, list_name: []const u8, program_name: []const u8, key: []const u8) bool {
            return self.programInfoIndexOfKeyByNameForListName(list_name, program_name, key) != null;
        }

        pub fn hasProgramInfoByNameForUnit(self: Self, unit_id: i32, program_name: []const u8, key: []const u8) bool {
            return self.programInfoIndexOfKeyByNameForUnit(unit_id, program_name, key) != null;
        }

        pub fn hasProgramInfoByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8, key: []const u8) bool {
            return self.programInfoIndexOfKeyByNameForUnitName(unit_name, program_name, key) != null;
        }

        pub fn hasDuplicateProgramInfoKeysByName(self: Self, list_id: i32, program_name: []const u8) bool {
            return self.duplicateProgramInfoKeyByName(list_id, program_name) != null;
        }

        pub fn hasDuplicateProgramInfoKeysByNameForListName(self: Self, list_name: []const u8, program_name: []const u8) bool {
            return self.duplicateProgramInfoKeyByNameForListName(list_name, program_name) != null;
        }

        pub fn hasDuplicateProgramInfoKeysByNameForUnit(self: Self, unit_id: i32, program_name: []const u8) bool {
            return self.duplicateProgramInfoKeyByNameForUnit(unit_id, program_name) != null;
        }

        pub fn hasDuplicateProgramInfoKeysByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8) bool {
            return self.duplicateProgramInfoKeyByNameForUnitName(unit_name, program_name) != null;
        }

        pub fn programInfoCount(self: Self, list_id: i32, program_index: usize) ?usize {
            const item = self.program(list_id, program_index) orelse return null;
            return item.info.len;
        }

        pub fn programInfoCountByListName(self: Self, list_name: []const u8, program_index: usize) ?usize {
            const item = self.programByListName(list_name, program_index) orelse return null;
            return item.info.len;
        }

        pub fn programInfoCountForUnit(self: Self, unit_id: i32, program_index: usize) ?usize {
            const item = self.programForUnit(unit_id, program_index) orelse return null;
            return item.info.len;
        }

        pub fn programInfoCountForUnitName(self: Self, unit_name: []const u8, program_index: usize) ?usize {
            const item = self.programForUnitName(unit_name, program_index) orelse return null;
            return item.info.len;
        }

        pub fn programInfoCountByName(self: Self, list_id: i32, program_name: []const u8) ?usize {
            const item = self.programByName(list_id, program_name) orelse return null;
            return item.info.len;
        }

        pub fn programInfoCountByNameForListName(self: Self, list_name: []const u8, program_name: []const u8) ?usize {
            const item = self.programByNameForListName(list_name, program_name) orelse return null;
            return item.info.len;
        }

        pub fn programInfoCountByNameForUnit(self: Self, unit_id: i32, program_name: []const u8) ?usize {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return null;
            return item.info.len;
        }

        pub fn programInfoCountByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8) ?usize {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return null;
            return item.info.len;
        }

        pub fn programHasInfoEntries(self: Self, list_id: i32, program_index: usize) bool {
            const item = self.program(list_id, program_index) orelse return false;
            return item.hasInfo();
        }

        pub fn programHasInfoEntriesByListName(self: Self, list_name: []const u8, program_index: usize) bool {
            const item = self.programByListName(list_name, program_index) orelse return false;
            return item.hasInfo();
        }

        pub fn programHasInfoEntriesForUnit(self: Self, unit_id: i32, program_index: usize) bool {
            const item = self.programForUnit(unit_id, program_index) orelse return false;
            return item.hasInfo();
        }

        pub fn programHasInfoEntriesForUnitName(self: Self, unit_name: []const u8, program_index: usize) bool {
            const item = self.programForUnitName(unit_name, program_index) orelse return false;
            return item.hasInfo();
        }

        pub fn programHasInfoEntriesByName(self: Self, list_id: i32, program_name: []const u8) bool {
            const item = self.programByName(list_id, program_name) orelse return false;
            return item.hasInfo();
        }

        pub fn programHasInfoEntriesByNameForListName(self: Self, list_name: []const u8, program_name: []const u8) bool {
            const item = self.programByNameForListName(list_name, program_name) orelse return false;
            return item.hasInfo();
        }

        pub fn programHasInfoEntriesByNameForUnit(self: Self, unit_id: i32, program_name: []const u8) bool {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return false;
            return item.hasInfo();
        }

        pub fn programHasInfoEntriesByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8) bool {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return false;
            return item.hasInfo();
        }

        pub fn programInfoEmpty(self: Self, list_id: i32, program_index: usize) bool {
            const item = self.program(list_id, program_index) orelse return true;
            return item.infoEmpty();
        }

        pub fn programInfoEmptyByListName(self: Self, list_name: []const u8, program_index: usize) bool {
            const item = self.programByListName(list_name, program_index) orelse return true;
            return item.infoEmpty();
        }

        pub fn programInfoEmptyForUnit(self: Self, unit_id: i32, program_index: usize) bool {
            const item = self.programForUnit(unit_id, program_index) orelse return true;
            return item.infoEmpty();
        }

        pub fn programInfoEmptyForUnitName(self: Self, unit_name: []const u8, program_index: usize) bool {
            const item = self.programForUnitName(unit_name, program_index) orelse return true;
            return item.infoEmpty();
        }

        pub fn programInfoEmptyByName(self: Self, list_id: i32, program_name: []const u8) bool {
            const item = self.programByName(list_id, program_name) orelse return true;
            return item.infoEmpty();
        }

        pub fn programInfoEmptyByNameForListName(self: Self, list_name: []const u8, program_name: []const u8) bool {
            const item = self.programByNameForListName(list_name, program_name) orelse return true;
            return item.infoEmpty();
        }

        pub fn programInfoEmptyByNameForUnit(self: Self, unit_id: i32, program_name: []const u8) bool {
            const item = self.programByNameForUnit(unit_id, program_name) orelse return true;
            return item.infoEmpty();
        }

        pub fn programInfoEmptyByNameForUnitName(self: Self, unit_name: []const u8, program_name: []const u8) bool {
            const item = self.programByNameForUnitName(unit_name, program_name) orelse return true;
            return item.infoEmpty();
        }

        pub fn rootUnit(self: Self) Unit {
            return self.unitById(root_unit_id) orelse Unit.root("Root");
        }

        pub fn rootUnitId(self: Self) i32 {
            return self.rootUnit().id;
        }

        pub fn rootUnitName(self: Self) []const u8 {
            return self.rootUnit().name;
        }

        pub fn validateUnits(self: Self) !void {
            if (config.units.len == 0) return error.MissingRootUnit;
            if (self.duplicateUnitId() != null) return error.DuplicateUnitId;
            if (self.duplicateUnitName() != null) return error.DuplicateUnitName;
            const root = self.unitById(root_unit_id) orelse return error.MissingRootUnit;
            if (root.name.len == 0) return error.EmptyUnitName;
            if (common.containsNul(root.name)) return error.InvalidUnitMetadata;
            if (root.parent_id != no_parent_unit_id) return error.InvalidUnitParent;
            for (config.units) |item| {
                if (item.id == no_parent_unit_id) return error.ReservedUnitId;
                if (item.name.len == 0) return error.EmptyUnitName;
                if (common.containsNul(item.name)) return error.InvalidUnitMetadata;
                if (item.id != root_unit_id and self.unitById(item.parent_id) == null) return error.InvalidUnitParent;
                if (item.program_list_id != no_program_list_id and self.programListById(item.program_list_id) == null) {
                    return error.InvalidUnitProgramList;
                }
                if (self.unitParentIsCyclic(item)) return error.CyclicUnitParent;
            }
        }

        pub fn validateProgramLists(self: Self) !void {
            if (self.duplicateProgramListId() != null) return error.DuplicateProgramListId;
            if (self.duplicateProgramListName() != null) return error.DuplicateProgramListName;
            for (config.program_lists) |list| {
                if (list.id == no_program_list_id) return error.ReservedProgramListId;
                if (list.name.len == 0) return error.EmptyProgramListName;
                if (common.containsNul(list.name)) return error.InvalidProgramListMetadata;
                if (self.duplicateProgramName(list.id) != null) return error.DuplicateProgramName;
                for (list.programs, 0..) |item, item_index| {
                    if (item.name.len == 0) return error.EmptyProgramName;
                    if (common.containsNul(item.name)) return error.InvalidProgramMetadata;
                    if (self.duplicateProgramParameterId(list.id, item_index) != null) return error.DuplicateProgramParameter;
                    if (self.duplicateProgramInfoKey(list.id, item_index) != null) return error.DuplicateProgramInfoKey;
                    for (item.parameters) |parameter| {
                        if (!common.isNormalized(parameter.normalized)) {
                            return error.ProgramParameterOutsideNormalizedRange;
                        }
                    }
                    for (item.info) |info| {
                        if (info.key.len == 0) return error.EmptyProgramInfoKey;
                        if (common.containsNul(info.key) or common.containsNul(info.value)) return error.InvalidProgramInfoMetadata;
                    }
                }
            }
        }

        pub fn validate(self: Self) !void {
            try self.validateProgramLists();
            try self.validateUnits();
        }

        pub fn validateProgramParameterIds(_: Self, parameter_set: anytype) !void {
            for (config.program_lists) |list| {
                for (list.programs) |item| {
                    for (item.parameters) |parameter| {
                        if (parameter_set.indexOfId(parameter.parameter_id) == null) return error.UnknownProgramParameter;
                    }
                }
            }
        }

        fn unitParentIsCyclic(self: Self, item: Unit) bool {
            if (item.id == root_unit_id) return false;
            var parent_id = item.parent_id;
            var depth: usize = 0;
            while (parent_id != root_unit_id) {
                if (depth >= config.units.len) return true;
                const parent = self.unitById(parent_id) orelse return false;
                if (parent.parent_id == no_parent_unit_id) return false;
                parent_id = parent.parent_id;
                depth += 1;
            }
            return false;
        }
    };
}
