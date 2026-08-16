const plug = @import("zig-vst3-plugin");

test "pre-candidate backend version path" {
    _ = plug.backendVersion();
}
