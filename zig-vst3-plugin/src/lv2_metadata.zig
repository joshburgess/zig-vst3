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

pub const MaintainerMetadata = struct {
    name: []const u8,
    email_uri: []const u8,
    homepage_uri: []const u8,
};

pub const ProjectMetadata = struct {
    uri: []const u8,
    name: []const u8,
    license_uri: []const u8,
    maintainer: MaintainerMetadata,
};

pub const Metadata = struct {
    class_uri: []const u8 = "http://lv2plug.in/ns/lv2core#Plugin",
    minor_version: u32 = 0,
    micro_version: u32 = 1,
    description: ?[]const u8 = null,
    short_description: ?[]const u8 = null,
    is_live: bool = false,
    project: ?ProjectMetadata = null,
    presets: []const FactoryPreset = &.{},
    ui: ?UiMetadata = null,
};

const AudioDirection = enum {
    input,
    output,
};

const AudioPortLocation = struct {
    direction: AudioDirection,
    bus_index: usize,
    channel_index: usize,
    layout: plugin_api.AudioBusLayout,
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
    const has_portable_state_paths =
        @hasDecl(Adapter, "portable_state_paths_enabled") and
        Adapter.portable_state_paths_enabled;
    const requires_state_make_path =
        @hasDecl(Adapter, "state_make_path_required") and
        Adapter.state_make_path_required;
    const requires_urid_unmap =
        @hasDecl(Adapter, "urid_unmap_required") and
        Adapter.urid_unmap_required;
    const has_port_resize =
        @hasDecl(Adapter, "port_resize_enabled") and
        Adapter.port_resize_enabled;
    const has_patch =
        @hasDecl(Adapter, "patch_enabled") and Adapter.patch_enabled;
    const has_readable_patch =
        @hasDecl(Adapter, "patch_readable") and Adapter.patch_readable;
    const has_writable_patch =
        @hasDecl(Adapter, "patch_writable") and Adapter.patch_writable;
    const projects_dynamic_audio_topology =
        @hasDecl(Adapter, "dynamic_audio_topology_projected") and
        Adapter.dynamic_audio_topology_projected;
    const Spec = plugin_api.PluginSpec(Plugin);

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
                    "@prefix foaf: <http://xmlns.com/foaf/0.1/> .\n" ++
                    "@prefix lv2:  <http://lv2plug.in/ns/lv2core#> .\n" ++
                    "@prefix midi: <http://lv2plug.in/ns/ext/midi#> .\n" ++
                    "@prefix opts: <http://lv2plug.in/ns/ext/options#> .\n" ++
                    "@prefix patch: <http://lv2plug.in/ns/ext/patch#> .\n" ++
                    "@prefix pgm:  <http://kxstudio.sf.net/ns/lv2ext/programs#> .\n" ++
                    "@prefix pg:   <http://lv2plug.in/ns/ext/port-groups#> .\n" ++
                    "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .\n" ++
                    "@prefix rsz:  <http://lv2plug.in/ns/ext/resize-port#> .\n" ++
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
            if (metadata.description) |description| {
                try writer.writeAll(" ;\n    doap:description ");
                try writeTurtleString(writer, description);
            }
            if (metadata.short_description) |short_description| {
                try writer.writeAll(" ;\n    doap:shortdesc ");
                try writeTurtleString(writer, short_description);
            }
            if (metadata.project) |project| {
                try writer.writeAll(" ;\n    lv2:project <");
                try writer.writeAll(project.uri);
                try writer.writeByte('>');
            }
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
            if (metadata.is_live)
                try writer.writeAll(" , lv2:isLive");
            if (Adapter.worker_enabled)
                try writer.writeAll(" , work:schedule");
            if (has_port_resize)
                try writer.writeAll(" , rsz:resize");
            try writer.writeAll(
                " ;\n    lv2:requiredFeature urid:map",
            );
            if (requires_urid_unmap)
                try writer.writeAll(" , urid:unmap");
            if (has_portable_state_paths)
                try writer.writeAll(" , state:mapPath , state:freePath");
            if (requires_state_make_path)
                try writer.writeAll(" , state:makePath");
            try writer.writeAll(
                " ;\n    lv2:extensionData opts:interface , state:interface",
            );
            if (Adapter.worker_enabled)
                try writer.writeAll(" , work:interface");
            if (has_programs)
                try writer.writeAll(" , pgm:Interface");
            if (has_readable_patch) {
                try writer.writeAll(" ;\n    patch:readable ");
                try writePatchPropertyList(writer, true);
            }
            if (has_writable_patch) {
                try writer.writeAll(" ;\n    patch:writable ");
                try writePatchPropertyList(writer, false);
            }
            try writer.writeAll(
                " ;\n    opts:supportedOption bufsz:minBlockLength ,\n" ++
                    "                         bufsz:maxBlockLength ,\n" ++
                    "                         bufsz:nominalBlockLength",
            );
            if (Adapter.event_input_port != null or
                Adapter.event_output_port != null)
                try writer.writeAll(" ,\n                         bufsz:sequenceSize");
            try writer.writeAll(" ;\n");
            if (Spec.audio_input_layout.hasBus()) {
                try writer.writeAll("    pg:mainInput <");
                try writeGroupUri(writer, .input, 0);
                try writer.writeAll("> ;\n");
            }
            if (Spec.audio_output_layout.hasBus()) {
                try writer.writeAll("    pg:mainOutput <");
                try writeGroupUri(writer, .output, 0);
                try writer.writeAll("> ;\n");
            }
            try writePorts(writer);
            try writer.writeAll(" .\n");
            try writePortGroups(writer);
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
                        "    lv2:optionalFeature ui:idleInterface , ui:resize , ui:touch , opts:options , urid:map ;\n" ++
                        "    opts:supportedOption ui:scaleFactor ;\n" ++
                        "    lv2:extensionData ui:idleInterface , ui:resize , ui:showInterface , opts:interface",
                );
                if (has_programs)
                    try writer.writeAll(" , pgm:UIInterface");
                try writer.writeAll(" .\n");
            }
            if (metadata.project) |project| {
                try writer.writeAll("\n<");
                try writer.writeAll(project.uri);
                try writer.writeAll(
                    ">\n    a doap:Project ;\n    doap:name ",
                );
                try writeTurtleString(writer, project.name);
                try writer.writeAll(" ;\n    doap:license <");
                try writer.writeAll(project.license_uri);
                try writer.writeAll(
                    "> ;\n    doap:maintainer [\n" ++
                        "        a foaf:Person ;\n" ++
                        "        foaf:name ",
                );
                try writeTurtleString(writer, project.maintainer.name);
                try writer.writeAll(" ;\n        foaf:mbox <");
                try writer.writeAll(project.maintainer.email_uri);
                try writer.writeAll("> ;\n        foaf:homepage <");
                try writer.writeAll(project.maintainer.homepage_uri);
                try writer.writeAll(">\n    ] .\n");
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
                const location = audioPortLocation(.input, offset) orelse
                    return error.InvalidLv2AudioBusMetadata;
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
                try writeAudioPortGroup(writer, location);
            }
            for (0..Adapter.output_channels) |offset| {
                const location = audioPortLocation(.output, offset) orelse
                    return error.InvalidLv2AudioBusMetadata;
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
                try writeAudioPortGroup(writer, location);
            }
            if (Adapter.event_input_port) |index| {
                try beginPort(writer, &first);
                try writer.writeAll(
                    "        a lv2:InputPort , atom:AtomPort ;\n",
                );
                try writeFixedIndexedPort(
                    writer,
                    index,
                    if (has_patch) "events_input" else "midi_input",
                    if (has_patch) "Events Input" else "MIDI Input",
                );
                try writer.writeAll(
                    " ;\n        atom:bufferType atom:Sequence ;\n" ++
                        "        atom:supports midi:MidiEvent , time:Position",
                );
                if (has_patch) try writer.writeAll(" , patch:Message");
                try writer.writeByte('\n');
            }
            if (Adapter.event_output_port) |index| {
                try beginPort(writer, &first);
                try writer.writeAll(
                    "        a lv2:OutputPort , atom:AtomPort ;\n",
                );
                try writeFixedIndexedPort(
                    writer,
                    index,
                    if (has_patch) "events_output" else "midi_output",
                    if (has_patch) "Events Output" else "MIDI Output",
                );
                try writer.writeAll(
                    " ;\n        atom:bufferType atom:Sequence ;\n" ++
                        "        atom:supports midi:MidiEvent",
                );
                if (has_patch) try writer.writeAll(" , patch:Message");
                try writer.writeByte('\n');
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
            if (metadata.description) |description| {
                if (!validText(description))
                    return error.InvalidLv2MetadataText;
            }
            if (metadata.short_description) |short_description| {
                if (!validText(short_description))
                    return error.InvalidLv2MetadataText;
            }
            if (metadata.project) |project| {
                if (!validUri(project.uri) or
                    !validUri(project.license_uri) or
                    !validUri(project.maintainer.homepage_uri))
                    return error.InvalidLv2MetadataUri;
                if (!validMailtoUri(project.maintainer.email_uri))
                    return error.InvalidLv2MaintainerEmail;
                if (!validText(project.name) or
                    !validText(project.maintainer.name))
                    return error.InvalidLv2MetadataText;
            }
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
            if (comptime has_readable_patch or has_writable_patch) {
                inline for (Plugin.lv2_patch_properties, 0..) |property, index| {
                    if (!validUri(property.uri))
                        return error.InvalidLv2MetadataUri;
                    for (Plugin.lv2_patch_properties[0..index]) |previous| {
                        if (std.mem.eql(u8, previous.uri, property.uri))
                            return error.DuplicateLv2PatchProperty;
                    }
                }
            }
        }

        fn writePatchPropertyList(
            writer: *std.Io.Writer,
            readable: bool,
        ) !void {
            var first = true;
            for (Plugin.lv2_patch_properties) |property| {
                const included = if (readable)
                    property.readable
                else
                    property.writable;
                if (!included) continue;
                if (!first) try writer.writeAll(" , ");
                try writer.writeByte('<');
                try writer.writeAll(property.uri);
                try writer.writeByte('>');
                first = false;
            }
        }

        fn writeAudioPortGroup(
            writer: *std.Io.Writer,
            location: AudioPortLocation,
        ) !void {
            if (projects_dynamic_audio_topology and
                location.bus_index != 0)
                try writer.writeAll(
                    " ;\n        lv2:portProperty lv2:connectionOptional",
                );
            try writer.writeAll(" ;\n        pg:group <");
            try writeGroupUri(
                writer,
                location.direction,
                location.bus_index,
            );
            try writer.writeByte('>');
            if (channelDesignation(
                location.layout,
                location.channel_index,
            )) |designation| {
                try writer.writeAll(
                    " ;\n        lv2:designation pg:",
                );
                try writer.writeAll(designation);
            } else if (ambisonicOrder(location.layout) != null and
                location.channel_index < 16)
            {
                try writer.print(
                    " ;\n        lv2:designation pg:ACN{d}",
                    .{location.channel_index},
                );
            }
            try writer.writeByte('\n');
        }

        fn writePortGroups(writer: *std.Io.Writer) !void {
            if (Spec.audio_input_layout.hasBus())
                try writePortGroup(
                    writer,
                    .input,
                    0,
                    Spec.audio_input_layout,
                );
            for (
                Spec.audio_auxiliary_input_layouts,
                0..,
            ) |layout, index| {
                try writePortGroup(writer, .input, index + 1, layout);
            }
            if (Spec.audio_output_layout.hasBus())
                try writePortGroup(
                    writer,
                    .output,
                    0,
                    Spec.audio_output_layout,
                );
            for (
                Spec.audio_auxiliary_output_layouts,
                0..,
            ) |layout, index| {
                try writePortGroup(writer, .output, index + 1, layout);
            }
        }

        fn writePortGroup(
            writer: *std.Io.Writer,
            direction: AudioDirection,
            bus_index: usize,
            layout: plugin_api.AudioBusLayout,
        ) !void {
            try writer.writeAll("\n<");
            try writeGroupUri(writer, direction, bus_index);
            try writer.writeAll(">\n    a pg:");
            try writer.writeAll(switch (direction) {
                .input => "InputGroup",
                .output => "OutputGroup",
            });
            try writer.writeAll(" , pg:");
            try writer.writeAll(groupClass(layout));
            try writer.writeAll(" ;\n    lv2:symbol ");
            try writeGroupSymbol(writer, direction, bus_index);
            try writer.writeAll(" ;\n    rdfs:label ");
            try writeGroupLabel(writer, direction, bus_index);
            if (direction == .input and bus_index != 0 and
                Spec.audio_input_layout.hasBus())
            {
                try writer.writeAll(" ;\n    pg:sideChainOf <");
                try writeGroupUri(writer, .input, 0);
                try writer.writeByte('>');
            }
            if (direction == .output and bus_index == 0 and
                Spec.audio_input_layout.hasBus())
            {
                try writer.writeAll(" ;\n    pg:source <");
                try writeGroupUri(writer, .input, 0);
                try writer.writeByte('>');
            }
            try writer.writeAll(" .\n");
        }

        fn writeGroupUri(
            writer: *std.Io.Writer,
            direction: AudioDirection,
            bus_index: usize,
        ) !void {
            try writer.writeAll(plugin_uri);
            try writer.writeByte('#');
            try writeGroupSymbolBody(writer, direction, bus_index);
        }

        fn writeGroupSymbol(
            writer: *std.Io.Writer,
            direction: AudioDirection,
            bus_index: usize,
        ) !void {
            try writer.writeByte('"');
            try writeGroupSymbolBody(writer, direction, bus_index);
            try writer.writeByte('"');
        }

        fn writeGroupSymbolBody(
            writer: *std.Io.Writer,
            direction: AudioDirection,
            bus_index: usize,
        ) !void {
            if (bus_index == 0) {
                try writer.writeAll("main_");
            } else {
                try writer.print("aux_{d}_", .{bus_index});
            }
            try writer.writeAll(switch (direction) {
                .input => "input_group",
                .output => "output_group",
            });
        }

        fn writeGroupLabel(
            writer: *std.Io.Writer,
            direction: AudioDirection,
            bus_index: usize,
        ) !void {
            try writer.writeByte('"');
            if (bus_index == 0) {
                try writer.writeAll("Main ");
            } else {
                try writer.print("Auxiliary {d} ", .{bus_index});
            }
            try writer.writeAll(switch (direction) {
                .input => "Input",
                .output => "Output",
            });
            try writer.writeByte('"');
        }

        fn audioPortLocation(
            direction: AudioDirection,
            flattened_index: usize,
        ) ?AudioPortLocation {
            const main_layout = switch (direction) {
                .input => Spec.audio_input_layout,
                .output => Spec.audio_output_layout,
            };
            var remaining = flattened_index;
            if (main_layout.hasBus()) {
                const channels = main_layout.channelCount();
                if (remaining < channels)
                    return .{
                        .direction = direction,
                        .bus_index = 0,
                        .channel_index = remaining,
                        .layout = main_layout,
                    };
                remaining -= channels;
            }
            const auxiliary_layouts = switch (direction) {
                .input => Spec.audio_auxiliary_input_layouts,
                .output => Spec.audio_auxiliary_output_layouts,
            };
            for (auxiliary_layouts, 0..) |layout, index| {
                const channels = layout.channelCount();
                if (remaining < channels)
                    return .{
                        .direction = direction,
                        .bus_index = index + 1,
                        .channel_index = remaining,
                        .layout = layout,
                    };
                remaining -= channels;
            }
            return null;
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
            if (Adapter.freewheeling_input_port != null and
                std.mem.eql(u8, symbol, "freewheeling"))
                return true;
            if (Adapter.event_input_port != null and
                std.mem.eql(
                    u8,
                    symbol,
                    if (has_patch) "events_input" else "midi_input",
                ))
                return true;
            if (Adapter.event_output_port != null and
                std.mem.eql(
                    u8,
                    symbol,
                    if (has_patch) "events_output" else "midi_output",
                ))
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
            if (Spec.audio_input_layout.hasBus() and
                groupSymbolEquals(symbol, .input, 0))
                return true;
            for (
                Spec.audio_auxiliary_input_layouts,
                0..,
            ) |_, index| {
                if (groupSymbolEquals(symbol, .input, index + 1))
                    return true;
            }
            if (Spec.audio_output_layout.hasBus() and
                groupSymbolEquals(symbol, .output, 0))
                return true;
            for (
                Spec.audio_auxiliary_output_layouts,
                0..,
            ) |_, index| {
                if (groupSymbolEquals(symbol, .output, index + 1))
                    return true;
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

fn groupClass(layout: plugin_api.AudioBusLayout) []const u8 {
    return switch (layout) {
        .mono => "MonoGroup",
        .stereo => "StereoGroup",
        .surround_3_0 => "ThreePointZeroGroup",
        .surround_4_0_cine => "FourPointZeroGroup",
        .surround_5_0 => "FivePointZeroGroup",
        .surround_5_1 => "FivePointOneGroup",
        .surround_6_1_cine => "SixPointOneGroup",
        .surround_7_1 => "SevenPointOneGroup",
        .surround_7_1_sdds => "SevenPointOneWideGroup",
        .ambisonic_first_order => "AmbisonicBH1P1Group",
        .ambisonic_second_order => "AmbisonicBH2P2Group",
        .ambisonic_third_order => "AmbisonicBH3P3Group",
        .ambisonic_fourth_order,
        .ambisonic_fifth_order,
        .ambisonic_sixth_order,
        .ambisonic_seventh_order,
        => "AmbisonicGroup",
        .none,
        .quadraphonic,
        .surround_7_0,
        .surround_5_1_2,
        .surround_7_1_4,
        .stereo_wide,
        .stereo_surround,
        .stereo_center,
        .stereo_side,
        .surround_3_0_music,
        .surround_3_1,
        .surround_3_1_music,
        .surround_4_1,
        .surround_4_1_cine,
        .surround_6_0,
        .surround_6_0_cine,
        .surround_6_1,
        .surround_7_0_sdds,
        .surround_5_0_2,
        .surround_5_0_4,
        .surround_5_1_4,
        .surround_7_0_2,
        .surround_7_1_2,
        .surround_7_0_4,
        => "DiscreteGroup",
    };
}

fn ambisonicOrder(layout: plugin_api.AudioBusLayout) ?u8 {
    return switch (layout) {
        .ambisonic_first_order => 1,
        .ambisonic_second_order => 2,
        .ambisonic_third_order => 3,
        .ambisonic_fourth_order => 4,
        .ambisonic_fifth_order => 5,
        .ambisonic_sixth_order => 6,
        .ambisonic_seventh_order => 7,
        else => null,
    };
}

fn channelDesignation(
    layout: plugin_api.AudioBusLayout,
    channel_index: usize,
) ?[]const u8 {
    return switch (layout) {
        .mono => designationAt(&.{"center"}, channel_index),
        .stereo => designationAt(
            &.{ "left", "right" },
            channel_index,
        ),
        .stereo_surround => designationAt(
            &.{ "rearLeft", "rearRight" },
            channel_index,
        ),
        .stereo_center => designationAt(
            &.{ "centerLeft", "centerRight" },
            channel_index,
        ),
        .stereo_side => designationAt(
            &.{ "sideLeft", "sideRight" },
            channel_index,
        ),
        .surround_3_0 => designationAt(
            &.{ "left", "right", "center" },
            channel_index,
        ),
        .quadraphonic => designationAt(
            &.{ "left", "right", "rearLeft", "rearRight" },
            channel_index,
        ),
        .surround_4_0_cine => designationAt(
            &.{ "left", "right", "center", "rearCenter" },
            channel_index,
        ),
        .surround_5_0 => designationAt(
            &.{ "left", "right", "center", "rearLeft", "rearRight" },
            channel_index,
        ),
        .surround_5_1 => designationAt(
            &.{
                "left",
                "right",
                "center",
                "lowFrequencyEffects",
                "rearLeft",
                "rearRight",
            },
            channel_index,
        ),
        .surround_6_1_cine => designationAt(
            &.{
                "left",
                "right",
                "center",
                "lowFrequencyEffects",
                "rearLeft",
                "rearRight",
                "rearCenter",
            },
            channel_index,
        ),
        .surround_7_1 => designationAt(
            &.{
                "left",
                "right",
                "center",
                "lowFrequencyEffects",
                "rearLeft",
                "rearRight",
                "sideLeft",
                "sideRight",
            },
            channel_index,
        ),
        .surround_7_1_sdds => designationAt(
            &.{
                "left",
                "right",
                "center",
                "lowFrequencyEffects",
                "rearLeft",
                "rearRight",
                "centerLeft",
                "centerRight",
            },
            channel_index,
        ),
        else => null,
    };
}

fn designationAt(
    designations: []const []const u8,
    index: usize,
) ?[]const u8 {
    if (index >= designations.len) return null;
    return designations[index];
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

fn groupSymbolEquals(
    symbol: []const u8,
    direction: AudioDirection,
    bus_index: usize,
) bool {
    const suffix = switch (direction) {
        .input => "_input_group",
        .output => "_output_group",
    };
    if (bus_index == 0) {
        const prefix = "main";
        return symbol.len == prefix.len + suffix.len and
            std.mem.startsWith(u8, symbol, prefix) and
            std.mem.endsWith(u8, symbol, suffix);
    }
    const prefix = "aux_";
    if (!std.mem.startsWith(u8, symbol, prefix) or
        !std.mem.endsWith(u8, symbol, suffix) or
        symbol.len <= prefix.len + suffix.len)
        return false;
    const number = symbol[prefix.len .. symbol.len - suffix.len];
    const parsed = std.fmt.parseInt(usize, number, 10) catch
        return false;
    return parsed == bus_index;
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

fn validMailtoUri(value: []const u8) bool {
    const prefix = "mailto:";
    if (!std.mem.startsWith(u8, value, prefix) or
        value.len == prefix.len)
        return false;
    const address = value[prefix.len..];
    const at = std.mem.indexOfScalar(u8, address, '@') orelse return false;
    return at != 0 and at + 1 < address.len and validUri(value);
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

test "LV2 metadata publishes graph-only Patch event support" {
    const Probe = struct {
        pub const name = "Graph Patch Metadata Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .mono;
        pub const event_input = true;
        pub const event_output = true;
        pub const Params = struct {};

        pub fn process(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
        ) void {}
    };
    const Adapter = struct {
        pub const input_channels = 1;
        pub const output_channels = 1;
        pub const audio_output_port_start = 1;
        pub const event_input_port: ?usize = 2;
        pub const event_output_port: ?usize = 3;
        pub const control_input_port_start = 4;
        pub const freewheeling_input_port: ?usize = null;
        pub const latency_output_port = 4;
        pub const worker_enabled = false;
        pub const programs_enabled = false;
        pub const portable_state_paths_enabled = false;
        pub const state_make_path_required = false;
        pub const patch_enabled = true;
        pub const patch_readable = false;
        pub const patch_writable = false;
    };
    const Generated = Generator(
        Probe,
        Adapter,
        "https://example.test/graph-patch-metadata",
        .{},
    );
    var bytes: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try Generated.writePlugin(&writer, .{});
    const output = writer.buffered();
    try std.testing.expect(
        std.mem.count(u8, output, "patch:Message") == 2,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, output, "patch:readable") == null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, output, "patch:writable") == null,
    );
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
        const PatchMetadataProperty = struct {
            uri: []const u8,
            readable: bool,
            writable: bool,
        };
        pub const lv2_patch_properties = &[_]PatchMetadataProperty{
            .{
                .uri = "https://example.test/metadata#resource",
                .readable = true,
                .writable = true,
            },
        };
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
        pub const port_resize_enabled = true;
        pub const programs_enabled = true;
        pub const portable_state_paths_enabled = true;
        pub const state_make_path_required = true;
        pub const urid_unmap_required = true;
        pub const patch_enabled = true;
        pub const patch_readable = true;
        pub const patch_writable = true;
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
        .description = "A metadata generator probe.",
        .short_description = "Metadata probe",
        .is_live = true,
        .project = .{
            .uri = "https://example.test/project",
            .name = "Metadata Project",
            .license_uri = "https://example.test/license",
            .maintainer = .{
                .name = "Project Maintainer",
                .email_uri = "mailto:maintainer@example.test",
                .homepage_uri = "https://example.test/maintainer",
            },
        },
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
        std.mem.indexOf(u8, plugin, "rsz:resize") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "pgm:Interface") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "lv2:requiredFeature urid:map , urid:unmap",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "state:mapPath , state:freePath , state:makePath",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "patch:readable <https://example.test/metadata#resource>",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "patch:writable <https://example.test/metadata#resource>",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "atom:supports midi:MidiEvent , time:Position , patch:Message",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "bufsz:sequenceSize") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "lv2:symbol \"events_input\"") !=
            null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "lv2:symbol \"output_2\"") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "pg:mainInput <https://example.test/metadata#main_input_group>",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "pg:mainOutput <https://example.test/metadata#main_output_group>",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "a pg:OutputGroup , pg:StereoGroup",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "lv2:designation pg:right",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "doap:name \"Metadata \\\"Probe\\\"\"") !=
            null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "doap:description \"A metadata generator probe.\"",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "doap:shortdesc \"Metadata probe\"") !=
            null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "lv2:project <https://example.test/project>",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "lv2:optionalFeature lv2:hardRTCapable , opts:options , lv2:isLive",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "doap:license <https://example.test/license>",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "foaf:mbox <mailto:maintainer@example.test>",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "ui:ui <https://example.test/metadata#ui>") !=
            null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "lv2:optionalFeature ui:idleInterface , ui:resize , ui:touch , opts:options , urid:map",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "opts:supportedOption ui:scaleFactor",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "lv2:extensionData ui:idleInterface , ui:resize , ui:showInterface , opts:interface",
        ) != null,
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

test "LV2 metadata groups main sidechain and auxiliary audio buses" {
    const Probe = struct {
        pub const name = "Bus Metadata Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout =
            .stereo;
        pub const audio_output_layout: plugin_api.AudioBusLayout =
            .stereo;
        pub const audio_auxiliary_input_layouts =
            &[_]plugin_api.AudioBusLayout{.mono};
        pub const audio_auxiliary_output_layouts =
            &[_]plugin_api.AudioBusLayout{.mono};
        pub const Params = struct {};

        pub fn process(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
        ) void {}
    };
    const Adapter = struct {
        pub const input_channels = 3;
        pub const output_channels = 3;
        pub const audio_output_port_start = 3;
        pub const event_input_port: ?usize = null;
        pub const event_output_port: ?usize = null;
        pub const control_input_port_start = 6;
        pub const freewheeling_input_port: ?usize = null;
        pub const latency_output_port = 6;
        pub const worker_enabled = false;
        pub const programs_enabled = false;
        pub const portable_state_paths_enabled = false;
        pub const state_make_path_required = false;
        pub const patch_enabled = false;
        pub const patch_readable = false;
        pub const patch_writable = false;
    };
    const Generated = Generator(
        Probe,
        Adapter,
        "https://example.test/bus-metadata",
        .{},
    );

    var bytes: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try Generated.writePlugin(&writer, .{});
    const plugin = writer.buffered();

    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "bufsz:sequenceSize") == null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "pg:group <https://example.test/bus-metadata#aux_1_input_group>",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "pg:sideChainOf <https://example.test/bus-metadata#main_input_group>",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "pg:source <https://example.test/bus-metadata#main_input_group>",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "a pg:OutputGroup , pg:MonoGroup",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "lv2:symbol \"aux_1_output_group\"",
        ) != null,
    );
    try std.testing.expectEqualStrings(
        "AmbisonicBH3P3Group",
        groupClass(.ambisonic_third_order),
    );
    try std.testing.expectEqualStrings(
        "AmbisonicGroup",
        groupClass(.ambisonic_seventh_order),
    );
    try std.testing.expectEqual(
        @as(?[]const u8, null),
        channelDesignation(.surround_7_1_4, 8),
    );
}

test "LV2 metadata preserves high-channel dynamic bus projection" {
    const Probe = struct {
        const Topology = plugin_api.BoundedDynamicAudioBusTopology(1);

        pub const name = "High-Channel Bus Metadata Probe";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const maximum_auxiliary_audio_buses = 1;
        pub const audio_bus_topology = makeTopology();

        fn makeTopology() Topology {
            const main = plugin_api.DynamicAudioBus.fixed(
                .ambisonic_sixth_order,
                true,
            ) catch unreachable;
            const auxiliary = plugin_api.DynamicAudioBus.fixed(
                .surround_7_1_4,
                false,
            ) catch unreachable;
            var topology = Topology.init(main, main) catch unreachable;
            _ = topology.addAuxiliary(
                .input,
                auxiliary,
            ) catch unreachable;
            _ = topology.addAuxiliary(
                .output,
                auxiliary,
            ) catch unreachable;
            return topology;
        }

        pub fn process(
            _: *@This(),
            _: *process_api.BoundedProcessContext(
                f32,
                maximum_auxiliary_audio_buses,
            ),
        ) void {}
    };
    const Adapter = struct {
        pub const input_channels = 61;
        pub const output_channels = 61;
        pub const audio_output_port_start = 61;
        pub const event_input_port: ?usize = null;
        pub const event_output_port: ?usize = null;
        pub const control_input_port_start = 122;
        pub const freewheeling_input_port: ?usize = null;
        pub const latency_output_port = 122;
        pub const worker_enabled = false;
        pub const programs_enabled = false;
        pub const portable_state_paths_enabled = false;
        pub const state_make_path_required = false;
        pub const patch_enabled = false;
        pub const patch_readable = false;
        pub const patch_writable = false;
        pub const dynamic_audio_topology_projected = true;
    };
    const Generated = Generator(
        Probe,
        Adapter,
        "https://example.test/high-channel-bus-metadata",
        .{},
    );

    var bytes: [64 * 1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try Generated.writePlugin(&writer, .{});
    const plugin = writer.buffered();
    try std.testing.expectEqual(
        @as(usize, 24),
        std.mem.count(
            u8,
            plugin,
            "lv2:portProperty lv2:connectionOptional",
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        std.mem.count(u8, plugin, "lv2:designation pg:ACN15"),
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "a pg:InputGroup , pg:AmbisonicGroup",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            plugin,
            "a pg:OutputGroup , pg:DiscreteGroup",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "lv2:index 121") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, plugin, "lv2:index 122") != null,
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
    writer = std.Io.Writer.fixed(&bytes);
    try std.testing.expectError(
        error.InvalidLv2MaintainerEmail,
        Generated.writePlugin(&writer, .{
            .project = .{
                .uri = "https://example.test/project",
                .name = "Metadata Project",
                .license_uri = "https://example.test/license",
                .maintainer = .{
                    .name = "Project Maintainer",
                    .email_uri = "maintainer@example.test",
                    .homepage_uri = "https://example.test/maintainer",
                },
            },
        }),
    );
    writer = std.Io.Writer.fixed(&bytes);
    try std.testing.expectError(
        error.InvalidLv2MetadataUri,
        Generated.writePlugin(&writer, .{
            .project = .{
                .uri = "relative-project",
                .name = "Metadata Project",
                .license_uri = "https://example.test/license",
                .maintainer = .{
                    .name = "Project Maintainer",
                    .email_uri = "mailto:maintainer@example.test",
                    .homepage_uri = "https://example.test/maintainer",
                },
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

    const GroupCollisionProbe = struct {
        pub const name = "Group Collision Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin_api.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin_api.AudioBusLayout = .mono;
        pub const Params = struct {
            main_input_group: parameters.FloatParam = .{
                .id = 0,
                .name = "Group Collision",
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
    const GroupCollisionGenerated = Generator(
        GroupCollisionProbe,
        Adapter,
        "https://example.test/group-collision",
        .{},
    );
    writer = std.Io.Writer.fixed(&bytes);
    try std.testing.expectError(
        error.DuplicateLv2PortSymbol,
        GroupCollisionGenerated.writePlugin(&writer, .{}),
    );
    try std.testing.expectEqual(@as(usize, 0), writer.buffered().len);
}
