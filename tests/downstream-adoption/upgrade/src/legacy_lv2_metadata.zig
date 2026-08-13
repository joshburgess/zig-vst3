const core = @import("zig-vst3-plugin-core");

test "pre-candidate LV2 metadata path" {
    _ = core.lv2_metadata.Metadata;
}
