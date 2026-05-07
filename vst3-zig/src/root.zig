const std = @import("std");

pub const entry = @import("entry.zig");
pub const factory = @import("factory.zig");
pub const funknown = @import("funknown.zig");
pub const gain_component = @import("gain_component.zig");
pub const gain_controller = @import("gain_controller.zig");
pub const gain_spec = @import("gain_spec.zig");
pub const interface_map = @import("interface_map.zig");
pub const multi_interface = @import("multi_interface.zig");
pub const pluginterfaces = struct {
    pub const base = @import("pluginterfaces/base/root.zig");
    pub const gui = @import("pluginterfaces/gui/root.zig");
    pub const @"test" = @import("pluginterfaces/test/root.zig");
    pub const vst = @import("pluginterfaces/vst/root.zig");
};
pub const tuid = @import("tuid.zig");
pub const version = "0.1.0-dev";

pub fn targetName() []const u8 {
    return @tagName(@import("builtin").target.os.tag);
}

test "vst3-zig module exposes a development version" {
    try std.testing.expect(std.mem.endsWith(u8, version, "-dev"));
}
