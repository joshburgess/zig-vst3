const pipewire = @import("zig-vst3-pipewire");

pub fn main() void {
    var backend = pipewire.Backend(f32){};
    _ = backend.statistics();
}
