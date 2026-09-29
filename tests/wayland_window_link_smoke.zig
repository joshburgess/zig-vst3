const wayland_window = @import("zig-vst3-waylandwindow");

pub fn main() !void {
    var backend = try wayland_window.Backend.init("Link Smoke");
    _ = backend.windowBackend();
}
