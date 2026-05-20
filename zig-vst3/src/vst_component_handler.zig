const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const ivstcontextmenu = @import("pluginterfaces/vst/ivstcontextmenu.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const ivstunits = @import("pluginterfaces/vst/ivstunits.zig");
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
        add_ref_count: types.uint32 = 0,
        release_count: types.uint32 = 0,
        last_param_id: vsttypes.ParamID = vsttypes.kNoParamId,
        last_value: vsttypes.ParamValue = -1,
        last_restart_flags: types.int32 = 0,

        pub fn asHandler(self: *Self) *ivsteditcontroller.IComponentHandler {
            return &self.iface;
        }

        fn recordBeginEdit(self: *Self, id: vsttypes.ParamID) void {
            self.begin_count +|= 1;
            self.last_param_id = id;
        }

        fn recordPerformEdit(self: *Self, id: vsttypes.ParamID, value: vsttypes.ParamValue) void {
            self.perform_count +|= 1;
            self.last_param_id = id;
            self.last_value = value;
        }

        fn recordEndEdit(self: *Self, id: vsttypes.ParamID) void {
            self.end_count +|= 1;
            self.last_param_id = id;
        }

        fn recordRestart(self: *Self, flags: types.int32) void {
            self.restart_count +|= 1;
            self.last_restart_flags = flags;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivsteditcontroller.IComponentHandler = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn queryInterface(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.iface },
                .{ .iid = &ivsteditcontroller.icomponent_handler_iid, .ptr = &self.iface },
            };
            return interface_map.queryWithAddRef(&self.iface, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = owner(ptr);
            self.add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = owner(ptr);
            self.release_count +|= 1;
            return funknown.decrementRefCount(&self.ref_count, "IComponentHandler");
        }

        fn beginEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.recordBeginEdit(id);
            if (@hasDecl(Config, "beginEdit")) return Config.beginEdit(self, id);
            return types.kResultOk;
        }

        fn performEdit(ptr: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.recordPerformEdit(id, value);
            if (@hasDecl(Config, "performEdit")) return Config.performEdit(self, id, value);
            return types.kResultOk;
        }

        fn endEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.recordEndEdit(id);
            if (@hasDecl(Config, "endEdit")) return Config.endEdit(self, id);
            return types.kResultOk;
        }

        fn restartComponent(ptr: *anyopaque, flags: types.int32) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.recordRestart(flags);
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
        begin_count: types.uint32 = 0,
        perform_count: types.uint32 = 0,
        end_count: types.uint32 = 0,
        restart_count: types.uint32 = 0,
        dirty_count: types.uint32 = 0,
        open_editor_count: types.uint32 = 0,
        start_group_count: types.uint32 = 0,
        finish_group_count: types.uint32 = 0,
        handler2_add_ref_count: types.uint32 = 0,
        handler2_release_count: types.uint32 = 0,
        last_param_id: vsttypes.ParamID = vsttypes.kNoParamId,
        last_value: vsttypes.ParamValue = -1,
        last_restart_flags: types.int32 = 0,
        last_dirty_state: types.TBool = 0,
        last_editor_name: types.FIDString = "",

        fn recordBeginEdit(self: *Self, id: vsttypes.ParamID) void {
            self.begin_count +|= 1;
            self.last_param_id = id;
        }

        fn recordPerformEdit(self: *Self, id: vsttypes.ParamID, value: vsttypes.ParamValue) void {
            self.perform_count +|= 1;
            self.last_param_id = id;
            self.last_value = value;
        }

        fn recordEndEdit(self: *Self, id: vsttypes.ParamID) void {
            self.end_count +|= 1;
            self.last_param_id = id;
        }

        fn recordRestart(self: *Self, flags: types.int32) void {
            self.restart_count +|= 1;
            self.last_restart_flags = flags;
        }

        pub fn asHandler(self: *Self) *ivsteditcontroller.IComponentHandler {
            return &self.handler;
        }

        pub fn asHandler2(self: *Self) *ivsteditcontroller.IComponentHandler2 {
            return &self.handler2;
        }

        fn recordDirty(self: *Self, state: types.TBool) void {
            self.dirty_count +|= 1;
            self.last_dirty_state = state;
        }

        fn recordOpenEditor(self: *Self, name: types.FIDString) void {
            self.open_editor_count +|= 1;
            self.last_editor_name = name;
        }

        const ownerFromHandler = interface_map.ownerFromField(Self, ivsteditcontroller.IComponentHandler, "handler");
        const ownerFromHandler2 = interface_map.ownerFromField(Self, ivsteditcontroller.IComponentHandler2, "handler2");

        fn queryFromHandler(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
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

        fn queryFromHandler2(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromHandler2(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.handler2 },
                .{ .iid = &ivsteditcontroller.icomponent_handler2_iid, .ptr = &self.handler2 },
            };
            return interface_map.queryWithAddRef(&self.handler2, addRefFromHandler2, &entries, requested_iid, out);
        }

        fn addRefFromHandler(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromHandler(ptr).handler_ref_count, "FUnknown");
        }

        fn releaseFromHandler(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromHandler(ptr).handler_ref_count, "IComponentHandler");
        }

        fn addRefFromHandler2(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromHandler2(ptr);
            self.handler2_add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.handler2_ref_count, "FUnknown");
        }

        fn releaseFromHandler2(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromHandler2(ptr);
            self.handler2_release_count +|= 1;
            return funknown.decrementRefCount(&self.handler2_ref_count, "IComponentHandler2");
        }

        fn beginEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordBeginEdit(id);
            if (@hasDecl(Config, "beginEdit")) return Config.beginEdit(self, id);
            return types.kResultOk;
        }

        fn performEdit(ptr: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordPerformEdit(id, value);
            if (@hasDecl(Config, "performEdit")) return Config.performEdit(self, id, value);
            return types.kResultOk;
        }

        fn endEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordEndEdit(id);
            if (@hasDecl(Config, "endEdit")) return Config.endEdit(self, id);
            return types.kResultOk;
        }

        fn restartComponent(ptr: *anyopaque, flags: types.int32) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordRestart(flags);
            if (@hasDecl(Config, "restartComponent")) return Config.restartComponent(self, flags);
            return types.kResultOk;
        }

        fn setDirty(ptr: *anyopaque, state: types.TBool) callconv(.c) types.tresult {
            const self = ownerFromHandler2(ptr);
            self.recordDirty(state);
            if (@hasDecl(Config, "setDirty")) return Config.setDirty(self, state);
            return types.kResultOk;
        }

        fn requestOpenEditor(ptr: *anyopaque, name: types.FIDString) callconv(.c) types.tresult {
            const self = ownerFromHandler2(ptr);
            self.recordOpenEditor(name);
            if (@hasDecl(Config, "requestOpenEditor")) return Config.requestOpenEditor(self, name);
            return types.kResultOk;
        }

        fn startGroupEdit(ptr: *anyopaque) callconv(.c) types.tresult {
            const self = ownerFromHandler2(ptr);
            self.start_group_count +|= 1;
            if (@hasDecl(Config, "startGroupEdit")) return Config.startGroupEdit(self);
            return types.kResultOk;
        }

        fn finishGroupEdit(ptr: *anyopaque) callconv(.c) types.tresult {
            const self = ownerFromHandler2(ptr);
            self.finish_group_count +|= 1;
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
        begin_count: types.uint32 = 0,
        perform_count: types.uint32 = 0,
        end_count: types.uint32 = 0,
        restart_count: types.uint32 = 0,
        context_menu_count: types.uint32 = 0,
        handler3_add_ref_count: types.uint32 = 0,
        handler3_release_count: types.uint32 = 0,
        last_param_id: vsttypes.ParamID = vsttypes.kNoParamId,
        last_value: vsttypes.ParamValue = -1,
        last_restart_flags: types.int32 = 0,

        fn recordBeginEdit(self: *Self, id: vsttypes.ParamID) void {
            self.begin_count +|= 1;
            self.last_param_id = id;
        }

        fn recordPerformEdit(self: *Self, id: vsttypes.ParamID, value: vsttypes.ParamValue) void {
            self.perform_count +|= 1;
            self.last_param_id = id;
            self.last_value = value;
        }

        fn recordEndEdit(self: *Self, id: vsttypes.ParamID) void {
            self.end_count +|= 1;
            self.last_param_id = id;
        }

        fn recordRestart(self: *Self, flags: types.int32) void {
            self.restart_count +|= 1;
            self.last_restart_flags = flags;
        }

        pub fn asHandler(self: *Self) *ivsteditcontroller.IComponentHandler {
            return &self.handler;
        }

        pub fn asHandler3(self: *Self) *ivstcontextmenu.IComponentHandler3 {
            return &self.handler3;
        }

        fn recordContextMenuRequest(self: *Self, param_id: ?*const vsttypes.ParamID) void {
            self.context_menu_count +|= 1;
            if (param_id) |id| self.last_param_id = id.*;
        }

        const ownerFromHandler = interface_map.ownerFromField(Self, ivsteditcontroller.IComponentHandler, "handler");
        const ownerFromHandler3 = interface_map.ownerFromField(Self, ivstcontextmenu.IComponentHandler3, "handler3");

        fn queryFromHandler(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
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

        fn queryFromHandler3(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromHandler3(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.handler3 },
                .{ .iid = &ivstcontextmenu.icomponent_handler3_iid, .ptr = &self.handler3 },
            };
            return interface_map.queryWithAddRef(&self.handler3, addRefFromHandler3, &entries, requested_iid, out);
        }

        fn addRefFromHandler(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromHandler(ptr).handler_ref_count, "FUnknown");
        }

        fn releaseFromHandler(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromHandler(ptr).handler_ref_count, "IComponentHandler");
        }

        fn addRefFromHandler3(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromHandler3(ptr);
            self.handler3_add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.handler3_ref_count, "FUnknown");
        }

        fn releaseFromHandler3(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromHandler3(ptr);
            self.handler3_release_count +|= 1;
            return funknown.decrementRefCount(&self.handler3_ref_count, "IComponentHandler3");
        }

        fn beginEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordBeginEdit(id);
            if (@hasDecl(Config, "beginEdit")) return Config.beginEdit(self, id);
            return types.kResultOk;
        }

        fn performEdit(ptr: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordPerformEdit(id, value);
            if (@hasDecl(Config, "performEdit")) return Config.performEdit(self, id, value);
            return types.kResultOk;
        }

        fn endEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordEndEdit(id);
            if (@hasDecl(Config, "endEdit")) return Config.endEdit(self, id);
            return types.kResultOk;
        }

        fn restartComponent(ptr: *anyopaque, flags: types.int32) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordRestart(flags);
            if (@hasDecl(Config, "restartComponent")) return Config.restartComponent(self, flags);
            return types.kResultOk;
        }

        fn createContextMenu(ptr: *anyopaque, view: ?*iplugview.IPlugView, param_id: ?*const vsttypes.ParamID) callconv(.c) ?*ivstcontextmenu.IContextMenu {
            const self = ownerFromHandler3(ptr);
            self.recordContextMenuRequest(param_id);
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
        begin_count: types.uint32 = 0,
        perform_count: types.uint32 = 0,
        end_count: types.uint32 = 0,
        restart_count: types.uint32 = 0,
        bus_activation_count: types.uint32 = 0,
        system_time_count: types.uint32 = 0,
        bus_add_ref_count: types.uint32 = 0,
        time_add_ref_count: types.uint32 = 0,
        bus_release_count: types.uint32 = 0,
        time_release_count: types.uint32 = 0,
        last_param_id: vsttypes.ParamID = vsttypes.kNoParamId,
        last_value: vsttypes.ParamValue = -1,
        last_restart_flags: types.int32 = 0,
        last_media_type: vsttypes.MediaType = 0,
        last_direction: vsttypes.BusDirection = 0,
        last_bus_index: types.int32 = 0,
        last_bus_state: types.TBool = 0,
        last_system_time: types.int64 = 0,

        fn recordBeginEdit(self: *Self, id: vsttypes.ParamID) void {
            self.begin_count +|= 1;
            self.last_param_id = id;
        }

        fn recordPerformEdit(self: *Self, id: vsttypes.ParamID, value: vsttypes.ParamValue) void {
            self.perform_count +|= 1;
            self.last_param_id = id;
            self.last_value = value;
        }

        fn recordEndEdit(self: *Self, id: vsttypes.ParamID) void {
            self.end_count +|= 1;
            self.last_param_id = id;
        }

        fn recordRestart(self: *Self, flags: types.int32) void {
            self.restart_count +|= 1;
            self.last_restart_flags = flags;
        }

        pub fn asHandler(self: *Self) *ivsteditcontroller.IComponentHandler {
            return &self.handler;
        }

        pub fn asBusActivation(self: *Self) *ivsteditcontroller.IComponentHandlerBusActivation {
            return &self.bus_activation;
        }

        pub fn asSystemTime(self: *Self) *ivsteditcontroller.IComponentHandlerSystemTime {
            return &self.system_time;
        }

        fn recordBusActivation(self: *Self, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, bus_index: types.int32, state: types.TBool) void {
            self.bus_activation_count +|= 1;
            self.last_media_type = media_type;
            self.last_direction = direction;
            self.last_bus_index = bus_index;
            self.last_bus_state = state;
        }

        fn startSystemTimeRequest(self: *Self) types.int64 {
            self.system_time_count +|= 1;
            const value = if (@hasDecl(Config, "system_time")) Config.system_time else 0;
            self.last_system_time = value;
            return value;
        }

        fn acceptSystemTime(self: *Self, value: types.int64) void {
            self.last_system_time = value;
        }

        const ownerFromHandler = interface_map.ownerFromField(Self, ivsteditcontroller.IComponentHandler, "handler");
        const ownerFromBus = interface_map.ownerFromField(Self, ivsteditcontroller.IComponentHandlerBusActivation, "bus_activation");
        const ownerFromTime = interface_map.ownerFromField(Self, ivsteditcontroller.IComponentHandlerSystemTime, "system_time");

        fn queryFromHandler(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
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

        fn queryFromBus(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromBus(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.bus_activation },
                .{ .iid = &ivsteditcontroller.icomponent_handler_bus_activation_iid, .ptr = &self.bus_activation },
            };
            return interface_map.queryWithAddRef(&self.bus_activation, addRefFromBus, &entries, requested_iid, out);
        }

        fn queryFromTime(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromTime(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.system_time },
                .{ .iid = &ivsteditcontroller.icomponent_handler_system_time_iid, .ptr = &self.system_time },
            };
            return interface_map.queryWithAddRef(&self.system_time, addRefFromTime, &entries, requested_iid, out);
        }

        fn addRefFromHandler(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromHandler(ptr).handler_ref_count, "FUnknown");
        }

        fn releaseFromHandler(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromHandler(ptr).handler_ref_count, "IComponentHandler");
        }

        fn addRefFromBus(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromBus(ptr);
            self.bus_add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.bus_ref_count, "FUnknown");
        }

        fn releaseFromBus(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromBus(ptr);
            self.bus_release_count +|= 1;
            return funknown.decrementRefCount(&self.bus_ref_count, "IComponentHandlerBusActivation");
        }

        fn addRefFromTime(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromTime(ptr);
            self.time_add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.time_ref_count, "FUnknown");
        }

        fn releaseFromTime(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromTime(ptr);
            self.time_release_count +|= 1;
            return funknown.decrementRefCount(&self.time_ref_count, "IComponentHandlerSystemTime");
        }

        fn beginEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordBeginEdit(id);
            if (@hasDecl(Config, "beginEdit")) return Config.beginEdit(self, id);
            return types.kResultOk;
        }

        fn performEdit(ptr: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordPerformEdit(id, value);
            if (@hasDecl(Config, "performEdit")) return Config.performEdit(self, id, value);
            return types.kResultOk;
        }

        fn endEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordEndEdit(id);
            if (@hasDecl(Config, "endEdit")) return Config.endEdit(self, id);
            return types.kResultOk;
        }

        fn restartComponent(ptr: *anyopaque, flags: types.int32) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordRestart(flags);
            if (@hasDecl(Config, "restartComponent")) return Config.restartComponent(self, flags);
            return types.kResultOk;
        }

        fn requestBusActivation(ptr: *anyopaque, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, bus_index: types.int32, state: types.TBool) callconv(.c) types.tresult {
            const self = ownerFromBus(ptr);
            self.recordBusActivation(media_type, direction, bus_index, state);
            if (@hasDecl(Config, "requestBusActivation")) return Config.requestBusActivation(self, media_type, direction, bus_index, state);
            return types.kResultOk;
        }

        fn failSystemTime(out: *types.int64, fallback: types.int64, result: types.tresult) types.tresult {
            out.* = fallback;
            return result;
        }

        fn getSystemTime(ptr: *anyopaque, out: *types.int64) callconv(.c) types.tresult {
            const self = ownerFromTime(ptr);
            const value = self.startSystemTimeRequest();
            out.* = value;
            if (@hasDecl(Config, "getSystemTime")) {
                const result = Config.getSystemTime(self, out);
                if (result != types.kResultOk) return failSystemTime(out, value, result);
                self.acceptSystemTime(out.*);
                return result;
            }
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

pub fn ComponentHandlerProgress(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        handler: ivsteditcontroller.IComponentHandler = .{ .vtable = &handler_vtable },
        progress: ivsteditcontroller.IProgress = .{ .vtable = &progress_vtable },
        handler_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        progress_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        begin_count: types.uint32 = 0,
        perform_count: types.uint32 = 0,
        end_count: types.uint32 = 0,
        restart_count: types.uint32 = 0,
        start_count: types.uint32 = 0,
        update_count: types.uint32 = 0,
        finish_count: types.uint32 = 0,
        progress_add_ref_count: types.uint32 = 0,
        progress_release_count: types.uint32 = 0,
        last_param_id: vsttypes.ParamID = vsttypes.kNoParamId,
        last_restart_flags: types.int32 = 0,
        last_type: types.uint32 = 0,
        last_id: ivsteditcontroller.ProgressID = 0,
        last_value: vsttypes.ParamValue = 0,

        fn recordBeginEdit(self: *Self, id: vsttypes.ParamID) void {
            self.begin_count +|= 1;
            self.last_param_id = id;
        }

        fn recordPerformEdit(self: *Self, id: vsttypes.ParamID, value: vsttypes.ParamValue) void {
            self.perform_count +|= 1;
            self.last_param_id = id;
            self.last_value = value;
        }

        fn recordEndEdit(self: *Self, id: vsttypes.ParamID) void {
            self.end_count +|= 1;
            self.last_param_id = id;
        }

        fn recordRestart(self: *Self, flags: types.int32) void {
            self.restart_count +|= 1;
            self.last_restart_flags = flags;
        }

        pub fn asHandler(self: *Self) *ivsteditcontroller.IComponentHandler {
            return &self.handler;
        }

        pub fn asProgress(self: *Self) *ivsteditcontroller.IProgress {
            return &self.progress;
        }

        fn startProgress(self: *Self, progress_type: types.uint32, out: *ivsteditcontroller.ProgressID) ivsteditcontroller.ProgressID {
            self.start_count +|= 1;
            self.last_type = progress_type;
            const id = if (@hasDecl(Config, "progress_id")) Config.progress_id else 1;
            out.* = id;
            self.last_id = id;
            return id;
        }

        fn acceptProgressStart(self: *Self, id: ivsteditcontroller.ProgressID) void {
            self.last_id = id;
        }

        fn recordProgressUpdate(self: *Self, id: ivsteditcontroller.ProgressID, value: vsttypes.ParamValue) void {
            self.update_count +|= 1;
            self.last_id = id;
            self.last_value = value;
        }

        fn recordProgressFinish(self: *Self, id: ivsteditcontroller.ProgressID) void {
            self.finish_count +|= 1;
            self.last_id = id;
        }

        const ownerFromHandler = interface_map.ownerFromField(Self, ivsteditcontroller.IComponentHandler, "handler");
        const ownerFromProgress = interface_map.ownerFromField(Self, ivsteditcontroller.IProgress, "progress");

        fn queryFromHandler(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.handler },
                .{ .iid = &ivsteditcontroller.icomponent_handler_iid, .ptr = &self.handler },
                .{ .iid = &ivsteditcontroller.iprogress_iid, .ptr = &self.progress },
            };
            if (std.mem.eql(u8, requested_iid, &ivsteditcontroller.iprogress_iid)) {
                return interface_map.queryWithAddRef(&self.progress, addRefFromProgress, &entries, requested_iid, out);
            }
            return interface_map.queryWithAddRef(&self.handler, addRefFromHandler, &entries, requested_iid, out);
        }

        fn queryFromProgress(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromProgress(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.progress },
                .{ .iid = &ivsteditcontroller.iprogress_iid, .ptr = &self.progress },
            };
            return interface_map.queryWithAddRef(&self.progress, addRefFromProgress, &entries, requested_iid, out);
        }

        fn addRefFromHandler(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromHandler(ptr).handler_ref_count, "FUnknown");
        }

        fn releaseFromHandler(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromHandler(ptr).handler_ref_count, "IComponentHandler");
        }

        fn addRefFromProgress(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromProgress(ptr);
            self.progress_add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.progress_ref_count, "FUnknown");
        }

        fn releaseFromProgress(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromProgress(ptr);
            self.progress_release_count +|= 1;
            return funknown.decrementRefCount(&self.progress_ref_count, "IProgress");
        }

        fn beginEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordBeginEdit(id);
            if (@hasDecl(Config, "beginEdit")) return Config.beginEdit(self, id);
            return types.kResultOk;
        }

        fn performEdit(ptr: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordPerformEdit(id, value);
            if (@hasDecl(Config, "performEdit")) return Config.performEdit(self, id, value);
            return types.kResultOk;
        }

        fn endEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordEndEdit(id);
            if (@hasDecl(Config, "endEdit")) return Config.endEdit(self, id);
            return types.kResultOk;
        }

        fn restartComponent(ptr: *anyopaque, flags: types.int32) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordRestart(flags);
            if (@hasDecl(Config, "restartComponent")) return Config.restartComponent(self, flags);
            return types.kResultOk;
        }

        fn failStartedProgress(out: *ivsteditcontroller.ProgressID, fallback: ivsteditcontroller.ProgressID, result: types.tresult) types.tresult {
            out.* = fallback;
            return result;
        }

        fn start(ptr: *anyopaque, progress_type: types.uint32, description: ?[*]const types.char16, out: *ivsteditcontroller.ProgressID) callconv(.c) types.tresult {
            const self = ownerFromProgress(ptr);
            const id = self.startProgress(progress_type, out);
            if (@hasDecl(Config, "start")) {
                const result = Config.start(self, progress_type, description, out);
                if (result != types.kResultOk) return failStartedProgress(out, id, result);
                self.acceptProgressStart(out.*);
                return result;
            }
            return types.kResultOk;
        }

        fn update(ptr: *anyopaque, id: ivsteditcontroller.ProgressID, value: vsttypes.ParamValue) callconv(.c) types.tresult {
            const self = ownerFromProgress(ptr);
            self.recordProgressUpdate(id, value);
            if (@hasDecl(Config, "update")) return Config.update(self, id, value);
            return types.kResultOk;
        }

        fn finish(ptr: *anyopaque, id: ivsteditcontroller.ProgressID) callconv(.c) types.tresult {
            const self = ownerFromProgress(ptr);
            self.recordProgressFinish(id);
            if (@hasDecl(Config, "finish")) return Config.finish(self, id);
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

        const progress_vtable = ivsteditcontroller.IProgressVTable{
            .queryInterface = queryFromProgress,
            .addRef = addRefFromProgress,
            .release = releaseFromProgress,
            .start = start,
            .update = update,
            .finish = finish,
        };
    };
}

pub fn ComponentHandlerUnits(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        handler: ivsteditcontroller.IComponentHandler = .{ .vtable = &handler_vtable },
        unit_handler: ivstunits.IUnitHandler = .{ .vtable = &unit_vtable },
        unit_handler2: ivstunits.IUnitHandler2 = .{ .vtable = &unit2_vtable },
        handler_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        unit_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        unit2_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        begin_count: types.uint32 = 0,
        perform_count: types.uint32 = 0,
        end_count: types.uint32 = 0,
        restart_count: types.uint32 = 0,
        unit_selection_count: types.uint32 = 0,
        program_list_count: types.uint32 = 0,
        unit_by_bus_count: types.uint32 = 0,
        unit_add_ref_count: types.uint32 = 0,
        unit2_add_ref_count: types.uint32 = 0,
        unit_release_count: types.uint32 = 0,
        unit2_release_count: types.uint32 = 0,
        last_param_id: vsttypes.ParamID = vsttypes.kNoParamId,
        last_value: vsttypes.ParamValue = -1,
        last_restart_flags: types.int32 = 0,
        last_unit_id: vsttypes.UnitID = ivstunits.kNoParentUnitId,
        last_program_list_id: vsttypes.ProgramListID = ivstunits.kNoProgramListId,
        last_program_index: types.int32 = 0,

        fn recordBeginEdit(self: *Self, id: vsttypes.ParamID) void {
            self.begin_count +|= 1;
            self.last_param_id = id;
        }

        fn recordPerformEdit(self: *Self, id: vsttypes.ParamID, value: vsttypes.ParamValue) void {
            self.perform_count +|= 1;
            self.last_param_id = id;
            self.last_value = value;
        }

        fn recordEndEdit(self: *Self, id: vsttypes.ParamID) void {
            self.end_count +|= 1;
            self.last_param_id = id;
        }

        fn recordRestart(self: *Self, flags: types.int32) void {
            self.restart_count +|= 1;
            self.last_restart_flags = flags;
        }

        pub fn asHandler(self: *Self) *ivsteditcontroller.IComponentHandler {
            return &self.handler;
        }

        pub fn asUnitHandler(self: *Self) *ivstunits.IUnitHandler {
            return &self.unit_handler;
        }

        pub fn asUnitHandler2(self: *Self) *ivstunits.IUnitHandler2 {
            return &self.unit_handler2;
        }

        fn recordUnitSelection(self: *Self, unit_id: vsttypes.UnitID) void {
            self.unit_selection_count +|= 1;
            self.last_unit_id = unit_id;
        }

        fn recordProgramListChange(self: *Self, list_id: vsttypes.ProgramListID, program_index: types.int32) void {
            self.program_list_count +|= 1;
            self.last_program_list_id = list_id;
            self.last_program_index = program_index;
        }

        const ownerFromHandler = interface_map.ownerFromField(Self, ivsteditcontroller.IComponentHandler, "handler");
        const ownerFromUnit = interface_map.ownerFromField(Self, ivstunits.IUnitHandler, "unit_handler");
        const ownerFromUnit2 = interface_map.ownerFromField(Self, ivstunits.IUnitHandler2, "unit_handler2");

        fn queryFromHandler(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.handler },
                .{ .iid = &ivsteditcontroller.icomponent_handler_iid, .ptr = &self.handler },
                .{ .iid = &ivstunits.iunit_handler_iid, .ptr = &self.unit_handler },
                .{ .iid = &ivstunits.iunit_handler2_iid, .ptr = &self.unit_handler2 },
            };
            if (std.mem.eql(u8, requested_iid, &ivstunits.iunit_handler_iid)) {
                return interface_map.queryWithAddRef(&self.unit_handler, addRefFromUnit, &entries, requested_iid, out);
            }
            if (std.mem.eql(u8, requested_iid, &ivstunits.iunit_handler2_iid)) {
                return interface_map.queryWithAddRef(&self.unit_handler2, addRefFromUnit2, &entries, requested_iid, out);
            }
            return interface_map.queryWithAddRef(&self.handler, addRefFromHandler, &entries, requested_iid, out);
        }

        fn queryFromUnit(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromUnit(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.unit_handler },
                .{ .iid = &ivstunits.iunit_handler_iid, .ptr = &self.unit_handler },
            };
            return interface_map.queryWithAddRef(&self.unit_handler, addRefFromUnit, &entries, requested_iid, out);
        }

        fn queryFromUnit2(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromUnit2(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.unit_handler2 },
                .{ .iid = &ivstunits.iunit_handler2_iid, .ptr = &self.unit_handler2 },
            };
            return interface_map.queryWithAddRef(&self.unit_handler2, addRefFromUnit2, &entries, requested_iid, out);
        }

        fn addRefFromHandler(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromHandler(ptr).handler_ref_count, "FUnknown");
        }

        fn releaseFromHandler(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromHandler(ptr).handler_ref_count, "IComponentHandler");
        }

        fn addRefFromUnit(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromUnit(ptr);
            self.unit_add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.unit_ref_count, "FUnknown");
        }

        fn releaseFromUnit(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromUnit(ptr);
            self.unit_release_count +|= 1;
            return funknown.decrementRefCount(&self.unit_ref_count, "IUnitHandler");
        }

        fn addRefFromUnit2(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromUnit2(ptr);
            self.unit2_add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.unit2_ref_count, "FUnknown");
        }

        fn releaseFromUnit2(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromUnit2(ptr);
            self.unit2_release_count +|= 1;
            return funknown.decrementRefCount(&self.unit2_ref_count, "IUnitHandler2");
        }

        fn beginEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordBeginEdit(id);
            if (@hasDecl(Config, "beginEdit")) return Config.beginEdit(self, id);
            return types.kResultOk;
        }

        fn performEdit(ptr: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordPerformEdit(id, value);
            if (@hasDecl(Config, "performEdit")) return Config.performEdit(self, id, value);
            return types.kResultOk;
        }

        fn endEdit(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordEndEdit(id);
            if (@hasDecl(Config, "endEdit")) return Config.endEdit(self, id);
            return types.kResultOk;
        }

        fn restartComponent(ptr: *anyopaque, flags: types.int32) callconv(.c) types.tresult {
            const self = ownerFromHandler(ptr);
            self.recordRestart(flags);
            if (@hasDecl(Config, "restartComponent")) return Config.restartComponent(self, flags);
            return types.kResultOk;
        }

        fn notifyUnitSelection(ptr: *anyopaque, unit_id: vsttypes.UnitID) callconv(.c) types.tresult {
            const self = ownerFromUnit(ptr);
            self.recordUnitSelection(unit_id);
            if (@hasDecl(Config, "notifyUnitSelection")) return Config.notifyUnitSelection(self, unit_id);
            return types.kResultOk;
        }

        fn notifyProgramListChange(ptr: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32) callconv(.c) types.tresult {
            const self = ownerFromUnit(ptr);
            self.recordProgramListChange(list_id, program_index);
            if (@hasDecl(Config, "notifyProgramListChange")) return Config.notifyProgramListChange(self, list_id, program_index);
            return types.kResultOk;
        }

        fn notifyUnitByBusChange(ptr: *anyopaque) callconv(.c) types.tresult {
            const self = ownerFromUnit2(ptr);
            self.unit_by_bus_count +|= 1;
            if (@hasDecl(Config, "notifyUnitByBusChange")) return Config.notifyUnitByBusChange(self);
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

        const unit_vtable = ivstunits.IUnitHandlerVTable{
            .queryInterface = queryFromUnit,
            .addRef = addRefFromUnit,
            .release = releaseFromUnit,
            .notifyUnitSelection = notifyUnitSelection,
            .notifyProgramListChange = notifyProgramListChange,
        };

        const unit2_vtable = ivstunits.IUnitHandler2VTable{
            .queryInterface = queryFromUnit2,
            .addRef = addRefFromUnit2,
            .release = releaseFromUnit2,
            .notifyUnitByBusChange = notifyUnitByBusChange,
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

test "component handler records delegated automation failures" {
    const Handler = ComponentHandler(struct {
        pub fn beginEdit(self: anytype, id: vsttypes.ParamID) types.tresult {
            _ = self;
            return if (id == 9) types.kResultFalse else types.kResultOk;
        }

        pub fn performEdit(self: anytype, id: vsttypes.ParamID, value: vsttypes.ParamValue) types.tresult {
            _ = self;
            return if (id == 9 and value == 0.5) types.kResultFalse else types.kResultOk;
        }

        pub fn endEdit(self: anytype, id: vsttypes.ParamID) types.tresult {
            _ = self;
            return if (id == 9) types.kResultFalse else types.kResultOk;
        }

        pub fn restartComponent(self: anytype, flags: types.int32) types.tresult {
            _ = self;
            return if (flags == 3) types.kResultFalse else types.kResultOk;
        }
    });
    var handler = Handler{};

    try std.testing.expectEqual(types.kResultFalse, handler.asHandler().vtable.beginEdit(handler.asHandler(), 9));
    try std.testing.expectEqual(types.kResultFalse, handler.asHandler().vtable.performEdit(handler.asHandler(), 9, 0.5));
    try std.testing.expectEqual(types.kResultFalse, handler.asHandler().vtable.endEdit(handler.asHandler(), 9));
    try std.testing.expectEqual(types.kResultFalse, handler.asHandler().vtable.restartComponent(handler.asHandler(), 3));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.begin_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.perform_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.end_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.restart_count);
    try std.testing.expectEqual(@as(vsttypes.ParamID, 9), handler.last_param_id);
    try std.testing.expectEqual(@as(types.int32, 3), handler.last_restart_flags);
}

test "component handler clears unsupported query outputs" {
    const Handler = ComponentHandler(struct {});
    var handler = Handler{};
    const iface = handler.asHandler();
    var out: ?*anyopaque = iface;

    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &out));
    try std.testing.expectEqual(@as(?*anyopaque, null), out);
    try std.testing.expectEqual(@as(types.uint32, 0), handler.add_ref_count);
}

test "component handler 2 exposes extension and records callbacks" {
    const Handler = ComponentHandler2(struct {});
    var handler = Handler{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.beginEdit(handler.asHandler(), 9));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.performEdit(handler.asHandler(), 9, 0.5));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.endEdit(handler.asHandler(), 9));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.restartComponent(handler.asHandler(), 3));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.begin_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.perform_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.end_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.restart_count);
    try std.testing.expectEqual(@as(vsttypes.ParamID, 9), handler.last_param_id);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), handler.last_value);
    try std.testing.expectEqual(@as(types.int32, 3), handler.last_restart_flags);

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

test "component handler 2 clears unsupported query outputs from both interfaces" {
    const Handler = ComponentHandler2(struct {});
    var handler = Handler{};
    var handler_out: ?*anyopaque = handler.asHandler();
    var handler2_out: ?*anyopaque = handler.asHandler2();

    try std.testing.expectEqual(types.kNoInterface, handler.asHandler().vtable.queryInterface(handler.asHandler(), &tuid.zero, &handler_out));
    try std.testing.expectEqual(@as(?*anyopaque, null), handler_out);

    try std.testing.expectEqual(types.kNoInterface, handler.asHandler2().vtable.queryInterface(handler.asHandler2(), &ivsteditcontroller.icomponent_handler_iid, &handler2_out));
    try std.testing.expectEqual(@as(?*anyopaque, null), handler2_out);
    try std.testing.expectEqual(@as(types.uint32, 0), handler.handler2_add_ref_count);
}

test "component handler secondary interfaces expose their own unknown identity" {
    const Handler2 = ComponentHandler2(struct {});
    const Handler3 = ComponentHandler3(struct {});
    const BusAndTime = ComponentHandlerBusAndTime(struct {});
    const Progress = ComponentHandlerProgress(struct {});
    const Units = ComponentHandlerUnits(struct {});

    var handler2 = Handler2{};
    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, handler2.asHandler2().vtable.queryInterface(handler2.asHandler2(), &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, handler2.asHandler2()), queried);
    try std.testing.expectEqual(@as(types.uint32, 1), handler2.handler2_add_ref_count);
    const handler2_unknown: *ivsteditcontroller.IComponentHandler2 = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), handler2_unknown.vtable.release(handler2_unknown));

    var handler3 = Handler3{};
    queried = null;
    try std.testing.expectEqual(types.kResultOk, handler3.asHandler3().vtable.queryInterface(handler3.asHandler3(), &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, handler3.asHandler3()), queried);
    try std.testing.expectEqual(@as(types.uint32, 1), handler3.handler3_add_ref_count);
    const handler3_unknown: *ivstcontextmenu.IComponentHandler3 = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), handler3_unknown.vtable.release(handler3_unknown));

    var bus_and_time = BusAndTime{};
    queried = null;
    try std.testing.expectEqual(types.kResultOk, bus_and_time.asBusActivation().vtable.queryInterface(bus_and_time.asBusActivation(), &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, bus_and_time.asBusActivation()), queried);
    try std.testing.expectEqual(@as(types.uint32, 1), bus_and_time.bus_add_ref_count);
    const bus_unknown: *ivsteditcontroller.IComponentHandlerBusActivation = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), bus_unknown.vtable.release(bus_unknown));

    queried = null;
    try std.testing.expectEqual(types.kResultOk, bus_and_time.asSystemTime().vtable.queryInterface(bus_and_time.asSystemTime(), &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, bus_and_time.asSystemTime()), queried);
    try std.testing.expectEqual(@as(types.uint32, 1), bus_and_time.time_add_ref_count);
    const time_unknown: *ivsteditcontroller.IComponentHandlerSystemTime = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), time_unknown.vtable.release(time_unknown));

    var progress = Progress{};
    queried = null;
    try std.testing.expectEqual(types.kResultOk, progress.asProgress().vtable.queryInterface(progress.asProgress(), &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, progress.asProgress()), queried);
    try std.testing.expectEqual(@as(types.uint32, 1), progress.progress_add_ref_count);
    const progress_unknown: *ivsteditcontroller.IProgress = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), progress_unknown.vtable.release(progress_unknown));

    var units = Units{};
    queried = null;
    try std.testing.expectEqual(types.kResultOk, units.asUnitHandler().vtable.queryInterface(units.asUnitHandler(), &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, units.asUnitHandler()), queried);
    try std.testing.expectEqual(@as(types.uint32, 1), units.unit_add_ref_count);
    const unit_unknown: *ivstunits.IUnitHandler = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), unit_unknown.vtable.release(unit_unknown));

    queried = null;
    try std.testing.expectEqual(types.kResultOk, units.asUnitHandler2().vtable.queryInterface(units.asUnitHandler2(), &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, units.asUnitHandler2()), queried);
    try std.testing.expectEqual(@as(types.uint32, 1), units.unit2_add_ref_count);
    const unit2_unknown: *ivstunits.IUnitHandler2 = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), unit2_unknown.vtable.release(unit2_unknown));
}

test "component handler 3 exposes context menu extension" {
    const Handler = ComponentHandler3(struct {});
    var handler = Handler{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.beginEdit(handler.asHandler(), 9));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.performEdit(handler.asHandler(), 9, 0.5));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.endEdit(handler.asHandler(), 9));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.restartComponent(handler.asHandler(), 3));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.begin_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.perform_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.end_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.restart_count);
    try std.testing.expectEqual(@as(vsttypes.ParamID, 9), handler.last_param_id);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), handler.last_value);
    try std.testing.expectEqual(@as(types.int32, 3), handler.last_restart_flags);

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.queryInterface(handler.asHandler(), &ivstcontextmenu.icomponent_handler3_iid, &queried));
    try std.testing.expect(queried != null);
    const handler3: *ivstcontextmenu.IComponentHandler3 = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.handler3_add_ref_count);
    try std.testing.expectEqual(@as(?*ivstcontextmenu.IContextMenu, null), handler3.vtable.createContextMenu(handler3, null, null));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.context_menu_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler3.vtable.release(handler3));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.handler3_release_count);
}

test "component handler 3 clears unsupported query outputs from both interfaces" {
    const Handler = ComponentHandler3(struct {});
    var handler = Handler{};
    var handler_out: ?*anyopaque = handler.asHandler();
    var handler3_out: ?*anyopaque = handler.asHandler3();

    try std.testing.expectEqual(types.kNoInterface, handler.asHandler().vtable.queryInterface(handler.asHandler(), &tuid.zero, &handler_out));
    try std.testing.expectEqual(@as(?*anyopaque, null), handler_out);

    try std.testing.expectEqual(types.kNoInterface, handler.asHandler3().vtable.queryInterface(handler.asHandler3(), &ivsteditcontroller.icomponent_handler_iid, &handler3_out));
    try std.testing.expectEqual(@as(?*anyopaque, null), handler3_out);
    try std.testing.expectEqual(@as(types.uint32, 0), handler.handler3_add_ref_count);
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

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.beginEdit(handler.asHandler(), 9));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.performEdit(handler.asHandler(), 9, 0.5));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.endEdit(handler.asHandler(), 9));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.restartComponent(handler.asHandler(), 3));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.begin_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.perform_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.end_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.restart_count);
    try std.testing.expectEqual(@as(vsttypes.ParamID, 9), handler.last_param_id);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), handler.last_value);
    try std.testing.expectEqual(@as(types.int32, 3), handler.last_restart_flags);

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

test "component handler resets failed delegated system time output" {
    const Handler = ComponentHandlerBusAndTime(struct {
        pub const system_time: types.int64 = 12345;

        pub fn getSystemTime(self: anytype, out: *types.int64) types.tresult {
            _ = self;
            out.* = 99999;
            return types.kResultFalse;
        }
    });
    var handler = Handler{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.queryInterface(handler.asHandler(), &ivsteditcontroller.icomponent_handler_system_time_iid, &queried));
    try std.testing.expect(queried != null);
    const time: *ivsteditcontroller.IComponentHandlerSystemTime = @ptrCast(@alignCast(queried.?));

    var value: types.int64 = 0;
    try std.testing.expectEqual(types.kResultFalse, time.vtable.getSystemTime(time, &value));
    try std.testing.expectEqual(@as(types.int64, 12345), value);
    try std.testing.expectEqual(@as(types.uint32, 1), time.vtable.release(time));
}

test "component handler records successful delegated system time output" {
    const Handler = ComponentHandlerBusAndTime(struct {
        pub const system_time: types.int64 = 12345;

        pub fn getSystemTime(self: anytype, out: *types.int64) types.tresult {
            _ = self;
            out.* = 99999;
            return types.kResultOk;
        }
    });
    var handler = Handler{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.queryInterface(handler.asHandler(), &ivsteditcontroller.icomponent_handler_system_time_iid, &queried));
    try std.testing.expect(queried != null);
    const time: *ivsteditcontroller.IComponentHandlerSystemTime = @ptrCast(@alignCast(queried.?));

    var value: types.int64 = 0;
    try std.testing.expectEqual(types.kResultOk, time.vtable.getSystemTime(time, &value));
    try std.testing.expectEqual(@as(types.int64, 99999), value);
    try std.testing.expectEqual(@as(types.int64, 99999), handler.last_system_time);
    try std.testing.expectEqual(@as(types.uint32, 1), time.vtable.release(time));
}

test "component handler bus and time clear unsupported query outputs" {
    const Handler = ComponentHandlerBusAndTime(struct {});
    var handler = Handler{};
    var handler_out: ?*anyopaque = handler.asHandler();
    var bus_out: ?*anyopaque = handler.asBusActivation();
    var time_out: ?*anyopaque = handler.asSystemTime();

    try std.testing.expectEqual(types.kNoInterface, handler.asHandler().vtable.queryInterface(handler.asHandler(), &tuid.zero, &handler_out));
    try std.testing.expectEqual(@as(?*anyopaque, null), handler_out);

    try std.testing.expectEqual(types.kNoInterface, handler.asBusActivation().vtable.queryInterface(handler.asBusActivation(), &ivsteditcontroller.icomponent_handler_iid, &bus_out));
    try std.testing.expectEqual(@as(?*anyopaque, null), bus_out);

    try std.testing.expectEqual(types.kNoInterface, handler.asSystemTime().vtable.queryInterface(handler.asSystemTime(), &ivsteditcontroller.icomponent_handler_iid, &time_out));
    try std.testing.expectEqual(@as(?*anyopaque, null), time_out);
    try std.testing.expectEqual(@as(types.uint32, 0), handler.bus_add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 0), handler.time_add_ref_count);
}

test "component handler exposes progress callbacks" {
    const Handler = ComponentHandlerProgress(struct {
        pub const progress_id: ivsteditcontroller.ProgressID = 77;
    });
    var handler = Handler{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.beginEdit(handler.asHandler(), 9));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.performEdit(handler.asHandler(), 9, 0.5));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.endEdit(handler.asHandler(), 9));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.restartComponent(handler.asHandler(), 3));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.begin_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.perform_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.end_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.restart_count);
    try std.testing.expectEqual(@as(vsttypes.ParamID, 9), handler.last_param_id);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), handler.last_value);
    try std.testing.expectEqual(@as(types.int32, 3), handler.last_restart_flags);

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.queryInterface(handler.asHandler(), &ivsteditcontroller.iprogress_iid, &queried));
    try std.testing.expect(queried != null);
    const progress: *ivsteditcontroller.IProgress = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.progress_add_ref_count);

    var progress_id: ivsteditcontroller.ProgressID = 0;
    try std.testing.expectEqual(types.kResultOk, progress.vtable.start(progress, @intFromEnum(ivsteditcontroller.ProgressType.UIBackgroundTask), null, &progress_id));
    try std.testing.expectEqual(@as(ivsteditcontroller.ProgressID, 77), progress_id);
    try std.testing.expectEqual(types.kResultOk, progress.vtable.update(progress, progress_id, 0.5));
    try std.testing.expectEqual(types.kResultOk, progress.vtable.finish(progress, progress_id));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.start_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.update_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.finish_count);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), handler.last_value);

    try std.testing.expectEqual(@as(types.uint32, 1), progress.vtable.release(progress));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.progress_release_count);
}

test "component handler resets failed delegated progress id output" {
    const Handler = ComponentHandlerProgress(struct {
        pub const progress_id: ivsteditcontroller.ProgressID = 77;

        pub fn start(self: anytype, progress_type: types.uint32, description: ?[*]const types.char16, out: *ivsteditcontroller.ProgressID) types.tresult {
            _ = self;
            _ = progress_type;
            _ = description;
            out.* = 999;
            return types.kResultFalse;
        }
    });
    var handler = Handler{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.queryInterface(handler.asHandler(), &ivsteditcontroller.iprogress_iid, &queried));
    try std.testing.expect(queried != null);
    const progress: *ivsteditcontroller.IProgress = @ptrCast(@alignCast(queried.?));

    var progress_id: ivsteditcontroller.ProgressID = 0;
    try std.testing.expectEqual(types.kResultFalse, progress.vtable.start(progress, @intFromEnum(ivsteditcontroller.ProgressType.UIBackgroundTask), null, &progress_id));
    try std.testing.expectEqual(@as(ivsteditcontroller.ProgressID, 77), progress_id);
    try std.testing.expectEqual(@as(types.uint32, 1), progress.vtable.release(progress));
}

test "component handler records successful delegated progress id output" {
    const Handler = ComponentHandlerProgress(struct {
        pub const progress_id: ivsteditcontroller.ProgressID = 77;

        pub fn start(self: anytype, progress_type: types.uint32, description: ?[*]const types.char16, out: *ivsteditcontroller.ProgressID) types.tresult {
            _ = self;
            _ = progress_type;
            _ = description;
            out.* = 999;
            return types.kResultOk;
        }
    });
    var handler = Handler{};
    var queried: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.queryInterface(handler.asHandler(), &ivsteditcontroller.iprogress_iid, &queried));
    try std.testing.expect(queried != null);
    const progress: *ivsteditcontroller.IProgress = @ptrCast(@alignCast(queried.?));

    var progress_id: ivsteditcontroller.ProgressID = 0;
    try std.testing.expectEqual(types.kResultOk, progress.vtable.start(progress, @intFromEnum(ivsteditcontroller.ProgressType.UIBackgroundTask), null, &progress_id));
    try std.testing.expectEqual(@as(ivsteditcontroller.ProgressID, 999), progress_id);
    try std.testing.expectEqual(@as(ivsteditcontroller.ProgressID, 999), handler.last_id);
    try std.testing.expectEqual(@as(types.uint32, 1), progress.vtable.release(progress));
}

test "component handler progress clears unsupported query outputs" {
    const Handler = ComponentHandlerProgress(struct {});
    var handler = Handler{};
    var handler_out: ?*anyopaque = handler.asHandler();
    var progress_out: ?*anyopaque = handler.asProgress();

    try std.testing.expectEqual(types.kNoInterface, handler.asHandler().vtable.queryInterface(handler.asHandler(), &tuid.zero, &handler_out));
    try std.testing.expectEqual(@as(?*anyopaque, null), handler_out);

    try std.testing.expectEqual(types.kNoInterface, handler.asProgress().vtable.queryInterface(handler.asProgress(), &ivsteditcontroller.icomponent_handler_iid, &progress_out));
    try std.testing.expectEqual(@as(?*anyopaque, null), progress_out);
    try std.testing.expectEqual(@as(types.uint32, 0), handler.progress_add_ref_count);
}

test "component handler exposes unit handler extensions" {
    const Handler = ComponentHandlerUnits(struct {});
    var handler = Handler{};
    var unit_out: ?*anyopaque = null;
    var unit2_out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.queryInterface(handler.asHandler(), &ivstunits.iunit_handler_iid, &unit_out));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.queryInterface(handler.asHandler(), &ivstunits.iunit_handler2_iid, &unit2_out));
    try std.testing.expect(unit_out != null);
    try std.testing.expect(unit2_out != null);

    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.beginEdit(handler.asHandler(), 9));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.performEdit(handler.asHandler(), 9, 0.5));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.endEdit(handler.asHandler(), 9));
    try std.testing.expectEqual(types.kResultOk, handler.asHandler().vtable.restartComponent(handler.asHandler(), 3));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.begin_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.perform_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.end_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.restart_count);
    try std.testing.expectEqual(@as(vsttypes.ParamID, 9), handler.last_param_id);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), handler.last_value);
    try std.testing.expectEqual(@as(types.int32, 3), handler.last_restart_flags);

    const unit: *ivstunits.IUnitHandler = @ptrCast(@alignCast(unit_out.?));
    const unit2: *ivstunits.IUnitHandler2 = @ptrCast(@alignCast(unit2_out.?));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.unit_add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.unit2_add_ref_count);

    try std.testing.expectEqual(types.kResultOk, unit.vtable.notifyUnitSelection(unit, ivstunits.kRootUnitId));
    try std.testing.expectEqual(types.kResultOk, unit.vtable.notifyProgramListChange(unit, ivstunits.kNoProgramListId, ivstunits.kAllProgramInvalid));
    try std.testing.expectEqual(types.kResultOk, unit2.vtable.notifyUnitByBusChange(unit2));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.unit_selection_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.program_list_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.unit_by_bus_count);

    try std.testing.expectEqual(@as(types.uint32, 1), unit.vtable.release(unit));
    try std.testing.expectEqual(@as(types.uint32, 1), unit2.vtable.release(unit2));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.unit_release_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.unit2_release_count);
}

test "component handler units clear unsupported query outputs" {
    const Handler = ComponentHandlerUnits(struct {});
    var handler = Handler{};
    var handler_out: ?*anyopaque = handler.asHandler();
    var unit_out: ?*anyopaque = handler.asUnitHandler();
    var unit2_out: ?*anyopaque = handler.asUnitHandler2();

    try std.testing.expectEqual(types.kNoInterface, handler.asHandler().vtable.queryInterface(handler.asHandler(), &tuid.zero, &handler_out));
    try std.testing.expectEqual(@as(?*anyopaque, null), handler_out);

    try std.testing.expectEqual(types.kNoInterface, handler.asUnitHandler().vtable.queryInterface(handler.asUnitHandler(), &ivsteditcontroller.icomponent_handler_iid, &unit_out));
    try std.testing.expectEqual(@as(?*anyopaque, null), unit_out);

    try std.testing.expectEqual(types.kNoInterface, handler.asUnitHandler2().vtable.queryInterface(handler.asUnitHandler2(), &ivsteditcontroller.icomponent_handler_iid, &unit2_out));
    try std.testing.expectEqual(@as(?*anyopaque, null), unit2_out);
    try std.testing.expectEqual(@as(types.uint32, 0), handler.unit_add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 0), handler.unit2_add_ref_count);
}
