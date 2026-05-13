const std = @import("std");

pub const root_unit_id: i32 = 0;
pub const no_parent_unit_id: i32 = -1;
pub const no_program_list_id: i32 = -1;

pub const Unit = struct {
    id: i32,
    name: []const u8,
    parent_id: i32 = root_unit_id,
    program_list_id: i32 = no_program_list_id,

    pub fn root(name: []const u8) Unit {
        return .{
            .id = root_unit_id,
            .name = name,
            .parent_id = no_parent_unit_id,
        };
    }

    pub fn isRoot(self: Unit) bool {
        return self.id == root_unit_id;
    }

    pub fn hasParent(self: Unit) bool {
        return self.parent_id != no_parent_unit_id;
    }

    pub fn hasProgramList(self: Unit) bool {
        return self.program_list_id != no_program_list_id;
    }
};

pub const Program = struct {
    name: []const u8,
    parameters: []const ProgramParameter = &.{},
    info: []const ProgramInfo = &.{},

    pub fn parameterCount(self: Program) usize {
        return self.parameters.len;
    }

    pub fn infoCount(self: Program) usize {
        return self.info.len;
    }

    pub fn hasParameters(self: Program) bool {
        return self.parameters.len != 0;
    }

    pub fn parametersEmpty(self: Program) bool {
        return self.parameters.len == 0;
    }

    pub fn hasInfo(self: Program) bool {
        return self.info.len != 0;
    }

    pub fn infoEmpty(self: Program) bool {
        return self.info.len == 0;
    }

    pub fn duplicateParameterId(self: Program) ?u32 {
        for (self.parameters, 0..) |left, left_index| {
            for (self.parameters[left_index + 1 ..]) |right| {
                if (right.parameter_id == left.parameter_id) return left.parameter_id;
            }
        }
        return null;
    }

    pub fn duplicateParameterIdIndex(self: Program) ?usize {
        for (self.parameters, 0..) |left, left_index| {
            for (self.parameters[left_index + 1 ..], left_index + 1..) |right, right_index| {
                if (right.parameter_id == left.parameter_id) return right_index;
            }
        }
        return null;
    }

    pub fn hasDuplicateParameterIds(self: Program) bool {
        return self.duplicateParameterId() != null;
    }

    pub fn duplicateInfoKey(self: Program) ?[]const u8 {
        for (self.info, 0..) |left, left_index| {
            for (self.info[left_index + 1 ..]) |right| {
                if (std.mem.eql(u8, right.key, left.key)) return left.key;
            }
        }
        return null;
    }

    pub fn duplicateInfoKeyIndex(self: Program) ?usize {
        for (self.info, 0..) |left, left_index| {
            for (self.info[left_index + 1 ..], left_index + 1..) |right, right_index| {
                if (std.mem.eql(u8, right.key, left.key)) return right_index;
            }
        }
        return null;
    }

    pub fn hasDuplicateInfoKeys(self: Program) bool {
        return self.duplicateInfoKey() != null;
    }

    pub fn parameter(self: Program, index: usize) ?ProgramParameter {
        if (index >= self.parameters.len) return null;
        return self.parameters[index];
    }

    pub fn parameterIndexOfId(self: Program, parameter_id: u32) ?usize {
        for (self.parameters, 0..) |item, index| {
            if (item.parameter_id == parameter_id) return index;
        }
        return null;
    }

    pub fn parameterById(self: Program, parameter_id: u32) ?ProgramParameter {
        const index = self.parameterIndexOfId(parameter_id) orelse return null;
        return self.parameter(index);
    }

    pub fn hasParameter(self: Program, parameter_id: u32) bool {
        return self.parameterIndexOfId(parameter_id) != null;
    }

    pub fn infoEntry(self: Program, index: usize) ?ProgramInfo {
        if (index >= self.info.len) return null;
        return self.info[index];
    }

    pub fn infoIndexOfKey(self: Program, key: []const u8) ?usize {
        for (self.info, 0..) |item, index| {
            if (std.mem.eql(u8, item.key, key)) return index;
        }
        return null;
    }

    pub fn infoEntryByKey(self: Program, key: []const u8) ?ProgramInfo {
        const index = self.infoIndexOfKey(key) orelse return null;
        return self.infoEntry(index);
    }

    pub fn infoValue(self: Program, key: []const u8) ?[]const u8 {
        const index = self.infoIndexOfKey(key) orelse return null;
        return self.info[index].value;
    }

    pub fn hasInfoKey(self: Program, key: []const u8) bool {
        return self.infoIndexOfKey(key) != null;
    }
};

pub const ProgramParameter = struct {
    parameter_id: u32,
    normalized: f64,
};

pub const ProgramInfo = struct {
    key: []const u8,
    value: []const u8,
};

pub const ProgramList = struct {
    id: i32,
    name: []const u8,
    programs: []const Program = &.{},

    pub fn programCount(self: ProgramList) usize {
        return self.programs.len;
    }

    pub fn isEmpty(self: ProgramList) bool {
        return self.programs.len == 0;
    }

    pub fn hasPrograms(self: ProgramList) bool {
        return self.programs.len != 0;
    }

    pub fn duplicateProgramName(self: ProgramList) ?[]const u8 {
        for (self.programs, 0..) |left, left_index| {
            for (self.programs[left_index + 1 ..]) |right| {
                if (std.mem.eql(u8, right.name, left.name)) return left.name;
            }
        }
        return null;
    }

    pub fn duplicateProgramNameIndex(self: ProgramList) ?usize {
        for (self.programs, 0..) |left, left_index| {
            for (self.programs[left_index + 1 ..], left_index + 1..) |right, right_index| {
                if (std.mem.eql(u8, right.name, left.name)) return right_index;
            }
        }
        return null;
    }

    pub fn hasDuplicateProgramNames(self: ProgramList) bool {
        return self.duplicateProgramName() != null;
    }

    pub fn program(self: ProgramList, index: usize) ?Program {
        if (index >= self.programs.len) return null;
        return self.programs[index];
    }

    pub fn programName(self: ProgramList, index: usize) ?[]const u8 {
        const item = self.program(index) orelse return null;
        return item.name;
    }

    pub fn programIndexOfName(self: ProgramList, name: []const u8) ?usize {
        for (self.programs, 0..) |item, index| {
            if (std.mem.eql(u8, item.name, name)) return index;
        }
        return null;
    }

    pub fn programByName(self: ProgramList, name: []const u8) ?Program {
        const index = self.programIndexOfName(name) orelse return null;
        return self.program(index);
    }

    pub fn hasProgramName(self: ProgramList, name: []const u8) bool {
        return self.programIndexOfName(name) != null;
    }
};

pub const Config = struct {
    units: []const Unit = &.{Unit.root("Root")},
    program_lists: []const ProgramList = &.{},
};
