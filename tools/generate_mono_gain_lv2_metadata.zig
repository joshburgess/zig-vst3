const std = @import("std");
const builtin = @import("builtin");
const core = @import("zig-vst3-plugin-core");
const mono = @import("mono-gain-lv2");

const Generator = core.lv2.metadata.Generator(
    mono.MonoGain,
    mono.Adapter,
    mono.uri,
    .{},
);

const presets = [_]core.lv2.metadata.FactoryPreset{
    .{
        .slug = "unity",
        .label = "Unity",
        .values = &.{.{ .symbol = "gain", .value = 1.0 }},
    },
    .{
        .slug = "muted",
        .label = "Muted",
        .values = &.{.{ .symbol = "gain", .value = 0.0 }},
    },
};

const ui_port_notifications = [_]core.lv2.metadata.UiPortNotification{
    .{ .port_symbol = "gain", .protocol = .float },
    .{ .port_symbol = "input", .protocol = .peak },
    .{ .port_symbol = "output", .protocol = .peak },
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 6) return error.InvalidArguments;
    const ui = if (std.mem.eql(u8, args[5], "-"))
        null
    else
        core.lv2.metadata.UiMetadata{
            .uri = mono.uri ++ "#vstgui-ui",
            .binary_name = args[5],
            .class_uri = switch (builtin.os.tag) {
                .macos => "http://lv2plug.in/ns/extensions/ui#CocoaUI",
                .windows => "http://lv2plug.in/ns/extensions/ui#WindowsUI",
                .linux => "http://lv2plug.in/ns/extensions/ui#X11UI",
                else => return error.UnsupportedUiPlatform,
            },
            .port_notifications = &ui_port_notifications,
        };
    const metadata = core.lv2.metadata.Metadata{
        .class_uri = "http://lv2plug.in/ns/lv2core#AmplifierPlugin",
        .description = "A mono gain reference plugin for the zig-vst3 plugin framework.",
        .short_description = "Mono gain reference plugin",
        .is_live = true,
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
        .presets = &presets,
        .ui = ui,
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
