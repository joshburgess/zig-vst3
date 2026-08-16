const alsa_ump = @import("zig-vst3-alsaump");

pub fn main() !void {
    var backend = alsa_ump.Backend{};
    if (!backend.available()) return;
    try backend.open("zig-vst3 ALSA UMP link smoke");
    defer backend.close();
    var descriptors: [64]@import(
        "zig-vst3-plugin-core",
    ).plugin.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&descriptors);
}
