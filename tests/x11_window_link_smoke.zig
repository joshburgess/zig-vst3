const x11_window = @import("zig-vst3-x11window");

pub fn main() !void {
    var backend = try x11_window.Backend.init("Link Smoke");
    _ = backend.windowBackend();
}
