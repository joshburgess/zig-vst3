const win_midi = @import("zig-vst3-winmidi");

pub fn main() void {
    var backend = win_midi.Backend{};
    _ = backend.inputStatistics();
}
