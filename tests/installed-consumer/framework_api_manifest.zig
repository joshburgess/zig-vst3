const std = @import("std");
const plug = @import("zig-vst3-plugin");
const core = @import("zig-vst3-plugin-core");

pub const Classification = enum {
    compatibility_ready,
    experimental,
    mixed,
};

pub const Entry = struct {
    name: []const u8,
    classification: Classification,
};

pub const plugin_api = [_]Entry{
    .{ .name = "core", .classification = .mixed },
    .{ .name = "gui", .classification = .experimental },
    .{ .name = "editor_state", .classification = .experimental },
    .{ .name = "gui_preset_browser", .classification = .experimental },
    .{ .name = "gui_telemetry", .classification = .experimental },
    .{ .name = "gui_graph", .classification = .experimental },
    .{ .name = "gui_piano", .classification = .experimental },
    .{ .name = "gui_step_sequencer", .classification = .experimental },
    .{ .name = "gui_file_drop", .classification = .experimental },
    .{ .name = "gui_file_importer", .classification = .experimental },
    .{ .name = "gui_audio_file_importer", .classification = .experimental },
    .{ .name = "gui_audio_sample_store", .classification = .experimental },
    .{ .name = "gui_sample_player", .classification = .experimental },
    .{ .name = "gui_ir_convolution", .classification = .experimental },
    .{ .name = "gui_ir_editor", .classification = .experimental },
    .{ .name = "gui_progress", .classification = .experimental },
    .{ .name = "gui_range_selection", .classification = .experimental },
    .{ .name = "gui_viewport", .classification = .experimental },
    .{ .name = "parameters", .classification = .compatibility_ready },
    .{ .name = "realtime_audit", .classification = .compatibility_ready },
    .{ .name = "lv2", .classification = .experimental },
    .{ .name = "dsp", .classification = .compatibility_ready },
    .{ .name = "resource", .classification = .compatibility_ready },
    .{ .name = "plugin", .classification = .mixed },
    .{ .name = "process", .classification = .compatibility_ready },
    .{ .name = "state", .classification = .compatibility_ready },
    .{ .name = "units", .classification = .compatibility_ready },
    .{ .name = "version", .classification = .compatibility_ready },
    .{ .name = "HostRequestSink", .classification = .compatibility_ready },
    .{ .name = "HostChange", .classification = .compatibility_ready },
    .{ .name = "vst3_adapter", .classification = .compatibility_ready },
    .{ .name = "Vst3Processor", .classification = .compatibility_ready },
    .{ .name = "Vst3ProcessorWithParameters", .classification = .compatibility_ready },
    .{ .name = "Vst3Effect", .classification = .compatibility_ready },
    .{ .name = "Vst3EffectWithParameters", .classification = .compatibility_ready },
    .{ .name = "Vst3Controller", .classification = .compatibility_ready },
    .{ .name = "Vst3ControllerWithParameters", .classification = .compatibility_ready },
};

pub const core_api = [_]Entry{
    .{ .name = "parameters", .classification = .compatibility_ready },
    .{ .name = "realtime_audit", .classification = .compatibility_ready },
    .{ .name = "gui", .classification = .experimental },
    .{ .name = "audio_unit", .classification = .experimental },
    .{ .name = "audio_unit_v2", .classification = .experimental },
    .{ .name = "lv2", .classification = .experimental },
    .{ .name = "dsp", .classification = .compatibility_ready },
    .{ .name = "resource", .classification = .compatibility_ready },
    .{ .name = "editor_state", .classification = .experimental },
    .{ .name = "gui_preset_browser", .classification = .experimental },
    .{ .name = "gui_telemetry", .classification = .experimental },
    .{ .name = "gui_graph", .classification = .experimental },
    .{ .name = "gui_piano", .classification = .experimental },
    .{ .name = "gui_step_sequencer", .classification = .experimental },
    .{ .name = "gui_file_drop", .classification = .experimental },
    .{ .name = "gui_file_importer", .classification = .experimental },
    .{ .name = "gui_audio_file_importer", .classification = .experimental },
    .{ .name = "gui_audio_sample_store", .classification = .experimental },
    .{ .name = "gui_sample_player", .classification = .experimental },
    .{ .name = "gui_ir_convolution", .classification = .experimental },
    .{ .name = "gui_ir_editor", .classification = .experimental },
    .{ .name = "gui_progress", .classification = .experimental },
    .{ .name = "gui_range_selection", .classification = .experimental },
    .{ .name = "gui_viewport", .classification = .experimental },
    .{ .name = "plugin", .classification = .mixed },
    .{ .name = "process", .classification = .compatibility_ready },
    .{ .name = "state", .classification = .compatibility_ready },
    .{ .name = "units", .classification = .compatibility_ready },
};

pub fn manifestMatches(comptime namespace: type, comptime manifest: []const Entry) bool {
    const declarations = @typeInfo(namespace).@"struct".decls;
    if (declarations.len != manifest.len)
        return false;

    inline for (manifest, 0..) |entry, index| {
        if (entry.name.len == 0)
            return false;
        if (!@hasDecl(namespace, entry.name))
            return false;
        inline for (manifest[0..index]) |previous| {
            if (std.mem.eql(u8, entry.name, previous.name))
                return false;
        }
    }

    inline for (declarations) |declaration| {
        var found = false;
        inline for (manifest) |entry| {
            if (std.mem.eql(u8, declaration.name, entry.name))
                found = true;
        }
        if (!found)
            return false;
    }
    return true;
}

fn validateManifest(comptime namespace: type, comptime manifest: []const Entry) void {
    if (!manifestMatches(namespace, manifest))
        @compileError("installed public declarations do not match the reviewed API manifest");
}

test "installed framework module roots match the reviewed API manifest" {
    comptime {
        @setEvalBranchQuota(10_000);
        validateManifest(plug, &plugin_api);
        validateManifest(core, &core_api);
    }
}

test "API manifest rejects additions, removals, empty entries, and duplicates" {
    const Namespace = struct {
        pub const existing = 1;
        pub const unclassified = 2;
    };
    const complete = [_]Entry{
        .{ .name = "existing", .classification = .compatibility_ready },
        .{ .name = "unclassified", .classification = .experimental },
    };
    const missing = [_]Entry{
        .{ .name = "existing", .classification = .compatibility_ready },
    };
    const removed = [_]Entry{
        .{ .name = "existing", .classification = .compatibility_ready },
        .{ .name = "gone", .classification = .experimental },
    };
    const empty = [_]Entry{
        .{ .name = "existing", .classification = .compatibility_ready },
        .{ .name = "", .classification = .experimental },
    };
    const duplicate = [_]Entry{
        .{ .name = "existing", .classification = .compatibility_ready },
        .{ .name = "existing", .classification = .experimental },
    };
    try std.testing.expect(manifestMatches(Namespace, &complete));
    try std.testing.expect(!manifestMatches(Namespace, &missing));
    try std.testing.expect(!manifestMatches(Namespace, &removed));
    try std.testing.expect(!manifestMatches(Namespace, &empty));
    try std.testing.expect(!manifestMatches(Namespace, &duplicate));
}
