const std = @import("std");
const aiff_writer = @import("aiff_writer.zig");
const file_writer_io = @import("file_writer_io.zig");
const pcm_dither = @import("pcm_dither.zig");
const rf64_writer = @import("rf64_writer.zig");
const wav_writer = @import("wav_writer.zig");
const wave64_writer = @import("wave64_writer.zig");

const Faults = struct {
    delegate: file_writer_io.Operations = .{},
    write_calls: usize = 0,
    set_length_calls: usize = 0,
    fail_write_call: ?usize = null,
    fail_set_length_call: ?usize = null,
    partial_write_bytes: usize = 0,
    maximum_write_bytes: usize = 0,

    fn operations(self: *Faults) file_writer_io.Operations {
        return .{
            .context = self,
            .vtable = &vtable,
        };
    }

    fn clear(self: *Faults) void {
        self.fail_write_call = null;
        self.fail_set_length_call = null;
        self.partial_write_bytes = 0;
    }

    fn writeAt(
        context: ?*anyopaque,
        io: std.Io,
        file: std.Io.File,
        offset: u64,
        bytes: []const u8,
    ) !usize {
        const self: *Faults = @ptrCast(@alignCast(
            context orelse return error.MissingFaultContext,
        ));
        self.write_calls += 1;
        if (self.fail_write_call == self.write_calls) {
            const partial = @min(self.partial_write_bytes, bytes.len);
            if (partial != 0)
                try self.delegate.writeAt(
                    io,
                    file,
                    offset,
                    bytes[0..partial],
                );
            return error.InjectedFileWriteFailure;
        }
        const count = if (self.maximum_write_bytes == 0)
            bytes.len
        else
            @min(self.maximum_write_bytes, bytes.len);
        try self.delegate.writeAt(io, file, offset, bytes[0..count]);
        return count;
    }

    fn setLength(
        context: ?*anyopaque,
        io: std.Io,
        file: std.Io.File,
        length: u64,
    ) !void {
        const self: *Faults = @ptrCast(@alignCast(
            context orelse return error.MissingFaultContext,
        ));
        self.set_length_calls += 1;
        if (self.fail_set_length_call == self.set_length_calls)
            return error.InjectedFileTruncateFailure;
        try self.delegate.setLength(io, file, length);
    }

    const vtable = file_writer_io.Operations.VTable{
        .write_at = writeAt,
        .set_length = setLength,
    };
};

fn exerciseFaultContract(
    comptime Writer: type,
    comptime file_name: []const u8,
    spec: anytype,
    initial_bytes: u64,
) !void {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    {
        var file = try temporary.dir.createFile(
            std.testing.io,
            file_name ++ "-init",
            .{ .read = true },
        );
        defer file.close(std.testing.io);
        var faults = Faults{ .fail_write_call = 1 };
        try std.testing.expectError(
            error.InjectedFileWriteFailure,
            Writer.initWithOperations(
                std.testing.io,
                file,
                spec,
                faults.operations(),
            ),
        );
        try std.testing.expectEqual(
            initial_bytes,
            try file.length(std.testing.io),
        );
    }

    var file = try temporary.dir.createFile(
        std.testing.io,
        file_name,
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var faults = Faults{};
    var writer = try Writer.initWithOperations(
        std.testing.io,
        file,
        spec,
        faults.operations(),
    );
    const dither_config = pcm_dither.Config{
        .channel_count = 1,
        .bits_per_sample = 16,
        .mode = .noise_shaped,
        .seed = 0x1234,
    };

    var dither = try pcm_dither.PcmDither.init(dither_config);
    const original_dither = dither;
    faults.fail_write_call = faults.write_calls + 1;
    faults.partial_write_bytes = 1;
    try std.testing.expectError(
        error.InjectedFileWriteFailure,
        writer.appendDithered(f32, &.{0.25}, &dither),
    );
    try std.testing.expectEqualDeep(original_dither, dither);
    try std.testing.expect(writer.valid());
    try std.testing.expectEqual(@as(u64, 0), writer.frames_written);
    try std.testing.expectEqual(
        initial_bytes,
        @as(u64, @intCast(writer.byte_count)),
    );
    try std.testing.expectEqual(
        initial_bytes,
        try file.length(std.testing.io),
    );

    faults.fail_write_call = faults.write_calls + 1;
    faults.fail_set_length_call = faults.set_length_calls + 1;
    faults.partial_write_bytes = 1;
    try std.testing.expectError(
        error.InjectedFileWriteFailure,
        writer.appendDithered(f32, &.{0.5}, &dither),
    );
    try std.testing.expectEqualDeep(original_dither, dither);
    try std.testing.expect(!writer.valid());
    try std.testing.expect(writer.recoverable());
    faults.clear();
    try writer.recover();
    try std.testing.expect(writer.valid());
    try std.testing.expectEqual(
        initial_bytes,
        try file.length(std.testing.io),
    );

    const committed_samples = [_]f32{ 0.125, -0.25, 0.375, -0.5 };
    faults.fail_write_call = faults.write_calls + 2;
    try std.testing.expectError(
        error.InjectedFileWriteFailure,
        writer.appendDithered(f32, &committed_samples, &dither),
    );
    try std.testing.expect(!std.meta.eql(original_dither, dither));
    try std.testing.expect(!writer.valid());
    try std.testing.expect(writer.recoverable());
    try std.testing.expectEqual(@as(u64, 4), writer.frames_written);
    try std.testing.expectEqual(
        initial_bytes + 8,
        @as(u64, @intCast(writer.byte_count)),
    );
    try std.testing.expectEqual(
        initial_bytes + 8,
        try file.length(std.testing.io),
    );
    faults.clear();
    try writer.recover();
    try std.testing.expect(writer.valid());

    faults.fail_set_length_call = faults.set_length_calls + 1;
    try std.testing.expectError(
        error.InjectedFileTruncateFailure,
        writer.recover(),
    );
    try std.testing.expect(!writer.valid());
    try std.testing.expect(writer.recoverable());
    faults.clear();
    try writer.recover();
    try std.testing.expect(writer.valid());

    const previous_byte_count: u64 = @intCast(writer.byte_count);
    const previous_write_calls = faults.write_calls;
    faults.maximum_write_bytes = 1;
    try writer.append(f32, &.{0.25});
    try std.testing.expect(writer.valid());
    try std.testing.expect(
        faults.write_calls >= previous_write_calls + 2,
    );
    try std.testing.expect(
        @as(u64, @intCast(writer.byte_count)) >
            previous_byte_count,
    );
    try std.testing.expectEqual(
        @as(u64, @intCast(writer.byte_count)),
        try file.length(std.testing.io),
    );
}

fn exercisePaddingRollback(
    comptime Writer: type,
    comptime file_name: []const u8,
    spec: anytype,
    padding_bytes: usize,
) !void {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        file_name,
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var faults = Faults{};
    var writer = try Writer.initWithOperations(
        std.testing.io,
        file,
        spec,
        faults.operations(),
    );
    try writer.append(f32, &.{0.25});
    const committed_bytes: u64 = @intCast(writer.byte_count);
    const padding_offset: u64 = @intCast(
        writer.data_offset + writer.data_bytes,
    );

    faults.fail_write_call = faults.write_calls + 1;
    faults.partial_write_bytes = 1;
    try std.testing.expectError(
        error.InjectedFileWriteFailure,
        writer.append(f32, &.{0.5}),
    );
    try std.testing.expect(writer.valid());
    try std.testing.expectEqual(@as(u64, 1), writer.frames_written);
    try std.testing.expectEqual(
        committed_bytes,
        @as(u64, @intCast(writer.byte_count)),
    );

    var padding: [7]u8 = undefined;
    const zeros: [7]u8 = @splat(0);
    try std.testing.expectEqual(
        padding_bytes,
        try file.readPositionalAll(
            std.testing.io,
            padding[0..padding_bytes],
            padding_offset,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        zeros[0..padding_bytes],
        padding[0..padding_bytes],
    );
}

test "file-backed PCM writers contain positional I/O failures" {
    try exerciseFaultContract(
        wav_writer.FileWriter,
        "faults.wav",
        wav_writer.Spec{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
        44,
    );
    try exerciseFaultContract(
        aiff_writer.FileWriter,
        "faults.aiff",
        aiff_writer.Spec{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
        54,
    );
    try exerciseFaultContract(
        rf64_writer.FileWriter,
        "faults.rf64",
        rf64_writer.Spec{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
        80,
    );
    try exerciseFaultContract(
        wave64_writer.FileWriter,
        "faults.w64",
        wave64_writer.Spec{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
        104,
    );
}

test "failed PCM appends restore existing container padding" {
    try exercisePaddingRollback(
        wav_writer.FileWriter,
        "padding.wav",
        wav_writer.Spec{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i24,
        },
        1,
    );
    try exercisePaddingRollback(
        aiff_writer.FileWriter,
        "padding.aiff",
        aiff_writer.Spec{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i24,
        },
        1,
    );
    try exercisePaddingRollback(
        rf64_writer.FileWriter,
        "padding.rf64",
        rf64_writer.Spec{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i24,
        },
        1,
    );
    try exercisePaddingRollback(
        wave64_writer.FileWriter,
        "padding.w64",
        wave64_writer.Spec{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
        6,
    );
}
