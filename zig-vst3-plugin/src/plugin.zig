const std = @import("std");
const audio_layout = @import("plugin/audio_layout.zig");
const spec = @import("plugin/spec.zig");
const config = @import("plugin/config.zig");
const instance = @import("plugin/instance.zig");
const lifecycle = @import("plugin/lifecycle.zig");

pub const PluginSpec = spec.PluginSpec;
pub const AudioBusLayout = audio_layout.AudioBusLayout;
pub const PrepareConfig = config.PrepareConfig;
pub const PluginInstance = instance.PluginInstance;
pub const validateLifecycle = lifecycle.validateLifecycle;

test {
    std.testing.refAllDecls(@import("plugin/tests.zig"));
}
