const alsa_midi = @import("zig-vst3-alsamidi");

pub fn main() void {
    var backend = alsa_midi.Backend{};
    _ = backend.inputStatistics();
}
