const std = @import("std");

pub const maximum_midi_notes = 128;

pub const NoteChange = struct {
    pitch: u8,
    velocity: f64,
    pressed: bool,
};

pub fn Keyboard(comptime capacity: usize) type {
    if (capacity == 0 or capacity > maximum_midi_notes) {
        @compileError("piano capacity must be between 1 and 128 notes");
    }

    return struct {
        const Self = @This();

        first_note: u8,
        note_count: u8,
        selected_note: u8,
        active: [2]u64 = @splat(0),

        pub fn init(first_note: u8, note_count: u8) !Self {
            if (note_count == 0 or @as(usize, note_count) > capacity) return error.InvalidNoteCount;
            if (@as(usize, first_note) + @as(usize, note_count) > maximum_midi_notes) {
                return error.InvalidNoteRange;
            }
            return .{
                .first_note = first_note,
                .note_count = note_count,
                .selected_note = first_note,
            };
        }

        pub fn contains(self: Self, pitch: u8) bool {
            if (!self.rangeValid()) return false;
            return pitch >= self.first_note and
                @as(usize, pitch) < @as(usize, self.first_note) + @as(usize, self.note_count);
        }

        pub fn valid(self: Self) bool {
            return self.rangeValid() and self.contains(self.selected_note);
        }

        pub fn select(self: *Self, pitch: u8) !void {
            if (!self.contains(pitch)) return error.NoteOutsideRange;
            self.selected_note = pitch;
        }

        pub fn moveSelection(self: *Self, direction: enum { previous, next }) bool {
            if (!self.valid()) return false;
            const next = switch (direction) {
                .previous => if (self.selected_note == self.first_note)
                    @as(u8, @intCast(@as(usize, self.first_note) + @as(usize, self.note_count) - 1))
                else
                    self.selected_note - 1,
                .next => if (@as(usize, self.selected_note) + 1 ==
                    @as(usize, self.first_note) + @as(usize, self.note_count))
                    self.first_note
                else
                    self.selected_note + 1,
            };
            const changed = next != self.selected_note;
            self.selected_note = next;
            return changed;
        }

        pub fn press(self: *Self, pitch: u8, velocity: f64) !?NoteChange {
            if (!self.contains(pitch)) return error.NoteOutsideRange;
            if (!std.math.isFinite(velocity) or velocity <= 0.0 or velocity > 1.0) {
                return error.InvalidVelocity;
            }
            self.selected_note = pitch;
            if (self.isPressed(pitch)) return null;
            self.setPressed(pitch, true);
            return .{ .pitch = pitch, .velocity = velocity, .pressed = true };
        }

        pub fn release(self: *Self, pitch: u8) !?NoteChange {
            if (!self.contains(pitch)) return error.NoteOutsideRange;
            if (!self.isPressed(pitch)) return null;
            self.setPressed(pitch, false);
            return .{ .pitch = pitch, .velocity = 0.0, .pressed = false };
        }

        pub fn toggleSelected(self: *Self, velocity: f64) !NoteChange {
            if (!self.valid()) return error.InvalidState;
            return if (self.isPressed(self.selected_note))
                (try self.release(self.selected_note)).?
            else
                (try self.press(self.selected_note, velocity)).?;
        }

        pub fn releaseAll(self: *Self, output: []NoteChange) usize {
            if (!self.rangeValid()) return 0;
            var count: usize = 0;
            var pitch: usize = self.first_note;
            const end = @as(usize, self.first_note) + @as(usize, self.note_count);
            while (pitch < end and count < output.len) : (pitch += 1) {
                const midi_pitch: u8 = @intCast(pitch);
                if (!self.isPressed(midi_pitch)) continue;
                self.setPressed(midi_pitch, false);
                output[count] = .{ .pitch = midi_pitch, .velocity = 0.0, .pressed = false };
                count += 1;
            }
            return count;
        }

        pub fn isPressed(self: Self, pitch: u8) bool {
            if (!self.contains(pitch)) return false;
            const word: usize = pitch / 64;
            const bit: u6 = @intCast(pitch % 64);
            return self.active[word] & (@as(u64, 1) << bit) != 0;
        }

        fn setPressed(self: *Self, pitch: u8, pressed: bool) void {
            const word: usize = pitch / 64;
            const bit: u6 = @intCast(pitch % 64);
            const mask = @as(u64, 1) << bit;
            if (pressed) self.active[word] |= mask else self.active[word] &= ~mask;
        }

        fn rangeValid(self: Self) bool {
            if (self.note_count == 0 or @as(usize, self.note_count) > capacity) return false;
            return @as(usize, self.first_note) + @as(usize, self.note_count) <= maximum_midi_notes;
        }
    };
}

pub fn computerKeyPitch(key: u8, base_pitch: u8) ?u8 {
    const keys = "awsedftgyhujkolp;";
    const offsets = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    const normalized = std.ascii.toLower(key);
    const index = std.mem.indexOfScalar(u8, keys, normalized) orelse return null;
    const pitch = @as(usize, base_pitch) + offsets[index];
    return if (pitch < maximum_midi_notes) @intCast(pitch) else null;
}

pub fn isBlackKey(pitch: u8) bool {
    return switch (pitch % 12) {
        1, 3, 6, 8, 10 => true,
        else => false,
    };
}

pub fn noteName(pitch: u8, output: []u8) ![]const u8 {
    if (pitch >= maximum_midi_notes) return error.InvalidPitch;
    const names = [_][]const u8{ "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" };
    const octave = @as(i16, pitch / 12) - 1;
    return std.fmt.bufPrint(output, "{s}{d}", .{ names[pitch % 12], octave });
}

test "keyboard tracks selection presses and bounded release" {
    const Piano = Keyboard(24);
    var piano = try Piano.init(48, 24);
    try std.testing.expectEqual(@as(u8, 48), piano.selected_note);
    try std.testing.expect(piano.moveSelection(.previous));
    try std.testing.expectEqual(@as(u8, 71), piano.selected_note);
    const pressed = (try piano.press(60, 0.75)).?;
    try std.testing.expect(pressed.pressed);
    try std.testing.expect(piano.isPressed(60));
    try std.testing.expect((try piano.press(60, 0.75)) == null);
    _ = try piano.press(64, 0.5);
    var releases: [1]NoteChange = undefined;
    try std.testing.expectEqual(@as(usize, 1), piano.releaseAll(&releases));
    try std.testing.expect(!releases[0].pressed);
    try std.testing.expect(!piano.isPressed(releases[0].pitch));
    try std.testing.expect(piano.isPressed(64));
}

test "keyboard releases the highest MIDI note without counter overflow" {
    const Piano = Keyboard(1);
    var piano = try Piano.init(127, 1);
    _ = try piano.press(127, 1.0);

    var released: [1]NoteChange = undefined;
    try std.testing.expectEqual(@as(usize, 1), piano.releaseAll(&released));
    try std.testing.expectEqual(@as(u8, 127), released[0].pitch);
    try std.testing.expect(!released[0].pressed);
    try std.testing.expect(!piano.isPressed(127));
}

test "keyboard rejects malformed direct state" {
    const Piano = Keyboard(24);
    var piano = try Piano.init(48, 24);

    piano.note_count = 0;
    try std.testing.expect(!piano.valid());
    try std.testing.expect(!piano.contains(48));
    try std.testing.expect(!piano.moveSelection(.next));
    try std.testing.expectError(error.InvalidState, piano.toggleSelected(0.5));
    var releases: [24]NoteChange = undefined;
    try std.testing.expectEqual(@as(usize, 0), piano.releaseAll(&releases));

    piano.note_count = 24;
    piano.first_note = 120;
    try std.testing.expect(!piano.valid());
    try std.testing.expectError(error.NoteOutsideRange, piano.press(127, 0.5));

    piano.first_note = 48;
    piano.selected_note = 80;
    try std.testing.expect(!piano.valid());
    try std.testing.expect(!piano.moveSelection(.previous));
    try std.testing.expectError(error.InvalidState, piano.toggleSelected(0.5));

    try piano.select(60);
    try std.testing.expect(piano.valid());
}

test "computer mapping and note names follow MIDI conventions" {
    try std.testing.expectEqual(@as(?u8, 60), computerKeyPitch('a', 60));
    try std.testing.expectEqual(@as(?u8, 61), computerKeyPitch('W', 60));
    try std.testing.expectEqual(@as(?u8, 76), computerKeyPitch(';', 60));
    try std.testing.expectEqual(@as(?u8, null), computerKeyPitch('q', 60));
    try std.testing.expect(isBlackKey(61));
    try std.testing.expect(!isBlackKey(60));
    var buffer: [8]u8 = undefined;
    try std.testing.expectEqualStrings("C4", try noteName(60, &buffer));
    try std.testing.expectEqualStrings("A4", try noteName(69, &buffer));
}
