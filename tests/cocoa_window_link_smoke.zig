const cocoa_window = @import("zig-vst3-cocoawindow");

pub fn main() !void {
    var backend = try cocoa_window.Backend.init("Link Smoke");
    _ = backend.windowBackend();
}
