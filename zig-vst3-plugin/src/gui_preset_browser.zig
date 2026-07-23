const std = @import("std");
const editor_state = @import("editor_state.zig");

pub const maximum_name_bytes = editor_state.maximum_text_bytes;

pub const Preset = struct {
    id: u32,
    name: editor_state.Text,

    pub fn init(id: u32, name: []const u8) !Preset {
        if (id == 0) return error.InvalidPresetId;
        return .{ .id = id, .name = try editor_state.Text.init(name) };
    }
};

pub const LoadStatus = enum {
    idle,
    loading,
    loaded,
    failed,
};

pub const StateFields = struct {
    search: u32,
    selection: u32,
};

pub fn Browser(comptime capacity: usize) type {
    if (capacity == 0) @compileError("preset browser capacity must be nonzero");

    return struct {
        const Self = @This();

        presets: [capacity]Preset = undefined,
        count: usize = 0,
        search: editor_state.Text = .{},
        selected_id: ?u32 = null,
        load_status: LoadStatus = .idle,

        pub fn add(self: *Self, preset: Preset) !void {
            if (!self.validStorage()) return error.InvalidPresetBrowserState;
            if (preset.id == 0 or preset.name.len > maximum_name_bytes) return error.InvalidPreset;
            if (self.count >= capacity) return error.PresetBrowserFull;
            if (self.indexOfId(preset.id) != null) return error.DuplicatePresetId;
            self.presets[self.count] = preset;
            self.count += 1;
            if (self.selected_id == null and self.matches(preset)) self.selected_id = preset.id;
        }

        pub fn setSearch(self: *Self, query: []const u8) !void {
            if (!self.validStorage()) return error.InvalidPresetBrowserState;
            self.search = try editor_state.Text.init(query);
            if (self.selected_id) |id| {
                const selected = self.indexOfId(id);
                if (selected != null and self.matches(self.presets[selected.?])) return;
            }
            self.selected_id = self.firstMatchingId();
            self.load_status = .idle;
        }

        pub fn select(self: *Self, id: u32) !void {
            if (!self.validStorage()) return error.InvalidPresetBrowserState;
            const index = self.indexOfId(id) orelse return error.UnknownPreset;
            if (!self.matches(self.presets[index])) return error.PresetFilteredOut;
            self.selected_id = id;
            self.load_status = .idle;
        }

        pub fn moveSelection(self: *Self, direction: enum { previous, next }) bool {
            if (!self.validStorage()) return false;
            if (self.count == 0) return false;
            const start = if (self.selected_id) |id| self.indexOfId(id) orelse 0 else 0;
            var offset: usize = 1;
            while (offset <= self.count) : (offset += 1) {
                const index = switch (direction) {
                    .next => (start + offset) % self.count,
                    .previous => (start + self.count - (offset % self.count)) % self.count,
                };
                if (self.matches(self.presets[index])) {
                    self.selected_id = self.presets[index].id;
                    self.load_status = .idle;
                    return true;
                }
            }
            return false;
        }

        pub fn beginLoad(self: *Self) !u32 {
            if (!self.validStorage()) return error.InvalidPresetBrowserState;
            const id = self.selected_id orelse return error.NoPresetSelected;
            const index = self.indexOfId(id) orelse return error.UnknownPreset;
            if (!self.matches(self.presets[index])) return error.PresetFilteredOut;
            self.load_status = .loading;
            return id;
        }

        pub fn finishLoad(self: *Self, succeeded: bool) void {
            if (self.load_status != .loading) return;
            self.load_status = if (succeeded) .loaded else .failed;
        }

        pub fn restore(self: *Self, state: anytype, fields: StateFields) !void {
            if (!self.validStorage()) return error.InvalidPresetBrowserState;
            const search_value = state.get(fields.search) orelse return error.UnknownEditorStateField;
            const selection_value = state.get(fields.selection) orelse return error.UnknownEditorStateField;
            self.search = switch (search_value) {
                .text => |text| blk: {
                    if (text.len > maximum_name_bytes) return error.InvalidPresetBrowserState;
                    break :blk text;
                },
                else => return error.EditorStateTypeMismatch,
            };
            const selected = switch (selection_value) {
                .index => |id| id,
                .point_id => |id| id,
                else => return error.EditorStateTypeMismatch,
            };
            self.selected_id = if (selected == 0) null else selected;
            if (self.selected_id) |id| {
                const index = self.indexOfId(id) orelse {
                    self.selected_id = self.firstMatchingId();
                    return;
                };
                if (!self.matches(self.presets[index])) self.selected_id = self.firstMatchingId();
            } else self.selected_id = self.firstMatchingId();
            self.load_status = .idle;
        }

        pub fn persist(self: *const Self, state: anytype, fields: StateFields) !void {
            if (!self.validStorage()) return error.InvalidPresetBrowserState;
            if (self.selected_id) |id| {
                const index = self.indexOfId(id) orelse return error.UnknownPreset;
                if (!self.matches(self.presets[index])) return error.PresetFilteredOut;
            }
            try state.set(fields.search, .{ .text = self.search });
            try state.setUnsigned(fields.selection, self.selected_id orelse 0);
        }

        pub fn matchingCount(self: *const Self) usize {
            if (!self.validStorage()) return 0;
            var result: usize = 0;
            for (self.presets[0..self.count]) |preset| if (self.matches(preset)) {
                result += 1;
            };
            return result;
        }

        fn firstMatchingId(self: *const Self) ?u32 {
            if (!self.validStorage()) return null;
            for (self.presets[0..self.count]) |preset| if (self.matches(preset)) return preset.id;
            return null;
        }

        fn indexOfId(self: *const Self, id: u32) ?usize {
            if (self.count > capacity) return null;
            for (self.presets[0..self.count], 0..) |preset, index| if (preset.id == id) return index;
            return null;
        }

        fn matches(self: *const Self, preset: Preset) bool {
            if (self.search.len > maximum_name_bytes or preset.name.len > maximum_name_bytes) return false;
            const query = self.search.slice();
            if (query.len == 0) return true;
            const name = preset.name.slice();
            if (query.len > name.len) return false;
            for (0..name.len - query.len + 1) |offset| {
                if (std.ascii.eqlIgnoreCase(name[offset..][0..query.len], query)) return true;
            }
            return false;
        }

        fn validStorage(self: *const Self) bool {
            if (self.count > capacity or self.search.len > maximum_name_bytes) return false;
            for (self.presets[0..self.count], 0..) |preset, index| {
                if (preset.id == 0 or preset.name.len > maximum_name_bytes) return false;
                for (self.presets[0..index]) |previous| {
                    if (previous.id == preset.id) return false;
                }
            }
            return true;
        }
    };
}

test "preset browser filters navigates and tracks loading" {
    const Presets = Browser(4);
    var browser = Presets{};
    try browser.add(try Preset.init(1, "Clean"));
    try browser.add(try Preset.init(2, "Bright Hall"));
    try browser.add(try Preset.init(3, "Dark Hall"));
    try browser.setSearch("hall");
    try std.testing.expectEqual(@as(usize, 2), browser.matchingCount());
    try std.testing.expectEqual(@as(?u32, 2), browser.selected_id);
    try std.testing.expect(browser.moveSelection(.next));
    try std.testing.expectEqual(@as(?u32, 3), browser.selected_id);
    try std.testing.expectEqual(@as(u32, 3), try browser.beginLoad());
    browser.finishLoad(false);
    try std.testing.expectEqual(LoadStatus.failed, browser.load_status);
}

test "preset browser persists search and selection through editor state" {
    const State = editor_state.Store(1, &.{
        .{ .id = 1, .default = .{ .text = editor_state.Text{} } },
        .{ .id = 2, .default = .{ .index = 0 } },
    });
    const Presets = Browser(3);
    const fields = StateFields{ .search = 1, .selection = 2 };
    var source = Presets{};
    try source.add(try Preset.init(1, "Clean"));
    try source.add(try Preset.init(2, "Bright Hall"));
    try source.add(try Preset.init(3, "Dark Hall"));
    try source.setSearch("dark");
    var state = State.init();
    try source.persist(&state, fields);

    var restored = Presets{};
    try restored.add(try Preset.init(1, "Clean"));
    try restored.add(try Preset.init(2, "Bright Hall"));
    try restored.add(try Preset.init(3, "Dark Hall"));
    try restored.restore(&state, fields);
    try std.testing.expectEqualStrings("dark", restored.search.slice());
    try std.testing.expectEqual(@as(?u32, 3), restored.selected_id);
}

test "preset browser rejects malformed direct collection state" {
    const Presets = Browser(2);
    var browser = Presets{};
    try browser.add(try Preset.init(1, "Clean"));
    browser.count = 3;
    try std.testing.expectEqual(@as(usize, 0), browser.matchingCount());
    try std.testing.expect(!browser.moveSelection(.next));
    try std.testing.expectError(error.InvalidPresetBrowserState, browser.add(try Preset.init(2, "Bright")));
    try std.testing.expectError(error.InvalidPresetBrowserState, browser.setSearch("clean"));
    try std.testing.expectError(error.InvalidPresetBrowserState, browser.beginLoad());

    browser.count = 1;
    browser.search.len = maximum_name_bytes + 1;
    try std.testing.expectEqual(@as(usize, 0), browser.matchingCount());
    try std.testing.expectError(error.InvalidPresetBrowserState, browser.select(1));

    browser.search = .{};
    browser.presets[0].name.len = maximum_name_bytes + 1;
    try std.testing.expectEqual(@as(usize, 0), browser.matchingCount());
}
