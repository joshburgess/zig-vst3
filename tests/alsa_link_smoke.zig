const alsa = @import("zig-vst3-alsa");

pub fn main() void {
    var backend = alsa.Backend(f32){};
    _ = backend.statistics();
}
