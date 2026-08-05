const std = @import("std");

const Source = struct {
    path: []const u8,
    text: []const u8,
};

const sources = [_]Source{
    .{ .path = "ara_playback_plugin.zig", .text = @embedFile("ara_playback_plugin.zig") },
    .{ .path = "aux_output_splitter_audio_unit.zig", .text = @embedFile("aux_output_splitter_audio_unit.zig") },
    .{ .path = "aux_output_splitter_core.zig", .text = @embedFile("aux_output_splitter_core.zig") },
    .{ .path = "c_kernel_core.zig", .text = @embedFile("c_kernel_core.zig") },
    .{ .path = "channel_strip_plugin.zig", .text = @embedFile("channel_strip_plugin.zig") },
    .{ .path = "event_echo_core.zig", .text = @embedFile("event_echo_core.zig") },
    .{ .path = "event_monitor_core.zig", .text = @embedFile("event_monitor_core.zig") },
    .{ .path = "fixed_rate_core.zig", .text = @embedFile("fixed_rate_core.zig") },
    .{ .path = "gain_core.zig", .text = @embedFile("gain_core.zig") },
    .{ .path = "ir_loader_plugin.zig", .text = @embedFile("ir_loader_plugin.zig") },
    .{ .path = "model_shell_core.zig", .text = @embedFile("model_shell_core.zig") },
    .{ .path = "mono_gain_audio_unit.zig", .text = @embedFile("mono_gain_audio_unit.zig") },
    .{ .path = "note_gate_core.zig", .text = @embedFile("note_gate_core.zig") },
    .{ .path = "parametric_eq_plugin.zig", .text = @embedFile("parametric_eq_plugin.zig") },
    .{ .path = "resonant_filter_plugin.zig", .text = @embedFile("resonant_filter_plugin.zig") },
    .{ .path = "resource_swap_core.zig", .text = @embedFile("resource_swap_core.zig") },
    .{ .path = "sample_player_plugin.zig", .text = @embedFile("sample_player_plugin.zig") },
    .{ .path = "sine_synth_core.zig", .text = @embedFile("sine_synth_core.zig") },
};

const Forbidden = struct {
    operation: []const u8,
    pattern: []const u8,
};

const forbidden = [_]Forbidden{
    .{ .operation = "allocation", .pattern = "std.heap" },
    .{ .operation = "allocation", .pattern = "page_allocator" },
    .{ .operation = "allocation", .pattern = ".alloc(" },
    .{ .operation = "allocation", .pattern = ".realloc(" },
    .{ .operation = "allocation", .pattern = ".dupe(" },
    .{ .operation = "allocation", .pattern = ".create(" },
    .{ .operation = "deallocation", .pattern = ".free(" },
    .{ .operation = "deallocation", .pattern = ".destroy(" },
    .{ .operation = "allocation", .pattern = "ArrayList" },
    .{ .operation = "lock", .pattern = ".lock(" },
    .{ .operation = "blocking wait", .pattern = ".wait(" },
    .{ .operation = "thread join", .pattern = ".join(" },
    .{ .operation = "thread operation", .pattern = "std.Thread" },
    .{ .operation = "sleep", .pattern = "std.time.sleep" },
    .{ .operation = "system call", .pattern = "std.posix" },
    .{ .operation = "file access", .pattern = "std.Io" },
    .{ .operation = "file access", .pattern = "openFile(" },
    .{ .operation = "file access", .pattern = "createFile(" },
    .{ .operation = "logging", .pattern = "std.log" },
    .{ .operation = "logging", .pattern = "std.debug" },
    .{ .operation = "host call", .pattern = ".vtable." },
    .{ .operation = "GUI call", .pattern = "vstgui" },
    .{ .operation = "GUI call", .pattern = "request_resize" },
};

const Callback = struct {
    name: []const u8,
    declaration: []const u8,
};

const callbacks = [_]Callback{
    .{ .name = "process", .declaration = "pub fn process(" },
    .{ .name = "process64", .declaration = "pub fn process64(" },
    .{ .name = "processBlock", .declaration = "fn processBlock(" },
    .{ .name = "processSample", .declaration = "fn processSample(" },
};

fn callbackBody(
    source: Source,
    declaration: usize,
) ![]const u8 {
    const body_start = std.mem.indexOfScalarPos(
        u8,
        source.text,
        declaration,
        '{',
    ) orelse return error.ProcessBodyMissing;
    var depth: usize = 0;
    for (source.text[body_start..], body_start..) |character, index| {
        switch (character) {
            '{' => depth += 1,
            '}' => {
                if (depth == 0) return error.ProcessBodyMissing;
                depth -= 1;
                if (depth == 0) return source.text[body_start .. index + 1];
            },
            else => {},
        }
    }
    return error.ProcessBodyMissing;
}

test "production GUI processors exclude forbidden realtime operations" {
    var audited_callbacks: usize = 0;
    for (sources) |source| {
        var primary_process_count: usize = 0;
        for (callbacks) |callback| {
            var cursor: usize = 0;
            while (std.mem.indexOfPos(
                u8,
                source.text,
                cursor,
                callback.declaration,
            )) |declaration| {
                const body = try callbackBody(source, declaration);
                audited_callbacks += 1;
                if (std.mem.eql(u8, callback.name, "process"))
                    primary_process_count += 1;
                for (forbidden) |rule| {
                    if (std.mem.indexOf(u8, body, rule.pattern) != null) {
                        std.debug.print(
                            "realtime source audit found {s} pattern '{s}' in {s} {s}\n",
                            .{
                                rule.operation,
                                rule.pattern,
                                source.path,
                                callback.name,
                            },
                        );
                        return error.ForbiddenRealtimeOperation;
                    }
                }
                cursor = @intFromPtr(body.ptr) -
                    @intFromPtr(source.text.ptr) + body.len;
            }
        }
        if (primary_process_count == 0) {
            std.debug.print(
                "realtime source audit could not find process body in {s}\n",
                .{source.path},
            );
            return error.ProcessBodyMissing;
        }
    }
    try std.testing.expect(audited_callbacks > sources.len);
}
