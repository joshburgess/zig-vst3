const std = @import("std");
const descriptors = @import("units/descriptors.zig");
const set_mod = @import("units/set.zig");

pub const root_unit_id = descriptors.root_unit_id;
pub const no_parent_unit_id = descriptors.no_parent_unit_id;
pub const no_program_list_id = descriptors.no_program_list_id;

pub const Unit = descriptors.Unit;
pub const Program = descriptors.Program;
pub const ProgramParameter = descriptors.ProgramParameter;
pub const ProgramInfo = descriptors.ProgramInfo;
pub const ProgramList = descriptors.ProgramList;
pub const Config = descriptors.Config;

pub const UnitSet = set_mod.UnitSet;

test {
    std.testing.refAllDecls(@import("units/tests.zig"));
}
