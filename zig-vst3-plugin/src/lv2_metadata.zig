const std = @import("std");
const parameters = @import("parameters.zig");
const plugin_api = @import("plugin.zig");
const process_api = @import("process.zig");

pub const PresetValue = struct {
    symbol: []const u8,
    value: f64,
};

pub const FactoryPreset = struct {
    slug: []const u8,
    label: []const u8,
    values: []const PresetValue,
};

pub const UiMetadata = struct {
    uri: []const u8,
    binary_name: []const u8,
    class_uri: []const u8,
};

pub const Metadata = struct {
    class_uri: []const u8 = "http://lv2plug.in/ns/lv2core#Plugin",
    minor_version: u32 = 0,
    micro_version: u32 = 1,
    presets: []const FactoryPreset = &.{},
    ui: ?UiMetadata = null,
};

pub fn Generator(
    comptime Plugin: type,
    comptime Adapter: type,
    comptime plugin_uri: [:0]const u8,
    comptime initial_parameters: Plugin.Params,
) type {
    const ParameterSet = parameters.ParameterSet(Plugin.Params);
    const fields = @typeInfo(Plugin.Params).@"struct".fields;
    const has_programs =
        @hasDecl(Adapter, "programs_enabled") and
        Adapter.programs_enabled;
    _ = plugin_api.PluginSpec(Plugin);

    return struct {
        pub fn writeManifest(
            writer: *std.Io.Writer,
            binary_name: []const u8,
            metadata: Metadata,
        ) !void {
            try validate(metadata, binary_name);
            try writer.writeAll(
                "@prefix lv2:  <http://lv2plug.in/ns/lv2core#> .\n" ++
                    "@prefix pset: <http://lv2plug.in/ns/ext/presets#> .\n" ++
                    "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .\n\n<",
            );
            try writer.writeAll(plugin_uri);
            try writer.writeAll(
                ">\n    a lv2:Plugin ;\n    lv2:binary <",
            );
            try writer.writeAll(binary_name);
            try writer.writeAll(
                "> ;\n    rdfs:seeAlso <plugin.ttl> .\n",
            );
            if (metadata.ui) |ui| {
                try writer.writeAll("\n<");
                try writer.writeAll(ui.uri);
                try writer.writeAll(">\n    a <");
                try writer.writeAll(ui.class_uri);
                try writer.writeAll("> ;\n    lv2:binary <");
                try writer.writeAll(ui.binary_name);
                try writer.writeAll(
                    "> ;\n    rdfs:seeAlso <plugin.ttl> .\n",
                );
            }
            for (metadata.presets) |preset| {
                try writer.writeAll("\n<");
                try writePresetUri(writer, preset.slug);
                try writer.writeAll(
                    ">\n    a pset:Preset ;\n    lv2:appliesTo <",
                );
                try writer.writeAll(plugin_uri);
                try writer.writeAll(
                    "> ;\n    rdfs:seeAlso <presets.ttl> .\n",
                );
            }
        }

        pub fn writePlugin(
            writer: *std.Io.Writer,
            metadata: Metadata,
        ) !void {
            try validate(metadata, "plugin");
            try writer.writeAll(
                "@prefix atom: <http://lv2plug.in/ns/ext/atom#> .\n" ++
                    "@prefix bufsz: <http://lv2plug.in/ns/ext/buf-size#> .\n" ++
                    "@prefix doap: <http://usefulinc.com/ns/doap#> .\n" ++
                    "@prefix lv2:  <http://lv2plug.in/ns/lv2core#> .\n" ++
                    "@prefix midi: <http://lv2plug.in/ns/ext/midi#> .\n" ++
                    "@prefix opts: <http://lv2plug.in/ns/ext/options#> .\n" ++
                    "@prefix pgm:  <http://kxstudio.sf.net/ns/lv2ext/programs#> .\n" ++
                    "@prefix state: <http://lv2plug.in/ns/ext/state#> .\n" ++
                    "@prefix time: <http://lv2plug.in/ns/ext/time#> .\n" ++
                    "@prefix ui:   <http://lv2plug.in/ns/extensions/ui#> .\n" ++
                    "@prefix urid: <http://lv2plug.in/ns/ext/urid#> .\n" ++
                    "@prefix work: <http://lv2plug.in/ns/ext/worker#> .\n\n<",
            );
            try writer.writeAll(plugin_uri);
            try writer.writeAll(">\n    a <");
            try writer.writeAll(metadata.class_uri);
            try writer.writeAll("> ;\n    doap:name ");
            try writeTurtleString(writer, Plugin.name);
            try writer.print(
                " ;\n    lv2:minorVersion {d} ;\n    lv2:microVersion {d} ;\n",
                .{ metadata.minor_version, metadata.micro_version },
            );
            if (metadata.ui) |ui| {
                try writer.writeAll("    ui:ui <");
                try writer.writeAll(ui.uri);
                try writer.writeAll("> ;\n");
            }
            try writer.writeAll(
                "    lv2:optionalFeature lv2:hardRTCapable , opts:options",
            );
            if (Adapter.worker_enabled)
                try writer.writeAll(" , work:schedule");
            try writer.writeAll(
                " ;\n    lv2:requiredFeature urid:map ;\n" ++
                    "    lv2:extensionData opts:interface , state:interface",
            );
            if (Adapter.worker_enabled)
                try writer.writeAll(" , work:interface");
            if (has_programs)
                try writer.writeAll(" , pgm:Interface");
            try writer.writeAll(
                " ;\n    opts:supportedOption bufsz:minBlockLength ,\n" ++
                    "                         bufsz:maxBlockLength ,\n" ++
                    "                         bufsz:nominalBlockLength ;\n",
            );
            try writePorts(writer);
            try writer.writeAll(" .\n");
            if (metadata.ui) |ui| {
                try writer.writeAll("\n<");
                try writer.writeAll(ui.uri);
                try writer.writeAll(">\n    a <");
                try writer.writeAll(ui.class_uri);
                try writer.writeAll("> ;\n    lv2:binary <");
                try writer.writeAll(ui.binary_name);
                try writer.writeAll(
                    "> ;\n" ++
                        "    lv2:requiredFeature ui:parent ;\n" ++
                        "    lv2:optionalFeature ui:resize , ui:touch ;\n" ++
                        "    lv2:extensionData ui:idleInterface , ui:resize , ui:showInterface",
                );
                if (has_programs)
                    try writer.writeAll(" , pgm:UIInterface");
                try writer.writeAll(" .\n");
            }
        }

        pub fn writePresets(
            writer: *std.Io.Writer,
            metadata: Metadata,
        ) !void {
            try validate(metadata, "plugin");
            try writer.writeAll(
                "@prefix lv2:  <http://lv2plug.in/ns/lv2core#> .\n" ++
                    "@prefix pset: <http://lv2plug.in/ns/ext/presets#> .\n" ++
                    "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .\n",
            );
            for (metadata.presets) |preset| {
                try writer.writeAll("\n<");
                try writePresetUri(writer, preset.slug);
                try writer.writeAll(
                    ">\n    a pset:Preset ;\n    rdfs:label ",
                );
                try writeTurtleString(writer, preset.label);
                try writer.writeAll(" ;\n    lv2:appliesTo <");
                try writer.writeAll(plugin_uri);
                if (preset.values.len == 0) {
                    try writer.writeAll("> .\n");
                    continue;
                }
                try writer.writeAll("> ;\n");
                for (preset.values, 0..) |value, index| {
                    try writer.writeAll(
                        if (index == 0)
                            "    lv2:port [\n"
                        else
                            "    ] , [\n",
                    );
                    try writer.writeAll("        lv2:symbol ");
                    try writeTurtleString(writer, value.symbol);
                    try writer.print(
                        " ;\n        pset:value {d}\n",
                        .{value.value},
                    );
                }
                try writer.writeAll("    ] .\n");
            }
        }

        fn writePorts(writer: *std.Io.Writer) !void {
            var first = true;
            for (0..Adapter.input_channels) |offset| {
                try beginPort(writer, &first);
                try writer.writeAll(
                    "        a lv2:InputPort , lv2:AudioPort ;\n",
                );
                try writeIndexedPortStart(
                    writer,
                    offset,
                    "input",
                    offset,
                    Adapter.input_channels,
                );
            }
            for (0..Adapter.output_channels) |offset| {
                try beginPort(writer, &first);
                try writer.writeAll(
                    "        a lv2:OutputPort , lv2:AudioPort ;\n",
                );
                try writeIndexedPortStart(
                    writer,
                    Adapter.audio_output_port_start + offset,
                    "output",
                    offset,
                    Adapter.output_channels,
                );
            }
            if (Adapter.event_input_port) |index| {
                try beginPort(writer, &first);
                try writer.writeAll(
                    "        a lv2:InputPort , atom:AtomPort ;\n",
                );
                try writeFixedIndexedPort(
                    writer,
                    index,
                    "midi_input",
                    "MIDI Input",
                );
                try writer.writeAll(
                    " ;\n        atom:bufferType atom:Sequence ;\n" ++
                        "        atom:supports midi:MidiEvent , time:Position\n",
                );
            }
            if (Adapter.event_output_port) |index| {
                try beginPort(writer, &first);
                try writer.writeAll(
                    "        a lv2:OutputPort , atom:AtomPort ;\n",
                );
                try writeFixedIndexedPort(
                    writer,
                    index,
                    "midi_output",
                    "MIDI Output",
                );
                try writer.writeAll(
                    " ;\n        atom:bufferType atom:Sequence ;\n" ++
                        "        atom:supports midi:MidiEvent\n",
                );
            }
            const set = ParameterSet.init(initial_parameters);
            inline for (fields, 0..) |field, parameter_index| {
                try beginPort(writer, &first);
                try writer.writeAll(
                    "        a lv2:InputPort , lv2:ControlPort ;\n",
                );
                try writeFixedIndexedPort(
                    writer,
                    Adapter.control_input_port_start + parameter_index,
                    field.name,
                    set.name(parameter_index) orelse
                        return error.InvalidParameterMetadata,
                );
                try writer.print(
                    " ;\n        lv2:minimum {d} ;\n" ++
                        "        lv2:maximum {d} ;\n" ++
                        "        lv2:default {d}\n",
                    .{
                        set.plainMinimum(parameter_index) orelse
                            return error.InvalidParameterMetadata,
                        set.plainMaximum(parameter_index) orelse
                            return error.InvalidParameterMetadata,
                        set.defaultPlain(parameter_index) orelse
                            return error.InvalidParameterMetadata,
                    },
                );
            }
            if (Adapter.freewheeling_input_port) |index| {
                try beginPort(writer, &first);
                try writer.writeAll(
                    "        a lv2:InputPort , lv2:ControlPort ;\n",
                );
                try writeFixedIndexedPort(
                    writer,
                    index,
                    "freewheeling",
                    "Freewheeling",
                );
                try writer.writeAll(
                    " ;\n        lv2:designation lv2:freeWheeling ;\n" ++
                        "        lv2:portProperty lv2:toggled ;\n" ++
                        "        lv2:minimum 0 ;\n" ++
                        "        lv2:maximum 1 ;\n" ++
                        "        lv2:default 0\n",
                );
            }
            try beginPort(writer, &first);
            try writer.writeAll(
                "        a lv2:OutputPort , lv2:ControlPort ;\n",
            );
            try writeFixedIndexedPort(
                writer,
                Adapter.latency_output_port,
                "latency",
                "Latency",
            );
            try writer.writeAll(
                " ;\n        lv2:designation lv2:latency ;\n" ++
                    "        lv2:portProperty lv2:integer\n    ]",
            );
        }

        fn validate(metadata: Metadata, binary_name: []const u8) !void {
            if (!validUri(plugin_uri) or !validUri(metadata.class_uri))
                return error.InvalidLv2MetadataUri;
            if (!validFileName(binary_name))
                return error.InvalidLv2BinaryName;
            if (!validText(Plugin.name))
                return error.InvalidLv2MetadataText;
            if (metadata.ui) |ui| {
                if (!validUri(ui.uri) or !validUri(ui.class_uri) or
                    std.mem.eql(u8, ui.uri, plugin_uri))
                    return error.InvalidLv2UiUri;
                if (!validFileName(ui.binary_name))
                    return error.InvalidLv2UiBinaryName;
            }
            const set = ParameterSet.init(initial_parameters);
            try set.validate();
            inline for (fields, 0..) |field, parameter_index| {
                if (!validSymbol(field.name))
                    return error.InvalidLv2PortSymbol;
                if (!validText(set.name(parameter_index) orelse
                    return error.InvalidParameterMetadata))
                    return error.InvalidLv2MetadataText;
                if (reservedPortSymbol(field.name))
                    return error.DuplicateLv2PortSymbol;
            }
            for (metadata.presets, 0..) |preset, preset_index| {
                if (!validSlug(preset.slug))
                    return error.InvalidLv2PresetSlug;
                if (!validText(preset.label))
                    return error.InvalidLv2MetadataText;
                for (metadata.presets[0..preset_index]) |previous| {
                    if (std.mem.eql(u8, previous.slug, preset.slug))
                        return error.DuplicateLv2PresetSlug;
                }
                for (preset.values, 0..) |value, value_index| {
                    if (!validSymbol(value.symbol))
                        return error.InvalidLv2PortSymbol;
                    const parameter_index =
                        parameterIndex(value.symbol) orelse
                        return error.UnknownLv2PresetParameter;
                    const minimum = set.plainMinimum(parameter_index) orelse
                        return error.InvalidParameterMetadata;
                    const maximum = set.plainMaximum(parameter_index) orelse
                        return error.InvalidParameterMetadata;
                    if (!std.math.isFinite(value.value) or
                        value.value < minimum or value.value > maximum)
                        return error.InvalidLv2PresetValue;
                    for (preset.values[0..value_index]) |previous| {
                        if (std.mem.eql(
                            u8,
                            previous.symbol,
                            value.symbol,
                        )) return error.DuplicateLv2PresetParameter;
                    }
                }
            }
        }

        fn parameterIndex(symbol: []const u8) ?usize {
            inline for (fields, 0..) |field, index| {
                if (std.mem.eql(u8, field.name, symbol)) return index;
            }
            return null;
        }

        fn reservedPortSymbol(symbol: []const u8) bool {
            if (std.mem.eql(u8, symbol, "latency"))
                return true;
            if (Adapter.event_input_port != null and
                std.mem.eql(u8, symbol, "midi_input"))
                return true;
            if (Adapter.event_output_port != null and
                std.mem.eql(u8, symbol, "midi_output"))
                return true;
            for (0..Adapter.input_channels) |index| {
                if (audioSymbolEquals(
                    symbol,
                    "input",
                    index,
                    Adapter.input_channels,
                )) return true;
            }
            for (0..Adapter.output_channels) |index| {
                if (audioSymbolEquals(
                    symbol,
                    "output",
                    index,
                    Adapter.output_channels,
                )) return true;
            }
            return false;
        }

        fn writePresetUri(
            writer: *std.Io.Writer,
            slug: []const u8,
        ) !void {
            try writer.writeAll(plugin_uri);
            try writer.writeByte('#');
            try writer.writeAll(slug);
        }
    };
}

fn beginPort(writer: *std.Io.Writer, first: *bool) !void {
    try writer.writeAll(
        if (first.*) "    lv2:port [\n" else "    ] , [\n",
    );
    first.* = false;
}

fn writeIndexedPortStart(
    writer: *std.Io.Writer,
    index: usize,
    comptime prefix: []const u8,
    channel: usize,
    channel_count: usize,
) !void {
    try writer.print("        lv2:index {d} ;\n", .{index});
    try writer.writeAll("        lv2:symbol \"");
    try writer.writeAll(prefix);
    if (channel_count != 1)
        try writer.print("_{d}", .{channel + 1});
    try writer.writeAll("\" ;\n        lv2:name \"");
    try writer.writeByte(std.ascii.toUpper(prefix[0]));
    try writer.writeAll(prefix[1..]);
    if (channel_count != 1)
        try writer.print(" {d}", .{channel + 1});
    try writer.writeByte('"');
}

fn writeFixedIndexedPort(
    writer: *std.Io.Writer,
    index: usize,
    symbol: []const u8,
    name: []const u8,
) !void {
    try writer.print("        lv2:index {d} ;\n", .{index});
    try writer.writeAll("        lv2:symbol ");
    try writeTurtleString(writer, symbol);
    try writer.writeAll(" ;\n        lv2:name ");
    try writeTurtleString(writer, name);
}

fn writeTurtleString(writer: *std.Io.Writer, value: []const u8) !void {
    if (!validText(value)) return error.InvalidLv2MetadataText;
    try writer.writeByte('"');
    for (value) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(byte),
        }
    }
    try writer.writeByte('"');
}

fn audioSymbolEquals(
    symbol: []const u8,
    comptime prefix: []const u8,
    index: usize,
    channel_count: usize,
) bool {
    if (channel_count == 1)
        return std.mem.eql(u8, symbol, prefix);
    if (!std.mem.startsWith(u8, symbol, prefix ++ "_"))
        return false;
    const suffix = symbol[prefix.len + 1 ..];
    const channel = std.fmt.parseInt(usize, suffix, 10) catch
        return false;
    return channel == index + 1;
}

fn validUri(value: []const u8) bool {
    const colon = std.mem.indexOfScalar(u8, value, ':') orelse return false;
    if (colon == 0) return false;
    for (value) |byte| {
        if (byte <= 0x20 or byte >= 0x7f or
            byte == '<' or byte == '>' or byte == '"' or byte == '\\')
            return false;
    }
    return true;
}

fn validFileName(value: []const u8) bool {
    if (value.len == 0 or
        std.mem.eql(u8, value, ".") or
        std.mem.eql(u8, value, ".."))
        return false;
    for (value) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and
            byte != '.' and byte != '_' and byte != '-')
            return false;
    }
    return true;
}

fn validSymbol(value: []const u8) bool {
    if (value.len == 0 or
        (!std.ascii.isAlphabetic(value[0]) and value[0] != '_'))
        return false;
    for (value[1..]) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_')
            return false;
    }
    return true;
}

fn validSlug(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and
            byte != '_' and byte != '-')
            return false;
    }
    return true;
}

fn validText(value: []const u8) bool {
    if (value.len == 0 or !std.unicode.utf8ValidateSlice(value))
        return false;
    for (value) |byte| {
        if (byte < 0x20 and
            byte != '\n' and byte != '\r' and byte != '\t')
            return false;
    }
    return true;
}

test "LV2 metadata generator writes ports workers and presets" {
    const Probe = struct {
        pub const name = "Metadata \"Probe\"";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .stereo;
        pub const Params = struct {
            gain: parameters.FloatParam = .{
                .id = 0,
                .name = "Gain",
                .min = 0.0,
                .max = 2.0,
                .default = 1.0,
            },
        };
        pub fn process(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
        ) void {}
    };
    const Adapter = struct {
        pub const input_channels = 1;
        pub const output_channels = 2;
        pub const audio_output_port_start = 1;
        pub const event_input_port: ?usize = 3;
        pub const event_output_port: ?usize = null;
        pub const control_input_port_start = 4;
        pub const freewheeling_input_port: ?usize = 5;
        pub const latency_output_port = 6;
        pub const worker_enabled = true;
        pub const programs_enabled = true;
    };
    const Generated = Generator(
        Probe,
        Adapter,
        "https://example.test/metadata",
        .{},
    );
    const presets = [_]FactoryPreset{
        .{
            .slug = "unity",
            .label = "Unity",
            .values = &.{.{ .symbol = "gain", .value = 1.0 }},
        },
    };
    const metadata = Metadata{
        .class_uri = "http://lv2plug.in/ns/lv2core#AmplifierPlugin",
        .presets = &presets,
        .ui = .{
            .uri = "https://example.test/metadata#ui",
            .binary_name = "probe_ui.so",
            .class_uri = "http://lv2plug.in/ns/extensions/ui#X11UI",
        },
    };
    var bytes: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try Generated.writeManifest(&writer, "probe.so", metadata);
    const manifest = writer.buffered();
    try std.testing.expect(
        std.mem.indexOf(u8, manifest, "lv2:binary <probe.so>") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, manifest, "#unity") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, manifest, "lv2:binary <probe_ui.so>") != null,
    );

    writer = std.Io.Writer.fixed(&bytes);
    try Generated.writePlugin(&writer, metadata);
    const plugin = writer.buffered();
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "work:schedule") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "pgm:Interface") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "lv2:symbol \"output_2\"") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "doap:name \"Metadata \\\"Probe\\\"\"") !=
            null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "ui:ui <https://example.test/metadata#ui>") !=
            null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "ui:idleInterface") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "pgm:UIInterface") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "lv2:designation lv2:freeWheeling",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "lv2:portProperty lv2:toggled",
        ) != null,
    );

    writer = std.Io.Writer.fixed(&bytes);
    try Generated.writePresets(&writer, metadata);
    const preset_text = writer.buffered();
    try std.testing.expect(
        std.mem.indexOf(u8, preset_text, "pset:value 1") != null,
    );
}

test "LV2 metadata generator rejects malformed presets" {
    const Probe = struct {
        pub const name = "Metadata Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .mono;
        pub const Params = struct {
            gain: parameters.FloatParam = .{
                .id = 0,
                .name = "Gain",
                .min = 0.0,
                .max = 1.0,
                .default = 0.5,
            },
        };
        pub fn process(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
        ) void {}
    };
    const Adapter = struct {
        pub const input_channels = 1;
        pub const output_channels = 1;
        pub const audio_output_port_start = 1;
        pub const event_input_port: ?usize = null;
        pub const event_output_port: ?usize = null;
        pub const control_input_port_start = 2;
        pub const freewheeling_input_port: ?usize = null;
        pub const latency_output_port = 3;
        pub const worker_enabled = false;
    };
    const Generated = Generator(
        Probe,
        Adapter,
        "https://example.test/metadata",
        .{},
    );
    var bytes: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try std.testing.expectError(
        error.UnknownLv2PresetParameter,
        Generated.writePresets(&writer, .{
            .presets = &.{.{
                .slug = "bad",
                .label = "Bad",
                .values = &.{.{ .symbol = "missing", .value = 0.5 }},
            }},
        }),
    );
    writer = std.Io.Writer.fixed(&bytes);
    try std.testing.expectError(
        error.InvalidLv2PresetValue,
        Generated.writePresets(&writer, .{
            .presets = &.{.{
                .slug = "bad",
                .label = "Bad",
                .values = &.{.{ .symbol = "gain", .value = 2.0 }},
            }},
        }),
    );
    writer = std.Io.Writer.fixed(&bytes);
    try std.testing.expectError(
        error.InvalidLv2BinaryName,
        Generated.writeManifest(&writer, "../probe.so", .{}),
    );
    writer = std.Io.Writer.fixed(&bytes);
    try std.testing.expectError(
        error.InvalidLv2UiBinaryName,
        Generated.writePlugin(&writer, .{
            .ui = .{
                .uri = "https://example.test/metadata#ui",
                .binary_name = "../probe-ui.so",
                .class_uri = "http://lv2plug.in/ns/extensions/ui#X11UI",
            },
        }),
    );

    const CollisionProbe = struct {
        pub const name = "Collision Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .mono;
        pub const Params = struct {
            latency: parameters.FloatParam = .{
                .id = 0,
                .name = "Latency Control",
                .min = 0.0,
                .max = 1.0,
                .default = 0.5,
            },
        };
        pub fn process(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
        ) void {}
    };
    const CollisionGenerated = Generator(
        CollisionProbe,
        Adapter,
        "https://example.test/collision",
        .{},
    );
    writer = std.Io.Writer.fixed(&bytes);
    try std.testing.expectError(
        error.DuplicateLv2PortSymbol,
        CollisionGenerated.writePlugin(&writer, .{}),
    );
    try std.testing.expectEqual(@as(usize, 0), writer.buffered().len);
}
