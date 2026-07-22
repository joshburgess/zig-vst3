const std = @import("std");

const Source = struct {
    path: []const u8,
    text: []const u8,
};

const sources = [_]Source{
    .{ .path = "channel_strip_plugin.zig", .text = @embedFile("channel_strip_plugin.zig") },
    .{ .path = "parametric_eq_plugin.zig", .text = @embedFile("parametric_eq_plugin.zig") },
    .{ .path = "resonant_filter_plugin.zig", .text = @embedFile("resonant_filter_plugin.zig") },
    .{ .path = "ir_loader_plugin.zig", .text = @embedFile("ir_loader_plugin.zig") },
    .{ .path = "sample_player_plugin.zig", .text = @embedFile("sample_player_plugin.zig") },
    .{ .path = "fixed_rate_core.zig", .text = @embedFile("fixed_rate_core.zig") },
};

const Forbidden = struct {
    operation: []const u8,
    pattern: []const u8,
};

const forbidden = [_]Forbidden{
    .{ .operation = "allocation", .pattern = "std.heap" },
    .{ .operation = "allocation", .pattern = "page_allocator" },
    .{ .operation = "allocation", .pattern = ".alloc(" },
    .{ .operation = "allocation", .pattern = ".create(" },
    .{ .operation = "lock", .pattern = ".lock(" },
    .{ .operation = "file access", .pattern = "std.Io" },
    .{ .operation = "file access", .pattern = "openFile(" },
    .{ .operation = "file access", .pattern = "createFile(" },
    .{ .operation = "logging", .pattern = "std.log" },
    .{ .operation = "logging", .pattern = "std.debug" },
    .{ .operation = "host call", .pattern = ".vtable." },
    .{ .operation = "GUI call", .pattern = "vstgui" },
    .{ .operation = "GUI call", .pattern = "request_resize" },
};

fn processBody(source: Source) ![]const u8 {
    const declaration = std.mem.indexOf(u8, source.text, "pub fn process(") orelse {
        std.debug.print("realtime source audit could not find process body in {s}\n", .{source.path});
        return error.ProcessBodyMissing;
    };
    const signature_end = std.mem.indexOfPos(u8, source.text, declaration, ") void {") orelse {
        std.debug.print("realtime source audit could not find process body start in {s}\n", .{source.path});
        return error.ProcessBodyMissing;
    };
    const body_start = std.mem.indexOfScalarPos(u8, source.text, signature_end, '{') orelse return error.ProcessBodyMissing;
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
    for (sources) |source| {
        const body = try processBody(source);
        for (forbidden) |rule| {
            if (std.mem.indexOf(u8, body, rule.pattern) != null) {
                std.debug.print("realtime source audit found {s} pattern '{s}' in {s}\n", .{
                    rule.operation, rule.pattern, source.path,
                });
                return error.ForbiddenRealtimeOperation;
            }
        }
    }
}
