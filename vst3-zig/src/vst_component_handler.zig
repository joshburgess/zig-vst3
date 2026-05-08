const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const ivstcontextmenu = @import("pluginterfaces/vst/ivstcontextmenu.zig");
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

pub fn ComponentHandler3(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        handler: ivsteditcontroller.IComponentHandler = .{ .vtable = &handler_vtable },
        handler3: ivstcontextmenu.IComponentHandler3 = .{ .vtable = &handler3_vtable },
        handler_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        handler3_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        context_menu_count: types.uint32 = 0,
        handler3_add_ref_count: types.uint32 = 0,
        handler3_release_count: types.uint32 = 0,
        last_param_id: vsttypes.ParamID = vsttypes.kNoParamId,

        pub fn asHandler(self: *Self) *ivsteditcontroller.IComponentHandler {
            return &self.handler;
        }

        pub fn asHandler3(self: *Self) *ivstcontextmenu.IComponentHandler3 {
            return &self.handler3;
        }

        fn ownerFromHandler(ptr: *anyopaque) *Self {
            const iface: *ivsteditcontroller.IComponentHandler = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("handler", iface);
        }

        fn ownerFromHandler3(ptr: *anyopaque) *Self {
            const iface: *ivstcontextmenu.IComponentHandler3 = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("handler3", iface);
        }

        fn queryFromHandler(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromHandler(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.handler },
                .{ .iid = &ivsteditcontroller.icomponent_handler_iid, .ptr = &self.handler },
                .{ .iid = &ivstcontextmenu.icomponent_handler3_iid, .ptr = &self.handler3 },
            };
            if (std.mem.eql(u8, requested_iid, &ivstcontextmenu.icomponent_handler3_iid)) {
                return interface_map.queryWithAddRef(&self.handler3, addRefFromHandler3, &entries, requested_iid, out);
            }
            return interface_map.queryWithAddRef(&self.handler, addRefFromHandler, &entries, requested_iid, out);
        }

        fn queryFromHandler3(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromHandler3(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.handler3 },
                .{ .iid = &ivstcontextmenu.icomponent_handler3_iid, .ptr = &self.handler3 },
            };
            return interface_map.queryWithAddRef(&self.handler3, addRefFromHandler3, &entries, requested_iid, out);
        }

        fn addRefFromHandler(ptr: *anyopaque) callconv(.C) types.uint32 {
            return ownerFromHandler(ptr).handler_ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn releaseFromHandler(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&ownerFromHandler(ptr).handler_ref_count, "IComponentHandler");
        }

        fn addRefFromHandler3(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = ownerFromHandler3(ptr);
            self.handler3_add_ref_count += 1;
            return self.handler3_ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn releaseFromHandler3(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = ownerFromHandler3(ptr);
            self.handler3_release_count += 1;
            return funknown.decrementRefCount(&self.handler3_ref_count, "IComponentHandler3");
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

        fn createContextMenu(ptr: *anyopaque, view: ?*iplugview.IPlugView, param_id: ?*const vsttypes.ParamID) callconv(.C) ?*ivstcontextmenu.IContextMenu {
            const self = ownerFromHandler3(ptr);
            self.context_menu_count += 1;
            if (param_id) |id| self.last_param_id = id.*;
            if (@hasDecl(Config, "createContextMenu")) return Config.createContextMenu(self, view, param_id);
            return null;
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

        const handler3_vtable = ivstcontextmenu.IComponentHandler3VTable{
            .queryInterface = queryFromHandler3,
            .addRef = addRefFromHandler3,
            .release = releaseFromHandler3,
            .createContextMenu = createContextMenu,
        };
    };
}

pub fn ComponentHandlerBusAndTime(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        handler: ivsteditcontroller.IComponentHandler = .{ .vtable = &handler_vtable },
        bus_activation: ivsteditcontroller.IComponentHandlerBusActivation = .{ .vtable = &bus_vtable },
        system_time: ivsteditcontroller.IComponentHandlerSystemTime = .{ .vtable = &time_vtable },
        handler_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        bus_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        time_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        bus_activation_count: types.uint32 = 0,
        system_time_count: types.uint32 = 0,
        bus_add_ref_count: types.uint32 = 0,
        time_add_ref_count: types.uint32 = 0,
        bus_release_count: types.uint32 = 0,
        time_release_count: types.uint32 = 0,
        last_media_type: vsttypes.MediaType = 0,
        last_direction: vsttypes.BusDirection = 0,
        last_bus_index: types.int32 = 0,
        last_bus_state: types.TBool = 0,
        last_system_time: types.int64 = 0,

        pub fn asHandler(self: *Self) *ivsteditcontroller.IComponentHandler {
            return &self.handler;
        }

        pub fn asBusActivation(self: *Self) *ivsteditcontroller.IComponentHandlerBusActivation {
            return &self.bus_activation;
        }

        pub fn asSystemTime(self: *Self) *ivsteditcontroller.IComponentHandlerSystemTime {
            return &self.system_time;
        }

        fn ownerFromHandler(ptr: *anyopaque) *Self {
            const iface: *ivsteditcontroller.IComponentHandler = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("handler", iface);
        }

        fn ownerFromBus(ptr: *anyopaque) *Self {
            const iface: *ivsteditcontroller.IComponentHandlerBusActivation = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("bus_activation", iface);
        }

        fn ownerFromTime(ptr: *anyopaque) *Self {
            const iface: *ivsteditcontroller.IComponentHandlerSystemTime = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("system_time", iface);
        }

        fn queryFromHandler(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromHandler(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.handler },
                .{ .iid = &ivsteditcontroller.icomponent_handler_iid, .ptr = &self.handler },
                .{ .iid = &ivsteditcontroller.icomponent_handler_bus_activation_iid, .ptr = &self.bus_activation },
                .{ .iid = &ivsteditcontroller.icomponent_handler_system_time_iid, .ptr = &self.system_time },
            };
            if (std.mem.eql(u8, requested_iid, &ivsteditcontroller.icomponent_handler_bus_activation_iid)) {
                return interface_map.queryWithAddRef(&self.bus_activation, addRefFromBus, &entries, requested_iid, out);
            }
            if (std.mem.eql(u8, requested_iid, &ivsteditcontroller.icomponent_handler_system_time_iid)) {
                return interface_map.queryWithAddRef(&self.system_time, addRefFromTime, &entries, requested_iid, out);
            }
            return interface_map.queryWithAddRef(&self.handler, addRefFromHandler, &entries, requested_iid, out);
        }

        fn queryFromBus(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromBus(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.bus_activation },
                .{ .iid = &ivsteditcontroller.icomponent_handler_bus_activation_iid, .ptr = &self.bus_activation },
            };
            return interface_map.queryWithAddRef(&self.bus_activation, addRefFromBus, &entries, requested_iid, out);
        }

        fn queryFromTime(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromTime(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.system_time },
                .{ .iid = &ivsteditcontroller.icomponent_handler_system_time_iid, .ptr = &self.system_time },
            };
            return interface_map.queryWithAddRef(&self.system_time, addRefFromTime, &entries, requested_iid, out);
        }

        fn addRefFromHandler(ptr: *anyopaque) callconv(.C) types.uint32 {
            return ownerFromHandler(ptr).handler_ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn releaseFromHandler(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&ownerFromHandler(ptr).handler_ref_count, "IComponentHandler");
        }

        fn addRefFromBus(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = ownerFromBus(ptr);
            self.bus_add_ref_count += 1;
            return self.bus_ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn releaseFromBus(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = ownerFromBus(ptr);
            self.bus_release_count += 1;
            return funknown.decrementRefCount(&self.bus_ref_count, "IComponentHandlerBusActivation");
        }

        fn addRefFromTime(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = ownerFromTime(ptr);
            self.time_add_ref_count += 1;
            return self.time_ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn releaseFromTime(ptr: *anyopaque) callconv(.C) types.uint32 {
            const self = ownerFromTime(ptr);
            self.time_release_count += 1;
            return funknown.decrementRefCount(&self.time_ref_count, "IComponentHandlerSystemTime");
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

        fn requestBusActivation(ptr: *anyopaque, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, bus_index: types.int32, state: types.TBool) callconv(.C) types.tresult {
            const self = ownerFromBus(ptr);
            self.bus_activation_count += 1;
            self.last_media_type = media_type;
            self.last_direction = direction;
            self.last_bus_index = bus_index;
            self.last_bus_state = state;
            if (@hasDecl(Config, "requestBusActivation")) return Config.requestBusActivation(self, media_type, direction, bus_index, state);
            return types.kResultOk;
        }

        fn getSystemTime(ptr: *anyopaque, out: *types.int64) callconv(.C) types.tresult {
            const self = ownerFromTime(ptr);
            self.system_time_count += 1;
            const value = if (@hasDecl(Config, "system_time")) Config.system_time else 0;
            self.last_system_time = value;
            out.* = value;
            if (@hasDecl(Config, "getSystemTime")) return Config.getSystemTime(self, out);
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

        const bus_vtable = ivsteditcontroller.IComponentHandlerBusActivationVTable{
            .queryInterface = queryFromBus,
            .addRef = addRefFromBus,
            .release = releaseFromBus,
            .requestBusActivation = requestBusActivation,
        };

        const time_vtable = ivsteditcontroller.IComponentHandlerSystemTimeVTable{
            .queryInterface = queryFromTime,
            .addRef = addRefFromTime,
            .release = releaseFromTime,
            .getSystemTime = getSystemTime,
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

test "component handler 3 exposes context menu extension" {
    const Handler = ComponentHandler3(struct {});
    var handler = Handler{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.queryInterface(handler.asHandler(), &ivstcontextmenu.icomponent_handler3_iid, &queried));
    try std.testing.expect(queried != null);
    const handler3: *ivstcontextmenu.IComponentHandler3 = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.handler3_add_ref_count);
    try std.testing.expectEqual(@as(?*ivstcontextmenu.IContextMenu, null), handler3.vtable.createContextMenu(handler3, null, null));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.context_menu_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler3.vtable.release(handler3));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.handler3_release_count);
}

test "component handler exposes bus activation and system time extensions" {
    const Handler = ComponentHandlerBusAndTime(struct {
        pub const system_time: types.int64 = 12345;
    });
    var handler = Handler{};
    var bus_out: ?*anyopaque = null;
    var time_out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.queryInterface(handler.asHandler(), &ivsteditcontroller.icomponent_handler_bus_activation_iid, &bus_out));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.queryInterface(handler.asHandler(), &ivsteditcontroller.icomponent_handler_system_time_iid, &time_out));
    try std.testing.expect(bus_out != null);
    try std.testing.expect(time_out != null);

    const bus: *ivsteditcontroller.IComponentHandlerBusActivation = @ptrCast(@alignCast(bus_out.?));
    const time: *ivsteditcontroller.IComponentHandlerSystemTime = @ptrCast(@alignCast(time_out.?));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.bus_add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.time_add_ref_count);

    try std.testing.expectEqual(types.kResultOk, bus.vtable.requestBusActivation(bus, 1, 0, 2, 1));
    var value: types.int64 = 0;
    try std.testing.expectEqual(types.kResultOk, time.vtable.getSystemTime(time, &value));
    try std.testing.expectEqual(@as(types.int64, 12345), value);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.bus_activation_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.system_time_count);

    try std.testing.expectEqual(@as(types.uint32, 1), bus.vtable.release(bus));
    try std.testing.expectEqual(@as(types.uint32, 1), time.vtable.release(time));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.bus_release_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.time_release_count);
}
