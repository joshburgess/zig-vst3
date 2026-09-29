const std = @import("std");
const ara = @import("zig-vst3-ara");
const ara_vst3 = @import("ara_vst3.zig");

pub const raw = ara.raw;

pub const Limits = struct {
    playback_regions: usize = 64,
    editor_regions: usize = 64,
    editor_sequences: usize = 32,
    selected_regions: usize = 64,
    selected_sequences: usize = 32,
    hidden_sequences: usize = 32,
};

pub const Error = error{
    AlreadyBound,
    InvalidDocumentController,
    InvalidRoles,
    MissingRole,
    CapacityExceeded,
    MixedEditorAssignments,
    InvalidReference,
    InvalidStructSize,
    InvalidCountedPointer,
    InvalidTimeRange,
};

pub const EditorAssignmentMode = enum {
    none,
    playback_regions,
    region_sequences,
};

pub fn State(comptime limits: Limits) type {
    return struct {
        playback_regions: [limits.playback_regions]raw.ARAPlaybackRegionRef =
            [_]raw.ARAPlaybackRegionRef{null} **
            limits.playback_regions,
        playback_region_count: usize = 0,
        editor_regions: [limits.editor_regions]raw.ARAPlaybackRegionRef =
            [_]raw.ARAPlaybackRegionRef{null} **
            limits.editor_regions,
        editor_region_count: usize = 0,
        editor_sequences: [limits.editor_sequences]raw.ARARegionSequenceRef =
            [_]raw.ARARegionSequenceRef{null} **
            limits.editor_sequences,
        editor_sequence_count: usize = 0,
        editor_assignment_mode: EditorAssignmentMode = .none,
        selected_regions: [limits.selected_regions]raw.ARAPlaybackRegionRef =
            [_]raw.ARAPlaybackRegionRef{null} **
            limits.selected_regions,
        selected_region_count: usize = 0,
        selected_sequences: [limits.selected_sequences]raw.ARARegionSequenceRef =
            [_]raw.ARARegionSequenceRef{null} **
            limits.selected_sequences,
        selected_sequence_count: usize = 0,
        selected_time_range: ?raw.ARAContentTimeRange = null,
        hidden_sequences: [limits.hidden_sequences]raw.ARARegionSequenceRef =
            [_]raw.ARARegionSequenceRef{null} **
            limits.hidden_sequences,
        hidden_sequence_count: usize = 0,
        revision: u64 = 0,
    };
}

pub fn PublicationSink(comptime limits: Limits) type {
    return struct {
        context: ?*anyopaque = null,
        changed: ?*const fn (
            ?*anyopaque,
            *const State(limits),
        ) void = null,
    };
}

pub fn Extension(comptime limits: Limits) type {
    return struct {
        const Self = @This();
        const Snapshot = State(limits);

        document_controller_ref: raw.ARADocumentControllerRef = null,
        assigned_roles: ara_vst3.RoleFlags = ara_vst3.no_roles,
        bound: bool = false,
        state: Snapshot = .{},
        publication_sink: PublicationSink(limits) = .{},
        retained_error: ?Error = null,
        raw_instance: raw.ARAPlugInExtensionInstance = .{},

        pub fn init(sink: PublicationSink(limits)) Self {
            return .{ .publication_sink = sink };
        }

        pub fn bind(
            self: *Self,
            document_controller_ref: raw.ARADocumentControllerRef,
            known_roles: ara_vst3.RoleFlags,
            assigned_roles: ara_vst3.RoleFlags,
        ) Error!*const raw.ARAPlugInExtensionInstance {
            if (self.bound) return error.AlreadyBound;
            if (document_controller_ref == null)
                return error.InvalidDocumentController;
            if (!ara_vst3.validRoles(known_roles) or
                !ara_vst3.validRoles(assigned_roles) or
                assigned_roles & ~known_roles != 0)
                return error.InvalidRoles;

            self.document_controller_ref = document_controller_ref;
            self.assigned_roles = assigned_roles;
            self.bound = true;
            self.raw_instance = .{
                .structSize = @sizeOf(raw.ARAPlugInExtensionInstance),
                .plugInExtensionRef = @ptrCast(self),
                .plugInExtensionInterface = &legacy_interface,
                .playbackRendererRef = if (hasRole(
                    assigned_roles,
                    ara_vst3.playback_renderer_role,
                )) @ptrCast(self) else null,
                .playbackRendererInterface = if (hasRole(
                    assigned_roles,
                    ara_vst3.playback_renderer_role,
                )) &playback_interface else null,
                .editorRendererRef = if (hasRole(
                    assigned_roles,
                    ara_vst3.editor_renderer_role,
                )) @ptrCast(self) else null,
                .editorRendererInterface = if (hasRole(
                    assigned_roles,
                    ara_vst3.editor_renderer_role,
                )) &editor_renderer_interface else null,
                .editorViewRef = if (hasRole(
                    assigned_roles,
                    ara_vst3.editor_view_role,
                )) @ptrCast(self) else null,
                .editorViewInterface = if (hasRole(
                    assigned_roles,
                    ara_vst3.editor_view_role,
                )) &editor_view_interface else null,
            };
            return &self.raw_instance;
        }

        pub fn snapshot(self: *const Self) *const Snapshot {
            return &self.state;
        }

        pub fn takeError(self: *Self) ?Error {
            const retained = self.retained_error;
            self.retained_error = null;
            return retained;
        }

        fn hasRole(
            roles: ara_vst3.RoleFlags,
            role: ara_vst3.RoleFlags,
        ) bool {
            return roles & role != 0;
        }

        fn retain(self: *Self, err: Error) void {
            if (self.retained_error == null)
                self.retained_error = err;
        }

        fn publish(self: *Self) void {
            self.state.revision +%= 1;
            if (self.publication_sink.changed) |changed|
                changed(self.publication_sink.context, &self.state);
        }

        fn owner(ref: ?*anyopaque) Error!*Self {
            const value = ref orelse return error.InvalidReference;
            return @ptrCast(@alignCast(value));
        }

        fn indexOf(
            comptime Ref: type,
            values: []const Ref,
            needle: Ref,
        ) ?usize {
            for (values, 0..) |value, index| {
                if (value == needle) return index;
            }
            return null;
        }

        fn addUnique(
            comptime Ref: type,
            values: []Ref,
            count: *usize,
            value: Ref,
        ) Error!bool {
            if (value == null) return error.InvalidReference;
            if (indexOf(Ref, values[0..count.*], value) != null)
                return false;
            if (count.* == values.len) return error.CapacityExceeded;
            values[count.*] = value;
            count.* += 1;
            return true;
        }

        fn removeValue(
            comptime Ref: type,
            values: []Ref,
            count: *usize,
            value: Ref,
        ) Error!bool {
            if (value == null) return error.InvalidReference;
            const index =
                indexOf(Ref, values[0..count.*], value) orelse
                return false;
            count.* -= 1;
            values[index] = values[count.*];
            values[count.*] = null;
            return true;
        }

        fn legacySet(
            ref: raw.ARAPlugInExtensionRef,
            playback_region_ref: raw.ARAPlaybackRegionRef,
        ) callconv(.c) void {
            const self = owner(ref) catch |err| return selflessError(err);
            if (!hasRole(
                self.assigned_roles,
                ara_vst3.playback_renderer_role,
            )) {
                self.retain(error.MissingRole);
                return;
            }
            if (playback_region_ref == null) {
                self.retain(error.InvalidReference);
                return;
            }
            if (self.state.playback_regions.len == 0) {
                self.retain(error.CapacityExceeded);
                return;
            }
            for (self.state.playback_regions[0..self.state.playback_region_count]) |region|
                if (region == playback_region_ref) return;
            @memset(&self.state.playback_regions, null);
            self.state.playback_regions[0] = playback_region_ref;
            self.state.playback_region_count = 1;
            self.publish();
        }

        fn legacyRemove(
            ref: raw.ARAPlugInExtensionRef,
            playback_region_ref: raw.ARAPlaybackRegionRef,
        ) callconv(.c) void {
            const self = owner(ref) catch |err| return selflessError(err);
            const changed = removeValue(
                raw.ARAPlaybackRegionRef,
                &self.state.playback_regions,
                &self.state.playback_region_count,
                playback_region_ref,
            ) catch |err| {
                self.retain(err);
                return;
            };
            if (changed) self.publish();
        }

        fn playbackAdd(
            ref: raw.ARAPlaybackRendererRef,
            playback_region_ref: raw.ARAPlaybackRegionRef,
        ) callconv(.c) void {
            const self = owner(ref) catch |err| return selflessError(err);
            const changed = addUnique(
                raw.ARAPlaybackRegionRef,
                &self.state.playback_regions,
                &self.state.playback_region_count,
                playback_region_ref,
            ) catch |err| {
                self.retain(err);
                return;
            };
            if (changed) self.publish();
        }

        fn playbackRemove(
            ref: raw.ARAPlaybackRendererRef,
            playback_region_ref: raw.ARAPlaybackRegionRef,
        ) callconv(.c) void {
            const self = owner(ref) catch |err| return selflessError(err);
            const changed = removeValue(
                raw.ARAPlaybackRegionRef,
                &self.state.playback_regions,
                &self.state.playback_region_count,
                playback_region_ref,
            ) catch |err| {
                self.retain(err);
                return;
            };
            if (changed) self.publish();
        }

        fn editorAddRegion(
            ref: raw.ARAEditorRendererRef,
            playback_region_ref: raw.ARAPlaybackRegionRef,
        ) callconv(.c) void {
            const self = owner(ref) catch |err| return selflessError(err);
            if (self.state.editor_assignment_mode ==
                .region_sequences)
            {
                self.retain(error.MixedEditorAssignments);
                return;
            }
            const changed = addUnique(
                raw.ARAPlaybackRegionRef,
                &self.state.editor_regions,
                &self.state.editor_region_count,
                playback_region_ref,
            ) catch |err| {
                self.retain(err);
                return;
            };
            if (changed) {
                self.state.editor_assignment_mode = .playback_regions;
                self.publish();
            }
        }

        fn editorRemoveRegion(
            ref: raw.ARAEditorRendererRef,
            playback_region_ref: raw.ARAPlaybackRegionRef,
        ) callconv(.c) void {
            const self = owner(ref) catch |err| return selflessError(err);
            const changed = removeValue(
                raw.ARAPlaybackRegionRef,
                &self.state.editor_regions,
                &self.state.editor_region_count,
                playback_region_ref,
            ) catch |err| {
                self.retain(err);
                return;
            };
            if (changed) {
                if (self.state.editor_region_count == 0)
                    self.state.editor_assignment_mode = .none;
                self.publish();
            }
        }

        fn editorAddSequence(
            ref: raw.ARAEditorRendererRef,
            region_sequence_ref: raw.ARARegionSequenceRef,
        ) callconv(.c) void {
            const self = owner(ref) catch |err| return selflessError(err);
            if (self.state.editor_assignment_mode ==
                .playback_regions)
            {
                self.retain(error.MixedEditorAssignments);
                return;
            }
            const changed = addUnique(
                raw.ARARegionSequenceRef,
                &self.state.editor_sequences,
                &self.state.editor_sequence_count,
                region_sequence_ref,
            ) catch |err| {
                self.retain(err);
                return;
            };
            if (changed) {
                self.state.editor_assignment_mode = .region_sequences;
                self.publish();
            }
        }

        fn editorRemoveSequence(
            ref: raw.ARAEditorRendererRef,
            region_sequence_ref: raw.ARARegionSequenceRef,
        ) callconv(.c) void {
            const self = owner(ref) catch |err| return selflessError(err);
            const changed = removeValue(
                raw.ARARegionSequenceRef,
                &self.state.editor_sequences,
                &self.state.editor_sequence_count,
                region_sequence_ref,
            ) catch |err| {
                self.retain(err);
                return;
            };
            if (changed) {
                if (self.state.editor_sequence_count == 0)
                    self.state.editor_assignment_mode = .none;
                self.publish();
            }
        }

        fn checkedCount(count: raw.ARASize, capacity: usize) Error!usize {
            const value =
                std.math.cast(usize, count) orelse
                return error.CapacityExceeded;
            if (value > capacity) return error.CapacityExceeded;
            return value;
        }

        fn validateTimeRange(
            value: raw.ARAContentTimeRange,
        ) Error!void {
            if (!std.math.isFinite(value.start) or
                !std.math.isFinite(value.duration) or
                value.duration < 0)
                return error.InvalidTimeRange;
        }

        fn copyRefs(
            comptime Ref: type,
            destination: []Ref,
            count: raw.ARASize,
            source: [*c]const Ref,
        ) Error!usize {
            const length = try checkedCount(count, destination.len);
            if (length > 0 and source == null)
                return error.InvalidCountedPointer;
            for (source[0..length], 0..) |value, index| {
                if (value == null) return error.InvalidReference;
                if (indexOf(Ref, destination[0..index], value) != null)
                    return error.InvalidReference;
                destination[index] = value;
            }
            @memset(destination[length..], null);
            return length;
        }

        fn notifySelection(
            ref: raw.ARAEditorViewRef,
            selection_ptr: [*c]const raw.ARAViewSelection,
        ) callconv(.c) void {
            const self = owner(ref) catch |err| return selflessError(err);
            if (selection_ptr == null) {
                self.retain(error.InvalidReference);
                return;
            }
            const selection = &selection_ptr[0];
            if (selection.structSize < raw.kARAViewSelectionMinSize) {
                self.retain(error.InvalidStructSize);
                return;
            }
            var next = self.state;
            next.selected_region_count = copyRefs(
                raw.ARAPlaybackRegionRef,
                &next.selected_regions,
                selection.playbackRegionRefsCount,
                selection.playbackRegionRefs,
            ) catch |err| {
                self.retain(err);
                return;
            };
            next.selected_sequence_count = copyRefs(
                raw.ARARegionSequenceRef,
                &next.selected_sequences,
                selection.regionSequenceRefsCount,
                selection.regionSequenceRefs,
            ) catch |err| {
                self.retain(err);
                return;
            };
            next.selected_time_range = if (selection.timeRange == null)
                null
            else
                selection.timeRange[0];
            if (next.selected_time_range) |time_range|
                validateTimeRange(time_range) catch |err| {
                    self.retain(err);
                    return;
                };
            const revision = self.state.revision;
            self.state = next;
            self.state.revision = revision;
            self.publish();
        }

        fn notifyHideSequences(
            ref: raw.ARAEditorViewRef,
            count: raw.ARASize,
            sequence_refs: [*c]const raw.ARARegionSequenceRef,
        ) callconv(.c) void {
            const self = owner(ref) catch |err| return selflessError(err);
            var next = self.state;
            next.hidden_sequence_count = copyRefs(
                raw.ARARegionSequenceRef,
                &next.hidden_sequences,
                count,
                sequence_refs,
            ) catch |err| {
                self.retain(err);
                return;
            };
            const revision = self.state.revision;
            self.state = next;
            self.state.revision = revision;
            self.publish();
        }

        fn selflessError(_: Error) void {}

        const legacy_interface = raw.ARAPlugInExtensionInterface{
            .structSize = @sizeOf(raw.ARAPlugInExtensionInterface),
            .setPlaybackRegion = legacySet,
            .removePlaybackRegion = legacyRemove,
        };

        const playback_interface = raw.ARAPlaybackRendererInterface{
            .structSize = @sizeOf(raw.ARAPlaybackRendererInterface),
            .addPlaybackRegion = playbackAdd,
            .removePlaybackRegion = playbackRemove,
        };

        const editor_renderer_interface =
            raw.ARAEditorRendererInterface{
                .structSize = @sizeOf(raw.ARAEditorRendererInterface),
                .addPlaybackRegion = editorAddRegion,
                .removePlaybackRegion = editorRemoveRegion,
                .addRegionSequence = editorAddSequence,
                .removeRegionSequence = editorRemoveSequence,
            };

        const editor_view_interface = raw.ARAEditorViewInterface{
            .structSize = @sizeOf(raw.ARAEditorViewInterface),
            .notifySelection = notifySelection,
            .notifyHideRegionSequences = notifyHideSequences,
        };
    };
}

pub fn Vst3BindConfig(comptime ExtensionType: type) type {
    return struct {
        pub fn bind(
            entry: anytype,
            document: *ara_vst3.DocumentController,
            known_roles: ara_vst3.RoleFlags,
            assigned_roles: ara_vst3.RoleFlags,
        ) ?*const ara_vst3.PlugInExtensionInstance {
            const context = entry.context orelse return null;
            const extension: *ExtensionType =
                @ptrCast(@alignCast(context));
            const effective_known_roles =
                if (known_roles == ara_vst3.no_roles and
                assigned_roles == ara_vst3.all_roles)
                    ara_vst3.all_roles
                else
                    known_roles;
            const instance = extension.bind(
                @ptrCast(document),
                effective_known_roles,
                assigned_roles,
            ) catch return null;
            return @ptrCast(instance);
        }
    };
}

test "ARA extension publishes bounded renderer assignments" {
    const TestExtension = Extension(.{
        .playback_regions = 2,
        .editor_regions = 2,
        .editor_sequences = 2,
    });
    const Observer = struct {
        var revisions: usize = 0;

        fn changed(_: ?*anyopaque, state: *const State(.{
            .playback_regions = 2,
            .editor_regions = 2,
            .editor_sequences = 2,
        })) void {
            revisions = state.revision;
        }
    };
    Observer.revisions = 0;
    var extension = TestExtension.init(.{ .changed = Observer.changed });
    const controller: raw.ARADocumentControllerRef =
        @ptrFromInt(0x1000);
    const instance = try extension.bind(
        controller,
        ara_vst3.all_roles,
        ara_vst3.playback_renderer_role |
            ara_vst3.editor_renderer_role,
    );
    try std.testing.expect(instance.playbackRendererInterface != null);
    try std.testing.expect(instance.editorRendererInterface != null);
    try std.testing.expect(instance.editorViewInterface == null);

    const first: raw.ARAPlaybackRegionRef = @ptrFromInt(0x2000);
    const second: raw.ARAPlaybackRegionRef = @ptrFromInt(0x3000);
    const third: raw.ARAPlaybackRegionRef = @ptrFromInt(0x4000);
    instance.playbackRendererInterface[0].addPlaybackRegion.?(
        instance.playbackRendererRef,
        first,
    );
    instance.playbackRendererInterface[0].addPlaybackRegion.?(
        instance.playbackRendererRef,
        second,
    );
    instance.playbackRendererInterface[0].addPlaybackRegion.?(
        instance.playbackRendererRef,
        third,
    );
    try std.testing.expectEqual(@as(usize, 2), extension
        .snapshot().playback_region_count);
    try std.testing.expectEqual(
        @as(?Error, error.CapacityExceeded),
        extension.takeError(),
    );
    try std.testing.expectEqual(@as(usize, 2), Observer.revisions);

    instance.editorRendererInterface[0].addPlaybackRegion.?(
        instance.editorRendererRef,
        first,
    );
    const sequence: raw.ARARegionSequenceRef = @ptrFromInt(0x5000);
    instance.editorRendererInterface[0].addRegionSequence.?(
        instance.editorRendererRef,
        sequence,
    );
    try std.testing.expectEqual(
        @as(?Error, error.MixedEditorAssignments),
        extension.takeError(),
    );
}

test "ARA editor view copies selection and hidden sequences" {
    const TestExtension = Extension(.{
        .selected_regions = 2,
        .selected_sequences = 2,
        .hidden_sequences = 2,
    });
    var extension = TestExtension.init(.{});
    const instance = try extension.bind(
        @ptrFromInt(0x1000),
        ara_vst3.all_roles,
        ara_vst3.editor_view_role,
    );
    const region_refs = [_]raw.ARAPlaybackRegionRef{
        @ptrFromInt(0x2000),
        @ptrFromInt(0x3000),
    };
    const sequence_refs = [_]raw.ARARegionSequenceRef{
        @ptrFromInt(0x4000),
    };
    const time_range = raw.ARAContentTimeRange{
        .start = 2.0,
        .duration = 4.0,
    };
    const selection = raw.ARAViewSelection{
        .structSize = @sizeOf(raw.ARAViewSelection),
        .playbackRegionRefsCount = region_refs.len,
        .playbackRegionRefs = &region_refs,
        .regionSequenceRefsCount = sequence_refs.len,
        .regionSequenceRefs = &sequence_refs,
        .timeRange = &time_range,
    };
    instance.editorViewInterface[0].notifySelection.?(
        instance.editorViewRef,
        &selection,
    );
    instance.editorViewInterface[0].notifyHideRegionSequences.?(
        instance.editorViewRef,
        sequence_refs.len,
        &sequence_refs,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        extension.snapshot().selected_region_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        extension.snapshot().hidden_sequence_count,
    );
    try std.testing.expectEqual(
        @as(f64, 4.0),
        extension.snapshot().selected_time_range.?.duration,
    );
}

test "ARA VST3 entry point binds a role-specific extension" {
    const TestExtension = Extension(.{});
    var extension = TestExtension.init(.{});
    const Entry = ara_vst3.PlugInEntryPoint(
        Vst3BindConfig(TestExtension),
    );
    var entry = Entry.init(&extension, @ptrFromInt(0x6000));
    const controller: *ara_vst3.DocumentController =
        @ptrFromInt(0x1000);
    const instance_ptr =
        entry.asEntryPoint2().vtable
            .bindToDocumentControllerWithRoles(
            entry.asEntryPoint2(),
            controller,
            ara_vst3.all_roles,
            ara_vst3.playback_renderer_role |
                ara_vst3.editor_view_role,
        ) orelse return error.TestUnexpectedResult;
    const instance: *const raw.ARAPlugInExtensionInstance =
        @ptrCast(@alignCast(instance_ptr));
    try std.testing.expect(instance.playbackRendererInterface != null);
    try std.testing.expect(instance.editorRendererInterface == null);
    try std.testing.expect(instance.editorViewInterface != null);
    try std.testing.expect(entry.isBound());
}

test "ARA legacy VST3 entry point assigns all roles" {
    const TestExtension = Extension(.{});
    var extension = TestExtension.init(.{});
    const Entry = ara_vst3.PlugInEntryPoint(
        Vst3BindConfig(TestExtension),
    );
    var entry = Entry.init(&extension, @ptrFromInt(0x6000));
    const instance_ptr =
        entry.asEntryPoint().vtable.bindToDocumentController(
            entry.asEntryPoint(),
            @ptrFromInt(0x1000),
        ) orelse return error.TestUnexpectedResult;
    const instance: *const raw.ARAPlugInExtensionInstance =
        @ptrCast(@alignCast(instance_ptr));
    try std.testing.expect(instance.playbackRendererInterface != null);
    try std.testing.expect(instance.editorRendererInterface != null);
    try std.testing.expect(instance.editorViewInterface != null);
    try std.testing.expectEqual(
        ara_vst3.all_roles,
        extension.assigned_roles,
    );
}

test "ARA editor selection rejects invalid input transactionally" {
    const TestExtension = Extension(.{
        .selected_regions = 2,
        .selected_sequences = 1,
    });
    var extension = TestExtension.init(.{});
    const instance = try extension.bind(
        @ptrFromInt(0x1000),
        ara_vst3.all_roles,
        ara_vst3.editor_view_role,
    );
    const duplicate: raw.ARAPlaybackRegionRef =
        @ptrFromInt(0x2000);
    const duplicate_refs = [_]raw.ARAPlaybackRegionRef{
        duplicate,
        duplicate,
    };
    const selection = raw.ARAViewSelection{
        .structSize = @sizeOf(raw.ARAViewSelection),
        .playbackRegionRefsCount = duplicate_refs.len,
        .playbackRegionRefs = &duplicate_refs,
    };
    instance.editorViewInterface[0].notifySelection.?(
        instance.editorViewRef,
        &selection,
    );
    try std.testing.expectEqual(
        @as(?Error, error.InvalidReference),
        extension.takeError(),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        extension.snapshot().selected_region_count,
    );
    try std.testing.expectEqual(
        @as(u64, 0),
        extension.snapshot().revision,
    );
}
