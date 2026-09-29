const std = @import("std");
const builtin = @import("builtin");
const process_api = @import("process.zig");
const abi = @import("audio_unit_v2/abi.zig");

pub const OSStatus = abi.OSStatus;
pub const OSType = abi.OSType;
pub const AudioUnitPropertyID = abi.AudioUnitPropertyID;
pub const AudioUnitScope = abi.AudioUnitScope;
pub const AudioUnitElement = abi.AudioUnitElement;
pub const AudioUnitParameterID = abi.AudioUnitParameterID;
pub const AudioUnitParameterValue = abi.AudioUnitParameterValue;
pub const AudioUnitParameterUnit = abi.AudioUnitParameterUnit;
pub const AudioUnitParameterOptions = abi.AudioUnitParameterOptions;
pub const AudioUnitRenderActionFlags = abi.AudioUnitRenderActionFlags;
pub const Boolean = abi.Boolean;
pub const AudioStreamBasicDescription = abi.AudioStreamBasicDescription;
pub const SMPTETime = abi.SMPTETime;
pub const AudioTimeStamp = abi.AudioTimeStamp;
pub const timestamp_flag = abi.timestamp_flag;
pub const AUChannelInfo = abi.AUChannelInfo;
pub const AudioUnitParameterInfo = abi.AudioUnitParameterInfo;
pub const AUParameterEventType = abi.AUParameterEventType;
pub const parameter_event_type = abi.parameter_event_type;
pub const AudioUnitParameterRampEvent = abi.AudioUnitParameterRampEvent;
pub const AudioUnitParameterImmediateEvent = abi.AudioUnitParameterImmediateEvent;
pub const AudioUnitParameterEvent = abi.AudioUnitParameterEvent;
pub const AudioComponentDescription = abi.AudioComponentDescription;
pub const AudioBuffer = abi.AudioBuffer;
pub const AudioBufferList = abi.AudioBufferList;
pub const AURenderCallback = abi.AURenderCallback;
pub const AudioUnitPropertyListenerProc = abi.AudioUnitPropertyListenerProc;

pub const PropertyInfo = struct {
    size: u32,
    writable: bool,
};

fn noopAudioUnitPropertyListener(
    _: ?*anyopaque,
    _: AudioComponentInstance,
    _: AudioUnitPropertyID,
    _: AudioUnitScope,
    _: AudioUnitElement,
) callconv(.c) void {}

fn noopAuRenderNotification(
    _: ?*anyopaque,
    _: ?*AudioUnitRenderActionFlags,
    _: ?*const AudioTimeStamp,
    _: u32,
    _: u32,
    _: *AudioBufferList,
) callconv(.c) OSStatus {
    return status.success;
}

pub const AURenderCallbackStruct = abi.AURenderCallbackStruct;
pub const AudioComponentInstance = abi.AudioComponentInstance;
pub const AudioComponentMethod = abi.AudioComponentMethod;
pub const AudioComponentPlugInInterface = abi.AudioComponentPlugInInterface;
pub const selector = abi.selector;
pub const scope = abi.scope;
pub const property = abi.property;
pub const parameter_unit = abi.parameter_unit;
pub const parameter_flag = abi.parameter_flag;
pub const render_action = abi.render_action;
pub const audio_format = abi.audio_format;
pub const status = abi.status;

pub fn ComponentDispatch(comptime Adapter: type) type {
    const supports_properties =
        @hasDecl(Adapter, "propertyInfo") and
        @hasDecl(Adapter, "getProperty") and
        @hasDecl(Adapter, "setProperty");
    const supports_parameters =
        @hasDecl(Adapter, "getParameter") and
        @hasDecl(Adapter, "setParameter");
    const supports_parameter_scheduling =
        @hasDecl(Adapter, "scheduleParameters");
    const supports_render = @hasDecl(Adapter, "renderCallback");

    return struct {
        const Self = @This();
        pub const maximum_property_listeners = 32;
        pub const maximum_render_notifications = 32;
        const PropertyListener = struct {
            property_id: AudioUnitPropertyID,
            procedure: AudioUnitPropertyListenerProc,
            user_data: ?*anyopaque,
        };
        const RenderNotification = struct {
            procedure: AURenderCallback,
            user_data: ?*anyopaque,
        };
        const empty_property_listener = PropertyListener{
            .property_id = 0,
            .procedure = noopAudioUnitPropertyListener,
            .user_data = null,
        };
        const empty_render_notification = RenderNotification{
            .procedure = noopAuRenderNotification,
            .user_data = null,
        };

        interface: AudioComponentPlugInInterface = .{
            .open = open,
            .close = close,
            .lookup = lookup,
            .reserved = null,
        },
        adapter: *Adapter,
        component_instance: ?AudioComponentInstance = null,
        property_listeners: [maximum_property_listeners]PropertyListener =
            @splat(empty_property_listener),
        property_listener_count: usize = 0,
        render_notifications: [maximum_render_notifications]RenderNotification =
            @splat(empty_render_notification),
        render_notification_count: usize = 0,

        pub fn init(adapter: *Adapter) Self {
            return .{ .adapter = adapter };
        }

        pub fn valid(self: *const Self) bool {
            return self.property_listener_count <= maximum_property_listeners and
                self.render_notification_count <= maximum_render_notifications;
        }

        pub fn asInterface(
            self: *Self,
        ) *AudioComponentPlugInInterface {
            return &self.interface;
        }

        fn fromOpaque(pointer: *anyopaque) *Self {
            const interface: *AudioComponentPlugInInterface =
                @ptrCast(@alignCast(pointer));
            return @fieldParentPtr("interface", interface);
        }

        fn open(
            pointer: *anyopaque,
            instance: AudioComponentInstance,
        ) callconv(.c) OSStatus {
            const self = fromOpaque(pointer);
            if (self.component_instance != null)
                return status.initialized;
            self.component_instance = instance;
            return status.success;
        }

        fn close(pointer: *anyopaque) callconv(.c) OSStatus {
            const self = fromOpaque(pointer);
            if (self.component_instance == null) {
                if (@hasDecl(Adapter, "closeComponent"))
                    self.adapter.closeComponent();
                return status.uninitialized;
            }
            self.adapter.uninitialize() catch {
                return status.cannot_do_in_current_context;
            };
            self.component_instance = null;
            @memset(&self.property_listeners, empty_property_listener);
            self.property_listener_count = 0;
            @memset(&self.render_notifications, empty_render_notification);
            self.render_notification_count = 0;
            if (@hasDecl(Adapter, "closeComponent"))
                self.adapter.closeComponent();
            return status.success;
        }

        fn lookup(selector_value: i16) callconv(.c) ?AudioComponentMethod {
            return switch (selector_value) {
                selector.initialize => @ptrCast(&initialize),
                selector.uninitialize => @ptrCast(&uninitialize),
                selector.get_property_info => if (supports_properties)
                    @ptrCast(&getPropertyInfo)
                else
                    null,
                selector.get_property => if (supports_properties)
                    @ptrCast(&getProperty)
                else
                    null,
                selector.set_property => if (supports_properties)
                    @ptrCast(&setProperty)
                else
                    null,
                selector.get_parameter => if (supports_parameters)
                    @ptrCast(&getParameter)
                else
                    null,
                selector.set_parameter => if (supports_parameters)
                    @ptrCast(&setParameter)
                else
                    null,
                selector.reset => @ptrCast(&reset),
                selector.add_property_listener => @ptrCast(&addPropertyListener),
                selector.remove_property_listener => @ptrCast(&removePropertyListener),
                selector.render => if (supports_render)
                    @ptrCast(&render)
                else
                    null,
                selector.add_render_notify => if (supports_render)
                    @ptrCast(&addRenderNotify)
                else
                    null,
                selector.remove_render_notify => if (supports_render)
                    @ptrCast(&removeRenderNotify)
                else
                    null,
                selector.schedule_parameters => if (supports_parameter_scheduling)
                    @ptrCast(&scheduleParameters)
                else
                    null,
                selector.remove_property_listener_with_user_data => @ptrCast(&removePropertyListenerWithUserData),
                else => null,
            };
        }

        fn initialize(pointer: *anyopaque) callconv(.c) OSStatus {
            const self = fromOpaque(pointer);
            if (self.component_instance == null)
                return status.uninitialized;
            self.adapter.initialize() catch {
                return status.failed_initialization;
            };
            return status.success;
        }

        fn getPropertyInfo(
            pointer: *anyopaque,
            property_id: AudioUnitPropertyID,
            property_scope: AudioUnitScope,
            element: AudioUnitElement,
            output_size: ?*u32,
            output_writable: ?*Boolean,
        ) callconv(.c) OSStatus {
            if (!supports_properties)
                return status.invalid_property;
            const self = fromOpaque(pointer);
            const info = self.adapter.propertyInfo(
                property_id,
                property_scope,
                element,
            ) catch |err| return propertyStatus(err);
            if (output_size) |size|
                size.* = info.size;
            if (output_writable) |writable|
                writable.* = @intFromBool(info.writable);
            return status.success;
        }

        fn getProperty(
            pointer: *anyopaque,
            property_id: AudioUnitPropertyID,
            property_scope: AudioUnitScope,
            element: AudioUnitElement,
            output_data: ?*anyopaque,
            input_output_size: ?*u32,
        ) callconv(.c) OSStatus {
            if (!supports_properties)
                return status.invalid_property;
            const size_pointer = input_output_size orelse
                return status.invalid_property_value;
            const info = fromOpaque(pointer).adapter.propertyInfo(
                property_id,
                property_scope,
                element,
            ) catch |err| return propertyStatus(err);
            const supplied_size = size_pointer.*;
            size_pointer.* = info.size;
            if (supplied_size < info.size)
                return status.invalid_property_value;
            if (info.size == 0)
                return status.success;
            const data = output_data orelse
                return status.invalid_property_value;
            const destination = @as([*]u8, @ptrCast(data))[0..info.size];
            const written = fromOpaque(pointer).adapter.getProperty(
                property_id,
                property_scope,
                element,
                destination,
            ) catch |err| return propertyStatus(err);
            if (written != info.size)
                return status.invalid_property_value;
            return status.success;
        }

        fn setProperty(
            pointer: *anyopaque,
            property_id: AudioUnitPropertyID,
            property_scope: AudioUnitScope,
            element: AudioUnitElement,
            input_data: ?*const anyopaque,
            input_size: u32,
        ) callconv(.c) OSStatus {
            if (!supports_properties)
                return status.invalid_property;
            const self = fromOpaque(pointer);
            if (!self.valid())
                return status.cannot_do_in_current_context;
            const info = self.adapter.propertyInfo(
                property_id,
                property_scope,
                element,
            ) catch |err| return propertyStatus(err);
            if (!info.writable)
                return status.property_not_writable;
            if (input_size != info.size)
                return status.invalid_property_value;
            const data = input_data orelse
                return status.invalid_property_value;
            const source =
                @as([*]const u8, @ptrCast(data))[0..input_size];
            self.adapter.setProperty(
                property_id,
                property_scope,
                element,
                source,
            ) catch |err| return propertyStatus(err);
            self.notifyPropertyListeners(
                property_id,
                property_scope,
                element,
            );
            return status.success;
        }

        fn addPropertyListener(
            pointer: *anyopaque,
            property_id: AudioUnitPropertyID,
            procedure: AudioUnitPropertyListenerProc,
            user_data: ?*anyopaque,
        ) callconv(.c) OSStatus {
            const self = fromOpaque(pointer);
            if (!self.valid())
                return status.cannot_do_in_current_context;
            for (self.property_listeners[0..self.property_listener_count]) |entry| {
                if (entry.property_id == property_id and
                    entry.procedure == procedure and
                    entry.user_data == user_data)
                    return status.success;
            }
            if (self.property_listener_count ==
                maximum_property_listeners)
                return status.cannot_do_in_current_context;
            self.property_listeners[self.property_listener_count] = .{
                .property_id = property_id,
                .procedure = procedure,
                .user_data = user_data,
            };
            self.property_listener_count += 1;
            return status.success;
        }

        fn removePropertyListener(
            pointer: *anyopaque,
            property_id: AudioUnitPropertyID,
            procedure: AudioUnitPropertyListenerProc,
        ) callconv(.c) OSStatus {
            const self = fromOpaque(pointer);
            if (!self.valid())
                return status.cannot_do_in_current_context;
            var index: usize = self.property_listener_count;
            while (index > 0) {
                index -= 1;
                const entry = self.property_listeners[index];
                if (entry.property_id == property_id and
                    entry.procedure == procedure)
                    self.removePropertyListenerAt(index);
            }
            return status.success;
        }

        fn removePropertyListenerWithUserData(
            pointer: *anyopaque,
            property_id: AudioUnitPropertyID,
            procedure: AudioUnitPropertyListenerProc,
            user_data: ?*anyopaque,
        ) callconv(.c) OSStatus {
            const self = fromOpaque(pointer);
            if (!self.valid())
                return status.cannot_do_in_current_context;
            var index: usize = self.property_listener_count;
            while (index > 0) {
                index -= 1;
                const entry = self.property_listeners[index];
                if (entry.property_id == property_id and
                    entry.procedure == procedure and
                    entry.user_data == user_data)
                    self.removePropertyListenerAt(index);
            }
            return status.success;
        }

        fn removePropertyListenerAt(self: *Self, index: usize) void {
            self.property_listener_count -= 1;
            if (index != self.property_listener_count)
                self.property_listeners[index] =
                    self.property_listeners[self.property_listener_count];
            self.property_listeners[self.property_listener_count] =
                empty_property_listener;
        }

        fn notifyPropertyListeners(
            self: *Self,
            property_id: AudioUnitPropertyID,
            property_scope: AudioUnitScope,
            element: AudioUnitElement,
        ) void {
            if (!self.valid()) return;
            const instance = self.component_instance orelse return;
            var listeners: [maximum_property_listeners]PropertyListener = undefined;
            var listener_count: usize = 0;
            for (self.property_listeners[0..self.property_listener_count]) |entry| {
                if (entry.property_id != property_id) continue;
                listeners[listener_count] = entry;
                listener_count += 1;
            }
            for (listeners[0..listener_count]) |entry| {
                entry.procedure(
                    entry.user_data,
                    instance,
                    property_id,
                    property_scope,
                    element,
                );
            }
        }

        fn getParameter(
            pointer: *anyopaque,
            parameter_id: AudioUnitParameterID,
            parameter_scope: AudioUnitScope,
            element: AudioUnitElement,
            output_value: ?*AudioUnitParameterValue,
        ) callconv(.c) OSStatus {
            if (!supports_parameters)
                return status.invalid_parameter;
            const value = output_value orelse
                return status.invalid_parameter;
            value.* = fromOpaque(pointer).adapter.getParameter(
                parameter_id,
                parameter_scope,
                element,
            ) catch |err| return parameterStatus(err);
            return status.success;
        }

        fn setParameter(
            pointer: *anyopaque,
            parameter_id: AudioUnitParameterID,
            parameter_scope: AudioUnitScope,
            element: AudioUnitElement,
            value: AudioUnitParameterValue,
            buffer_offset_frames: u32,
        ) callconv(.c) OSStatus {
            if (!supports_parameters)
                return status.invalid_parameter;
            fromOpaque(pointer).adapter.setParameter(
                parameter_id,
                parameter_scope,
                element,
                value,
                buffer_offset_frames,
            ) catch |err| return parameterStatus(err);
            return status.success;
        }

        fn scheduleParameters(
            pointer: *anyopaque,
            events: ?[*]const AudioUnitParameterEvent,
            event_count: u32,
        ) callconv(.c) OSStatus {
            if (!supports_parameter_scheduling)
                return status.invalid_parameter;
            if (event_count == 0)
                return status.success;
            const event_pointer = events orelse
                return status.invalid_parameter;
            fromOpaque(pointer).adapter.scheduleParameters(
                event_pointer[0..event_count],
            ) catch |err| return parameterStatus(err);
            return status.success;
        }

        fn uninitialize(pointer: *anyopaque) callconv(.c) OSStatus {
            const self = fromOpaque(pointer);
            if (self.component_instance == null)
                return status.uninitialized;
            self.adapter.uninitialize() catch {
                return status.cannot_do_in_current_context;
            };
            return status.success;
        }

        fn reset(
            pointer: *anyopaque,
            reset_scope: AudioUnitScope,
            element: AudioUnitElement,
        ) callconv(.c) OSStatus {
            const self = fromOpaque(pointer);
            if (self.component_instance == null)
                return status.uninitialized;
            if (reset_scope != scope.global)
                return status.invalid_scope;
            if (element != 0)
                return status.invalid_element;
            self.adapter.reset() catch |err| {
                return if (err == error.AudioUnitUninitialized)
                    status.uninitialized
                else
                    status.cannot_do_in_current_context;
            };
            return status.success;
        }

        fn render(
            pointer: *anyopaque,
            action_flags: ?*AudioUnitRenderActionFlags,
            timestamp: ?*const AudioTimeStamp,
            output_bus: u32,
            frame_count: u32,
            data: *AudioBufferList,
        ) callconv(.c) OSStatus {
            if (!supports_render)
                return status.invalid_property;
            const self = fromOpaque(pointer);
            if (!self.valid())
                return status.cannot_do_in_current_context;
            if (self.component_instance == null)
                return status.uninitialized;
            var local_action_flags: AudioUnitRenderActionFlags = 0;
            const flags = action_flags orelse &local_action_flags;
            self.notifyRender(
                flags,
                render_action.pre_render,
                timestamp,
                output_bus,
                frame_count,
                data,
            );
            self.adapter.renderCallback(
                flags,
                timestamp,
                output_bus,
                frame_count,
                data,
            ) catch |err| {
                self.notifyRender(
                    flags,
                    render_action.post_render |
                        render_action.post_render_error,
                    timestamp,
                    output_bus,
                    frame_count,
                    data,
                );
                return renderStatus(err);
            };
            self.notifyRender(
                flags,
                render_action.post_render,
                timestamp,
                output_bus,
                frame_count,
                data,
            );
            return status.success;
        }

        fn addRenderNotify(
            pointer: *anyopaque,
            procedure: AURenderCallback,
            user_data: ?*anyopaque,
        ) callconv(.c) OSStatus {
            const self = fromOpaque(pointer);
            if (!self.valid())
                return status.cannot_do_in_current_context;
            for (self.render_notifications[0..self.render_notification_count]) |entry| {
                if (entry.procedure == procedure and
                    entry.user_data == user_data)
                    return status.success;
            }
            if (self.render_notification_count ==
                maximum_render_notifications)
                return status.cannot_do_in_current_context;
            self.render_notifications[self.render_notification_count] = .{
                .procedure = procedure,
                .user_data = user_data,
            };
            self.render_notification_count += 1;
            return status.success;
        }

        fn removeRenderNotify(
            pointer: *anyopaque,
            procedure: AURenderCallback,
            user_data: ?*anyopaque,
        ) callconv(.c) OSStatus {
            const self = fromOpaque(pointer);
            if (!self.valid())
                return status.cannot_do_in_current_context;
            var index: usize = self.render_notification_count;
            while (index > 0) {
                index -= 1;
                const entry = self.render_notifications[index];
                if (entry.procedure == procedure and
                    entry.user_data == user_data)
                    self.removeRenderNotificationAt(index);
            }
            return status.success;
        }

        fn removeRenderNotificationAt(
            self: *Self,
            index: usize,
        ) void {
            self.render_notification_count -= 1;
            if (index != self.render_notification_count)
                self.render_notifications[index] =
                    self.render_notifications[
                        self.render_notification_count
                    ];
            self.render_notifications[self.render_notification_count] =
                empty_render_notification;
        }

        fn notifyRender(
            self: *Self,
            action_flags: *AudioUnitRenderActionFlags,
            notification_flags: AudioUnitRenderActionFlags,
            timestamp: ?*const AudioTimeStamp,
            output_bus: u32,
            frame_count: u32,
            data: *AudioBufferList,
        ) void {
            if (!self.valid()) return;
            var notifications: [maximum_render_notifications]RenderNotification =
                undefined;
            const count = self.render_notification_count;
            @memcpy(
                notifications[0..count],
                self.render_notifications[0..count],
            );
            const previous_notification_flags =
                action_flags.* & notification_flags;
            action_flags.* |= notification_flags;
            for (notifications[0..count]) |entry| {
                _ = entry.procedure(
                    entry.user_data,
                    action_flags,
                    timestamp,
                    output_bus,
                    frame_count,
                    data,
                );
            }
            action_flags.* =
                (action_flags.* & ~notification_flags) |
                previous_notification_flags;
        }
    };
}

pub const LifecycleDispatch = ComponentDispatch;

pub fn ComponentFactory(
    comptime Plugin: type,
    comptime maximum_block_size: usize,
    comptime description: AudioComponentDescription,
    comptime initial_sample_rate: f64,
    comptime initial_maximum_frames: usize,
) type {
    return ComponentFactoryWithClassInfoBridge(
        Plugin,
        maximum_block_size,
        description,
        initial_sample_rate,
        initial_maximum_frames,
        NoClassInfoBridge,
    );
}

pub fn NativeComponentFactory(
    comptime Plugin: type,
    comptime maximum_block_size: usize,
    comptime description: AudioComponentDescription,
    comptime initial_sample_rate: f64,
    comptime initial_maximum_frames: usize,
) type {
    return ComponentFactoryWithClassInfoBridge(
        Plugin,
        maximum_block_size,
        description,
        initial_sample_rate,
        initial_maximum_frames,
        NativeClassInfoBridgeFor(Plugin, description),
    );
}

pub fn ComponentFactoryWithClassInfoBridge(
    comptime Plugin: type,
    comptime maximum_block_size: usize,
    comptime description: AudioComponentDescription,
    comptime initial_sample_rate: f64,
    comptime initial_maximum_frames: usize,
    comptime ClassInfoBridge: type,
) type {
    const audio_unit = @import("audio_unit.zig");
    const RenderAdapter = audio_unit.RenderAdapter(
        Plugin,
        maximum_block_size,
    );
    const Properties = RenderPropertyAdapterWithClassInfo(
        RenderAdapter,
        ClassInfoBridge,
    );
    const Dispatch = ComponentDispatch(Properties);

    return struct {
        const Self = @This();
        const Storage = struct {
            allocator: std.mem.Allocator,
            render_adapter: RenderAdapter,
            properties: Properties,
            dispatch: Dispatch,
        };

        pub const component_description = description;

        pub fn create(
            requested: ?*const AudioComponentDescription,
        ) callconv(.c) ?*AudioComponentPlugInInterface {
            return createWithAllocator(
                requested,
                std.heap.page_allocator,
            );
        }

        fn createWithAllocator(
            requested: ?*const AudioComponentDescription,
            allocator: std.mem.Allocator,
        ) ?*AudioComponentPlugInInterface {
            const requested_description = requested orelse return null;
            if (!matchesDescription(requested_description.*))
                return null;
            const storage = allocator.create(Storage) catch return null;
            storage.allocator = allocator;
            storage.render_adapter = RenderAdapter.init(
                allocator,
                .{},
                initial_sample_rate,
                initial_maximum_frames,
            ) catch {
                allocator.destroy(storage);
                return null;
            };
            storage.properties = Properties.init(
                &storage.render_adapter,
            );
            storage.properties.close_callback = closeStorage;
            storage.dispatch = Dispatch.init(&storage.properties);
            return storage.dispatch.asInterface();
        }

        fn matchesDescription(
            requested: AudioComponentDescription,
        ) bool {
            return requested.component_type ==
                description.component_type and
                requested.component_subtype ==
                    description.component_subtype and
                requested.component_manufacturer ==
                    description.component_manufacturer;
        }

        fn closeStorage(properties: *Properties) callconv(.c) void {
            const storage: *Storage =
                @fieldParentPtr("properties", properties);
            storage.render_adapter.deinit();
            storage.allocator.destroy(storage);
        }
    };
}

pub fn RenderPropertyAdapter(comptime Adapter: type) type {
    return RenderPropertyAdapterWithClassInfo(
        Adapter,
        NoClassInfoBridge,
    );
}

pub const NoClassInfoBridge = struct {
    pub const supported = false;

    pub fn create(_: []const u8) !?*anyopaque {
        return error.AudioUnitClassInfoUnsupported;
    }

    pub fn copy(_: ?*const anyopaque, _: []u8) !usize {
        return error.AudioUnitClassInfoUnsupported;
    }
};

pub const NativeClassInfoBridge = struct {
    pub const supported = builtin.os.tag == .macos;

    pub fn create(state_bytes: []const u8) !?*anyopaque {
        return createNativeClassInfo(
            state_bytes,
            0,
            0,
            0,
            "ZigVst3",
        );
    }

    pub fn copy(
        property_list: ?*const anyopaque,
        destination: []u8,
    ) !usize {
        return copyNativeClassInfo(property_list, destination);
    }
};

fn NativeClassInfoBridgeFor(
    comptime Plugin: type,
    comptime description: AudioComponentDescription,
) type {
    return struct {
        pub const supported = NativeClassInfoBridge.supported;

        pub fn create(state_bytes: []const u8) !?*anyopaque {
            return createNativeClassInfo(
                state_bytes,
                description.component_type,
                description.component_subtype,
                description.component_manufacturer,
                Plugin.name,
            );
        }

        pub fn copy(
            property_list: ?*const anyopaque,
            destination: []u8,
        ) !usize {
            return copyNativeClassInfo(property_list, destination);
        }
    };
}

fn createNativeClassInfo(
    state_bytes: []const u8,
    component_type: u32,
    component_subtype: u32,
    component_manufacturer: u32,
    name: []const u8,
) !?*anyopaque {
    if (comptime !NativeClassInfoBridge.supported)
        return error.AudioUnitClassInfoUnsupported;
    return zv3_auv2_class_info_create(
        state_bytes.ptr,
        state_bytes.len,
        component_type,
        component_subtype,
        component_manufacturer,
        name.ptr,
        name.len,
    ) orelse error.AudioUnitClassInfoCreationFailed;
}

fn copyNativeClassInfo(
    property_list: ?*const anyopaque,
    destination: []u8,
) !usize {
    if (comptime !NativeClassInfoBridge.supported)
        return error.AudioUnitClassInfoUnsupported;
    var written: usize = 0;
    if (zv3_auv2_class_info_copy_state(
        property_list,
        destination.ptr,
        destination.len,
        &written,
    ) == 0)
        return error.InvalidAudioUnitClassInfo;
    return written;
}

extern fn zv3_auv2_class_info_create(
    state_bytes: [*]const u8,
    state_size: usize,
    component_type: u32,
    component_subtype: u32,
    component_manufacturer: u32,
    name_bytes: [*]const u8,
    name_size: usize,
) ?*anyopaque;

extern fn zv3_auv2_class_info_copy_state(
    property_list: ?*const anyopaque,
    destination: [*]u8,
    destination_capacity: usize,
    output_size: *usize,
) c_int;

pub fn RenderPropertyAdapterWithClassInfo(
    comptime Adapter: type,
    comptime ClassInfoBridge: type,
) type {
    if (!@hasDecl(ClassInfoBridge, "supported"))
        @compileError("class-info bridge must declare supported");
    if (ClassInfoBridge.supported and
        (!@hasDecl(ClassInfoBridge, "create") or
            !@hasDecl(ClassInfoBridge, "copy")))
        @compileError("class-info bridge must provide create and copy");

    return struct {
        const Self = @This();
        pub const maximum_parameter_events = 256;
        const total_input_channels =
            Adapter.input_channel_count +
            Adapter.auxiliary_input_channel_count;
        const total_output_channels =
            Adapter.output_channel_count +
            Adapter.auxiliary_output_channel_count;
        const BlockKey = struct {
            valid_identity: u2,
            sample_time_bits: u64,
            host_time: u64,
            frame_count: u32,
        };
        const InputBufferList = extern struct {
            number_buffers: u32,
            buffers: [total_input_channels]AudioBuffer,
        };

        render_adapter: *Adapter,
        sample_bytes: u32 = @sizeOf(f32),
        input_callbacks: [Adapter.input_bus_count]AURenderCallbackStruct =
            [_]AURenderCallbackStruct{
                .{ .input = null, .reference = null },
            } ** Adapter.input_bus_count,
        input_scratch_f32: [total_input_channels][Adapter.maximum_frames]f32 =
            undefined,
        input_scratch_f64: [total_input_channels][Adapter.maximum_frames]f64 =
            undefined,
        input_headers_f32: [total_input_channels][]const f32 =
            undefined,
        input_headers_f64: [total_input_channels][]const f64 =
            undefined,
        output_headers_f32: [total_output_channels][]f32 = undefined,
        output_headers_f64: [total_output_channels][]f64 = undefined,
        output_cache_f32: [total_output_channels][Adapter.maximum_frames]f32 =
            undefined,
        output_cache_f64: [total_output_channels][Adapter.maximum_frames]f64 =
            undefined,
        cached_block: ?BlockKey = null,
        parameter_events: [maximum_parameter_events]process_api.ParameterChange =
            @splat(.{}),
        parameter_event_sequences: [maximum_parameter_events]usize = @splat(0),
        parameter_event_count: usize = 0,
        parameter_ramps: [maximum_parameter_events]process_api.ParameterRamp =
            @splat(.{}),
        parameter_ramp_count: usize = 0,
        scheduled_parameter_event_count: usize = 0,
        state_storage: [Adapter.maximum_state_bytes]u8 = @splat(0),
        close_callback: ?*const fn (*Self) callconv(.c) void = null,

        pub fn init(render_adapter: *Adapter) Self {
            return .{ .render_adapter = render_adapter };
        }

        pub fn valid(self: *const Self) bool {
            if (self.parameter_event_count > maximum_parameter_events or
                self.parameter_ramp_count > maximum_parameter_events or
                self.scheduled_parameter_event_count > maximum_parameter_events)
            {
                return false;
            }
            const retained_count = std.math.add(
                usize,
                self.parameter_event_count,
                self.parameter_ramp_count,
            ) catch return false;
            return retained_count == self.scheduled_parameter_event_count;
        }

        pub fn initialize(self: *Self) !void {
            self.cached_block = null;
            self.clearParameterEvents();
            try self.render_adapter.initialize();
        }

        pub fn uninitialize(self: *Self) !void {
            try self.render_adapter.uninitialize();
            self.cached_block = null;
            self.clearParameterEvents();
        }

        pub fn reset(self: *Self) !void {
            try self.render_adapter.reset();
            self.cached_block = null;
            self.clearParameterEvents();
        }

        pub fn closeComponent(self: *Self) void {
            const callback = self.close_callback orelse return;
            self.close_callback = null;
            callback(self);
        }

        pub fn propertyInfo(
            self: *Self,
            property_id: AudioUnitPropertyID,
            property_scope: AudioUnitScope,
            element: AudioUnitElement,
        ) !PropertyInfo {
            const size = try self.propertySize(
                property_id,
                property_scope,
                element,
            );
            return .{
                .size = size,
                .writable = switch (property_id) {
                    property.class_info,
                    property.sample_rate,
                    property.stream_format,
                    property.maximum_frames_per_slice,
                    property.set_render_callback,
                    => true,
                    else => false,
                },
            };
        }

        pub fn getProperty(
            self: *Self,
            property_id: AudioUnitPropertyID,
            property_scope: AudioUnitScope,
            element: AudioUnitElement,
            destination: []u8,
        ) !u32 {
            const expected_size = try self.propertySize(
                property_id,
                property_scope,
                element,
            );
            if (destination.len != expected_size)
                return error.InvalidPropertyValue;
            switch (property_id) {
                property.class_info => {
                    @memset(&self.state_storage, 0);
                    defer @memset(&self.state_storage, 0);
                    const state_bytes = try self.render_adapter.writeState(
                        &self.state_storage,
                    );
                    const class_info = try ClassInfoBridge.create(
                        state_bytes,
                    );
                    copyValue(destination, class_info);
                },
                property.parameter_list => {
                    var offset: usize = 0;
                    for (0..self.render_adapter.parameterCount()) |index| {
                        const parameter_id =
                            self.render_adapter.parameterId(index) orelse
                            return error.InvalidParameter;
                        copyValue(
                            destination[offset..][0..@sizeOf(
                                AudioUnitParameterID,
                            )],
                            parameter_id,
                        );
                        offset += @sizeOf(AudioUnitParameterID);
                    }
                },
                property.parameter_info => {
                    copyValue(
                        destination,
                        try self.parameterInfo(element),
                    );
                },
                property.sample_rate => {
                    copyValue(destination, self.render_adapter.sample_rate);
                },
                property.stream_format => {
                    const channels = try self.busChannelCount(
                        property_scope,
                        element,
                    );
                    copyValue(destination, self.streamFormat(channels));
                },
                property.element_count => {
                    const count: u32 = switch (property_scope) {
                        scope.input => @intCast(Adapter.input_bus_count),
                        scope.output => @intCast(Adapter.output_bus_count),
                        else => return error.InvalidScope,
                    };
                    copyValue(destination, count);
                },
                property.latency => {
                    copyValue(destination, self.samplesToSeconds(
                        self.render_adapter.latencySamples(),
                    ));
                },
                property.supported_channel_counts => {
                    const input_channels =
                        Adapter.inputBusChannelCount(0) orelse
                        return error.InvalidElement;
                    const output_channels =
                        Adapter.outputBusChannelCount(0) orelse
                        return error.InvalidElement;
                    if (input_channels > std.math.maxInt(i16) or
                        output_channels > std.math.maxInt(i16))
                        return error.InvalidPropertyValue;
                    copyValue(destination, AUChannelInfo{
                        .input_channels = @intCast(input_channels),
                        .output_channels = @intCast(output_channels),
                    });
                },
                property.maximum_frames_per_slice => {
                    const maximum: u32 = @intCast(
                        self.render_adapter.configured_maximum_frames,
                    );
                    copyValue(destination, maximum);
                },
                property.tail_time => {
                    copyValue(destination, self.samplesToSeconds(
                        self.render_adapter.tailSamples(),
                    ));
                },
                property.in_place_processing => {
                    const supported: u32 = @intFromBool(
                        Adapter.inputBusChannelCount(0) ==
                            Adapter.outputBusChannelCount(0),
                    );
                    copyValue(destination, supported);
                },
                property.set_render_callback => {
                    const callback = self.input_callbacks[element];
                    copyValue(destination, callback);
                },
                else => return error.InvalidProperty,
            }
            return expected_size;
        }

        pub fn getParameter(
            self: *Self,
            parameter_id: AudioUnitParameterID,
            parameter_scope: AudioUnitScope,
            element: AudioUnitElement,
        ) !AudioUnitParameterValue {
            try validateGlobalParameterAddress(
                parameter_scope,
                element,
            );
            const value =
                self.render_adapter.loadParameterPlainById(parameter_id) orelse
                return error.InvalidParameter;
            return try audioUnitParameterValue(value);
        }

        pub fn setParameter(
            self: *Self,
            parameter_id: AudioUnitParameterID,
            parameter_scope: AudioUnitScope,
            element: AudioUnitElement,
            value: AudioUnitParameterValue,
            buffer_offset_frames: u32,
        ) !void {
            try validateGlobalParameterAddress(
                parameter_scope,
                element,
            );
            if (buffer_offset_frames != 0)
                return self.scheduleImmediateParameter(
                    parameter_id,
                    value,
                    buffer_offset_frames,
                );
            if (!std.math.isFinite(value))
                return error.InvalidParameterValue;
            if (self.render_adapter.parameterIsReadOnlyById(
                parameter_id,
            ) orelse return error.InvalidParameter)
                return error.ParameterNotWritable;
            if (!self.render_adapter.storeParameterPlainById(
                parameter_id,
                value,
            ))
                return error.InvalidParameterValue;
            self.cached_block = null;
        }

        pub fn scheduleParameters(
            self: *Self,
            events: []const AudioUnitParameterEvent,
        ) !void {
            if (!self.valid()) return error.InvalidAudioUnitParameterEventState;
            if (events.len >
                maximum_parameter_events -
                    self.scheduled_parameter_event_count)
                return error.ParameterEventCapacityExceeded;
            var change_count = self.parameter_event_count;
            var ramp_count = self.parameter_ramp_count;
            const initial_change_count = change_count;
            const initial_ramp_count = ramp_count;
            errdefer {
                @memset(
                    self.parameter_events[initial_change_count..change_count],
                    .{},
                );
                @memset(
                    self.parameter_event_sequences[initial_change_count..change_count],
                    0,
                );
                @memset(
                    self.parameter_ramps[initial_ramp_count..ramp_count],
                    .{},
                );
            }
            for (events, 0..) |event, index| {
                const sequence =
                    self.scheduled_parameter_event_count + index;
                switch (event.event_type) {
                    parameter_event_type.immediate => {
                        self.parameter_events[change_count] =
                            try self.parameterChange(
                                event.parameter,
                                event.parameter_scope,
                                event.element,
                                event.event_values.immediate.value,
                                event.event_values.immediate.buffer_offset,
                            );
                        self.parameter_event_sequences[change_count] =
                            sequence;
                        change_count += 1;
                    },
                    parameter_event_type.ramped => {
                        self.parameter_ramps[ramp_count] =
                            try self.parameterRamp(
                                event.parameter,
                                event.parameter_scope,
                                event.element,
                                event.event_values.ramp,
                                sequence,
                            );
                        ramp_count += 1;
                    },
                    else => return error.InvalidParameterValue,
                }
            }
            self.parameter_event_count = change_count;
            self.parameter_ramp_count = ramp_count;
            self.scheduled_parameter_event_count += events.len;
            self.cached_block = null;
        }

        fn scheduleImmediateParameter(
            self: *Self,
            parameter_id: AudioUnitParameterID,
            value: AudioUnitParameterValue,
            buffer_offset_frames: u32,
        ) !void {
            if (!self.valid()) return error.InvalidAudioUnitParameterEventState;
            if (self.scheduled_parameter_event_count ==
                maximum_parameter_events)
                return error.ParameterEventCapacityExceeded;
            self.parameter_events[self.parameter_event_count] =
                try self.parameterChange(
                    parameter_id,
                    scope.global,
                    0,
                    value,
                    buffer_offset_frames,
                );
            self.parameter_event_sequences[self.parameter_event_count] =
                self.scheduled_parameter_event_count;
            self.parameter_event_count += 1;
            self.scheduled_parameter_event_count += 1;
            self.cached_block = null;
        }

        fn parameterRamp(
            self: *const Self,
            parameter_id: AudioUnitParameterID,
            parameter_scope: AudioUnitScope,
            element: AudioUnitElement,
            ramp: AudioUnitParameterRampEvent,
            sequence: usize,
        ) !process_api.ParameterRamp {
            try validateGlobalParameterAddress(
                parameter_scope,
                element,
            );
            if (self.render_adapter.parameterIsReadOnlyById(
                parameter_id,
            ) orelse return error.InvalidParameter)
                return error.ParameterNotWritable;
            if (!(self.render_adapter.parameterCanAutomateById(
                parameter_id,
            ) orelse return error.InvalidParameter))
                return error.ParameterNotAutomatable;
            const step_count =
                self.render_adapter.parameterStepCountById(
                    parameter_id,
                ) orelse return error.InvalidParameter;
            if (step_count != 0)
                return error.ParameterNotRampable;
            const result = process_api.ParameterRamp{
                .id = parameter_id,
                .start_offset = ramp.start_buffer_offset,
                .duration_frames = ramp.duration_in_frames,
                .start_normalized = self.render_adapter.parameterNormalizedFromPlainById(
                    parameter_id,
                    ramp.start_value,
                ) orelse return error.InvalidParameterValue,
                .end_normalized = self.render_adapter.parameterNormalizedFromPlainById(
                    parameter_id,
                    ramp.end_value,
                ) orelse return error.InvalidParameterValue,
                .sequence = sequence,
            };
            try result.validate(
                self.render_adapter.configured_maximum_frames,
            );
            return result;
        }

        fn parameterChange(
            self: *const Self,
            parameter_id: AudioUnitParameterID,
            parameter_scope: AudioUnitScope,
            element: AudioUnitElement,
            value: AudioUnitParameterValue,
            buffer_offset_frames: u32,
        ) !process_api.ParameterChange {
            try validateGlobalParameterAddress(
                parameter_scope,
                element,
            );
            if (!std.math.isFinite(value))
                return error.InvalidParameterValue;
            if (buffer_offset_frames >=
                self.render_adapter.configured_maximum_frames)
                return error.InvalidParameterOffset;
            if (self.render_adapter.parameterIsReadOnlyById(
                parameter_id,
            ) orelse return error.InvalidParameter)
                return error.ParameterNotWritable;
            if (!(self.render_adapter.parameterCanAutomateById(
                parameter_id,
            ) orelse return error.InvalidParameter))
                return error.ParameterNotAutomatable;
            const normalized =
                self.render_adapter.parameterNormalizedFromPlainById(
                    parameter_id,
                    value,
                ) orelse return error.InvalidParameterValue;
            return .{
                .id = parameter_id,
                .sample_offset = buffer_offset_frames,
                .normalized = normalized,
            };
        }

        pub fn setProperty(
            self: *Self,
            property_id: AudioUnitPropertyID,
            property_scope: AudioUnitScope,
            element: AudioUnitElement,
            source: []const u8,
        ) !void {
            if (property_id != property.class_info and
                self.render_adapter.initialized)
                return error.AudioUnitInitialized;
            const expected_size = try self.propertySize(
                property_id,
                property_scope,
                element,
            );
            if (source.len != expected_size)
                return error.InvalidPropertyValue;
            switch (property_id) {
                property.class_info => {
                    @memset(&self.state_storage, 0);
                    defer @memset(&self.state_storage, 0);
                    const class_info = std.mem.bytesToValue(
                        ?*const anyopaque,
                        source[0..@sizeOf(?*const anyopaque)],
                    );
                    const state_size = try ClassInfoBridge.copy(
                        class_info,
                        &self.state_storage,
                    );
                    if (state_size > self.state_storage.len)
                        return error.InvalidAudioUnitClassInfo;
                    try self.render_adapter.readState(
                        self.state_storage[0..state_size],
                    );
                    self.cached_block = null;
                    self.clearParameterEvents();
                },
                property.sample_rate => {
                    const sample_rate = std.mem.bytesToValue(
                        f64,
                        source[0..@sizeOf(f64)],
                    );
                    try self.reconfigure(
                        sample_rate,
                        self.render_adapter.configured_maximum_frames,
                    );
                },
                property.stream_format => {
                    const format = std.mem.bytesToValue(
                        AudioStreamBasicDescription,
                        source[0..@sizeOf(AudioStreamBasicDescription)],
                    );
                    const channels = try self.busChannelCount(
                        property_scope,
                        element,
                    );
                    const sample_bytes =
                        try validateStreamFormat(format, channels);
                    try self.reconfigure(
                        format.sample_rate,
                        self.render_adapter.configured_maximum_frames,
                    );
                    self.sample_bytes = sample_bytes;
                },
                property.maximum_frames_per_slice => {
                    const maximum_frames = std.mem.bytesToValue(
                        u32,
                        source[0..@sizeOf(u32)],
                    );
                    try self.reconfigure(
                        self.render_adapter.sample_rate,
                        maximum_frames,
                    );
                },
                property.set_render_callback => {
                    const callback = std.mem.bytesToValue(
                        AURenderCallbackStruct,
                        source[0..@sizeOf(AURenderCallbackStruct)],
                    );
                    self.input_callbacks[element] = callback;
                    self.cached_block = null;
                },
                else => return error.PropertyNotWritable,
            }
        }

        pub fn renderCallback(
            self: *Self,
            action_flags: ?*AudioUnitRenderActionFlags,
            timestamp: ?*const AudioTimeStamp,
            output_bus: u32,
            frame_count: u32,
            data: *AudioBufferList,
        ) !void {
            self.renderCallbackChecked(
                action_flags,
                timestamp,
                output_bus,
                frame_count,
                data,
            ) catch |err| {
                self.clearOutput(output_bus, data, frame_count);
                if (action_flags) |flags|
                    flags.* |= render_action.output_is_silence;
                return err;
            };
            if (action_flags) |flags|
                flags.* &= ~render_action.output_is_silence;
        }

        fn propertySize(
            self: *Self,
            property_id: AudioUnitPropertyID,
            property_scope: AudioUnitScope,
            element: AudioUnitElement,
        ) !u32 {
            return switch (property_id) {
                property.class_info => blk: {
                    if (!ClassInfoBridge.supported)
                        return error.InvalidProperty;
                    break :blk try globalPropertySize(
                        property_scope,
                        element,
                        @sizeOf(?*anyopaque),
                    );
                },
                property.parameter_list => blk: {
                    try validateGlobalParameterAddress(
                        property_scope,
                        element,
                    );
                    const count = self.render_adapter.parameterCount();
                    if (count > std.math.maxInt(u32) /
                        @sizeOf(AudioUnitParameterID))
                        return error.InvalidPropertyValue;
                    break :blk @intCast(
                        count * @sizeOf(AudioUnitParameterID),
                    );
                },
                property.parameter_info => blk: {
                    if (property_scope != scope.global)
                        return error.InvalidScope;
                    if (self.render_adapter.parameterNameById(
                        element,
                    ) == null)
                        return error.InvalidParameter;
                    break :blk @sizeOf(AudioUnitParameterInfo);
                },
                property.sample_rate => blk: {
                    _ = try self.busChannelCount(
                        property_scope,
                        element,
                    );
                    break :blk @sizeOf(f64);
                },
                property.stream_format => blk: {
                    _ = try self.busChannelCount(
                        property_scope,
                        element,
                    );
                    break :blk @sizeOf(AudioStreamBasicDescription);
                },
                property.element_count => blk: {
                    if (property_scope != scope.input and
                        property_scope != scope.output)
                        return error.InvalidScope;
                    if (element != 0)
                        return error.InvalidElement;
                    break :blk @sizeOf(u32);
                },
                property.latency,
                property.tail_time,
                => try globalPropertySize(
                    property_scope,
                    element,
                    @sizeOf(f64),
                ),
                property.supported_channel_counts => try globalPropertySize(
                    property_scope,
                    element,
                    @sizeOf(AUChannelInfo),
                ),
                property.maximum_frames_per_slice,
                property.in_place_processing,
                => try globalPropertySize(
                    property_scope,
                    element,
                    @sizeOf(u32),
                ),
                property.set_render_callback => blk: {
                    if (property_scope != scope.input)
                        return error.InvalidScope;
                    if (Adapter.inputBusChannelCount(
                        @intCast(element),
                    ) == null)
                        return error.InvalidElement;
                    break :blk @sizeOf(AURenderCallbackStruct);
                },
                else => error.InvalidProperty,
            };
        }

        fn parameterInfo(
            self: *const Self,
            parameter_id: AudioUnitParameterID,
        ) !AudioUnitParameterInfo {
            const name = self.render_adapter.parameterNameById(
                parameter_id,
            ) orelse return error.InvalidParameter;
            const default_value =
                self.render_adapter.parameterDefaultPlainById(
                    parameter_id,
                ) orelse return error.InvalidParameter;
            const read_only = self.render_adapter.parameterIsReadOnlyById(
                parameter_id,
            ) orelse return error.InvalidParameter;
            const can_automate = self.render_adapter.parameterCanAutomateById(
                parameter_id,
            ) orelse return error.InvalidParameter;
            const step_count = self.render_adapter.parameterStepCountById(
                parameter_id,
            ) orelse return error.InvalidParameter;
            const is_list = self.render_adapter.parameterIsListById(
                parameter_id,
            ) orelse return error.InvalidParameter;
            const minimum = self.render_adapter.parameterPlainMinimumById(
                parameter_id,
            ) orelse 0.0;
            const maximum = self.render_adapter.parameterPlainMaximumById(
                parameter_id,
            ) orelse @as(f64, @floatFromInt(step_count));
            var info = AudioUnitParameterInfo{
                .name = [_]u8{0} ** 52,
                .unit_name = null,
                .clump_id = 0,
                .cf_name_string = null,
                .unit = parameterUnit(
                    self.render_adapter.parameterUnitsById(
                        parameter_id,
                    ) orelse "",
                    step_count,
                    is_list,
                ),
                .min_value = try audioUnitParameterValue(minimum),
                .max_value = try audioUnitParameterValue(maximum),
                .default_value = try audioUnitParameterValue(default_value),
                .flags = parameter_flag.is_readable,
            };
            const name_length = @min(name.len, info.name.len - 1);
            @memcpy(info.name[0..name_length], name[0..name_length]);
            if (!read_only)
                info.flags |= parameter_flag.is_writable;
            if (!read_only and can_automate and step_count == 0)
                info.flags |= parameter_flag.is_high_resolution |
                    parameter_flag.can_ramp;
            return info;
        }

        fn busChannelCount(
            _: *Self,
            property_scope: AudioUnitScope,
            element: AudioUnitElement,
        ) !u32 {
            return switch (property_scope) {
                scope.input => Adapter.inputBusChannelCount(
                    @intCast(element),
                ) orelse error.InvalidElement,
                scope.output => Adapter.outputBusChannelCount(
                    @intCast(element),
                ) orelse error.InvalidElement,
                else => error.InvalidScope,
            };
        }

        fn streamFormat(
            self: *const Self,
            channels: u32,
        ) AudioStreamBasicDescription {
            return .{
                .sample_rate = self.render_adapter.sample_rate,
                .format_id = audio_format.linear_pcm,
                .format_flags = audio_format.native_float_non_interleaved,
                .bytes_per_packet = self.sample_bytes,
                .frames_per_packet = 1,
                .bytes_per_frame = self.sample_bytes,
                .channels_per_frame = channels,
                .bits_per_channel = self.sample_bytes * 8,
                .reserved = 0,
            };
        }

        fn samplesToSeconds(
            self: *const Self,
            samples: u32,
        ) f64 {
            return @as(f64, @floatFromInt(samples)) /
                self.render_adapter.sample_rate;
        }

        fn reconfigure(
            self: *Self,
            sample_rate: f64,
            maximum_frames: usize,
        ) !void {
            if (!std.math.isFinite(sample_rate) or sample_rate <= 0)
                return error.InvalidPropertyValue;
            if (maximum_frames == 0 or
                maximum_frames > Adapter.maximum_frames)
                return error.InvalidPropertyValue;
            try self.render_adapter.configure(
                sample_rate,
                maximum_frames,
                self.render_adapter.process_mode,
            );
            self.cached_block = null;
            self.clearParameterEvents();
        }

        fn clearParameterEvents(self: *Self) void {
            @memset(&self.parameter_events, .{});
            @memset(&self.parameter_event_sequences, 0);
            @memset(&self.parameter_ramps, .{});
            self.parameter_event_count = 0;
            self.parameter_ramp_count = 0;
            self.scheduled_parameter_event_count = 0;
        }

        fn blockKey(
            timestamp: ?*const AudioTimeStamp,
            frame_count: u32,
        ) !?BlockKey {
            const value = timestamp orelse return null;
            const identity_flags = value.flags &
                (timestamp_flag.sample_time_valid |
                    timestamp_flag.host_time_valid);
            if (identity_flags == 0)
                return null;
            if (identity_flags & timestamp_flag.sample_time_valid != 0 and
                !std.math.isFinite(value.sample_time))
                return error.InvalidTimestamp;
            return .{
                .valid_identity = @intCast(identity_flags),
                .sample_time_bits = if (identity_flags &
                    timestamp_flag.sample_time_valid != 0)
                    @bitCast(value.sample_time)
                else
                    0,
                .host_time = if (identity_flags &
                    timestamp_flag.host_time_valid != 0)
                    value.host_time
                else
                    0,
                .frame_count = frame_count,
            };
        }

        fn renderCallbackChecked(
            self: *Self,
            action_flags: ?*AudioUnitRenderActionFlags,
            timestamp: ?*const AudioTimeStamp,
            output_bus: u32,
            frame_count: u32,
            data: *AudioBufferList,
        ) !void {
            if (!self.render_adapter.initialized)
                return error.AudioUnitUninitialized;
            if (Adapter.outputBusChannelCount(output_bus) == null)
                return error.InvalidElement;
            if (frame_count > self.render_adapter.configured_maximum_frames)
                return error.AudioUnitBlockTooLarge;
            const block_key = try blockKey(timestamp, frame_count);
            if (Adapter.output_bus_count > 1 and block_key == null)
                return error.InvalidTimestamp;
            if (self.sample_bytes == @sizeOf(f32)) {
                try self.renderTyped(
                    f32,
                    action_flags,
                    timestamp,
                    block_key,
                    output_bus,
                    frame_count,
                    data,
                );
            } else if (self.sample_bytes == @sizeOf(f64)) {
                try self.renderTyped(
                    f64,
                    action_flags,
                    timestamp,
                    block_key,
                    output_bus,
                    frame_count,
                    data,
                );
            } else {
                return error.FormatNotSupported;
            }
        }

        fn renderTyped(
            self: *Self,
            comptime Sample: type,
            action_flags: ?*AudioUnitRenderActionFlags,
            timestamp: ?*const AudioTimeStamp,
            block_key: ?BlockKey,
            output_bus: u32,
            frame_count: u32,
            data: *AudioBufferList,
        ) !void {
            const needs_processing = if (block_key) |current_block|
                if (self.cached_block) |cached|
                    !std.meta.eql(cached, current_block)
                else
                    true
            else
                true;
            if (needs_processing) {
                self.cached_block = null;
                try self.processBlock(
                    Sample,
                    action_flags,
                    timestamp,
                    frame_count,
                );
                self.cached_block = block_key;
            }
            try self.deliverOutputBus(
                Sample,
                output_bus,
                frame_count,
                data,
            );
        }

        fn processBlock(
            self: *Self,
            comptime Sample: type,
            action_flags: ?*AudioUnitRenderActionFlags,
            timestamp: ?*const AudioTimeStamp,
            frame_count: u32,
        ) !void {
            if (!self.valid()) return error.InvalidAudioUnitParameterEventState;
            const parameter_changes =
                self.parameter_events[0..self.parameter_event_count];
            const parameter_change_sequences =
                self.parameter_event_sequences[0..self.parameter_event_count];
            const parameter_ramps =
                self.parameter_ramps[0..self.parameter_ramp_count];
            for (parameter_changes) |change|
                try change.validate(frame_count);
            for (parameter_ramps) |ramp|
                try ramp.validate(frame_count);
            const input_headers = try self.pullInputs(
                Sample,
                action_flags,
                timestamp,
                frame_count,
            );
            const output_headers =
                self.cachedOutputChannels(Sample, frame_count);
            const main_input_count = Adapter.input_channel_count;
            const main_output_count = Adapter.output_channel_count;
            if (Sample == f32) {
                try self.render_adapter.render(.{
                    .input_channels = input_headers[0..main_input_count],
                    .auxiliary_input_channels = input_headers[main_input_count..],
                    .output_channels = output_headers[0..main_output_count],
                    .auxiliary_output_channels = output_headers[main_output_count..],
                    .attachments = .{
                        .parameter_changes = parameter_changes,
                        .parameter_change_sequences = parameter_change_sequences,
                        .parameter_ramps = parameter_ramps,
                    },
                });
            } else if (Sample == f64) {
                try self.render_adapter.render64(.{
                    .input_channels = input_headers[0..main_input_count],
                    .auxiliary_input_channels = input_headers[main_input_count..],
                    .output_channels = output_headers[0..main_output_count],
                    .auxiliary_output_channels = output_headers[main_output_count..],
                    .attachments = .{
                        .parameter_changes = parameter_changes,
                        .parameter_change_sequences = parameter_change_sequences,
                        .parameter_ramps = parameter_ramps,
                    },
                });
            }
            self.clearParameterEvents();
        }

        fn pullInputs(
            self: *Self,
            comptime Sample: type,
            action_flags: ?*AudioUnitRenderActionFlags,
            timestamp: ?*const AudioTimeStamp,
            frame_count: u32,
        ) ![]const []const Sample {
            var storage: InputBufferList = undefined;
            var flat_channel: usize = 0;
            for (0..Adapter.input_bus_count) |bus| {
                const channel_count =
                    Adapter.inputBusChannelCount(bus) orelse
                    return error.InvalidElement;
                if (channel_count == 0)
                    continue;
                const callback = self.input_callbacks[bus].input orelse
                    return error.NoConnection;
                storage.number_buffers = channel_count;
                for (0..channel_count) |channel| {
                    const scratch = if (Sample == f32)
                        self.input_scratch_f32[flat_channel + channel][0..frame_count]
                    else
                        self.input_scratch_f64[flat_channel + channel][0..frame_count];
                    storage.buffers[channel] = .{
                        .number_channels = 1,
                        .data_byte_size = frame_count * @sizeOf(Sample),
                        .data = scratch.ptr,
                    };
                }
                const list: *AudioBufferList = @ptrCast(&storage);
                const callback_status = callback(
                    self.input_callbacks[bus].reference,
                    action_flags,
                    timestamp,
                    @intCast(bus),
                    frame_count,
                    list,
                );
                if (callback_status != status.success)
                    return error.NoConnection;
                if (list.number_buffers != channel_count)
                    return error.FormatNotSupported;
                const pulled_buffers = audioBuffers(list);
                for (pulled_buffers[0..channel_count], 0..) |
                    buffer,
                    channel,
                | {
                    if (buffer.number_channels != 1 or
                        buffer.data_byte_size <
                            frame_count * @sizeOf(Sample))
                        return error.FormatNotSupported;
                    const input_data = buffer.data orelse
                        return error.FormatNotSupported;
                    const samples = @as(
                        [*]const Sample,
                        @ptrCast(@alignCast(input_data)),
                    )[0..frame_count];
                    if (Sample == f32) {
                        self.input_headers_f32[
                            flat_channel + channel
                        ] = samples;
                    } else {
                        self.input_headers_f64[
                            flat_channel + channel
                        ] = samples;
                    }
                }
                flat_channel += channel_count;
            }
            if (flat_channel != total_input_channels)
                return error.FormatNotSupported;
            return if (Sample == f32)
                self.input_headers_f32[0..]
            else
                self.input_headers_f64[0..];
        }

        fn cachedOutputChannels(
            self: *Self,
            comptime Sample: type,
            frame_count: u32,
        ) []const []Sample {
            for (0..total_output_channels) |channel| {
                if (Sample == f32) {
                    self.output_headers_f32[channel] =
                        self.output_cache_f32[channel][0..frame_count];
                } else {
                    self.output_headers_f64[channel] =
                        self.output_cache_f64[channel][0..frame_count];
                }
            }
            return if (Sample == f32)
                self.output_headers_f32[0..]
            else
                self.output_headers_f64[0..];
        }

        fn deliverOutputBus(
            self: *Self,
            comptime Sample: type,
            output_bus: u32,
            frame_count: u32,
            data: *AudioBufferList,
        ) !void {
            const channel_count = Adapter.outputBusChannelCount(
                @intCast(output_bus),
            ) orelse return error.InvalidElement;
            if (data.number_buffers != channel_count)
                return error.FormatNotSupported;
            const first_channel = try outputBusChannelOffset(output_bus);
            const buffers = audioBuffers(data);
            for (buffers[0..channel_count], 0..) |buffer, channel| {
                if (buffer.number_channels != 1 or
                    buffer.data_byte_size <
                        frame_count * @sizeOf(Sample))
                    return error.FormatNotSupported;
                const output_data = buffer.data orelse
                    return error.FormatNotSupported;
                const destination = @as(
                    [*]Sample,
                    @ptrCast(@alignCast(output_data)),
                )[0..frame_count];
                const source = if (Sample == f32)
                    self.output_cache_f32[first_channel + channel][0..frame_count]
                else
                    self.output_cache_f64[first_channel + channel][0..frame_count];
                @memcpy(destination, source);
            }
        }

        fn outputBusChannelOffset(output_bus: u32) !usize {
            if (output_bus >= Adapter.output_bus_count)
                return error.InvalidElement;
            var offset: usize = 0;
            for (0..output_bus) |bus| {
                offset += Adapter.outputBusChannelCount(bus) orelse
                    return error.InvalidElement;
            }
            return offset;
        }

        fn clearOutput(
            _: *Self,
            output_bus: u32,
            data: *AudioBufferList,
            frame_count: u32,
        ) void {
            const expected_channels =
                Adapter.outputBusChannelCount(
                    @intCast(output_bus),
                ) orelse 0;
            const buffer_count = @min(
                data.number_buffers,
                expected_channels,
            );
            const buffers = audioBuffers(data);
            for (buffers[0..buffer_count]) |buffer| {
                const output_data = buffer.data orelse continue;
                const byte_count = @min(
                    buffer.data_byte_size,
                    frame_count * @as(u32, @intCast(@sizeOf(f64))),
                );
                @memset(
                    @as([*]u8, @ptrCast(output_data))[0..byte_count],
                    0,
                );
            }
        }
    };
}

fn audioBuffers(list: *AudioBufferList) [*]AudioBuffer {
    return @ptrCast(&list.buffers);
}

fn globalPropertySize(
    property_scope: AudioUnitScope,
    element: AudioUnitElement,
    size: u32,
) !u32 {
    if (property_scope != scope.global)
        return error.InvalidScope;
    if (element != 0)
        return error.InvalidElement;
    return size;
}

fn validateGlobalParameterAddress(
    parameter_scope: AudioUnitScope,
    element: AudioUnitElement,
) !void {
    if (parameter_scope != scope.global)
        return error.InvalidScope;
    if (element != 0)
        return error.InvalidElement;
}

fn audioUnitParameterValue(value: f64) !AudioUnitParameterValue {
    if (!std.math.isFinite(value) or
        value < -std.math.floatMax(AudioUnitParameterValue) or
        value > std.math.floatMax(AudioUnitParameterValue))
        return error.InvalidParameterValue;
    return @floatCast(value);
}

fn parameterUnit(
    units: []const u8,
    step_count: i32,
    is_list: bool,
) AudioUnitParameterUnit {
    if (is_list or step_count > 1)
        return parameter_unit.indexed;
    if (step_count == 1)
        return parameter_unit.boolean;
    if (std.ascii.eqlIgnoreCase(units, "%") or
        std.ascii.eqlIgnoreCase(units, "percent"))
        return parameter_unit.percent;
    if (std.ascii.eqlIgnoreCase(units, "s") or
        std.ascii.eqlIgnoreCase(units, "seconds"))
        return parameter_unit.seconds;
    if (std.ascii.eqlIgnoreCase(units, "samples") or
        std.ascii.eqlIgnoreCase(units, "frames"))
        return parameter_unit.sample_frames;
    if (std.ascii.eqlIgnoreCase(units, "hz"))
        return parameter_unit.hertz;
    if (std.ascii.eqlIgnoreCase(units, "cents"))
        return parameter_unit.cents;
    if (std.ascii.eqlIgnoreCase(units, "semitones"))
        return parameter_unit.relative_semitones;
    if (std.ascii.eqlIgnoreCase(units, "db"))
        return parameter_unit.decibels;
    if (std.ascii.eqlIgnoreCase(units, "degrees"))
        return parameter_unit.degrees;
    if (std.ascii.eqlIgnoreCase(units, "bpm"))
        return parameter_unit.bpm;
    if (std.ascii.eqlIgnoreCase(units, "beats"))
        return parameter_unit.beats;
    if (std.ascii.eqlIgnoreCase(units, "ms") or
        std.ascii.eqlIgnoreCase(units, "milliseconds"))
        return parameter_unit.milliseconds;
    if (std.ascii.eqlIgnoreCase(units, "ratio"))
        return parameter_unit.ratio;
    return parameter_unit.generic;
}

fn validateStreamFormat(
    format: AudioStreamBasicDescription,
    channels: u32,
) !u32 {
    if (!std.math.isFinite(format.sample_rate) or
        format.sample_rate <= 0 or
        format.format_id != audio_format.linear_pcm or
        format.format_flags !=
            audio_format.native_float_non_interleaved or
        format.frames_per_packet != 1 or
        format.channels_per_frame != channels or
        format.reserved != 0)
        return error.InvalidPropertyValue;
    const sample_bytes = switch (format.bits_per_channel) {
        32 => @as(u32, @sizeOf(f32)),
        64 => @as(u32, @sizeOf(f64)),
        else => return error.InvalidPropertyValue,
    };
    if (format.bytes_per_packet != sample_bytes or
        format.bytes_per_frame != sample_bytes)
        return error.InvalidPropertyValue;
    return sample_bytes;
}

fn copyValue(destination: []u8, value: anytype) void {
    var copy = value;
    @memcpy(destination, std.mem.asBytes(&copy));
}

fn propertyStatus(err: anyerror) OSStatus {
    return switch (err) {
        error.InvalidProperty => status.invalid_property,
        error.InvalidScope => status.invalid_scope,
        error.InvalidElement => status.invalid_element,
        error.PropertyNotWritable => status.property_not_writable,
        error.InvalidPropertyValue => status.invalid_property_value,
        error.InvalidParameter,
        error.InvalidParameterValue,
        error.InvalidParameterOffset,
        error.ParameterNotAutomatable,
        error.ParameterNotRampable,
        error.ParameterRampHasZeroDuration,
        error.ParameterRampOutsideBlock,
        error.ParameterRampOutsideNormalizedRange,
        => status.invalid_parameter,
        error.AudioUnitInitialized => status.initialized,
        else => status.cannot_do_in_current_context,
    };
}

fn parameterStatus(err: anyerror) OSStatus {
    return switch (err) {
        error.InvalidScope => status.invalid_scope,
        error.InvalidElement => status.invalid_element,
        error.InvalidParameter,
        error.InvalidParameterValue,
        error.InvalidParameterOffset,
        error.ParameterNotAutomatable,
        error.ParameterNotRampable,
        error.ParameterRampHasZeroDuration,
        error.ParameterRampOutsideBlock,
        error.ParameterRampOutsideNormalizedRange,
        => status.invalid_parameter,
        error.ParameterNotWritable => status.property_not_writable,
        else => status.cannot_do_in_current_context,
    };
}

fn renderStatus(err: anyerror) OSStatus {
    return switch (err) {
        error.AudioUnitUninitialized => status.uninitialized,
        error.AudioUnitBlockTooLarge => status.too_many_frames,
        error.InvalidElement => status.invalid_element,
        error.NoConnection => status.no_connection,
        error.FormatNotSupported => status.format_not_supported,
        else => status.cannot_do_in_current_context,
    };
}

test "AUv2 public ABI names are exact internal aliases" {
    comptime {
        if (OSStatus != abi.OSStatus or
            OSType != abi.OSType or
            AudioUnitPropertyID != abi.AudioUnitPropertyID or
            AudioUnitScope != abi.AudioUnitScope or
            AudioUnitElement != abi.AudioUnitElement or
            AudioUnitParameterID != abi.AudioUnitParameterID or
            AudioUnitParameterValue != abi.AudioUnitParameterValue or
            AudioUnitParameterUnit != abi.AudioUnitParameterUnit or
            AudioUnitParameterOptions != abi.AudioUnitParameterOptions or
            AudioUnitRenderActionFlags != abi.AudioUnitRenderActionFlags or
            Boolean != abi.Boolean or
            AudioStreamBasicDescription != abi.AudioStreamBasicDescription or
            SMPTETime != abi.SMPTETime or
            AudioTimeStamp != abi.AudioTimeStamp or
            timestamp_flag != abi.timestamp_flag or
            AUChannelInfo != abi.AUChannelInfo or
            AudioUnitParameterInfo != abi.AudioUnitParameterInfo or
            AUParameterEventType != abi.AUParameterEventType or
            parameter_event_type != abi.parameter_event_type or
            AudioUnitParameterRampEvent != abi.AudioUnitParameterRampEvent or
            AudioUnitParameterImmediateEvent != abi.AudioUnitParameterImmediateEvent or
            AudioUnitParameterEvent != abi.AudioUnitParameterEvent or
            AudioComponentDescription != abi.AudioComponentDescription or
            AudioBuffer != abi.AudioBuffer or
            AudioBufferList != abi.AudioBufferList or
            AURenderCallback != abi.AURenderCallback or
            AudioUnitPropertyListenerProc != abi.AudioUnitPropertyListenerProc or
            AURenderCallbackStruct != abi.AURenderCallbackStruct or
            AudioComponentInstance != abi.AudioComponentInstance or
            AudioComponentMethod != abi.AudioComponentMethod or
            AudioComponentPlugInInterface != abi.AudioComponentPlugInInterface or
            selector != abi.selector or
            scope != abi.scope or
            property != abi.property or
            parameter_unit != abi.parameter_unit or
            parameter_flag != abi.parameter_flag or
            render_action != abi.render_action or
            audio_format != abi.audio_format or
            status != abi.status)
        {
            @compileError("AUv2 public ABI alias identity changed");
        }
    }
}

test "AUv2 declarations retain their public ABI shape" {
    try std.testing.expectEqual(@as(usize, 20), @sizeOf(AudioComponentDescription));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(AudioComponentDescription));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(AudioComponentDescription, "component_type"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(AudioComponentDescription, "component_flags_mask"));

    try std.testing.expectEqual(@sizeOf(usize) + 8, @sizeOf(AudioBuffer));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(AudioBuffer, "data"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(AudioBufferList, "buffers"));
    try std.testing.expectEqual(4 * @sizeOf(usize), @sizeOf(AudioComponentPlugInInterface));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(AudioComponentPlugInInterface, "open"));
    try std.testing.expectEqual(3 * @sizeOf(usize), @offsetOf(AudioComponentPlugInInterface, "reserved"));
    try std.testing.expectEqual(
        @as(usize, 40),
        @sizeOf(AudioStreamBasicDescription),
    );
    try std.testing.expectEqual(
        @as(usize, 8),
        @alignOf(AudioStreamBasicDescription),
    );
    try std.testing.expectEqual(
        @as(usize, 32),
        @offsetOf(AudioStreamBasicDescription, "bits_per_channel"),
    );
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(AUChannelInfo));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(SMPTETime));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(AudioTimeStamp));
    try std.testing.expectEqual(
        @as(usize, 56),
        @offsetOf(AudioTimeStamp, "flags"),
    );
    try std.testing.expectEqual(
        @as(usize, if (@sizeOf(usize) == 8) 104 else 84),
        @sizeOf(AudioUnitParameterInfo),
    );
    try std.testing.expectEqual(
        @as(usize, if (@sizeOf(usize) == 8) 56 else 52),
        @offsetOf(AudioUnitParameterInfo, "unit_name"),
    );
    try std.testing.expectEqual(
        @as(usize, if (@sizeOf(usize) == 8) 96 else 80),
        @offsetOf(AudioUnitParameterInfo, "flags"),
    );
    try std.testing.expectEqual(
        @as(usize, 32),
        @sizeOf(AudioUnitParameterEvent),
    );
    try std.testing.expectEqual(
        @as(usize, 16),
        @offsetOf(AudioUnitParameterEvent, "event_values"),
    );
}

test "AUv2 selector, scope, property, and render constants are exact" {
    try std.testing.expectEqual(@as(i16, 0x000e), selector.render);
    try std.testing.expectEqual(@as(i16, 0x0015), selector.process_multiple);
    try std.testing.expectEqual(@as(AudioUnitScope, 2), scope.output);
    try std.testing.expectEqual(@as(AudioUnitPropertyID, 14), property.maximum_frames_per_slice);
    try std.testing.expectEqual(@as(AudioUnitRenderActionFlags, 1 << 9), render_action.do_not_check_render_args);
}

test "AUv2 lifecycle dispatch checks open state, scope, and element" {
    const Probe = struct {
        active: bool = false,
        resets: usize = 0,

        fn initialize(self: *@This()) !void {
            self.active = true;
        }

        fn uninitialize(self: *@This()) !void {
            self.active = false;
        }

        fn reset(self: *@This()) !void {
            if (!self.active)
                return error.AudioUnitUninitialized;
            self.resets += 1;
        }
    };
    const Dispatch = LifecycleDispatch(Probe);
    const InitializeProc =
        *const fn (*anyopaque) callconv(.c) OSStatus;
    const ResetProc = *const fn (
        *anyopaque,
        AudioUnitScope,
        AudioUnitElement,
    ) callconv(.c) OSStatus;

    var probe = Probe{};
    var dispatch = Dispatch.init(&probe);
    try std.testing.expect(dispatch.valid());
    for (dispatch.property_listeners) |entry|
        try std.testing.expectEqualDeep(
            Dispatch.empty_property_listener,
            entry,
        );
    const interface = dispatch.asInterface();
    const opaque_interface: *anyopaque = @ptrCast(interface);
    const instance: AudioComponentInstance = @ptrFromInt(1);

    const initialize_method = interface.lookup(selector.initialize) orelse
        return error.MissingInitializeSelector;
    const initialize_proc: InitializeProc =
        @ptrCast(@alignCast(initialize_method));
    const reset_method = interface.lookup(selector.reset) orelse
        return error.MissingResetSelector;
    const reset_proc: ResetProc = @ptrCast(@alignCast(reset_method));

    try std.testing.expectEqual(
        status.uninitialized,
        initialize_proc(opaque_interface),
    );
    try std.testing.expectEqual(
        status.success,
        interface.open(opaque_interface, instance),
    );
    try std.testing.expectEqual(
        status.initialized,
        interface.open(opaque_interface, instance),
    );
    try std.testing.expectEqual(
        status.success,
        initialize_proc(opaque_interface),
    );
    try std.testing.expect(probe.active);
    try std.testing.expectEqual(
        status.invalid_scope,
        reset_proc(opaque_interface, scope.input, 0),
    );
    try std.testing.expectEqual(
        status.invalid_element,
        reset_proc(opaque_interface, scope.global, 1),
    );
    try std.testing.expectEqual(
        status.success,
        reset_proc(opaque_interface, scope.global, 0),
    );
    try std.testing.expectEqual(@as(usize, 1), probe.resets);
    try std.testing.expectEqual(
        status.success,
        interface.close(opaque_interface),
    );
    try std.testing.expect(!probe.active);
    try std.testing.expectEqual(
        status.uninitialized,
        interface.close(opaque_interface),
    );
    try std.testing.expect(interface.lookup(0x7fff) == null);
}

test "AUv2 component factory owns one dispatch instance through close" {
    const Plugin = struct {
        pub const name = "AUv2 Factory Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: process_api.AudioBusLayout = .mono;
        pub const audio_output_layout: process_api.AudioBusLayout = .mono;
        pub const Params = struct {};

        pub fn process(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
        ) void {}
    };
    const description = AudioComponentDescription{
        .component_type = 0x61756678,
        .component_subtype = 0x5a475031,
        .component_manufacturer = 0x5a696733,
        .component_flags = 0,
        .component_flags_mask = 0,
    };
    const Factory = ComponentFactory(
        Plugin,
        512,
        description,
        48_000.0,
        128,
    );

    var wrong_description = description;
    wrong_description.component_subtype = 0;
    try std.testing.expect(Factory.create(&wrong_description) == null);
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expect(
        Factory.createWithAllocator(
            &description,
            failing.allocator(),
        ) == null,
    );
    const interface = Factory.createWithAllocator(
        &description,
        std.testing.allocator,
    ) orelse
        return error.FactoryCreationFailed;
    const opaque_interface: *anyopaque = @ptrCast(interface);
    const instance: AudioComponentInstance = @ptrFromInt(1);
    try std.testing.expectEqual(
        status.success,
        interface.open(opaque_interface, instance),
    );
    const initialize_method =
        interface.lookup(selector.initialize) orelse
        return error.MissingInitializeSelector;
    const initialize: *const fn (
        *anyopaque,
    ) callconv(.c) OSStatus = @ptrCast(@alignCast(initialize_method));
    try std.testing.expectEqual(
        status.success,
        initialize(opaque_interface),
    );
    try std.testing.expectEqual(
        status.success,
        interface.close(opaque_interface),
    );
}

test "AUv2 property dispatch preserves sizes writability and errors" {
    const Probe = struct {
        maximum_frames: u32 = 512,

        fn initialize(_: *@This()) !void {}
        fn uninitialize(_: *@This()) !void {}
        fn reset(_: *@This()) !void {}

        fn propertyInfo(
            _: *@This(),
            property_id: AudioUnitPropertyID,
            property_scope: AudioUnitScope,
            element: AudioUnitElement,
        ) !PropertyInfo {
            if (property_scope != scope.global)
                return error.InvalidScope;
            if (element != 0)
                return error.InvalidElement;
            return switch (property_id) {
                property.maximum_frames_per_slice => .{
                    .size = @sizeOf(u32),
                    .writable = true,
                },
                property.latency => .{
                    .size = @sizeOf(f64),
                    .writable = false,
                },
                else => error.InvalidProperty,
            };
        }

        fn getProperty(
            self: *@This(),
            property_id: AudioUnitPropertyID,
            _: AudioUnitScope,
            _: AudioUnitElement,
            destination: []u8,
        ) !u32 {
            switch (property_id) {
                property.maximum_frames_per_slice => {
                    @memcpy(
                        destination,
                        std.mem.asBytes(&self.maximum_frames),
                    );
                    return @sizeOf(u32);
                },
                property.latency => {
                    const latency: f64 = 0.125;
                    @memcpy(
                        destination,
                        std.mem.asBytes(&latency),
                    );
                    return @sizeOf(f64);
                },
                else => return error.InvalidProperty,
            }
        }

        fn setProperty(
            self: *@This(),
            property_id: AudioUnitPropertyID,
            _: AudioUnitScope,
            _: AudioUnitElement,
            source: []const u8,
        ) !void {
            if (property_id != property.maximum_frames_per_slice)
                return error.PropertyNotWritable;
            self.maximum_frames =
                std.mem.bytesToValue(u32, source[0..@sizeOf(u32)]);
        }
    };
    const Dispatch = ComponentDispatch(Probe);
    const GetInfoProc = *const fn (
        *anyopaque,
        AudioUnitPropertyID,
        AudioUnitScope,
        AudioUnitElement,
        ?*u32,
        ?*Boolean,
    ) callconv(.c) OSStatus;
    const GetProc = *const fn (
        *anyopaque,
        AudioUnitPropertyID,
        AudioUnitScope,
        AudioUnitElement,
        ?*anyopaque,
        ?*u32,
    ) callconv(.c) OSStatus;
    const SetProc = *const fn (
        *anyopaque,
        AudioUnitPropertyID,
        AudioUnitScope,
        AudioUnitElement,
        ?*const anyopaque,
        u32,
    ) callconv(.c) OSStatus;

    var probe = Probe{};
    var dispatch = Dispatch.init(&probe);
    const interface = dispatch.asInterface();
    const opaque_interface: *anyopaque = @ptrCast(interface);
    const get_info: GetInfoProc = @ptrCast(@alignCast(
        interface.lookup(selector.get_property_info) orelse
            return error.MissingPropertyInfoSelector,
    ));
    const get: GetProc = @ptrCast(@alignCast(
        interface.lookup(selector.get_property) orelse
            return error.MissingGetPropertySelector,
    ));
    const set: SetProc = @ptrCast(@alignCast(
        interface.lookup(selector.set_property) orelse
            return error.MissingSetPropertySelector,
    ));

    var size: u32 = 0;
    var writable: Boolean = 0;
    try std.testing.expectEqual(
        status.success,
        get_info(
            opaque_interface,
            property.maximum_frames_per_slice,
            scope.global,
            0,
            &size,
            &writable,
        ),
    );
    try std.testing.expectEqual(@as(u32, @sizeOf(u32)), size);
    try std.testing.expectEqual(@as(Boolean, 1), writable);

    var frames: u32 = 0;
    try std.testing.expectEqual(
        status.success,
        get(
            opaque_interface,
            property.maximum_frames_per_slice,
            scope.global,
            0,
            &frames,
            &size,
        ),
    );
    try std.testing.expectEqual(@as(u32, 512), frames);

    const replacement: u32 = 1024;
    try std.testing.expectEqual(
        status.success,
        set(
            opaque_interface,
            property.maximum_frames_per_slice,
            scope.global,
            0,
            &replacement,
            @sizeOf(u32),
        ),
    );
    try std.testing.expectEqual(replacement, probe.maximum_frames);

    size = @sizeOf(u32) - 1;
    try std.testing.expectEqual(
        status.invalid_property_value,
        get(
            opaque_interface,
            property.maximum_frames_per_slice,
            scope.global,
            0,
            &frames,
            &size,
        ),
    );
    try std.testing.expectEqual(@as(u32, @sizeOf(u32)), size);
    try std.testing.expectEqual(
        status.property_not_writable,
        set(
            opaque_interface,
            property.latency,
            scope.global,
            0,
            &replacement,
            @sizeOf(f64),
        ),
    );
    try std.testing.expectEqual(
        status.invalid_scope,
        get_info(
            opaque_interface,
            property.maximum_frames_per_slice,
            scope.input,
            0,
            null,
            null,
        ),
    );
    try std.testing.expectEqual(
        status.invalid_property,
        get_info(
            opaque_interface,
            0xffff,
            scope.global,
            0,
            null,
            null,
        ),
    );
}

test "AUv2 property listeners preserve callback tuples and removals" {
    const Probe = struct {
        value: u32 = 0,

        fn initialize(_: *@This()) !void {}
        fn uninitialize(_: *@This()) !void {}
        fn reset(_: *@This()) !void {}

        fn propertyInfo(
            _: *@This(),
            property_id: AudioUnitPropertyID,
            property_scope: AudioUnitScope,
            element: AudioUnitElement,
        ) !PropertyInfo {
            if (property_id != property.maximum_frames_per_slice)
                return error.InvalidProperty;
            if (property_scope != scope.global)
                return error.InvalidScope;
            if (element != 0)
                return error.InvalidElement;
            return .{ .size = @sizeOf(u32), .writable = true };
        }

        fn getProperty(
            self: *@This(),
            _: AudioUnitPropertyID,
            _: AudioUnitScope,
            _: AudioUnitElement,
            destination: []u8,
        ) !u32 {
            copyValue(destination, self.value);
            return @sizeOf(u32);
        }

        fn setProperty(
            self: *@This(),
            _: AudioUnitPropertyID,
            _: AudioUnitScope,
            _: AudioUnitElement,
            source: []const u8,
        ) !void {
            self.value = std.mem.bytesToValue(
                u32,
                source[0..@sizeOf(u32)],
            );
        }
    };
    const ListenerState = struct {
        calls: usize = 0,
        unit: ?AudioComponentInstance = null,
        property_id: AudioUnitPropertyID = 0,
        property_scope: AudioUnitScope = 0,
        element: AudioUnitElement = 0,

        fn callback(
            reference: ?*anyopaque,
            unit: AudioComponentInstance,
            property_id: AudioUnitPropertyID,
            property_scope: AudioUnitScope,
            element: AudioUnitElement,
        ) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(
                reference orelse return,
            ));
            self.calls += 1;
            self.unit = unit;
            self.property_id = property_id;
            self.property_scope = property_scope;
            self.element = element;
        }
    };
    const Dispatch = ComponentDispatch(Probe);
    const AddProc = *const fn (
        *anyopaque,
        AudioUnitPropertyID,
        AudioUnitPropertyListenerProc,
        ?*anyopaque,
    ) callconv(.c) OSStatus;
    const RemoveProc = *const fn (
        *anyopaque,
        AudioUnitPropertyID,
        AudioUnitPropertyListenerProc,
    ) callconv(.c) OSStatus;
    const RemoveWithUserDataProc = *const fn (
        *anyopaque,
        AudioUnitPropertyID,
        AudioUnitPropertyListenerProc,
        ?*anyopaque,
    ) callconv(.c) OSStatus;
    const SetProc = *const fn (
        *anyopaque,
        AudioUnitPropertyID,
        AudioUnitScope,
        AudioUnitElement,
        ?*const anyopaque,
        u32,
    ) callconv(.c) OSStatus;

    var probe = Probe{};
    var dispatch = Dispatch.init(&probe);
    const interface = dispatch.asInterface();
    const opaque_interface: *anyopaque = @ptrCast(interface);
    const instance: AudioComponentInstance = @ptrFromInt(0x1234);
    try std.testing.expectEqual(
        status.success,
        interface.open(opaque_interface, instance),
    );
    const add: AddProc = @ptrCast(@alignCast(
        interface.lookup(selector.add_property_listener) orelse
            return error.MissingAddPropertyListenerSelector,
    ));
    const remove: RemoveProc = @ptrCast(@alignCast(
        interface.lookup(selector.remove_property_listener) orelse
            return error.MissingRemovePropertyListenerSelector,
    ));
    const remove_with_user_data: RemoveWithUserDataProc =
        @ptrCast(@alignCast(
            interface.lookup(
                selector.remove_property_listener_with_user_data,
            ) orelse
                return error.MissingRemovePropertyListenerWithUserDataSelector,
        ));
    const set: SetProc = @ptrCast(@alignCast(
        interface.lookup(selector.set_property) orelse
            return error.MissingSetPropertySelector,
    ));

    var first = ListenerState{};
    var second = ListenerState{};
    try std.testing.expectEqual(
        status.success,
        add(
            opaque_interface,
            property.maximum_frames_per_slice,
            ListenerState.callback,
            &first,
        ),
    );
    try std.testing.expectEqual(
        status.success,
        add(
            opaque_interface,
            property.maximum_frames_per_slice,
            ListenerState.callback,
            &first,
        ),
    );
    try std.testing.expectEqual(
        status.success,
        add(
            opaque_interface,
            property.maximum_frames_per_slice,
            ListenerState.callback,
            &second,
        ),
    );

    const replacement: u32 = 1024;
    try std.testing.expectEqual(
        status.success,
        set(
            opaque_interface,
            property.maximum_frames_per_slice,
            scope.global,
            0,
            &replacement,
            @sizeOf(u32),
        ),
    );
    try std.testing.expectEqual(@as(usize, 1), first.calls);
    try std.testing.expectEqual(@as(usize, 1), second.calls);
    try std.testing.expectEqual(instance, first.unit.?);
    try std.testing.expectEqual(
        property.maximum_frames_per_slice,
        first.property_id,
    );
    try std.testing.expectEqual(scope.global, first.property_scope);
    try std.testing.expectEqual(@as(AudioUnitElement, 0), first.element);

    try std.testing.expectEqual(
        status.success,
        remove_with_user_data(
            opaque_interface,
            property.maximum_frames_per_slice,
            ListenerState.callback,
            &first,
        ),
    );
    try std.testing.expectEqual(
        status.success,
        set(
            opaque_interface,
            property.maximum_frames_per_slice,
            scope.global,
            0,
            &replacement,
            @sizeOf(u32),
        ),
    );
    try std.testing.expectEqual(@as(usize, 1), first.calls);
    try std.testing.expectEqual(@as(usize, 2), second.calls);

    try std.testing.expectEqual(
        status.success,
        remove(
            opaque_interface,
            property.maximum_frames_per_slice,
            ListenerState.callback,
        ),
    );
    try std.testing.expectEqual(
        status.success,
        set(
            opaque_interface,
            property.maximum_frames_per_slice,
            scope.global,
            0,
            &replacement,
            @sizeOf(u32),
        ),
    );
    try std.testing.expectEqual(@as(usize, 2), second.calls);
    try std.testing.expectEqual(@as(usize, 0), dispatch.property_listener_count);
    for (dispatch.property_listeners) |entry|
        try std.testing.expectEqualDeep(
            Dispatch.empty_property_listener,
            entry,
        );

    dispatch.property_listener_count = std.math.maxInt(usize);
    try std.testing.expect(!dispatch.valid());
    try std.testing.expectEqual(
        status.cannot_do_in_current_context,
        add(
            opaque_interface,
            property.maximum_frames_per_slice,
            ListenerState.callback,
            &first,
        ),
    );
    try std.testing.expectEqual(
        status.cannot_do_in_current_context,
        set(
            opaque_interface,
            property.maximum_frames_per_slice,
            scope.global,
            0,
            &replacement,
            @sizeOf(u32),
        ),
    );
    try std.testing.expectEqual(@as(u32, 1024), probe.value);
    try std.testing.expectEqual(
        status.success,
        interface.close(opaque_interface),
    );
    try std.testing.expect(dispatch.valid());
    for (dispatch.property_listeners) |entry|
        try std.testing.expectEqualDeep(
            Dispatch.empty_property_listener,
            entry,
        );
}

test "AUv2 render notifications bracket success and failure" {
    const Probe = struct {
        fail: bool = false,
        renders: usize = 0,

        fn initialize(_: *@This()) !void {}
        fn uninitialize(_: *@This()) !void {}
        fn reset(_: *@This()) !void {}

        fn renderCallback(
            self: *@This(),
            _: ?*AudioUnitRenderActionFlags,
            _: ?*const AudioTimeStamp,
            _: u32,
            _: u32,
            _: *AudioBufferList,
        ) !void {
            self.renders += 1;
            if (self.fail)
                return error.RenderProbeFailure;
        }
    };
    const NotificationState = struct {
        calls: usize = 0,
        flags: [4]AudioUnitRenderActionFlags = .{ 0, 0, 0, 0 },

        fn callback(
            reference: ?*anyopaque,
            action_flags: ?*AudioUnitRenderActionFlags,
            _: ?*const AudioTimeStamp,
            _: u32,
            _: u32,
            _: *AudioBufferList,
        ) callconv(.c) OSStatus {
            const self: *@This() = @ptrCast(@alignCast(
                reference orelse return status.invalid_property_value,
            ));
            if (self.calls < self.flags.len)
                self.flags[self.calls] =
                    if (action_flags) |value| value.* else 0;
            self.calls += 1;
            return status.success;
        }
    };
    const Dispatch = ComponentDispatch(Probe);
    const NotifyProc = *const fn (
        *anyopaque,
        AURenderCallback,
        ?*anyopaque,
    ) callconv(.c) OSStatus;
    const RenderProc = *const fn (
        *anyopaque,
        ?*AudioUnitRenderActionFlags,
        ?*const AudioTimeStamp,
        u32,
        u32,
        *AudioBufferList,
    ) callconv(.c) OSStatus;

    var probe = Probe{};
    var dispatch = Dispatch.init(&probe);
    try std.testing.expect(dispatch.valid());
    for (dispatch.render_notifications) |entry|
        try std.testing.expectEqualDeep(
            Dispatch.empty_render_notification,
            entry,
        );
    const interface = dispatch.asInterface();
    const opaque_interface: *anyopaque = @ptrCast(interface);
    try std.testing.expectEqual(
        status.success,
        interface.open(opaque_interface, @ptrFromInt(1)),
    );
    const add: NotifyProc = @ptrCast(@alignCast(
        interface.lookup(selector.add_render_notify) orelse
            return error.MissingAddRenderNotifySelector,
    ));
    const remove: NotifyProc = @ptrCast(@alignCast(
        interface.lookup(selector.remove_render_notify) orelse
            return error.MissingRemoveRenderNotifySelector,
    ));
    const render: RenderProc = @ptrCast(@alignCast(
        interface.lookup(selector.render) orelse
            return error.MissingRenderSelector,
    ));

    var notification = NotificationState{};
    try std.testing.expectEqual(
        status.success,
        add(
            opaque_interface,
            NotificationState.callback,
            &notification,
        ),
    );
    try std.testing.expectEqual(
        status.success,
        add(
            opaque_interface,
            NotificationState.callback,
            &notification,
        ),
    );
    var buffers = AudioBufferList{
        .number_buffers = 1,
        .buffers = .{.{
            .number_channels = 1,
            .data_byte_size = 0,
            .data = null,
        }},
    };
    var flags: AudioUnitRenderActionFlags =
        render_action.output_is_silence;
    try std.testing.expectEqual(
        status.success,
        render(
            opaque_interface,
            &flags,
            null,
            0,
            0,
            &buffers,
        ),
    );
    try std.testing.expectEqual(@as(usize, 2), notification.calls);
    try std.testing.expect(
        notification.flags[0] & render_action.pre_render != 0,
    );
    try std.testing.expect(
        notification.flags[1] & render_action.post_render != 0,
    );
    try std.testing.expect(
        notification.flags[1] &
            render_action.post_render_error == 0,
    );
    try std.testing.expectEqual(
        render_action.output_is_silence,
        flags,
    );

    probe.fail = true;
    try std.testing.expectEqual(
        status.cannot_do_in_current_context,
        render(
            opaque_interface,
            &flags,
            null,
            0,
            0,
            &buffers,
        ),
    );
    try std.testing.expectEqual(@as(usize, 4), notification.calls);
    try std.testing.expect(
        notification.flags[2] & render_action.pre_render != 0,
    );
    try std.testing.expect(
        notification.flags[3] &
            render_action.post_render != 0,
    );
    try std.testing.expect(
        notification.flags[3] &
            render_action.post_render_error != 0,
    );
    try std.testing.expectEqual(
        render_action.output_is_silence,
        flags,
    );

    try std.testing.expectEqual(
        status.success,
        remove(
            opaque_interface,
            NotificationState.callback,
            &notification,
        ),
    );
    probe.fail = false;
    try std.testing.expectEqual(
        status.success,
        render(
            opaque_interface,
            null,
            null,
            0,
            0,
            &buffers,
        ),
    );
    try std.testing.expectEqual(@as(usize, 4), notification.calls);
    try std.testing.expectEqual(@as(usize, 3), probe.renders);
    try std.testing.expectEqual(@as(usize, 0), dispatch.render_notification_count);
    for (dispatch.render_notifications) |entry|
        try std.testing.expectEqualDeep(
            Dispatch.empty_render_notification,
            entry,
        );

    dispatch.render_notification_count = std.math.maxInt(usize);
    try std.testing.expect(!dispatch.valid());
    try std.testing.expectEqual(
        status.cannot_do_in_current_context,
        add(
            opaque_interface,
            NotificationState.callback,
            &notification,
        ),
    );
    try std.testing.expectEqual(
        status.cannot_do_in_current_context,
        render(
            opaque_interface,
            null,
            null,
            0,
            0,
            &buffers,
        ),
    );
    try std.testing.expectEqual(@as(usize, 3), probe.renders);
    try std.testing.expectEqual(
        status.success,
        interface.close(opaque_interface),
    );
    try std.testing.expect(dispatch.valid());
    for (dispatch.render_notifications) |entry|
        try std.testing.expectEqualDeep(
            Dispatch.empty_render_notification,
            entry,
        );
}

test "AUv2 parameter properties and immediate selectors use plain values" {
    const audio_unit = @import("audio_unit.zig");
    const parameters = @import("parameters.zig");
    const Plugin = struct {
        pub const name = "AUv2 Parameter Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: process_api.AudioBusLayout = .mono;
        pub const audio_output_layout: process_api.AudioBusLayout = .mono;
        pub const Params = struct {
            gain: parameters.FloatParam = .{
                .id = 7,
                .name = "Output Gain",
                .units = "dB",
                .min = -24.0,
                .max = 12.0,
                .default = 0.0,
            },
            voices: parameters.IntParam = .{
                .id = 19,
                .name = "Voices",
                .min = 1,
                .max = 8,
                .default = 4,
                .is_read_only = true,
            },
        };

        pub fn process(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
        ) void {}
    };
    const RenderAdapter = audio_unit.RenderAdapter(Plugin, 32);
    const Properties = RenderPropertyAdapter(RenderAdapter);
    const Dispatch = ComponentDispatch(Properties);
    const GetPropertyProc = *const fn (
        *anyopaque,
        AudioUnitPropertyID,
        AudioUnitScope,
        AudioUnitElement,
        ?*anyopaque,
        ?*u32,
    ) callconv(.c) OSStatus;
    const GetParameterProc = *const fn (
        *anyopaque,
        AudioUnitParameterID,
        AudioUnitScope,
        AudioUnitElement,
        ?*AudioUnitParameterValue,
    ) callconv(.c) OSStatus;
    const SetParameterProc = *const fn (
        *anyopaque,
        AudioUnitParameterID,
        AudioUnitScope,
        AudioUnitElement,
        AudioUnitParameterValue,
        u32,
    ) callconv(.c) OSStatus;
    const ScheduleParametersProc = *const fn (
        *anyopaque,
        ?[*]const AudioUnitParameterEvent,
        u32,
    ) callconv(.c) OSStatus;

    var render_adapter = try RenderAdapter.init(
        std.testing.allocator,
        .{},
        48_000.0,
        16,
    );
    defer render_adapter.deinit();
    var properties = Properties.init(&render_adapter);
    try std.testing.expect(properties.valid());
    for (properties.parameter_events) |event|
        try std.testing.expectEqualDeep(process_api.ParameterChange{}, event);
    for (properties.parameter_event_sequences) |sequence|
        try std.testing.expectEqual(@as(usize, 0), sequence);
    for (properties.parameter_ramps) |ramp|
        try std.testing.expectEqualDeep(process_api.ParameterRamp{}, ramp);
    var dispatch = Dispatch.init(&properties);
    const interface = dispatch.asInterface();
    const opaque_interface: *anyopaque = @ptrCast(interface);
    const get_property: GetPropertyProc = @ptrCast(@alignCast(
        interface.lookup(selector.get_property) orelse
            return error.MissingGetPropertySelector,
    ));
    const get_parameter: GetParameterProc = @ptrCast(@alignCast(
        interface.lookup(selector.get_parameter) orelse
            return error.MissingGetParameterSelector,
    ));
    const set_parameter: SetParameterProc = @ptrCast(@alignCast(
        interface.lookup(selector.set_parameter) orelse
            return error.MissingSetParameterSelector,
    ));
    const schedule_parameters: ScheduleParametersProc =
        @ptrCast(@alignCast(
            interface.lookup(selector.schedule_parameters) orelse
                return error.MissingScheduleParametersSelector,
        ));

    var parameter_ids: [2]AudioUnitParameterID = undefined;
    var size: u32 = @sizeOf(@TypeOf(parameter_ids));
    try std.testing.expectEqual(
        status.success,
        get_property(
            opaque_interface,
            property.parameter_list,
            scope.global,
            0,
            &parameter_ids,
            &size,
        ),
    );
    try std.testing.expectEqualSlices(
        AudioUnitParameterID,
        &.{ 7, 19 },
        &parameter_ids,
    );

    var info: AudioUnitParameterInfo = undefined;
    size = @sizeOf(AudioUnitParameterInfo);
    try std.testing.expectEqual(
        status.success,
        get_property(
            opaque_interface,
            property.parameter_info,
            scope.global,
            7,
            &info,
            &size,
        ),
    );
    try std.testing.expectEqualStrings(
        "Output Gain",
        std.mem.sliceTo(info.name[0..], 0),
    );
    try std.testing.expectEqual(parameter_unit.decibels, info.unit);
    try std.testing.expectEqual(@as(f32, -24.0), info.min_value);
    try std.testing.expectEqual(@as(f32, 12.0), info.max_value);
    try std.testing.expectEqual(@as(f32, 0.0), info.default_value);
    try std.testing.expect(
        info.flags & parameter_flag.is_readable != 0,
    );
    try std.testing.expect(
        info.flags & parameter_flag.is_writable != 0,
    );
    try std.testing.expect(
        info.flags & parameter_flag.can_ramp != 0,
    );
    try std.testing.expect(
        info.flags & parameter_flag.is_high_resolution != 0,
    );

    size = @sizeOf(AudioUnitParameterInfo);
    try std.testing.expectEqual(
        status.success,
        get_property(
            opaque_interface,
            property.parameter_info,
            scope.global,
            19,
            &info,
            &size,
        ),
    );
    try std.testing.expectEqual(parameter_unit.indexed, info.unit);
    try std.testing.expectEqual(@as(f32, 1.0), info.min_value);
    try std.testing.expectEqual(@as(f32, 8.0), info.max_value);
    try std.testing.expectEqual(@as(f32, 4.0), info.default_value);
    try std.testing.expect(
        info.flags & parameter_flag.is_writable == 0,
    );
    try std.testing.expect(
        info.flags & parameter_flag.can_ramp == 0,
    );

    var value: AudioUnitParameterValue = undefined;
    try std.testing.expectEqual(
        status.success,
        get_parameter(
            opaque_interface,
            7,
            scope.global,
            0,
            &value,
        ),
    );
    try std.testing.expectEqual(@as(f32, 0.0), value);
    try std.testing.expectEqual(
        status.success,
        set_parameter(
            opaque_interface,
            7,
            scope.global,
            0,
            6.0,
            0,
        ),
    );
    try std.testing.expectEqual(
        @as(?f64, 6.0),
        render_adapter.loadParameterPlainById(7),
    );
    try std.testing.expectEqual(
        status.invalid_parameter,
        get_parameter(
            opaque_interface,
            99,
            scope.global,
            0,
            &value,
        ),
    );
    try std.testing.expectEqual(
        status.invalid_scope,
        set_parameter(
            opaque_interface,
            7,
            scope.input,
            0,
            0.0,
            0,
        ),
    );
    try std.testing.expectEqual(
        status.success,
        set_parameter(
            opaque_interface,
            7,
            scope.global,
            0,
            0.0,
            3,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        properties.parameter_event_count,
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        properties.parameter_events[0].sample_offset,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0 / 3.0),
        properties.parameter_events[0].normalized,
        0.000001,
    );

    var immediate_event = AudioUnitParameterEvent{
        .parameter_scope = scope.global,
        .element = 0,
        .parameter = 7,
        .event_type = parameter_event_type.immediate,
        .event_values = .{ .immediate = .{
            .buffer_offset = 2,
            .value = -12.0,
        } },
    };
    try std.testing.expectEqual(
        status.success,
        schedule_parameters(
            opaque_interface,
            @ptrCast(&immediate_event),
            1,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        properties.parameter_event_count,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0 / 3.0),
        properties.parameter_events[1].normalized,
        0.000001,
    );
    const ramp_event = AudioUnitParameterEvent{
        .parameter_scope = scope.global,
        .element = 0,
        .parameter = 7,
        .event_type = parameter_event_type.ramped,
        .event_values = .{ .ramp = .{
            .start_buffer_offset = -2,
            .duration_in_frames = 6,
            .start_value = -24.0,
            .end_value = 12.0,
        } },
    };
    try std.testing.expectEqual(
        status.success,
        schedule_parameters(
            opaque_interface,
            @ptrCast(&ramp_event),
            1,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        properties.parameter_event_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        properties.parameter_ramp_count,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0 / 3.0),
        properties.parameter_ramps[0].valueAt(0).?,
        0.000001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        properties.parameter_ramps[0].valueAt(1).?,
        0.000001,
    );
    var invalid_ramp = ramp_event;
    invalid_ramp.event_values.ramp.duration_in_frames = 0;
    try std.testing.expectEqual(
        status.invalid_parameter,
        schedule_parameters(
            opaque_interface,
            @ptrCast(&invalid_ramp),
            1,
        ),
    );
    invalid_ramp = ramp_event;
    invalid_ramp.event_values.ramp.start_buffer_offset = 16;
    try std.testing.expectEqual(
        status.invalid_parameter,
        schedule_parameters(
            opaque_interface,
            @ptrCast(&invalid_ramp),
            1,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        properties.scheduled_parameter_event_count,
    );
    const invalid_batch = [_]AudioUnitParameterEvent{
        .{
            .parameter_scope = scope.global,
            .element = 0,
            .parameter = 7,
            .event_type = parameter_event_type.ramped,
            .event_values = .{ .ramp = .{
                .start_buffer_offset = 0,
                .duration_in_frames = 4,
                .start_value = -12.0,
                .end_value = 0.0,
            } },
        },
        .{
            .parameter_scope = scope.input,
            .element = 0,
            .parameter = 7,
            .event_type = parameter_event_type.immediate,
            .event_values = .{ .immediate = .{
                .buffer_offset = 1,
                .value = 3.0,
            } },
        },
    };
    try std.testing.expectEqual(
        status.invalid_scope,
        schedule_parameters(
            opaque_interface,
            &invalid_batch,
            invalid_batch.len,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        properties.parameter_event_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        properties.parameter_ramp_count,
    );
    try std.testing.expectEqualDeep(
        process_api.ParameterRamp{},
        properties.parameter_ramps[1],
    );
    try std.testing.expect(properties.valid());
    properties.scheduled_parameter_event_count = std.math.maxInt(usize);
    try std.testing.expect(!properties.valid());
    try std.testing.expectError(
        error.InvalidAudioUnitParameterEventState,
        properties.scheduleParameters(&.{immediate_event}),
    );
    properties.scheduled_parameter_event_count = 3;
    try std.testing.expect(properties.valid());
    try std.testing.expectEqual(
        status.property_not_writable,
        set_parameter(
            opaque_interface,
            19,
            scope.global,
            0,
            5.0,
            0,
        ),
    );
    properties.clearParameterEvents();
    try std.testing.expect(properties.valid());
    for (properties.parameter_events) |event|
        try std.testing.expectEqualDeep(process_api.ParameterChange{}, event);
    for (properties.parameter_event_sequences) |sequence|
        try std.testing.expectEqual(@as(usize, 0), sequence);
    for (properties.parameter_ramps) |ramp|
        try std.testing.expectEqualDeep(process_api.ParameterRamp{}, ramp);
}

test "AUv2 render properties negotiate buses precision rate and block size" {
    const audio_unit = @import("audio_unit.zig");
    const Plugin = struct {
        pub const name = "AUv2 Property Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: process_api.AudioBusLayout = .stereo;
        pub const audio_output_layout: process_api.AudioBusLayout = .stereo;
        pub const audio_auxiliary_input_layouts: []const process_api.AudioBusLayout = &.{.mono};
        pub const audio_auxiliary_output_layouts: []const process_api.AudioBusLayout = &.{.mono};
        pub const Params = struct {
            gain: @import("parameters.zig").FloatParam = .{
                .id = 7,
                .name = "Gain",
                .min = 0.0,
                .max = 2.0,
                .default = 1.0,
            },
        };
        process_count: usize = 0,

        pub fn process(
            self: *@This(),
            context: *process_api.ProcessContext(f32),
        ) void {
            const sidechain = context.sidechainInputChannel(0) orelse return;
            self.process_count += 1;
            for (0..2) |channel| {
                const input = context.inputChannel(channel) orelse return;
                const output = context.outputChannel(channel) orelse return;
                for (input, sidechain, output, 0..) |
                    input_sample,
                    sidechain_sample,
                    *output_sample,
                    sample_offset,
                | {
                    const gain: f32 = @floatCast(
                        context.parameterNormalizedAtOrBeforeOr(
                            7,
                            sample_offset,
                            0.5,
                        ) * 2.0,
                    );
                    output_sample.* =
                        (input_sample + sidechain_sample) * gain;
                }
            }
            const input = context.inputChannel(0) orelse return;
            const auxiliary =
                context.auxiliaryOutputChannel(0) orelse return;
            for (input, sidechain, auxiliary, 0..) |
                input_sample,
                sidechain_sample,
                *output_sample,
                sample_offset,
            | {
                const gain: f32 = @floatCast(
                    context.parameterNormalizedAtOrBeforeOr(
                        7,
                        sample_offset,
                        0.5,
                    ) * 2.0,
                );
                output_sample.* =
                    (input_sample - sidechain_sample) * gain;
            }
        }

        pub fn process64(
            self: *@This(),
            context: *process_api.ProcessContext(f64),
        ) void {
            const sidechain = context.sidechainInputChannel(0) orelse return;
            self.process_count += 1;
            for (0..2) |channel| {
                const input = context.inputChannel(channel) orelse return;
                const output = context.outputChannel(channel) orelse return;
                for (input, sidechain, output, 0..) |
                    input_sample,
                    sidechain_sample,
                    *output_sample,
                    sample_offset,
                | {
                    const gain =
                        context.parameterNormalizedAtOrBeforeOr(
                            7,
                            sample_offset,
                            0.5,
                        ) * 2.0;
                    output_sample.* =
                        (input_sample + sidechain_sample) * gain;
                }
            }
            const input = context.inputChannel(0) orelse return;
            const auxiliary =
                context.auxiliaryOutputChannel(0) orelse return;
            for (input, sidechain, auxiliary, 0..) |
                input_sample,
                sidechain_sample,
                *output_sample,
                sample_offset,
            | {
                const gain =
                    context.parameterNormalizedAtOrBeforeOr(
                        7,
                        sample_offset,
                        0.5,
                    ) * 2.0;
                output_sample.* =
                    (input_sample - sidechain_sample) * gain;
            }
        }
    };
    const PullSource = struct {
        main: [2][4]f64 = .{
            .{ 1, 2, 3, 4 },
            .{ 5, 6, 7, 8 },
        },
        sidechain: [4]f64 = .{ 0.5, 1, 1.5, 2 },

        fn callback(
            reference: ?*anyopaque,
            _: ?*AudioUnitRenderActionFlags,
            _: ?*const AudioTimeStamp,
            bus: u32,
            frame_count: u32,
            data: *AudioBufferList,
        ) callconv(.c) OSStatus {
            const self: *@This() = @ptrCast(@alignCast(
                reference orelse return status.no_connection,
            ));
            if (frame_count != 4)
                return status.too_many_frames;
            const buffers = audioBuffers(data);
            if (bus == 0 and data.number_buffers == 2) {
                for (0..2) |channel| {
                    tryCopy(
                        buffers[channel],
                        &self.main[channel],
                    ) catch return status.format_not_supported;
                }
                return status.success;
            }
            if (bus == 1 and data.number_buffers == 1) {
                tryCopy(
                    buffers[0],
                    &self.sidechain,
                ) catch return status.format_not_supported;
                return status.success;
            }
            return status.invalid_element;
        }

        fn tryCopy(
            buffer: AudioBuffer,
            source: []const f64,
        ) !void {
            const destination = buffer.data orelse
                return error.MissingData;
            if (buffer.data_byte_size == 4 * @sizeOf(f64)) {
                @memcpy(
                    @as(
                        [*]f64,
                        @ptrCast(@alignCast(destination)),
                    )[0..4],
                    source,
                );
                return;
            }
            if (buffer.data_byte_size == 4 * @sizeOf(f32)) {
                const samples = @as(
                    [*]f32,
                    @ptrCast(@alignCast(destination)),
                )[0..4];
                for (samples, source) |*output, input|
                    output.* = @floatCast(input);
                return;
            }
            return error.InvalidSize;
        }
    };
    const RenderAdapter = audio_unit.RenderAdapter(Plugin, 32);
    const Properties = RenderPropertyAdapter(RenderAdapter);
    const Dispatch = ComponentDispatch(Properties);

    var render_adapter = try RenderAdapter.init(
        std.testing.allocator,
        .{},
        48_000.0,
        8,
    );
    defer render_adapter.deinit();
    var properties = Properties.init(&render_adapter);
    var dispatch = Dispatch.init(&properties);
    const interface = dispatch.asInterface();
    const opaque_interface: *anyopaque = @ptrCast(interface);

    var count: u32 = 0;
    var size: u32 = @sizeOf(u32);
    const get_method = interface.lookup(selector.get_property) orelse
        return error.MissingGetPropertySelector;
    const get: *const fn (
        *anyopaque,
        AudioUnitPropertyID,
        AudioUnitScope,
        AudioUnitElement,
        ?*anyopaque,
        ?*u32,
    ) callconv(.c) OSStatus = @ptrCast(@alignCast(get_method));
    const set_method = interface.lookup(selector.set_property) orelse
        return error.MissingSetPropertySelector;
    const set: *const fn (
        *anyopaque,
        AudioUnitPropertyID,
        AudioUnitScope,
        AudioUnitElement,
        ?*const anyopaque,
        u32,
    ) callconv(.c) OSStatus = @ptrCast(@alignCast(set_method));

    try std.testing.expectEqual(
        status.success,
        get(
            opaque_interface,
            property.element_count,
            scope.input,
            0,
            &count,
            &size,
        ),
    );
    try std.testing.expectEqual(@as(u32, 2), count);

    var format: AudioStreamBasicDescription = undefined;
    size = @sizeOf(AudioStreamBasicDescription);
    try std.testing.expectEqual(
        status.success,
        get(
            opaque_interface,
            property.stream_format,
            scope.input,
            1,
            &format,
            &size,
        ),
    );
    try std.testing.expectEqual(@as(u32, 1), format.channels_per_frame);
    try std.testing.expectEqual(@as(u32, 32), format.bits_per_channel);
    try std.testing.expectEqual(@as(f64, 48_000.0), format.sample_rate);

    format.sample_rate = 96_000.0;
    format.bytes_per_packet = @sizeOf(f64);
    format.bytes_per_frame = @sizeOf(f64);
    format.bits_per_channel = 64;
    try std.testing.expectEqual(
        status.success,
        set(
            opaque_interface,
            property.stream_format,
            scope.input,
            1,
            &format,
            @sizeOf(AudioStreamBasicDescription),
        ),
    );
    try std.testing.expectEqual(@as(f64, 96_000.0), render_adapter.sample_rate);
    try std.testing.expectEqual(@as(u32, @sizeOf(f64)), properties.sample_bytes);

    const maximum_frames: u32 = 16;
    try std.testing.expectEqual(
        status.success,
        set(
            opaque_interface,
            property.maximum_frames_per_slice,
            scope.global,
            0,
            &maximum_frames,
            @sizeOf(u32),
        ),
    );
    try std.testing.expectEqual(
        @as(usize, maximum_frames),
        render_adapter.configured_maximum_frames,
    );

    format.channels_per_frame = 2;
    try std.testing.expectEqual(
        status.invalid_property_value,
        set(
            opaque_interface,
            property.stream_format,
            scope.input,
            1,
            &format,
            @sizeOf(AudioStreamBasicDescription),
        ),
    );
    try std.testing.expectEqual(@as(f64, 96_000.0), render_adapter.sample_rate);

    var pull_source = PullSource{};
    const callback = AURenderCallbackStruct{
        .input = PullSource.callback,
        .reference = &pull_source,
    };
    for (0..2) |bus| {
        try std.testing.expectEqual(
            status.success,
            set(
                opaque_interface,
                property.set_render_callback,
                scope.input,
                @intCast(bus),
                &callback,
                @sizeOf(AURenderCallbackStruct),
            ),
        );
    }

    const instance: AudioComponentInstance = @ptrFromInt(1);
    try std.testing.expectEqual(
        status.success,
        interface.open(opaque_interface, instance),
    );
    const initialize_method = interface.lookup(selector.initialize) orelse
        return error.MissingInitializeSelector;
    const initialize: *const fn (
        *anyopaque,
    ) callconv(.c) OSStatus = @ptrCast(@alignCast(initialize_method));
    try std.testing.expectEqual(
        status.success,
        initialize(opaque_interface),
    );
    try std.testing.expectEqual(
        status.initialized,
        set(
            opaque_interface,
            property.maximum_frames_per_slice,
            scope.global,
            0,
            &maximum_frames,
            @sizeOf(u32),
        ),
    );

    const OutputList = extern struct {
        number_buffers: u32,
        buffers: [2]AudioBuffer,
    };
    var left = [_]f64{ 9, 9, 9, 9 };
    var right = [_]f64{ 9, 9, 9, 9 };
    var output_list = OutputList{
        .number_buffers = 2,
        .buffers = .{
            .{
                .number_channels = 1,
                .data_byte_size = @sizeOf(@TypeOf(left)),
                .data = &left,
            },
            .{
                .number_channels = 1,
                .data_byte_size = @sizeOf(@TypeOf(right)),
                .data = &right,
            },
        },
    };
    const render_method = interface.lookup(selector.render) orelse
        return error.MissingRenderSelector;
    const render: *const fn (
        *anyopaque,
        ?*AudioUnitRenderActionFlags,
        ?*const AudioTimeStamp,
        u32,
        u32,
        *AudioBufferList,
    ) callconv(.c) OSStatus = @ptrCast(@alignCast(render_method));
    const schedule_method =
        interface.lookup(selector.schedule_parameters) orelse
        return error.MissingScheduleParametersSelector;
    const schedule: *const fn (
        *anyopaque,
        ?[*]const AudioUnitParameterEvent,
        u32,
    ) callconv(.c) OSStatus =
        @ptrCast(@alignCast(schedule_method));
    var timestamp = AudioTimeStamp{
        .sample_time = 128,
        .host_time = 0,
        .rate_scalar = 0,
        .word_clock_time = 0,
        .smpte_time = std.mem.zeroes(SMPTETime),
        .flags = timestamp_flag.sample_time_valid,
        .reserved = 0,
    };
    var flags: AudioUnitRenderActionFlags = 0;
    try std.testing.expectEqual(
        status.cannot_do_in_current_context,
        render(
            opaque_interface,
            &flags,
            null,
            0,
            4,
            @ptrCast(&output_list),
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0, 0, 0, 0 },
        &left,
    );

    const AuxiliaryList = extern struct {
        number_buffers: u32,
        buffers: [1]AudioBuffer,
    };
    var auxiliary = [_]f64{ 9, 9, 9, 9 };
    var auxiliary_list = AuxiliaryList{
        .number_buffers = 1,
        .buffers = .{.{
            .number_channels = 1,
            .data_byte_size = @sizeOf(@TypeOf(auxiliary)),
            .data = &auxiliary,
        }},
    };
    flags = render_action.output_is_silence;
    try std.testing.expectEqual(
        status.success,
        render(
            opaque_interface,
            &flags,
            &timestamp,
            1,
            4,
            @ptrCast(&auxiliary_list),
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.5, 1, 1.5, 2 },
        &auxiliary,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        render_adapter.runtime.instance.plugin.process_count,
    );

    @memset(&left, 9);
    @memset(&right, 9);
    try std.testing.expectEqual(
        status.success,
        render(
            opaque_interface,
            &flags,
            &timestamp,
            0,
            4,
            @ptrCast(&output_list),
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1.5, 3, 4.5, 6 },
        &left,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 5.5, 7, 8.5, 10 },
        &right,
    );
    try std.testing.expectEqual(
        @as(AudioUnitRenderActionFlags, 0),
        flags & render_action.output_is_silence,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        render_adapter.runtime.instance.plugin.process_count,
    );

    @memset(&auxiliary, 9);
    try std.testing.expectEqual(
        status.success,
        render(
            opaque_interface,
            &flags,
            &timestamp,
            1,
            4,
            @ptrCast(&auxiliary_list),
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.5, 1, 1.5, 2 },
        &auxiliary,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        render_adapter.runtime.instance.plugin.process_count,
    );

    timestamp.sample_time += 4;
    try std.testing.expectEqual(
        status.success,
        render(
            opaque_interface,
            &flags,
            &timestamp,
            0,
            4,
            @ptrCast(&output_list),
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        render_adapter.runtime.instance.plugin.process_count,
    );
    @memset(&auxiliary, 9);
    try std.testing.expectEqual(
        status.success,
        render(
            opaque_interface,
            &flags,
            &timestamp,
            1,
            4,
            @ptrCast(&auxiliary_list),
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        render_adapter.runtime.instance.plugin.process_count,
    );

    timestamp.sample_time = std.math.nan(f64);
    timestamp.host_time = 777;
    timestamp.flags = timestamp_flag.host_time_valid;
    try std.testing.expectEqual(
        status.success,
        render(
            opaque_interface,
            &flags,
            &timestamp,
            1,
            4,
            @ptrCast(&auxiliary_list),
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        render_adapter.runtime.instance.plugin.process_count,
    );
    try std.testing.expectEqual(
        status.success,
        render(
            opaque_interface,
            &flags,
            &timestamp,
            0,
            4,
            @ptrCast(&output_list),
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        render_adapter.runtime.instance.plugin.process_count,
    );

    timestamp.flags = timestamp_flag.sample_time_valid;
    flags = 0;
    try std.testing.expectEqual(
        status.cannot_do_in_current_context,
        render(
            opaque_interface,
            &flags,
            &timestamp,
            0,
            4,
            @ptrCast(&output_list),
        ),
    );
    try std.testing.expect(
        flags & render_action.output_is_silence != 0,
    );

    timestamp.flags = timestamp_flag.host_time_valid;
    try properties.reset();
    try std.testing.expectEqual(
        status.success,
        render(
            opaque_interface,
            &flags,
            &timestamp,
            0,
            4,
            @ptrCast(&output_list),
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 4),
        render_adapter.runtime.instance.plugin.process_count,
    );

    output_list.number_buffers = 1;
    @memset(&left, 9);
    flags = 0;
    try std.testing.expectEqual(
        status.format_not_supported,
        render(
            opaque_interface,
            &flags,
            &timestamp,
            0,
            4,
            @ptrCast(&output_list),
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0, 0, 0, 0 },
        &left,
    );
    try std.testing.expect(
        flags & render_action.output_is_silence != 0,
    );
    try std.testing.expectEqual(
        status.success,
        interface.close(opaque_interface),
    );

    format.channels_per_frame = 2;
    format.bytes_per_packet = @sizeOf(f32);
    format.bytes_per_frame = @sizeOf(f32);
    format.bits_per_channel = 32;
    try std.testing.expectEqual(
        status.success,
        set(
            opaque_interface,
            property.stream_format,
            scope.input,
            0,
            &format,
            @sizeOf(AudioStreamBasicDescription),
        ),
    );
    try std.testing.expectEqual(
        status.success,
        interface.open(opaque_interface, instance),
    );
    try std.testing.expectEqual(
        status.success,
        initialize(opaque_interface),
    );

    var left32 = [_]f32{ 9, 9, 9, 9 };
    var right32 = [_]f32{ 9, 9, 9, 9 };
    var output_list32 = OutputList{
        .number_buffers = 2,
        .buffers = .{
            .{
                .number_channels = 1,
                .data_byte_size = @sizeOf(@TypeOf(left32)),
                .data = &left32,
            },
            .{
                .number_channels = 1,
                .data_byte_size = @sizeOf(@TypeOf(right32)),
                .data = &right32,
            },
        },
    };
    var scheduled_gain_ramp = AudioUnitParameterEvent{
        .parameter_scope = scope.global,
        .element = 0,
        .parameter = 7,
        .event_type = parameter_event_type.ramped,
        .event_values = .{ .ramp = .{
            .start_buffer_offset = 0,
            .duration_in_frames = 4,
            .start_value = 1.0,
            .end_value = 2.0,
        } },
    };
    try std.testing.expectEqual(
        status.success,
        schedule(
            opaque_interface,
            @ptrCast(&scheduled_gain_ramp),
            1,
        ),
    );
    timestamp.sample_time = 256;
    timestamp.flags = timestamp_flag.sample_time_valid;
    try std.testing.expectEqual(
        status.success,
        render(
            opaque_interface,
            &flags,
            &timestamp,
            0,
            4,
            @ptrCast(&output_list32),
        ),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1.5, 3.75, 6.75, 10.5 },
        &left32,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 5.5, 8.75, 12.75, 17.5 },
        &right32,
    );
    try std.testing.expectEqual(
        @as(?f64, 2.0),
        render_adapter.loadParameterPlainById(7),
    );
    try std.testing.expectEqual(
        @as(usize, 5),
        render_adapter.runtime.instance.plugin.process_count,
    );

    var auxiliary32 = [_]f32{ 9, 9, 9, 9 };
    var auxiliary_list32 = AuxiliaryList{
        .number_buffers = 1,
        .buffers = .{.{
            .number_channels = 1,
            .data_byte_size = @sizeOf(@TypeOf(auxiliary32)),
            .data = &auxiliary32,
        }},
    };
    try std.testing.expectEqual(
        status.success,
        render(
            opaque_interface,
            &flags,
            &timestamp,
            1,
            4,
            @ptrCast(&auxiliary_list32),
        ),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.5, 1.25, 2.25, 3.5 },
        &auxiliary32,
    );
    try std.testing.expectEqual(
        @as(usize, 5),
        render_adapter.runtime.instance.plugin.process_count,
    );
    try std.testing.expectEqual(
        status.success,
        interface.close(opaque_interface),
    );
}

test "AUv2 class info round trips parameter state transactionally" {
    const audio_unit = @import("audio_unit.zig");
    const Plugin = struct {
        pub const name = "Class Info Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: process_api.AudioBusLayout = .mono;
        pub const audio_output_layout: process_api.AudioBusLayout = .mono;
        pub const Params = struct {
            gain: @import("parameters.zig").FloatParam = .{
                .id = 7,
                .name = "Gain",
                .min = 0.0,
                .max = 2.0,
                .default = 1.0,
            },
        };
    };
    const Adapter = audio_unit.RenderAdapter(Plugin, 16);
    const Bridge = struct {
        pub const supported = true;
        var bytes: [Adapter.maximum_state_bytes]u8 = undefined;
        var size: usize = 0;
        var token: u8 = 0;

        pub fn create(source: []const u8) !?*anyopaque {
            if (source.len > bytes.len)
                return error.AudioUnitStateBufferTooSmall;
            @memcpy(bytes[0..source.len], source);
            size = source.len;
            return &token;
        }

        pub fn copy(
            property_list: ?*const anyopaque,
            destination: []u8,
        ) !usize {
            if (property_list !=
                @as(*const anyopaque, @ptrCast(&token)) or
                destination.len < size)
                return error.InvalidAudioUnitClassInfo;
            @memcpy(destination[0..size], bytes[0..size]);
            return size;
        }
    };
    const Properties = RenderPropertyAdapterWithClassInfo(
        Adapter,
        Bridge,
    );
    var adapter = try Adapter.init(
        std.testing.allocator,
        .{},
        48_000.0,
        8,
    );
    defer adapter.deinit();
    var properties = Properties.init(&adapter);
    for (properties.state_storage) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);

    const info = try properties.propertyInfo(
        property.class_info,
        scope.global,
        0,
    );
    try std.testing.expect(info.writable);
    try std.testing.expectEqual(
        @as(u32, @sizeOf(?*anyopaque)),
        info.size,
    );
    try properties.setParameter(7, scope.global, 0, 1.5, 0);

    var class_info_bytes: [@sizeOf(?*anyopaque)]u8 = undefined;
    _ = try properties.getProperty(
        property.class_info,
        scope.global,
        0,
        &class_info_bytes,
    );
    for (properties.state_storage) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    try properties.setParameter(7, scope.global, 0, 0.25, 0);
    try properties.setProperty(
        property.class_info,
        scope.global,
        0,
        &class_info_bytes,
    );
    for (properties.state_storage) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    try std.testing.expectApproxEqAbs(
        @as(AudioUnitParameterValue, 1.5),
        try properties.getParameter(7, scope.global, 0),
        0.000_001,
    );

    const saved = Bridge.bytes;
    Bridge.bytes[0] ^= 0xff;
    try std.testing.expectError(
        error.InvalidStateMagic,
        properties.setProperty(
            property.class_info,
            scope.global,
            0,
            &class_info_bytes,
        ),
    );
    for (properties.state_storage) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    try std.testing.expectApproxEqAbs(
        @as(AudioUnitParameterValue, 1.5),
        try properties.getParameter(7, scope.global, 0),
        0.000_001,
    );
    Bridge.bytes = saved;
}

test "AUv2 properties expose selected auxiliary bus capacity" {
    const audio_unit = @import("audio_unit.zig");
    const Plugin = struct {
        pub const name = "AUv2 Large Bus Probe";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const maximum_auxiliary_audio_buses = 12;
        pub const audio_input_layout: process_api.AudioBusLayout = .mono;
        pub const audio_output_layout: process_api.AudioBusLayout = .none;
        pub const auxiliary_layouts =
            [_]process_api.AudioBusLayout{.mono} ** 12;
        pub const audio_auxiliary_input_layouts: []const process_api.AudioBusLayout =
            &auxiliary_layouts;

        pub fn process(
            _: *@This(),
            _: *process_api.BoundedProcessContext(
                f32,
                maximum_auxiliary_audio_buses,
            ),
        ) void {}
    };
    const Adapter = audio_unit.RenderAdapter(Plugin, 1);
    const Properties = RenderPropertyAdapter(Adapter);
    var adapter = try Adapter.init(
        std.testing.allocator,
        .{},
        48_000.0,
        1,
    );
    defer adapter.deinit();
    var properties = Properties.init(&adapter);
    var count_bytes: [@sizeOf(u32)]u8 = undefined;
    _ = try properties.getProperty(
        property.element_count,
        scope.input,
        0,
        &count_bytes,
    );

    try std.testing.expectEqual(
        @as(u32, 13),
        std.mem.bytesToValue(u32, &count_bytes),
    );
    try std.testing.expectEqual(
        @as(?u32, 1),
        Adapter.inputBusChannelCount(12),
    );
}

export fn zig_auv2_sizeof_component_description() usize {
    return @sizeOf(AudioComponentDescription);
}

export fn zig_auv2_alignof_component_description() usize {
    return @alignOf(AudioComponentDescription);
}

export fn zig_auv2_offsetof_component_flags_mask() usize {
    return @offsetOf(AudioComponentDescription, "component_flags_mask");
}

export fn zig_auv2_sizeof_audio_buffer() usize {
    return @sizeOf(AudioBuffer);
}

export fn zig_auv2_offsetof_audio_buffer_data() usize {
    return @offsetOf(AudioBuffer, "data");
}

export fn zig_auv2_sizeof_audio_buffer_list() usize {
    return @sizeOf(AudioBufferList);
}

export fn zig_auv2_offsetof_audio_buffer_list_buffers() usize {
    return @offsetOf(AudioBufferList, "buffers");
}

export fn zig_auv2_sizeof_plugin_interface() usize {
    return @sizeOf(AudioComponentPlugInInterface);
}

export fn zig_auv2_offsetof_plugin_interface_lookup() usize {
    return @offsetOf(AudioComponentPlugInInterface, "lookup");
}

export fn zig_auv2_offsetof_plugin_interface_reserved() usize {
    return @offsetOf(AudioComponentPlugInInterface, "reserved");
}

export fn zig_auv2_sizeof_stream_description() usize {
    return @sizeOf(AudioStreamBasicDescription);
}

export fn zig_auv2_alignof_stream_description() usize {
    return @alignOf(AudioStreamBasicDescription);
}

export fn zig_auv2_offsetof_stream_description_bits() usize {
    return @offsetOf(
        AudioStreamBasicDescription,
        "bits_per_channel",
    );
}

export fn zig_auv2_sizeof_channel_info() usize {
    return @sizeOf(AUChannelInfo);
}

export fn zig_auv2_sizeof_render_callback() usize {
    return @sizeOf(AURenderCallbackStruct);
}

export fn zig_auv2_offsetof_render_callback_reference() usize {
    return @offsetOf(AURenderCallbackStruct, "reference");
}

export fn zig_auv2_sizeof_audio_timestamp() usize {
    return @sizeOf(AudioTimeStamp);
}

export fn zig_auv2_offsetof_audio_timestamp_flags() usize {
    return @offsetOf(AudioTimeStamp, "flags");
}

export fn zig_auv2_sizeof_parameter_info() usize {
    return @sizeOf(AudioUnitParameterInfo);
}

export fn zig_auv2_offsetof_parameter_info_unit_name() usize {
    return @offsetOf(AudioUnitParameterInfo, "unit_name");
}

export fn zig_auv2_offsetof_parameter_info_flags() usize {
    return @offsetOf(AudioUnitParameterInfo, "flags");
}

export fn zig_auv2_sizeof_parameter_event() usize {
    return @sizeOf(AudioUnitParameterEvent);
}

export fn zig_auv2_offsetof_parameter_event_values() usize {
    return @offsetOf(AudioUnitParameterEvent, "event_values");
}

export fn zig_auv2_sizeof_parameter_ramp_event() usize {
    return @sizeOf(AudioUnitParameterRampEvent);
}

export fn zig_auv2_offsetof_parameter_ramp_duration() usize {
    return @offsetOf(
        AudioUnitParameterRampEvent,
        "duration_in_frames",
    );
}

export fn zig_auv2_offsetof_parameter_ramp_start_value() usize {
    return @offsetOf(AudioUnitParameterRampEvent, "start_value");
}

export fn zig_auv2_offsetof_parameter_ramp_end_value() usize {
    return @offsetOf(AudioUnitParameterRampEvent, "end_value");
}

export fn zig_auv2_parameter_event_ramped() u32 {
    return parameter_event_type.ramped;
}

export fn zig_auv2_selector_render() i16 {
    return selector.render;
}

export fn zig_auv2_selector_add_property_listener() i16 {
    return selector.add_property_listener;
}

export fn zig_auv2_selector_remove_property_listener() i16 {
    return selector.remove_property_listener;
}

export fn zig_auv2_selector_remove_property_listener_with_user_data() i16 {
    return selector.remove_property_listener_with_user_data;
}

export fn zig_auv2_selector_add_render_notify() i16 {
    return selector.add_render_notify;
}

export fn zig_auv2_selector_remove_render_notify() i16 {
    return selector.remove_render_notify;
}

export fn zig_auv2_render_action_post_render_error() u32 {
    return render_action.post_render_error;
}

export fn zig_auv2_property_maximum_frames() u32 {
    return property.maximum_frames_per_slice;
}

export fn zig_auv2_property_class_info() u32 {
    return property.class_info;
}
