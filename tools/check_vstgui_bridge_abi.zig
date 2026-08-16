const adapter = @import("vstgui-adapter-raw");
const bridge = @import("vstgui-bridge-source");

pub fn main() void {
    comptime bridge.verifyAdapterAbi(adapter);
}
