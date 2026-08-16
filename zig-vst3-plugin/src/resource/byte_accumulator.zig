const std = @import("std");

pub const ByteAccumulator = struct {
    allocator: std.mem.Allocator,
    maximum_bytes: usize,
    interface: std.Io.Writer,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        maximum_bytes: usize,
    ) Self {
        return .{
            .allocator = allocator,
            .maximum_bytes = maximum_bytes,
            .interface = .{
                .buffer = &.{},
                .vtable = &writer_vtable,
            },
        };
    }

    pub fn initCapacity(
        allocator: std.mem.Allocator,
        maximum_bytes: usize,
        initial_capacity: usize,
    ) !Self {
        if (initial_capacity > maximum_bytes)
            return error.ByteAccumulatorLimitExceeded;
        var result = init(allocator, maximum_bytes);
        if (initial_capacity != 0) {
            result.interface.buffer =
                try allocator.alloc(u8, initial_capacity);
        }
        return result;
    }

    pub fn deinit(self: *Self) void {
        if (self.interface.buffer.len != 0)
            self.allocator.free(self.interface.buffer);
        self.interface.buffer = &.{};
        self.interface.end = 0;
        self.maximum_bytes = 0;
    }

    pub fn valid(self: *const Self) bool {
        return self.interface.vtable == &writer_vtable and
            self.interface.end <= self.interface.buffer.len and
            self.interface.buffer.len <= self.maximum_bytes;
    }

    pub fn bytes(self: *const Self) ![]const u8 {
        if (!self.valid()) return error.InvalidByteAccumulatorState;
        return self.interface.buffer[0..self.interface.end];
    }

    pub fn capacity(self: *const Self) !usize {
        if (!self.valid()) return error.InvalidByteAccumulatorState;
        return self.interface.buffer.len;
    }

    pub fn writer(self: *Self) !*std.Io.Writer {
        if (!self.valid()) return error.InvalidByteAccumulatorState;
        return &self.interface;
    }

    pub fn reserve(self: *Self, required_capacity: usize) !void {
        if (!self.valid()) return error.InvalidByteAccumulatorState;
        try self.ensureTotalCapacity(required_capacity);
    }

    pub fn append(self: *Self, source: []const u8) !void {
        if (!self.valid()) return error.InvalidByteAccumulatorState;
        if (slicesOverlap(source, self.interface.buffer))
            return error.AliasedByteAccumulatorInput;
        const next_length = std.math.add(
            usize,
            self.interface.end,
            source.len,
        ) catch return error.ByteAccumulatorLimitExceeded;
        try self.ensureTotalCapacity(next_length);
        @memcpy(
            self.interface.buffer[self.interface.end..next_length],
            source,
        );
        self.interface.end = next_length;
    }

    pub fn appendByte(self: *Self, byte: u8) !void {
        if (!self.valid()) return error.InvalidByteAccumulatorState;
        const next_length = std.math.add(
            usize,
            self.interface.end,
            1,
        ) catch return error.ByteAccumulatorLimitExceeded;
        try self.ensureTotalCapacity(next_length);
        self.interface.buffer[self.interface.end] = byte;
        self.interface.end = next_length;
    }

    pub fn resize(self: *Self, new_length: usize, fill: u8) !void {
        if (!self.valid()) return error.InvalidByteAccumulatorState;
        const previous_length = self.interface.end;
        try self.ensureTotalCapacity(new_length);
        if (new_length > previous_length)
            @memset(
                self.interface.buffer[previous_length..new_length],
                fill,
            );
        self.interface.end = new_length;
    }

    pub fn replaceRange(
        self: *Self,
        offset: usize,
        removed_length: usize,
        replacement: []const u8,
    ) !void {
        if (!self.valid()) return error.InvalidByteAccumulatorState;
        if (offset > self.interface.end or
            removed_length > self.interface.end - offset)
            return error.ByteAccumulatorRangeOutOfBounds;
        if (slicesOverlap(replacement, self.interface.buffer))
            return error.AliasedByteAccumulatorInput;
        const retained_length = self.interface.end - removed_length;
        const next_length = std.math.add(
            usize,
            retained_length,
            replacement.len,
        ) catch return error.ByteAccumulatorLimitExceeded;
        try self.ensureTotalCapacity(next_length);

        const tail_start = offset + removed_length;
        const destination_tail_start = offset + replacement.len;
        const tail_length = self.interface.end - tail_start;
        if (destination_tail_start > tail_start) {
            std.mem.copyBackwards(
                u8,
                self.interface.buffer[destination_tail_start .. destination_tail_start + tail_length],
                self.interface.buffer[tail_start..self.interface.end],
            );
        } else if (destination_tail_start < tail_start) {
            std.mem.copyForwards(
                u8,
                self.interface.buffer[destination_tail_start .. destination_tail_start + tail_length],
                self.interface.buffer[tail_start..self.interface.end],
            );
        }
        @memcpy(
            self.interface.buffer[offset..][0..replacement.len],
            replacement,
        );
        self.interface.end = next_length;
    }

    pub fn clearRetainingCapacity(self: *Self) !void {
        if (!self.valid()) return error.InvalidByteAccumulatorState;
        self.interface.end = 0;
    }

    pub fn toOwnedSlice(self: *Self) ![]u8 {
        if (!self.valid()) return error.InvalidByteAccumulatorState;
        const storage = self.interface.buffer;
        const length = self.interface.end;
        if (length == 0) {
            if (storage.len != 0) self.allocator.free(storage);
            self.interface.buffer = &.{};
            self.interface.end = 0;
            return &.{};
        }
        const result = if (storage.len == length)
            storage
        else
            try self.allocator.realloc(storage, length);
        self.interface.buffer = &.{};
        self.interface.end = 0;
        return result;
    }

    fn ensureTotalCapacity(self: *Self, required: usize) !void {
        if (required > self.maximum_bytes)
            return error.ByteAccumulatorLimitExceeded;
        if (required <= self.interface.buffer.len) return;
        const grown = std.ArrayList(u8).growCapacity(required);
        const next_capacity = @min(grown, self.maximum_bytes);
        if (self.interface.buffer.len == 0) {
            self.interface.buffer =
                try self.allocator.alloc(u8, next_capacity);
        } else {
            self.interface.buffer = try self.allocator.realloc(
                self.interface.buffer,
                next_capacity,
            );
        }
    }

    const writer_vtable: std.Io.Writer.VTable = .{
        .drain = drain,
        .flush = flush,
        .rebase = rebase,
    };

    fn drain(
        interface: *std.Io.Writer,
        data: []const []const u8,
        splat: usize,
    ) std.Io.Writer.Error!usize {
        const self: *Self = @fieldParentPtr("interface", interface);
        if (!self.valid()) return error.WriteFailed;
        const byte_count = checkedWriterByteCount(data, splat) catch
            return error.WriteFailed;
        const next_length = std.math.add(
            usize,
            interface.end,
            byte_count,
        ) catch return error.WriteFailed;
        self.ensureTotalCapacity(next_length) catch
            return error.WriteFailed;

        var cursor = interface.end;
        for (data[0 .. data.len - 1]) |segment| {
            @memcpy(interface.buffer[cursor..][0..segment.len], segment);
            cursor += segment.len;
        }
        const pattern = data[data.len - 1];
        for (0..splat) |_| {
            @memcpy(
                interface.buffer[cursor..][0..pattern.len],
                pattern,
            );
            cursor += pattern.len;
        }
        interface.end = cursor;
        return byte_count;
    }

    fn flush(_: *std.Io.Writer) std.Io.Writer.Error!void {}

    fn rebase(
        interface: *std.Io.Writer,
        _: usize,
        minimum_length: usize,
    ) std.Io.Writer.Error!void {
        const self: *Self = @fieldParentPtr("interface", interface);
        if (!self.valid()) return error.WriteFailed;
        const required = std.math.add(
            usize,
            interface.end,
            minimum_length,
        ) catch return error.WriteFailed;
        self.ensureTotalCapacity(required) catch
            return error.WriteFailed;
    }
};

fn checkedWriterByteCount(
    data: []const []const u8,
    splat: usize,
) !usize {
    if (data.len == 0) return error.InvalidWriterInput;
    var total: usize = 0;
    for (data[0 .. data.len - 1]) |segment| {
        total = std.math.add(usize, total, segment.len) catch
            return error.WriterByteCountOverflow;
    }
    const repeated = std.math.mul(
        usize,
        data[data.len - 1].len,
        splat,
    ) catch return error.WriterByteCountOverflow;
    return std.math.add(usize, total, repeated) catch
        return error.WriterByteCountOverflow;
}

fn slicesOverlap(left: []const u8, right: []const u8) bool {
    if (left.len == 0 or right.len == 0) return false;
    const left_start = @intFromPtr(left.ptr);
    const right_start = @intFromPtr(right.ptr);
    const left_end = std.math.add(usize, left_start, left.len) catch
        return true;
    const right_end = std.math.add(usize, right_start, right.len) catch
        return true;
    return left_start < right_end and right_start < left_end;
}

test "byte accumulator grows through direct and writer APIs" {
    var accumulator = try ByteAccumulator.initCapacity(
        std.testing.allocator,
        64,
        2,
    );
    defer accumulator.deinit();

    try accumulator.append("ab");
    try accumulator.appendByte('c');
    const output = try accumulator.writer();
    try output.writeAll("def");
    try output.writeInt(u16, 0x1234, .little);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 'a', 'b', 'c', 'd', 'e', 'f', 0x34, 0x12 },
        try accumulator.bytes(),
    );
    try std.testing.expect((try accumulator.capacity()) >= 8);
}

test "byte accumulator writer reserves after its retained prefix" {
    var accumulator = try ByteAccumulator.initCapacity(
        std.testing.allocator,
        32,
        4,
    );
    defer accumulator.deinit();
    try accumulator.append("abcd");

    const output = try accumulator.writer();
    const reserved = try output.writableSlice(8);
    @memcpy(reserved, "efghijkl");
    try std.testing.expectEqualStrings(
        "abcdefghijkl",
        try accumulator.bytes(),
    );
}

test "byte accumulator enforces its limit transactionally" {
    var accumulator = try ByteAccumulator.initCapacity(
        std.testing.allocator,
        5,
        2,
    );
    defer accumulator.deinit();
    try accumulator.append("abcd");

    try std.testing.expectError(
        error.ByteAccumulatorLimitExceeded,
        accumulator.append("ef"),
    );
    try std.testing.expectEqualStrings("abcd", try accumulator.bytes());
    const output = try accumulator.writer();
    try std.testing.expectError(
        error.WriteFailed,
        output.writeAll("ef"),
    );
    try std.testing.expectEqualStrings("abcd", try accumulator.bytes());
}

test "byte accumulator resizes clears and transfers ownership" {
    var accumulator = ByteAccumulator.init(std.testing.allocator, 16);
    defer accumulator.deinit();
    try accumulator.append("ab");
    try accumulator.resize(5, 0x7f);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 'a', 'b', 0x7f, 0x7f, 0x7f },
        try accumulator.bytes(),
    );
    try accumulator.resize(3, 0);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 'a', 'b', 0x7f },
        try accumulator.bytes(),
    );
    const owned = try accumulator.toOwnedSlice();
    defer std.testing.allocator.free(owned);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 'a', 'b', 0x7f },
        owned,
    );
    try std.testing.expectEqual(@as(usize, 0), (try accumulator.bytes()).len);
    try accumulator.append("reused");
    try accumulator.clearRetainingCapacity();
    try std.testing.expectEqual(@as(usize, 0), (try accumulator.bytes()).len);
}

test "byte accumulator replaces inserts and removes ranges" {
    var accumulator = ByteAccumulator.init(std.testing.allocator, 16);
    defer accumulator.deinit();
    try accumulator.append("abcdef");
    try accumulator.replaceRange(2, 2, "WXYZ");
    try std.testing.expectEqualStrings(
        "abWXYZef",
        try accumulator.bytes(),
    );
    try accumulator.replaceRange(2, 4, "q");
    try std.testing.expectEqualStrings("abqef", try accumulator.bytes());
    try accumulator.replaceRange(2, 1, "");
    try std.testing.expectEqualStrings("abef", try accumulator.bytes());

    try std.testing.expectError(
        error.ByteAccumulatorRangeOutOfBounds,
        accumulator.replaceRange(5, 0, "x"),
    );
    try std.testing.expectError(
        error.ByteAccumulatorLimitExceeded,
        accumulator.replaceRange(2, 0, "0123456789abcdef"),
    );
    try std.testing.expectEqualStrings("abef", try accumulator.bytes());
}

test "byte accumulator rejects aliases and hostile state" {
    var accumulator = ByteAccumulator.init(std.testing.allocator, 16);
    defer accumulator.deinit();
    try accumulator.append("abcd");
    try std.testing.expectError(
        error.AliasedByteAccumulatorInput,
        accumulator.append((try accumulator.bytes())[1..3]),
    );
    try std.testing.expectEqualStrings("abcd", try accumulator.bytes());

    accumulator.interface.end = accumulator.interface.buffer.len + 1;
    try std.testing.expectError(
        error.InvalidByteAccumulatorState,
        accumulator.appendByte(0),
    );
    accumulator.interface.end = 4;
}

test "byte accumulator preserves data after allocation failure" {
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 1 },
    );
    var accumulator = try ByteAccumulator.initCapacity(
        failing.allocator(),
        64,
        4,
    );
    defer accumulator.deinit();
    try accumulator.append("abcd");
    try std.testing.expectError(
        error.OutOfMemory,
        accumulator.append("efgh"),
    );
    try std.testing.expectEqualStrings("abcd", try accumulator.bytes());
}

test "byte accumulator writer contains hostile splat counts" {
    var accumulator = ByteAccumulator.init(std.testing.allocator, 16);
    defer accumulator.deinit();
    try accumulator.append("prefix");

    const output = try accumulator.writer();
    const repeated = [_][]const u8{"xx"};
    try std.testing.expectError(
        error.WriteFailed,
        ByteAccumulator.writer_vtable.drain(
            output,
            &repeated,
            std.math.maxInt(usize),
        ),
    );
    try std.testing.expectEqualStrings(
        "prefix",
        try accumulator.bytes(),
    );
}

test "byte accumulator operations match a bounded reference model" {
    const maximum_bytes = 64;
    var accumulator = ByteAccumulator.init(
        std.testing.allocator,
        maximum_bytes,
    );
    defer accumulator.deinit();
    var model: [maximum_bytes]u8 = undefined;
    var model_length: usize = 0;
    var random_state = std.Random.DefaultPrng.init(
        0x4259_5445_2D41_4343,
    );
    const random = random_state.random();

    for (0..1_000) |_| {
        switch (random.uintLessThan(u8, 6)) {
            0 => {
                var source: [8]u8 = undefined;
                random.bytes(&source);
                const length = random.uintLessThan(
                    usize,
                    source.len + 1,
                );
                if (model_length + length > maximum_bytes) {
                    try std.testing.expectError(
                        error.ByteAccumulatorLimitExceeded,
                        accumulator.append(source[0..length]),
                    );
                } else {
                    try accumulator.append(source[0..length]);
                    @memcpy(
                        model[model_length..][0..length],
                        source[0..length],
                    );
                    model_length += length;
                }
            },
            1 => {
                const next_length = random.uintLessThan(
                    usize,
                    maximum_bytes + 9,
                );
                const fill = random.int(u8);
                if (next_length > maximum_bytes) {
                    try std.testing.expectError(
                        error.ByteAccumulatorLimitExceeded,
                        accumulator.resize(next_length, fill),
                    );
                } else {
                    if (next_length > model_length)
                        @memset(model[model_length..next_length], fill);
                    model_length = next_length;
                    try accumulator.resize(next_length, fill);
                }
            },
            2 => {
                var replacement: [8]u8 = undefined;
                random.bytes(&replacement);
                const replacement_length = random.uintLessThan(
                    usize,
                    replacement.len + 1,
                );
                const offset = random.uintLessThan(
                    usize,
                    model_length + 1,
                );
                const removed_length = random.uintLessThan(
                    usize,
                    model_length - offset + 1,
                );
                const next_length =
                    model_length - removed_length + replacement_length;
                if (next_length > maximum_bytes) {
                    try std.testing.expectError(
                        error.ByteAccumulatorLimitExceeded,
                        accumulator.replaceRange(
                            offset,
                            removed_length,
                            replacement[0..replacement_length],
                        ),
                    );
                } else {
                    const tail_start = offset + removed_length;
                    const destination_tail = offset + replacement_length;
                    const tail_length = model_length - tail_start;
                    if (destination_tail > tail_start) {
                        std.mem.copyBackwards(
                            u8,
                            model[destination_tail..][0..tail_length],
                            model[tail_start..][0..tail_length],
                        );
                    } else {
                        std.mem.copyForwards(
                            u8,
                            model[destination_tail..][0..tail_length],
                            model[tail_start..][0..tail_length],
                        );
                    }
                    @memcpy(
                        model[offset..][0..replacement_length],
                        replacement[0..replacement_length],
                    );
                    model_length = next_length;
                    try accumulator.replaceRange(
                        offset,
                        removed_length,
                        replacement[0..replacement_length],
                    );
                }
            },
            3 => {
                try accumulator.clearRetainingCapacity();
                model_length = 0;
            },
            4 => {
                const requested = random.uintLessThan(
                    usize,
                    maximum_bytes + 9,
                );
                if (requested > maximum_bytes) {
                    try std.testing.expectError(
                        error.ByteAccumulatorLimitExceeded,
                        accumulator.reserve(requested),
                    );
                } else {
                    try accumulator.reserve(requested);
                }
            },
            5 => {
                const byte = random.int(u8);
                if (model_length == maximum_bytes) {
                    try std.testing.expectError(
                        error.ByteAccumulatorLimitExceeded,
                        accumulator.appendByte(byte),
                    );
                } else {
                    try accumulator.appendByte(byte);
                    model[model_length] = byte;
                    model_length += 1;
                }
            },
            else => unreachable,
        }
        try std.testing.expect(accumulator.valid());
        try std.testing.expectEqualSlices(
            u8,
            model[0..model_length],
            try accumulator.bytes(),
        );
    }
}
