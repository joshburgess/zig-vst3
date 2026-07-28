const win_window = @import("zig-vst3-winwindow");

pub fn main() !void {
    var backend = try win_window.Backend.init("Link Smoke");
    _ = backend.windowBackend();
}
