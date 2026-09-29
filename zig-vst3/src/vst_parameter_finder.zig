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

        const owner = interface_map.ownerFromField(Self, ivstplugview.IParameterFinder, "iface");

        fn query(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
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

        fn findParameter(_: *anyopaque, x: types.int32, y: types.int32, out_raw: [*c]vsttypes.ParamID) callconv(.c) types.tresult {
            if (out_raw == null) return types.kInvalidArgument;
            const out: *vsttypes.ParamID = @ptrCast(out_raw);
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

        const owner = interface_map.ownerFromField(Self, ivstparameterfunctionname.IParameterFunctionName, "iface");

        fn query(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
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

        fn getParameterIDFromFunctionName(_: *anyopaque, unit_id: vsttypes.UnitID, function_name: ?types.FIDString, out_raw: [*c]vsttypes.ParamID) callconv(.c) types.tresult {
            if (out_raw == null) return types.kInvalidArgument;
            const out: *vsttypes.ParamID = @ptrCast(out_raw);
            const name = function_name orelse return failParamIdWithResult(out, types.kInvalidArgument);
            if (@hasDecl(Config, "getParameterIDFromFunctionName")) {
                if (Config.getParameterIDFromFunctionName(unit_id, name)) |id| {
                    out.* = id;
                    return types.kResultOk;
                }
            }
            return failParamId(out);
        }

        fn failParamIdWithResult(out: *vsttypes.ParamID, result: types.tresult) types.tresult {
            out.* = vsttypes.kNoParamId;
            return result;
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

        const owner = interface_map.ownerFromField(Self, ivstremapparamid.IRemapParamID, "iface");

        fn query(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
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

        fn getCompatibleParamID(_: *anyopaque, class_id_raw: [*c]const tuid.TUID, old_param_id: vsttypes.ParamID, out_raw: [*c]vsttypes.ParamID) callconv(.c) types.tresult {
            if (class_id_raw == null or out_raw == null) return types.kInvalidArgument;
            const class_id: *const tuid.TUID = @ptrCast(class_id_raw);
            const out: *vsttypes.ParamID = @ptrCast(out_raw);
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
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.findParameter(iface, 12, 6, null));
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

    queried = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, iface), queried);
    try std.testing.expectEqual(@as(types.uint32, 2), finder.ref_count.load(.seq_cst));
    const queried_unknown: *ivstplugview.IParameterFinder = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_unknown.vtable.release(queried_unknown));
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

    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getParameterIDFromFunctionName(iface, 2, ivstparameterfunctionname.FunctionNameType.kDryWetMix, null));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getParameterIDFromFunctionName(iface, 2, null, &found));
    try std.testing.expectEqual(vsttypes.kNoParamId, found);
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

test "remap param ID returns no-param without a config hook" {
    const Remap = RemapParamID(struct {});
    var remap = Remap{};
    const iface = remap.asInterface();
    var found: vsttypes.ParamID = 123;

    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getCompatibleParamID(iface, null, 1, &found));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 123), found);
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getCompatibleParamID(iface, &funknown.iid, 1, null));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.getCompatibleParamID(iface, &funknown.iid, 1, &found));
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

    function_query = null;
    try std.testing.expectEqual(types.kResultOk, functions.asInterface().vtable.queryInterface(functions.asInterface(), &funknown.iid, &function_query));
    try std.testing.expectEqual(@as(?*anyopaque, functions.asInterface()), function_query);
    try std.testing.expectEqual(@as(types.uint32, 2), functions.ref_count.load(.seq_cst));
    const function_unknown: *ivstparameterfunctionname.IParameterFunctionName = @ptrCast(@alignCast(function_query.?));
    try std.testing.expectEqual(@as(types.uint32, 1), function_unknown.vtable.release(function_unknown));

    var remap_query: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, remap.asInterface().vtable.queryInterface(remap.asInterface(), &ivstremapparamid.iremap_param_id_iid, &remap_query));
    try std.testing.expect(remap_query != null);
    const remap_iface: *ivstremapparamid.IRemapParamID = @ptrCast(@alignCast(remap_query.?));
    try std.testing.expectEqual(@as(types.uint32, 1), remap_iface.vtable.release(remap_iface));

    remap_query = null;
    try std.testing.expectEqual(types.kResultOk, remap.asInterface().vtable.queryInterface(remap.asInterface(), &funknown.iid, &remap_query));
    try std.testing.expectEqual(@as(?*anyopaque, remap.asInterface()), remap_query);
    try std.testing.expectEqual(@as(types.uint32, 2), remap.ref_count.load(.seq_cst));
    const remap_unknown: *ivstremapparamid.IRemapParamID = @ptrCast(@alignCast(remap_query.?));
    try std.testing.expectEqual(@as(types.uint32, 1), remap_unknown.vtable.release(remap_unknown));
}

test "parameter helper unsupported queries clear stale outputs" {
    const Finder = ParameterFinder(struct {});
    const FunctionNames = ParameterFunctionName(struct {});
    const Remap = RemapParamID(struct {});
    var finder = Finder{};
    var functions = FunctionNames{};
    var remap = Remap{};

    var finder_query: ?*anyopaque = finder.asInterface();
    try std.testing.expectEqual(types.kNoInterface, finder.asInterface().vtable.queryInterface(finder.asInterface(), &tuid.zero, &finder_query));
    try std.testing.expectEqual(@as(?*anyopaque, null), finder_query);

    var function_query: ?*anyopaque = functions.asInterface();
    try std.testing.expectEqual(types.kNoInterface, functions.asInterface().vtable.queryInterface(functions.asInterface(), &tuid.zero, &function_query));
    try std.testing.expectEqual(@as(?*anyopaque, null), function_query);

    var remap_query: ?*anyopaque = remap.asInterface();
    try std.testing.expectEqual(types.kNoInterface, remap.asInterface().vtable.queryInterface(remap.asInterface(), &tuid.zero, &remap_query));
    try std.testing.expectEqual(@as(?*anyopaque, null), remap_query);
}
