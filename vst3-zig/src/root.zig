const std = @import("std");

pub const entry = @import("entry.zig");
pub const bypass_component = @import("bypass_component.zig");
pub const bypass_controller = @import("bypass_controller.zig");
pub const bypass_plugin = @import("bypass_plugin.zig");
pub const bypass_spec = @import("bypass_spec.zig");
pub const factory = @import("factory.zig");
pub const funknown = @import("funknown.zig");
pub const gain_component = @import("gain_component.zig");
pub const gain_controller = @import("gain_controller.zig");
pub const gain_spec = @import("gain_spec.zig");
pub const interface_map = @import("interface_map.zig");
pub const mode_gain_component = @import("mode_gain_component.zig");
pub const mode_gain_controller = @import("mode_gain_controller.zig");
pub const mode_gain_plugin = @import("mode_gain_plugin.zig");
pub const mode_gain_spec = @import("mode_gain_spec.zig");
pub const multi_interface = @import("multi_interface.zig");
pub const pluginterfaces = struct {
    pub const base = @import("pluginterfaces/base/root.zig");
    pub const gui = @import("pluginterfaces/gui/root.zig");
    pub const @"test" = @import("pluginterfaces/test/root.zig");
    pub const vst = @import("pluginterfaces/vst/root.zig");
};
pub const tuid = @import("tuid.zig");
pub const version = "0.1.0-dev";
pub const zig_plug_bridge = @import("zig_plug_bridge.zig");
pub const zig_plug_effect = @import("zig_plug_effect.zig");

pub fn targetName() []const u8 {
    return @tagName(@import("builtin").target.os.tag);
}

test "vst3-zig module exposes a development version" {
    try std.testing.expect(std.mem.endsWith(u8, version, "-dev"));
}
