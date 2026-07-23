const std = @import("std");
const gui_file_drop = @import("gui_file_drop.zig");

pub const EntryPoint = enum {
    drop,
    picker,
};

pub const Command = enum {
    cancel,
    retry,
    reset,
};

pub const Status = enum {
    idle,
    validating,
    importing,
    ready,
    empty,
    unsupported_file,
    capacity_limit,
    invalid_path,
    cancelled,
    failed,
};

pub const Snapshot = struct {
    status: Status,
    entry_point: EntryPoint,
    path_count: usize,
    completed_units: usize,
    total_units: usize,
    generation: u64,
    cancellation_pending: bool,

    pub fn progress(self: Snapshot) f64 {
        if (self.total_units == 0) return 0.0;
        return @as(f64, @floatFromInt(self.completed_units)) /
            @as(f64, @floatFromInt(self.total_units));
    }

    pub fn validate(self: Snapshot) !void {
        if (self.path_count > gui_file_drop.maximum_files) return error.InvalidPathCount;
        if (self.completed_units > self.total_units) return error.InvalidImportProgress;
        if (self.cancellation_pending and !self.canCancel()) return error.InvalidCancellationState;
        switch (self.status) {
            .idle, .empty, .unsupported_file, .capacity_limit, .invalid_path => {
                if (self.completed_units != 0 or self.total_units != 0) return error.InvalidImportProgress;
            },
            .validating => {
                if (self.path_count == 0) return error.InvalidPathCount;
                if (self.completed_units != 0 or self.total_units != 0) return error.InvalidImportProgress;
            },
            .importing => {
                if (self.path_count == 0) return error.InvalidPathCount;
                if (self.total_units == 0) return error.InvalidImportProgress;
            },
            .ready => {
                if (self.path_count == 0) return error.InvalidPathCount;
                if (self.total_units == 0 or self.completed_units != self.total_units) return error.InvalidImportProgress;
            },
            .cancelled, .failed => {
                if (self.path_count == 0) return error.InvalidPathCount;
            },
        }
    }

    pub fn canCancel(self: Snapshot) bool {
        return self.status == .validating or self.status == .importing;
    }

    pub fn canRetry(self: Snapshot) bool {
        return self.path_count > 0 and (self.status == .cancelled or self.status == .failed);
    }
};

pub fn Model(comptime file_capacity: usize, comptime extension_capacity: usize) type {
    const DropZone = gui_file_drop.DropZone(file_capacity, extension_capacity);

    return struct {
        const Self = @This();

        zone: DropZone,
        entry_point: EntryPoint = .drop,
        status: Status = .idle,
        completed_units: usize = 0,
        total_units: usize = 0,
        generation: u64 = 0,
        cancel_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        pub fn init(extensions: []const []const u8) !Self {
            return .{ .zone = try DropZone.init(extensions) };
        }

        pub fn begin(self: *Self, entry_point: EntryPoint, paths: []const []const u8) Status {
            self.entry_point = entry_point;
            self.completed_units = 0;
            self.total_units = 0;
            self.cancel_requested.store(false, .release);
            self.generation +%= 1;

            if (paths.len == 0) {
                self.zone.reset();
                self.status = .empty;
                return self.status;
            }
            self.status = switch (self.zone.inspect(paths)) {
                .acceptable => .validating,
                .rejected_type => .unsupported_file,
                .rejected_count => .capacity_limit,
                .rejected_path => .invalid_path,
                else => .failed,
            };
            return self.status;
        }

        pub fn startImport(self: *Self, total_units: usize) !void {
            if (self.status != .validating or total_units == 0 or !self.validRetainedPaths()) {
                return error.InvalidImportTransition;
            }
            self.completed_units = 0;
            self.total_units = total_units;
            self.status = .importing;
        }

        pub fn advance(self: *Self, completed_units: usize) !void {
            if (self.status != .importing or completed_units < self.completed_units or completed_units > self.total_units) {
                return error.InvalidImportProgress;
            }
            self.completed_units = completed_units;
        }

        pub fn complete(self: *Self, preview_point_count: usize) !void {
            if (self.status != .importing or self.completed_units != self.total_units) {
                return error.InvalidImportTransition;
            }
            self.cancel_requested.store(false, .release);
            self.status = if (preview_point_count == 0) .empty else .ready;
        }

        pub fn fail(self: *Self) !void {
            try self.finishWith(.failed);
        }

        pub fn finishWith(self: *Self, status: Status) !void {
            if (self.status != .validating and self.status != .importing) return error.InvalidImportTransition;
            switch (status) {
                .empty, .unsupported_file, .capacity_limit, .invalid_path, .cancelled, .failed => {},
                else => return error.InvalidTerminalStatus,
            }
            self.cancel_requested.store(false, .release);
            self.status = status;
        }

        pub fn requestCancel(self: *Self) !void {
            if (self.status != .validating and self.status != .importing) return error.InvalidImportTransition;
            self.cancel_requested.store(true, .release);
        }

        pub fn cancellationRequested(self: *const Self) bool {
            return self.cancel_requested.load(.acquire);
        }

        pub fn acknowledgeCancel(self: *Self) !void {
            if (!self.cancellationRequested() or (self.status != .validating and self.status != .importing)) {
                return error.InvalidImportTransition;
            }
            self.cancel_requested.store(false, .release);
            self.status = .cancelled;
        }

        pub fn retry(self: *Self) !void {
            if (!self.validRetainedPaths() or (self.status != .cancelled and self.status != .failed)) {
                return error.InvalidImportTransition;
            }
            self.completed_units = 0;
            self.total_units = 0;
            self.cancel_requested.store(false, .release);
            self.generation +%= 1;
            self.status = .validating;
        }

        pub fn reset(self: *Self) void {
            self.zone.reset();
            self.completed_units = 0;
            self.total_units = 0;
            self.cancel_requested.store(false, .release);
            self.generation +%= 1;
            self.status = .idle;
        }

        pub fn snapshot(self: *const Self) Snapshot {
            return .{
                .status = self.status,
                .entry_point = self.entry_point,
                .path_count = self.zone.path_count,
                .completed_units = self.completed_units,
                .total_units = self.total_units,
                .generation = self.generation,
                .cancellation_pending = self.cancellationRequested(),
            };
        }

        pub fn path(self: *const Self, index: usize) ?[]const u8 {
            const path_count: usize = self.zone.path_count;
            if (path_count > file_capacity or index >= path_count or index >= file_capacity) return null;
            const value = self.zone.paths[index].slice();
            return if (value.len == 0) null else value;
        }

        fn validRetainedPaths(self: *const Self) bool {
            const path_count: usize = self.zone.path_count;
            if (path_count == 0 or path_count > file_capacity) return false;
            for (0..path_count) |index| {
                if (self.zone.paths[index].slice().len == 0) return false;
            }
            return true;
        }
    };
}

test "import model copies and validates drop and picker paths" {
    const Importer = Model(1, 1);
    var importer = try Importer.init(&.{".wav"});
    var caller = [_]u8{ '/', 't', 'm', 'p', '/', 'k', 'i', 'c', 'k', '.', 'W', 'A', 'V' };

    try std.testing.expectEqual(Status.validating, importer.begin(.drop, &.{&caller}));
    caller[5] = 'x';
    try std.testing.expectEqualStrings("/tmp/kick.WAV", importer.path(0).?);
    try std.testing.expectEqual(EntryPoint.drop, importer.snapshot().entry_point);

    try importer.startImport(100);
    try importer.advance(25);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), importer.snapshot().progress(), 0.0001);
    try importer.advance(100);
    try importer.complete(64);
    try std.testing.expectEqual(Status.ready, importer.snapshot().status);

    try std.testing.expectEqual(Status.validating, importer.begin(.picker, &.{"/tmp/snare.wav"}));
    try std.testing.expectEqual(EntryPoint.picker, importer.snapshot().entry_point);
}

test "import model reports bounded selection failures" {
    const Importer = Model(1, 1);
    var importer = try Importer.init(&.{".wav"});
    try std.testing.expectEqual(Status.empty, importer.begin(.picker, &.{}));
    try std.testing.expectEqual(Status.capacity_limit, importer.begin(.drop, &.{ "a.wav", "b.wav" }));
    try std.testing.expectEqual(Status.unsupported_file, importer.begin(.drop, &.{"a.aiff"}));
    const oversized = [_]u8{'a'} ** (gui_file_drop.maximum_path_bytes + 1);
    try std.testing.expectEqual(Status.invalid_path, importer.begin(.drop, &.{&oversized}));
}

test "import snapshot rejects impossible progress and cancellation" {
    const valid = Snapshot{
        .status = .importing,
        .entry_point = .picker,
        .path_count = 1,
        .completed_units = 4,
        .total_units = 8,
        .generation = 3,
        .cancellation_pending = true,
    };
    try valid.validate();

    var malformed = valid;
    malformed.completed_units = 9;
    try std.testing.expectError(error.InvalidImportProgress, malformed.validate());
    malformed = valid;
    malformed.status = .ready;
    malformed.cancellation_pending = false;
    try std.testing.expectError(error.InvalidImportProgress, malformed.validate());
    malformed = valid;
    malformed.status = .idle;
    malformed.completed_units = 0;
    malformed.total_units = 0;
    try std.testing.expectError(error.InvalidCancellationState, malformed.validate());
    malformed = valid;
    malformed.path_count = 0;
    try std.testing.expectError(error.InvalidPathCount, malformed.validate());
    malformed = valid;
    malformed.path_count = gui_file_drop.maximum_files + 1;
    try std.testing.expectError(error.InvalidPathCount, malformed.validate());
}

test "import model cancellation and retry preserve the copied job" {
    const Importer = Model(1, 1);
    var importer = try Importer.init(&.{".wav"});
    try std.testing.expectEqual(Status.validating, importer.begin(.picker, &.{"/tmp/room.wav"}));
    const first_generation = importer.snapshot().generation;
    try importer.startImport(8);
    try importer.advance(3);
    try importer.requestCancel();
    try std.testing.expect(importer.cancellationRequested());
    try importer.acknowledgeCancel();
    try std.testing.expect(!importer.snapshot().cancellation_pending);
    try std.testing.expect(importer.snapshot().canRetry());
    try importer.retry();
    try std.testing.expect(importer.snapshot().generation != first_generation);
    try std.testing.expectEqualStrings("/tmp/room.wav", importer.path(0).?);
    try std.testing.expect(!importer.cancellationRequested());
    try importer.fail();
    try importer.retry();
    try importer.startImport(1);
    try importer.advance(1);
    try importer.complete(0);
    try std.testing.expectEqual(Status.empty, importer.snapshot().status);
}

test "import model rejects invalid transitions without losing progress" {
    const Importer = Model(1, 1);
    var importer = try Importer.init(&.{".wav"});
    try std.testing.expectError(error.InvalidImportTransition, importer.startImport(1));
    _ = importer.begin(.drop, &.{"/tmp/room.wav"});
    try importer.startImport(4);
    try importer.advance(2);
    try std.testing.expectError(error.InvalidImportProgress, importer.advance(1));
    try std.testing.expectError(error.InvalidImportProgress, importer.advance(5));
    try std.testing.expectEqual(@as(usize, 2), importer.snapshot().completed_units);
    try std.testing.expectError(error.InvalidImportTransition, importer.complete(10));
    try std.testing.expectError(error.InvalidTerminalStatus, importer.finishWith(.ready));
    try importer.finishWith(.capacity_limit);
    try std.testing.expectEqual(Status.capacity_limit, importer.snapshot().status);
    importer.reset();
    try std.testing.expectEqual(Status.idle, importer.snapshot().status);
    try std.testing.expectEqual(@as(?[]const u8, null), importer.path(0));
}

test "import model generated transition sequences remain bounded" {
    const seed = 0x1a90_77e2_2026_0720;
    const Importer = Model(1, 2);
    var random_state = std.Random.DefaultPrng.init(seed);
    const random = random_state.random();

    for (0..256) |case_index| {
        var importer = try Importer.init(&.{ ".wav", ".aiff" });
        for (0..128) |operation_index| {
            switch (random.uintLessThan(u8, 10)) {
                0 => _ = importer.begin(.drop, &.{"/tmp/generated.wav"}),
                1 => _ = importer.begin(.picker, &.{"/tmp/generated.aiff"}),
                2 => _ = importer.begin(.picker, &.{}),
                3 => importer.startImport(1 + random.uintLessThan(usize, 64)) catch {},
                4 => importer.advance(random.uintLessThan(usize, 96)) catch {},
                5 => importer.complete(random.uintLessThan(usize, 8)) catch {},
                6 => importer.requestCancel() catch {},
                7 => importer.acknowledgeCancel() catch {},
                8 => importer.retry() catch {},
                else => importer.reset(),
            }
            const snapshot = importer.snapshot();
            const valid = snapshot.path_count <= 1 and
                snapshot.completed_units <= snapshot.total_units and
                snapshot.progress() >= 0.0 and snapshot.progress() <= 1.0 and
                (!snapshot.cancellation_pending or snapshot.canCancel()) and
                (!snapshot.canRetry() or snapshot.path_count == 1);
            if (!valid) {
                std.debug.print("import model seed={x} case={} operation={} status={s}\n", .{
                    seed, case_index, operation_index, @tagName(snapshot.status),
                });
                return error.GeneratedImportInvariantFailed;
            }
        }
    }
}

test "import model rejects malformed direct retained paths" {
    const Importer = Model(1, 1);
    var importer = try Importer.init(&.{".wav"});
    try std.testing.expectEqual(Status.validating, importer.begin(.picker, &.{"/tmp/sample.wav"}));

    importer.zone.path_count = 2;
    try std.testing.expectEqual(@as(?[]const u8, null), importer.path(0));
    try std.testing.expectError(error.InvalidImportTransition, importer.startImport(1));

    importer.zone.path_count = 1;
    importer.zone.paths[0].len = 0;
    try std.testing.expectEqual(@as(?[]const u8, null), importer.path(0));
    try std.testing.expectError(error.InvalidImportTransition, importer.startImport(1));

    var malformed_snapshot = importer.snapshot();
    malformed_snapshot.status = .validating;
    malformed_snapshot.path_count = 0;
    try std.testing.expectError(error.InvalidPathCount, malformed_snapshot.validate());
}
