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
