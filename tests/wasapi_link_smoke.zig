const core = @import("zig-vst3-plugin-core");
const wasapi = @import("zig-vst3-wasapi");

pub fn main() void {
    var backend = wasapi.Backend(f32){};
    backend.startObservingTopology() catch {};
    defer backend.deinit();
    var descriptors: [1]core.plugin.DeviceDescriptor = undefined;
    _ = backend.enumerate(&descriptors) catch return;
    var context: u8 = 0;
    var device = backend.audioDevice();
    device.start(.{
        .sample_rate = 48_000.0,
        .max_block_size = 1024,
        .input_channel_count = 0,
        .output_channel_count = 1,
    }, .{
        .context = &context,
        .process_block = process,
    }) catch return;
    _ = backend.statistics();
    device.stop();
}

fn process(
    _: *anyopaque,
    block: core.plugin.CallbackBlock(f32),
) void {
    for (block.output_channels) |channel|
        @memset(channel, 0.0);
}
