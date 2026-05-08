const std = @import("std");
const vst3 = @import("vst3-zig");

pub const core = @import("zig-plug-core");
pub const parameters = core.parameters;
pub const plugin = core.plugin;
pub const process = core.process;
pub const state = core.state;
pub const units = core.units;
pub const version = "0.1.0-dev";

pub fn backendVersion() []const u8 {
    return vst3.version;
}

test "zig-plug sees vst3-zig" {
    try std.testing.expectEqualStrings("0.1.0-dev", backendVersion());
}

test "zig-plug re-exports core modules" {
    try std.testing.expect(@hasDecl(parameters, "FloatParam"));
    try std.testing.expect(@hasDecl(plugin, "PluginSpec"));
    try std.testing.expect(@hasDecl(process, "ProcessContext"));
    try std.testing.expect(@hasDecl(state, "writeParameterState"));
    try std.testing.expect(@hasDecl(state, "format_version"));
    try std.testing.expect(@hasDecl(units, "UnitSet"));
}
