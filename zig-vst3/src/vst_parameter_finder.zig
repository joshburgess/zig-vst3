const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivstparameterfunctionname = @import("pluginterfaces/vst/ivstparameterfunctionname.zig");
const ivstplugview = @import("pluginterfaces/vst/ivstplugview.zig");
const ivstremapparamid = @import("pluginterfaces/vst/ivstremapparamid.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

fn failParamId(out: *vsttypes.ParamID) types.tresult {
    out.* = vsttypes.kNoParamId;
    return types.kResultFalse;
}

pub fn ParameterFinder(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivstplugview.IParameterFinder = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),

        pub fn asInterface(self: *Self) *ivstplugview.IParameterFinder {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstplugview.IParameterFinder = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstplugview.iparameter_finder_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IParameterFinder");
        }

        fn findParameter(_: *anyopaque, x: types.int32, y: types.int32, out: *vsttypes.ParamID) callconv(.c) types.tresult {
            if (@hasDecl(Config, "findParameter")) {
                if (Config.findParameter(x, y)) |id| {
                    out.* = id;
                    return types.kResultOk;
                }
            }
            return failParamId(out);
        }

        const vtable = ivstplugview.IParameterFinderVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .findParameter = findParameter,
        };
    };
}

pub fn ParameterFunctionName(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivstparameterfunctionname.IParameterFunctionName = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),

        pub fn asInterface(self: *Self) *ivstparameterfunctionname.IParameterFunctionName {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstparameterfunctionname.IParameterFunctionName = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstparameterfunctionname.iparameter_function_name_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IParameterFunctionName");
        }

        fn getParameterIDFromFunctionName(_: *anyopaque, unit_id: vsttypes.UnitID, function_name: types.FIDString, out: *vsttypes.ParamID) callconv(.c) types.tresult {
            if (@hasDecl(Config, "getParameterIDFromFunctionName")) {
                if (Config.getParameterIDFromFunctionName(unit_id, function_name)) |id| {
                    out.* = id;
                    return types.kResultOk;
                }
            }
            return failParamId(out);
        }

        const vtable = ivstparameterfunctionname.IParameterFunctionNameVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getParameterIDFromFunctionName = getParameterIDFromFunctionName,
        };
    };
}

pub fn RemapParamID(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivstremapparamid.IRemapParamID = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),

        pub fn asInterface(self: *Self) *ivstremapparamid.IRemapParamID {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstremapparamid.IRemapParamID = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstremapparamid.iremap_param_id_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IRemapParamID");
        }

        fn getCompatibleParamID(_: *anyopaque, class_id: *const tuid.TUID, old_param_id: vsttypes.ParamID, out: *vsttypes.ParamID) callconv(.c) types.tresult {
            if (@hasDecl(Config, "getCompatibleParamID")) {
                if (Config.getCompatibleParamID(class_id, old_param_id)) |id| {
                    out.* = id;
                    return types.kResultOk;
                }
            }
            return failParamId(out);
        }

        const vtable = ivstremapparamid.IRemapParamIDVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getCompatibleParamID = getCompatibleParamID,
        };
    };
}

test "parameter finder maps coordinates to parameter ids" {
    const Finder = ParameterFinder(struct {
        pub fn findParameter(x: types.int32, y: types.int32) ?vsttypes.ParamID {
            if (x >= 10 and x < 20 and y >= 5 and y < 15) return 42;
            return null;
        }
    });

    var finder = Finder{};
    const iface = finder.asInterface();

    var found: vsttypes.ParamID = 0;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.findParameter(iface, 12, 6, &found));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 42), found);

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.findParameter(iface, 2, 6, &found));
    try std.testing.expectEqual(vsttypes.kNoParamId, found);
}

test "parameter finder returns no-param without a config hook" {
    const Finder = ParameterFinder(struct {});
    var finder = Finder{};
    const iface = finder.asInterface();
    var found: vsttypes.ParamID = 123;

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.findParameter(iface, 0, 0, &found));
    try std.testing.expectEqual(vsttypes.kNoParamId, found);
}

test "parameter finder supports query interface" {
    const Finder = ParameterFinder(struct {});
    var finder = Finder{};
    const iface = finder.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstplugview.iparameter_finder_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_finder: *ivstplugview.IParameterFinder = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_finder.vtable.release(queried_finder));
}

test "parameter function name maps known host function names" {
    const FunctionNames = ParameterFunctionName(struct {
        pub fn getParameterIDFromFunctionName(unit_id: vsttypes.UnitID, function_name: types.FIDString) ?vsttypes.ParamID {
            if (unit_id == 2 and std.mem.eql(u8, std.mem.span(function_name), std.mem.span(ivstparameterfunctionname.FunctionNameType.kDryWetMix))) return 12;
            return null;
        }
    });

    var functions = FunctionNames{};
    const iface = functions.asInterface();
    var found: vsttypes.ParamID = 0;

    try std.testing.expectEqual(types.kResultOk, iface.vtable.getParameterIDFromFunctionName(iface, 2, ivstparameterfunctionname.FunctionNameType.kDryWetMix, &found));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 12), found);

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.getParameterIDFromFunctionName(iface, 1, ivstparameterfunctionname.FunctionNameType.kDryWetMix, &found));
    try std.testing.expectEqual(vsttypes.kNoParamId, found);
}

test "parameter function name returns no-param without a config hook" {
    const FunctionNames = ParameterFunctionName(struct {});
    var functions = FunctionNames{};
    const iface = functions.asInterface();
    var found: vsttypes.ParamID = 123;

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.getParameterIDFromFunctionName(iface, 0, ivstparameterfunctionname.FunctionNameType.kRandomize, &found));
    try std.testing.expectEqual(vsttypes.kNoParamId, found);
}

test "remap param ID maps compatible old parameter IDs" {
    const target_cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444);
    const Remap = RemapParamID(struct {
        pub fn getCompatibleParamID(class_id: *const tuid.TUID, old_param_id: vsttypes.ParamID) ?vsttypes.ParamID {
            const supported_cid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444);
            if (std.mem.eql(u8, class_id, &supported_cid) and old_param_id == 100) return 200;
            return null;
        }
    });

    var remap = Remap{};
    const iface = remap.asInterface();
    var found: vsttypes.ParamID = 0;

    try std.testing.expectEqual(types.kResultOk, iface.vtable.getCompatibleParamID(iface, &target_cid, 100, &found));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 200), found);

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.getCompatibleParamID(iface, &target_cid, 101, &found));
    try std.testing.expectEqual(vsttypes.kNoParamId, found);
}

test "parameter function name and remap helpers support query interface" {
    const FunctionNames = ParameterFunctionName(struct {});
    const Remap = RemapParamID(struct {});
    var functions = FunctionNames{};
    var remap = Remap{};

    var function_query: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, functions.asInterface().vtable.queryInterface(functions.asInterface(), &ivstparameterfunctionname.iparameter_function_name_iid, &function_query));
    try std.testing.expect(function_query != null);
    const function_iface: *ivstparameterfunctionname.IParameterFunctionName = @ptrCast(@alignCast(function_query.?));
    try std.testing.expectEqual(@as(types.uint32, 1), function_iface.vtable.release(function_iface));

    var remap_query: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, remap.asInterface().vtable.queryInterface(remap.asInterface(), &ivstremapparamid.iremap_param_id_iid, &remap_query));
    try std.testing.expect(remap_query != null);
    const remap_iface: *ivstremapparamid.IRemapParamID = @ptrCast(@alignCast(remap_query.?));
    try std.testing.expectEqual(@as(types.uint32, 1), remap_iface.vtable.release(remap_iface));
}
