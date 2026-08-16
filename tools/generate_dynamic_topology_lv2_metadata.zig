const std = @import("std");
const core = @import("zig-vst3-plugin-core");
const probe = @import("dynamic-topology-lv2");

const Generator = core.lv2.metadata.Generator(
    probe.DynamicTopologyProbe,
    probe.Adapter,
    probe.uri,
    .{},
);

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 6 or !std.mem.eql(u8, args[5], "-"))
        return error.InvalidArguments;

    const metadata = core.lv2.metadata.Metadata{
        .class_uri = "http://lv2plug.in/ns/lv2core#UtilityPlugin",
        .description = "A distribution validation fixture for fixed LV2 projection of dynamic audio buses.",
        .short_description = "Dynamic audio bus projection fixture",
        .project = .{
            .uri = "https://github.com/joshburgess/zig-vst3",
            .name = "zig-vst3",
            .license_uri = "https://spdx.org/licenses/MIT.html",
            .maintainer = .{
                .name = "Josh Burgess",
                .email_uri = "mailto:joshburgesswebdev@gmail.com",
                .homepage_uri = "https://github.com/joshburgess",
            },
        },
    };

    var bytes: [64 * 1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try Generator.writeManifest(&writer, args[1], metadata);
    try writeFile(init.io, args[2], writer.buffered());

    writer = std.Io.Writer.fixed(&bytes);
    try Generator.writePlugin(&writer, metadata);
    try writeFile(init.io, args[3], writer.buffered());

    writer = std.Io.Writer.fixed(&bytes);
    try Generator.writePresets(&writer, metadata);
    try writeFile(init.io, args[4], writer.buffered());
}

fn writeFile(io: std.Io, path: []const u8, bytes: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
}
