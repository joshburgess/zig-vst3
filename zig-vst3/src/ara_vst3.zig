const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub const Factory = opaque {};
pub const DocumentController = opaque {};
pub const PlugInExtensionInstance = opaque {};

pub const main_factory_class = "ARA Main Factory Class";

pub const main_factory_iid = tuid.inlineUid(
    0xDB2A1669,
    0xFAFD42A5,
    0xA82F864F,
    0x7B6872EA,
);
pub const plug_in_entry_point_iid = tuid.inlineUid(
    0x12814E54,
    0xA1CE4076,
    0x82B96813,
    0x16950BD6,
);
pub const plug_in_entry_point_2_iid = tuid.inlineUid(
    0xCD9A5913,
    0xC9EB46D7,
    0x96CA53AD,
    0xD1DB89F5,
);

pub const RoleFlags = types.int32;
pub const no_roles: RoleFlags = 0;
pub const playback_renderer_role: RoleFlags = 1 << 0;
pub const editor_renderer_role: RoleFlags = 1 << 1;
pub const editor_view_role: RoleFlags = 1 << 2;
pub const all_roles: RoleFlags =
    playback_renderer_role |
    editor_renderer_role |
    editor_view_role;

pub const IMainFactoryVTable = extern struct {
    queryInterface: *const fn (
        *anyopaque,
        [*c]const tuid.TUID,
        [*c]?*anyopaque,
    ) callconv(.c) types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) types.uint32,
    release: *const fn (*anyopaque) callconv(.c) types.uint32,
    getFactory: *const fn (
        *anyopaque,
    ) callconv(.c) ?*const Factory,
};

pub const IMainFactory = extern struct {
    vtable: *const IMainFactoryVTable,
};

pub const IPlugInEntryPointVTable = extern struct {
    queryInterface: *const fn (
        *anyopaque,
        [*c]const tuid.TUID,
        [*c]?*anyopaque,
    ) callconv(.c) types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) types.uint32,
    release: *const fn (*anyopaque) callconv(.c) types.uint32,
    getFactory: *const fn (
        *anyopaque,
    ) callconv(.c) ?*const Factory,
    bindToDocumentController: *const fn (
        *anyopaque,
        ?*DocumentController,
    ) callconv(.c) ?*const PlugInExtensionInstance,
};

pub const IPlugInEntryPoint = extern struct {
    vtable: *const IPlugInEntryPointVTable,
};

pub const IPlugInEntryPoint2VTable = extern struct {
    queryInterface: *const fn (
        *anyopaque,
        [*c]const tuid.TUID,
        [*c]?*anyopaque,
    ) callconv(.c) types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) types.uint32,
    release: *const fn (*anyopaque) callconv(.c) types.uint32,
    bindToDocumentControllerWithRoles: *const fn (
        *anyopaque,
        ?*DocumentController,
        RoleFlags,
        RoleFlags,
    ) callconv(.c) ?*const PlugInExtensionInstance,
};

pub const IPlugInEntryPoint2 = extern struct {
    vtable: *const IPlugInEntryPoint2VTable,
};

pub const DelegatedIdentity = struct {
    context: *anyopaque,
    query: *const fn (
        *anyopaque,
        [*c]const tuid.TUID,
        [*c]?*anyopaque,
    ) callconv(.c) types.tresult,
    add_ref: *const fn (
        *anyopaque,
    ) callconv(.c) types.uint32,
    release: *const fn (
        *anyopaque,
    ) callconv(.c) types.uint32,
};

pub fn validRoles(roles: RoleFlags) bool {
    return roles >= 0 and roles & ~all_roles == 0;
}

pub const MainFactory = extern struct {
    const Self = @This();

    iface: IMainFactory = .{ .vtable = &vtable },
    ref_count: std.atomic.Value(types.uint32) =
        std.atomic.Value(types.uint32).init(1),
    factory: ?*const Factory,

    pub fn init(factory: *const Factory) Self {
        return .{ .factory = factory };
    }

    pub fn asInterface(self: *Self) *IMainFactory {
        return &self.iface;
    }

    const owner = interface_map.ownerFromField(
        Self,
        IMainFactory,
        "iface",
    );

    fn query(
        ptr: *anyopaque,
        requested_iid: [*c]const tuid.TUID,
        out: [*c]?*anyopaque,
    ) callconv(.c) types.tresult {
        const entries = [_]interface_map.Entry{
            .{ .iid = &funknown.iid, .ptr = ptr },
            .{ .iid = &main_factory_iid, .ptr = ptr },
        };
        return interface_map.queryWithAddRef(
            ptr,
            addRef,
            &entries,
            requested_iid,
            out,
        );
    }

    fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
        return funknown.incrementRefCount(
            &owner(ptr).ref_count,
            "ARA::IMainFactory",
        );
    }

    fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
        return funknown.decrementRefCount(
            &owner(ptr).ref_count,
            "ARA::IMainFactory",
        );
    }

    fn getFactory(ptr: *anyopaque) callconv(.c) ?*const Factory {
        return owner(ptr).factory;
    }

    const vtable = IMainFactoryVTable{
        .queryInterface = query,
        .addRef = addRef,
        .release = release,
        .getFactory = getFactory,
    };
};

pub fn PlugInEntryPoint(comptime Config: type) type {
    return struct {
        const Self = @This();

        entry: IPlugInEntryPoint = .{ .vtable = &entry_vtable },
        entry2: IPlugInEntryPoint2 = .{ .vtable = &entry_2_vtable },
        ref_count: std.atomic.Value(types.uint32) =
            std.atomic.Value(types.uint32).init(1),
        context: ?*anyopaque = null,
        factory: ?*const Factory = null,
        delegated_identity: ?DelegatedIdentity = null,
        binding_attempted: u8 = 0,
        assigned_roles: RoleFlags = no_roles,

        pub fn init(
            context: ?*anyopaque,
            factory: *const Factory,
        ) Self {
            return .{
                .context = context,
                .factory = factory,
            };
        }

        pub fn initDelegated(
            context: ?*anyopaque,
            factory: *const Factory,
            identity: DelegatedIdentity,
        ) Self {
            return .{
                .context = context,
                .factory = factory,
                .delegated_identity = identity,
            };
        }

        pub fn asEntryPoint(self: *Self) *IPlugInEntryPoint {
            return &self.entry;
        }

        pub fn asEntryPoint2(self: *Self) *IPlugInEntryPoint2 {
            return &self.entry2;
        }

        pub fn isBound(self: *const Self) bool {
            return self.binding_attempted != 0;
        }

        const ownerFromEntry = interface_map.ownerFromField(
            Self,
            IPlugInEntryPoint,
            "entry",
        );
        const ownerFromEntry2 = interface_map.ownerFromField(
            Self,
            IPlugInEntryPoint2,
            "entry2",
        );

        fn queryCanonical(
            self: *Self,
            add_ref_ptr: *anyopaque,
            requested_iid: [*c]const tuid.TUID,
            out: [*c]?*anyopaque,
        ) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.entry },
                .{ .iid = &plug_in_entry_point_iid, .ptr = &self.entry },
                .{ .iid = &plug_in_entry_point_2_iid, .ptr = &self.entry2 },
            };
            return interface_map.queryWithAddRef(
                add_ref_ptr,
                entryAddRef,
                &entries,
                requested_iid,
                out,
            );
        }

        fn entryQuery(
            ptr: *anyopaque,
            requested_iid: [*c]const tuid.TUID,
            out: [*c]?*anyopaque,
        ) callconv(.c) types.tresult {
            const self = ownerFromEntry(ptr);
            if (self.delegated_identity) |identity|
                return identity.query(
                    identity.context,
                    requested_iid,
                    out,
                );
            return self.queryCanonical(
                ptr,
                requested_iid,
                out,
            );
        }

        fn entry2Query(
            ptr: *anyopaque,
            requested_iid: [*c]const tuid.TUID,
            out: [*c]?*anyopaque,
        ) callconv(.c) types.tresult {
            const self = ownerFromEntry2(ptr);
            if (self.delegated_identity) |identity|
                return identity.query(
                    identity.context,
                    requested_iid,
                    out,
                );
            return self.queryCanonical(
                &self.entry,
                requested_iid,
                out,
            );
        }

        fn entryAddRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            if (ownerFromEntry(ptr).delegated_identity) |identity|
                return identity.add_ref(identity.context);
            return funknown.incrementRefCount(
                &ownerFromEntry(ptr).ref_count,
                "ARA::IPlugInEntryPoint",
            );
        }

        fn entry2AddRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            if (ownerFromEntry2(ptr).delegated_identity) |identity|
                return identity.add_ref(identity.context);
            return funknown.incrementRefCount(
                &ownerFromEntry2(ptr).ref_count,
                "ARA::IPlugInEntryPoint2",
            );
        }

        fn entryRelease(ptr: *anyopaque) callconv(.c) types.uint32 {
            if (ownerFromEntry(ptr).delegated_identity) |identity|
                return identity.release(identity.context);
            return funknown.decrementRefCount(
                &ownerFromEntry(ptr).ref_count,
                "ARA::IPlugInEntryPoint",
            );
        }

        fn entry2Release(ptr: *anyopaque) callconv(.c) types.uint32 {
            if (ownerFromEntry2(ptr).delegated_identity) |identity|
                return identity.release(identity.context);
            return funknown.decrementRefCount(
                &ownerFromEntry2(ptr).ref_count,
                "ARA::IPlugInEntryPoint2",
            );
        }

        fn bindLegacy(
            ptr: *anyopaque,
            controller: ?*DocumentController,
        ) callconv(.c) ?*const PlugInExtensionInstance {
            return bind(
                ownerFromEntry(ptr),
                controller,
                no_roles,
                all_roles,
                true,
            );
        }

        fn getFactory(
            ptr: *anyopaque,
        ) callconv(.c) ?*const Factory {
            return ownerFromEntry(ptr).factory;
        }

        fn bindWithRoles(
            ptr: *anyopaque,
            controller: ?*DocumentController,
            known_roles: RoleFlags,
            requested_roles: RoleFlags,
        ) callconv(.c) ?*const PlugInExtensionInstance {
            return bind(
                ownerFromEntry2(ptr),
                controller,
                known_roles,
                requested_roles,
                false,
            );
        }

        fn bind(
            self: *Self,
            controller: ?*DocumentController,
            known_roles: RoleFlags,
            requested_roles: RoleFlags,
            legacy: bool,
        ) ?*const PlugInExtensionInstance {
            const document = controller orelse return null;
            if (self.binding_attempted != 0) return null;
            if (!validRoles(known_roles) or
                !validRoles(requested_roles) or
                (!legacy and requested_roles & ~known_roles != 0))
                return null;
            self.binding_attempted = 1;
            self.assigned_roles = requested_roles;
            return Config.bind(
                self,
                document,
                known_roles,
                requested_roles,
            );
        }

        const entry_vtable = IPlugInEntryPointVTable{
            .queryInterface = entryQuery,
            .addRef = entryAddRef,
            .release = entryRelease,
            .getFactory = getFactory,
            .bindToDocumentController = bindLegacy,
        };

        const entry_2_vtable = IPlugInEntryPoint2VTable{
            .queryInterface = entry2Query,
            .addRef = entry2AddRef,
            .release = entry2Release,
            .bindToDocumentControllerWithRoles = bindWithRoles,
        };
    };
}

test "ARA VST3 main factory uses COM identity and stable factory pointer" {
    const factory: *const Factory = @ptrFromInt(0x1000);
    var main_factory = MainFactory.init(factory);
    const iface = main_factory.asInterface();
    try std.testing.expect(iface.vtable.getFactory(iface) == factory);

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        iface.vtable.queryInterface(
            iface,
            &main_factory_iid,
            &out,
        ),
    );
    try std.testing.expect(
        out == @as(?*anyopaque, @ptrCast(iface)),
    );
    try std.testing.expectEqual(
        @as(types.uint32, 1),
        iface.vtable.release(iface),
    );
    try std.testing.expectEqual(
        @as(types.uint32, 0),
        iface.vtable.release(iface),
    );
}

test "ARA VST3 entry point validates roles and binds only once" {
    const Entry = PlugInEntryPoint(struct {
        pub fn bind(
            _: anytype,
            _: *DocumentController,
            _: RoleFlags,
            _: RoleFlags,
        ) ?*const PlugInExtensionInstance {
            return @ptrFromInt(0x3000);
        }
    });
    const factory: *const Factory = @ptrFromInt(0x1000);
    var entry = Entry.init(null, factory);
    const first = entry.asEntryPoint();
    const second = entry.asEntryPoint2();
    try std.testing.expect(first.vtable.getFactory(first) == factory);

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        first.vtable.queryInterface(
            first,
            &plug_in_entry_point_2_iid,
            &out,
        ),
    );
    try std.testing.expect(
        out == @as(?*anyopaque, @ptrCast(second)),
    );
    try std.testing.expectEqual(
        @as(types.uint32, 1),
        second.vtable.release(second),
    );

    const controller: *DocumentController = @ptrFromInt(0x2000);
    try std.testing.expect(
        second.vtable.bindToDocumentControllerWithRoles(
            second,
            controller,
            playback_renderer_role,
            editor_view_role,
        ) == null,
    );
    try std.testing.expect(!entry.isBound());
    const extension =
        second.vtable.bindToDocumentControllerWithRoles(
            second,
            controller,
            all_roles,
            playback_renderer_role | editor_view_role,
        );
    try std.testing.expect(
        extension ==
            @as(*const PlugInExtensionInstance, @ptrFromInt(0x3000)),
    );
    try std.testing.expect(entry.isBound());
    try std.testing.expectEqual(
        playback_renderer_role | editor_view_role,
        entry.assigned_roles,
    );
    try std.testing.expect(
        first.vtable.bindToDocumentController(
            first,
            controller,
        ) == null,
    );
}

test "ARA VST3 entry point can delegate canonical COM identity" {
    const Identity = struct {
        add_count: usize = 0,
        release_count: usize = 0,

        fn query(
            context: *anyopaque,
            requested_iid_raw: [*c]const tuid.TUID,
            out_raw: [*c]?*anyopaque,
        ) callconv(.c) types.tresult {
            const arguments = funknown.queryArguments(
                requested_iid_raw,
                out_raw,
            ) orelse return types.kInvalidArgument;
            const requested_iid = arguments.requested_iid;
            const out = arguments.out;
            if (!std.mem.eql(
                u8,
                requested_iid[0..tuid.byte_count],
                &funknown.iid,
            )) {
                out.* = null;
                return types.kNoInterface;
            }
            out.* = context;
            _ = addRef(context);
            return types.kResultOk;
        }

        fn addRef(context: *anyopaque) callconv(.c) types.uint32 {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.add_count += 1;
            return @intCast(self.add_count);
        }

        fn release(context: *anyopaque) callconv(.c) types.uint32 {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.release_count += 1;
            return @intCast(self.release_count);
        }
    };
    const Entry = PlugInEntryPoint(struct {
        pub fn bind(
            _: anytype,
            _: *DocumentController,
            _: RoleFlags,
            _: RoleFlags,
        ) ?*const PlugInExtensionInstance {
            return @ptrFromInt(0x3000);
        }
    });
    var identity = Identity{};
    var entry = Entry.initDelegated(
        null,
        @ptrFromInt(0x1000),
        .{
            .context = &identity,
            .query = Identity.query,
            .add_ref = Identity.addRef,
            .release = Identity.release,
        },
    );
    var out: ?*anyopaque = null;
    const iface = entry.asEntryPoint2();
    try std.testing.expectEqual(
        types.kResultOk,
        iface.vtable.queryInterface(
            iface,
            &funknown.iid,
            &out,
        ),
    );
    try std.testing.expect(out == @as(?*anyopaque, &identity));
    try std.testing.expectEqual(@as(usize, 1), identity.add_count);
    try std.testing.expectEqual(
        @as(types.uint32, 2),
        iface.vtable.addRef(iface),
    );
    try std.testing.expectEqual(
        @as(types.uint32, 1),
        iface.vtable.release(iface),
    );
}
