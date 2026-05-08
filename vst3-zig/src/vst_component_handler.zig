const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub fn ComponentHandler(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivsteditcontroller.IComponentHandler = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        begin_count: types.uint32 = 0,
        perform_count: types.uint32 = 0,
        end_count: types.uint32 = 0,
        restart_count: types.uint32 = 0,
        last_param_id: vsttypes.ParamID = vsttypes.kNoParamId,
        last_value: vsttypes.ParamValue = -1,
        last_restart_flags: types.int32 = 0,

        pub fn asHandler(self: *Self) *ivsteditcontroller.IComponentHandler {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivsteditcontroller.IComponentHandler = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn queryInterface(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = owner(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.iface },
                .{ .iid = &ivsteditcontroller.icomponent_handler_iid, .ptr = &self.iface },
            };
            return interface_map.queryWithAddRef(&self.iface, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IComponentHandler");
        }

        fn beginEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.begin_count += 1;
            self.last_param_id = id;
            if (@hasDecl(Config, "beginEdit")) return Config.beginEdit(self, id);
            return types.kResultOk;
        }

        fn performEdit(ptr: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.perform_count += 1;
            self.last_param_id = id;
            self.last_value = value;
            if (@hasDecl(Config, "performEdit")) return Config.performEdit(self, id, value);
            return types.kResultOk;
        }

        fn endEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.end_count += 1;
            self.last_param_id = id;
            if (@hasDecl(Config, "endEdit")) return Config.endEdit(self, id);
            return types.kResultOk;
        }

        fn restartComponent(ptr: *anyopaque, flags: types.int32) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.restart_count += 1;
            self.last_restart_flags = flags;
            if (@hasDecl(Config, "restartComponent")) return Config.restartComponent(self, flags);
            return types.kResultOk;
        }

        const vtable = ivsteditcontroller.IComponentHandlerVTable{
            .queryInterface = queryInterface,
            .addRef = addRef,
            .release = release,
            .beginEdit = beginEdit,
            .performEdit = performEdit,
            .endEdit = endEdit,
            .restartComponent = restartComponent,
        };
    };
}

pub fn ComponentHandler2(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        handler: ivsteditcontroller.IComponentHandler = .{ .vtable = &handler_vtable },
        handler2: ivsteditcontroller.IComponentHandler2 = .{ .vtable = &handler2_vtable },
        handler_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        handler2_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        dirty_count: types.uint32 = 0,
        open_editor_count: types.uint32 = 0,
        start_group_count: types.uint32 = 0,
        finish_group_count: types.uint32 = 0,
        handler2_add_ref_count: types.uint32 = 0,
        handler2_release_count: types.uint32 = 0,
        last_dirty_state: types.TBool = 0,
        last_editor_name: types.FIDString = "",

        pub fn asHandler(self: *Self) *ivsteditcontroller.IComponentHandler {
            return &self.handler;
        }

        pub fn asHandler2(self: *Self) *ivsteditcontroller.IComponentHandler2 {
            return &self.handler2;
        }

        fn ownerFromHandler(ptr: *anyopaque) *Self {
            const iface: *ivsteditcontroller.IComponentHandler = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("handler", iface);
        }

        fn ownerFromHandler2(ptr: *anyopaque) *Self {
            const iface: *ivsteditcontroller.IComponentHandler2 = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("handler2", iface);
        }

        fn queryFromHandler(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromHandler(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.handler },
                .{ .iid = &ivsteditcontroller.icomponent_handler_iid, .ptr = &self.handler },
                .{ .iid = &ivsteditcontroller.icomponent_handler2_iid, .ptr = &self.handler2 },
            };
            if (std.mem.eql(u8, requested_iid, &ivsteditcontroller.icomponent_handler2_iid)) {
                return interface_map.queryWithAddRef(&self.handler2, addRefFromHandler2, &entries, requested_iid, out);
            }
            return interface_map.queryWithAddRef(&self.handler, addRefFromHandler, &entries, requested_iid, out);
        }

        fn queryFromHandler2(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromHandler2(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.handler2 },
                .{ .iid = &ivsteditcontroller.icomponent_handler2_iid, .ptr = &self.handler2 },
            };
            return interface_map.queryWithAddRef(&self.handler2, addRefFromHandler2, &entries, requested_iid, out);
        }

        fn addRefFromHandler(ptr: *anyopaque) callconv(.C) types.uint32 {
            return ownerFromHandler(ptr).handler_ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn releaseFromHandler(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&ownerFromHandler(ptr).handler_ref_count, "IComponentHandler");
        }

        fn addRefFromHandler2(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = ownerFromHandler2(ptr);
            self.handler2_add_ref_count += 1;
            return self.handler2_ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn releaseFromHandler2(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = ownerFromHandler2(ptr);
            self.handler2_release_count += 1;
            return funknown.decrementRefCount(&self.handler2_ref_count, "IComponentHandler2");
        }

        fn beginEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.C) types.tresult {
            const self = ownerFromHandler(ptr);
            if (@hasDecl(Config, "beginEdit")) return Config.beginEdit(self, id);
            return types.kResultOk;
        }

        fn performEdit(ptr: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.C) types.tresult {
            const self = ownerFromHandler(ptr);
            if (@hasDecl(Config, "performEdit")) return Config.performEdit(self, id, value);
            return types.kResultOk;
        }

        fn endEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.C) types.tresult {
            const self = ownerFromHandler(ptr);
            if (@hasDecl(Config, "endEdit")) return Config.endEdit(self, id);
            return types.kResultOk;
        }

        fn restartComponent(ptr: *anyopaque, flags: types.int32) callconv(.C) types.tresult {
            const self = ownerFromHandler(ptr);
            if (@hasDecl(Config, "restartComponent")) return Config.restartComponent(self, flags);
            return types.kResultOk;
        }

        fn setDirty(ptr: *anyopaque, state: types.TBool) callconv(.C) types.tresult {
            const self = ownerFromHandler2(ptr);
            self.dirty_count += 1;
            self.last_dirty_state = state;
            if (@hasDecl(Config, "setDirty")) return Config.setDirty(self, state);
            return types.kResultOk;
        }

        fn requestOpenEditor(ptr: *anyopaque, name: types.FIDString) callconv(.C) types.tresult {
            const self = ownerFromHandler2(ptr);
            self.open_editor_count += 1;
            self.last_editor_name = name;
            if (@hasDecl(Config, "requestOpenEditor")) return Config.requestOpenEditor(self, name);
            return types.kResultOk;
        }

        fn startGroupEdit(ptr: *anyopaque) callconv(.C) types.tresult {
            const self = ownerFromHandler2(ptr);
            self.start_group_count += 1;
            if (@hasDecl(Config, "startGroupEdit")) return Config.startGroupEdit(self);
            return types.kResultOk;
        }

        fn finishGroupEdit(ptr: *anyopaque) callconv(.C) types.tresult {
            const self = ownerFromHandler2(ptr);
            self.finish_group_count += 1;
            if (@hasDecl(Config, "finishGroupEdit")) return Config.finishGroupEdit(self);
            return types.kResultOk;
        }

        const handler_vtable = ivsteditcontroller.IComponentHandlerVTable{
            .queryInterface = queryFromHandler,
            .addRef = addRefFromHandler,
            .release = releaseFromHandler,
            .beginEdit = beginEdit,
            .performEdit = performEdit,
            .endEdit = endEdit,
            .restartComponent = restartComponent,
        };

        const handler2_vtable = ivsteditcontroller.IComponentHandler2VTable{
            .queryInterface = queryFromHandler2,
            .addRef = addRefFromHandler2,
            .release = releaseFromHandler2,
            .setDirty = setDirty,
            .requestOpenEditor = requestOpenEditor,
            .startGroupEdit = startGroupEdit,
            .finishGroupEdit = finishGroupEdit,
        };
    };
}

test "component handler records automation callbacks" {
    const Handler = ComponentHandler(struct {});
    var handler = Handler{};

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.beginEdit(handler.asHandler(), 9));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.performEdit(handler.asHandler(), 9, 0.5));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.endEdit(handler.asHandler(), 9));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.begin_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.perform_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.end_count);
    try std.testing.expectEqual(@as(vsttypes.ParamID, 9), handler.last_param_id);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), handler.last_value);
}

test "component handler 2 exposes extension and records callbacks" {
    const Handler = ComponentHandler2(struct {});
    var handler = Handler{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.queryInterface(handler.asHandler(), &ivsteditcontroller.icomponent_handler2_iid, &queried));
    try std.testing.expect(queried != null);
    const handler2: *ivsteditcontroller.IComponentHandler2 = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.handler2_add_ref_count);

    try std.testing.expectEqual(types.kResultOk, handler2.vtable.setDirty(handler2, 1));
    try std.testing.expectEqual(types.kResultOk, handler2.vtable.requestOpenEditor(handler2, "editor"));
    try std.testing.expectEqual(types.kResultOk, handler2.vtable.startGroupEdit(handler2));
    try std.testing.expectEqual(types.kResultOk, handler2.vtable.finishGroupEdit(handler2));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.dirty_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.open_editor_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.start_group_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.finish_group_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler2.vtable.release(handler2));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.handler2_release_count);
}
