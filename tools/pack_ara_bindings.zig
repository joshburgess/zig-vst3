const std = @import("std");

const maximum_input_bytes = 4 * 1024 * 1024;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return error.InvalidArguments;

    const source = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[1],
        init.arena.allocator(),
        .limited(maximum_input_bytes),
    );
    var output = try std.Io.Dir.cwd().createFile(init.io, args[2], .{});
    defer output.close(init.io);

    var buffer: [64 * 1024]u8 = undefined;
    var file_writer = output.writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};

    var container_depth: usize = 0;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (container_depth == 0 and
            (std.mem.indexOf(u8, line, "= extern struct {") != null or
                std.mem.indexOf(u8, line, "= extern union {") != null))
        {
            container_depth = 1;
            try writer.print("{s}\n", .{line});
            continue;
        }

        if (container_depth > 0 and isField(line)) {
            const default_offset = std.mem.indexOf(u8, line, " = ").?;
            try writer.print(
                "{s} align(1){s}\n",
                .{ line[0..default_offset], line[default_offset..] },
            );
        } else {
            try writer.print("{s}\n", .{line});
        }

        if (container_depth > 0) {
            container_depth += std.mem.count(u8, line, "{");
            const closing_count = std.mem.count(u8, line, "}");
            if (closing_count > container_depth) return error.InvalidGeneratedSource;
            container_depth -= closing_count;
        }
    }
    if (container_depth != 0) return error.InvalidGeneratedSource;
    try writer.flush();
}

fn isField(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "    ") and
        std.mem.indexOf(u8, line, ": ") != null and
        std.mem.indexOf(u8, line, " = ") != null;
}

test "field detection excludes declarations and container endings" {
    try std.testing.expect(isField("    structSize: c_int = 0,"));
    try std.testing.expect(!isField("pub const Value = extern struct {"));
    try std.testing.expect(!isField("};"));
}
