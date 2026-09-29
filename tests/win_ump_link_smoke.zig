const win_ump = @import("zig-vst3-winump");

pub fn main() void {
    var backend = win_ump.Backend{};
    _ = backend.isOpen();
}
