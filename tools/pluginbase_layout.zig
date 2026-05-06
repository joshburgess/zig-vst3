const std = @import("std");
const pluginbase = @import("vst3-zig").pluginterfaces.base.ipluginbase;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("PFactoryInfo.kURLSize {}\n", .{pluginbase.PFactoryInfo.kURLSize});
    try stdout.print("PFactoryInfo.kEmailSize {}\n", .{pluginbase.PFactoryInfo.kEmailSize});
    try stdout.print("PFactoryInfo.kNameSize {}\n", .{pluginbase.PFactoryInfo.kNameSize});
    try stdout.print("PFactoryInfo.kNoFlags {}\n", .{pluginbase.PFactoryInfo.kNoFlags});
    try stdout.print("PFactoryInfo.kClassesDiscardable {}\n", .{pluginbase.PFactoryInfo.kClassesDiscardable});
    try stdout.print("PFactoryInfo.kLicenseCheck {}\n", .{pluginbase.PFactoryInfo.kLicenseCheck});
    try stdout.print("PFactoryInfo.kComponentNonDiscardable {}\n", .{pluginbase.PFactoryInfo.kComponentNonDiscardable});
    try stdout.print("PFactoryInfo.kUnicode {}\n", .{pluginbase.PFactoryInfo.kUnicode});
    try stdout.print("PClassInfo.kManyInstances {}\n", .{pluginbase.PClassInfo.kManyInstances});
    try stdout.print("PClassInfo.kCategorySize {}\n", .{pluginbase.PClassInfo.kCategorySize});
    try stdout.print("PClassInfo.kNameSize {}\n", .{pluginbase.PClassInfo.kNameSize});
    try stdout.print("PClassInfo2.kVendorSize {}\n", .{pluginbase.PClassInfo2.kVendorSize});
    try stdout.print("PClassInfo2.kVersionSize {}\n", .{pluginbase.PClassInfo2.kVersionSize});
    try stdout.print("PClassInfo2.kSubCategoriesSize {}\n", .{pluginbase.PClassInfo2.kSubCategoriesSize});
    try stdout.print("PClassInfoW.kVendorSize {}\n", .{pluginbase.PClassInfoW.kVendorSize});
    try stdout.print("PClassInfoW.kVersionSize {}\n", .{pluginbase.PClassInfoW.kVersionSize});
    try stdout.print("PClassInfoW.kSubCategoriesSize {}\n", .{pluginbase.PClassInfoW.kSubCategoriesSize});

    try printType(stdout, "PFactoryInfo", pluginbase.PFactoryInfo);
    try printOffset(stdout, "PFactoryInfo", "vendor", pluginbase.PFactoryInfo, "vendor");
    try printOffset(stdout, "PFactoryInfo", "url", pluginbase.PFactoryInfo, "url");
    try printOffset(stdout, "PFactoryInfo", "email", pluginbase.PFactoryInfo, "email");
    try printOffset(stdout, "PFactoryInfo", "flags", pluginbase.PFactoryInfo, "flags");

    try printType(stdout, "PClassInfo", pluginbase.PClassInfo);
    try printOffset(stdout, "PClassInfo", "cid", pluginbase.PClassInfo, "cid");
    try printOffset(stdout, "PClassInfo", "cardinality", pluginbase.PClassInfo, "cardinality");
    try printOffset(stdout, "PClassInfo", "category", pluginbase.PClassInfo, "category");
    try printOffset(stdout, "PClassInfo", "name", pluginbase.PClassInfo, "name");

    try printType(stdout, "PClassInfo2", pluginbase.PClassInfo2);
    try printOffset(stdout, "PClassInfo2", "cid", pluginbase.PClassInfo2, "cid");
    try printOffset(stdout, "PClassInfo2", "cardinality", pluginbase.PClassInfo2, "cardinality");
    try printOffset(stdout, "PClassInfo2", "category", pluginbase.PClassInfo2, "category");
    try printOffset(stdout, "PClassInfo2", "name", pluginbase.PClassInfo2, "name");
    try printOffset(stdout, "PClassInfo2", "classFlags", pluginbase.PClassInfo2, "classFlags");
    try printOffset(stdout, "PClassInfo2", "subCategories", pluginbase.PClassInfo2, "subCategories");
    try printOffset(stdout, "PClassInfo2", "vendor", pluginbase.PClassInfo2, "vendor");
    try printOffset(stdout, "PClassInfo2", "version", pluginbase.PClassInfo2, "version");
    try printOffset(stdout, "PClassInfo2", "sdkVersion", pluginbase.PClassInfo2, "sdkVersion");

    try printType(stdout, "PClassInfoW", pluginbase.PClassInfoW);
    try printOffset(stdout, "PClassInfoW", "cid", pluginbase.PClassInfoW, "cid");
    try printOffset(stdout, "PClassInfoW", "cardinality", pluginbase.PClassInfoW, "cardinality");
    try printOffset(stdout, "PClassInfoW", "category", pluginbase.PClassInfoW, "category");
    try printOffset(stdout, "PClassInfoW", "name", pluginbase.PClassInfoW, "name");
    try printOffset(stdout, "PClassInfoW", "classFlags", pluginbase.PClassInfoW, "classFlags");
    try printOffset(stdout, "PClassInfoW", "subCategories", pluginbase.PClassInfoW, "subCategories");
    try printOffset(stdout, "PClassInfoW", "vendor", pluginbase.PClassInfoW, "vendor");
    try printOffset(stdout, "PClassInfoW", "version", pluginbase.PClassInfoW, "version");
    try printOffset(stdout, "PClassInfoW", "sdkVersion", pluginbase.PClassInfoW, "sdkVersion");

    try printType(stdout, "IPluginFactory", pluginbase.IPluginFactory);
    try printType(stdout, "IPluginFactory2", pluginbase.IPluginFactory2);
    try printType(stdout, "IPluginFactory3", pluginbase.IPluginFactory3);
}

fn printType(writer: anytype, comptime name: []const u8, comptime Type: type) !void {
    try writer.print("{s} size {} align {}\n", .{ name, @sizeOf(Type), @alignOf(Type) });
}

fn printOffset(writer: anytype, comptime type_name: []const u8, comptime field_label: []const u8, comptime Type: type, comptime field_name: []const u8) !void {
    try writer.print("{s}.{s} offset {}\n", .{ type_name, field_label, @offsetOf(Type, field_name) });
}
