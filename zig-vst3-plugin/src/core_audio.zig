const std = @import("std");
const implementation = @import("plugin/core_audio.zig");

pub const Backend = implementation.CoreAudioBackend;
pub const BoundedBackend =
    implementation.BoundedCoreAudioBackend;
pub const CallbackStatistics = implementation.CallbackStatistics;
pub const DirectionalDeviceFailures =
    implementation.DirectionalDeviceFailures;
pub const DeviceRuntimeInfo = implementation.DeviceRuntimeInfo;

test {
    std.testing.refAllDecls(implementation);
}
