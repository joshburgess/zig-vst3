const builtin = @import("builtin");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");

pub const EntryContext = switch (builtin.os.tag) {
    .windows => void,
    else => ?*anyopaque,
};

pub fn Exports(comptime PluginFactory: type) type {
    return switch (builtin.os.tag) {
        .windows => WindowsExports(PluginFactory),
        .macos => MacExports(PluginFactory),
        else => LinuxExports(PluginFactory),
    };
}

pub fn exportPlugin(comptime PluginFactory: type) void {
    if (builtin.is_test) return;

    const PluginExports = Exports(PluginFactory);
    @export(&PluginExports.GetPluginFactory, .{ .name = "GetPluginFactory" });

    switch (builtin.os.tag) {
        .windows => {
            @export(&PluginExports.InitDll, .{ .name = "InitDll" });
            @export(&PluginExports.ExitDll, .{ .name = "ExitDll" });
        },
        .macos => {
            @export(&PluginExports.bundleEntry, .{ .name = "bundleEntry" });
            @export(&PluginExports.bundleExit, .{ .name = "bundleExit" });
        },
        else => {
            @export(&PluginExports.ModuleEntry, .{ .name = "ModuleEntry" });
            @export(&PluginExports.ModuleExit, .{ .name = "ModuleExit" });
        },
    }
}

fn WindowsExports(comptime PluginFactory: type) type {
    return struct {
        pub fn GetPluginFactory() callconv(.c) ?*ipluginbase.IPluginFactory {
            return PluginFactory.getPluginFactory();
        }

        pub fn InitDll() callconv(.c) bool {
            if (@hasDecl(PluginFactory, "initDll")) {
                return PluginFactory.initDll();
            }
            if (@hasDecl(PluginFactory, "moduleEntry")) {
                return PluginFactory.moduleEntry({});
            }
            return true;
        }

        pub fn ExitDll() callconv(.c) bool {
            if (@hasDecl(PluginFactory, "exitDll")) {
                return PluginFactory.exitDll();
            }
            if (@hasDecl(PluginFactory, "moduleExit")) {
                return PluginFactory.moduleExit();
            }
            return true;
        }
    };
}

fn MacExports(comptime PluginFactory: type) type {
    return struct {
        pub fn GetPluginFactory() callconv(.c) ?*ipluginbase.IPluginFactory {
            return PluginFactory.getPluginFactory();
        }

        pub fn bundleEntry(context: EntryContext) callconv(.c) bool {
            if (@hasDecl(PluginFactory, "bundleEntry")) {
                return PluginFactory.bundleEntry(context);
            }
            if (@hasDecl(PluginFactory, "moduleEntry")) {
                return PluginFactory.moduleEntry(context);
            }
            return true;
        }

        pub fn bundleExit() callconv(.c) bool {
            if (@hasDecl(PluginFactory, "bundleExit")) {
                return PluginFactory.bundleExit();
            }
            if (@hasDecl(PluginFactory, "moduleExit")) {
                return PluginFactory.moduleExit();
            }
            return true;
        }
    };
}

fn LinuxExports(comptime PluginFactory: type) type {
    return struct {
        pub fn GetPluginFactory() callconv(.c) ?*ipluginbase.IPluginFactory {
            return PluginFactory.getPluginFactory();
        }

        pub fn ModuleEntry(context: EntryContext) callconv(.c) bool {
            if (@hasDecl(PluginFactory, "moduleEntry")) {
                return PluginFactory.moduleEntry(context);
            }
            return true;
        }

        pub fn ModuleExit() callconv(.c) bool {
            if (@hasDecl(PluginFactory, "moduleExit")) {
                return PluginFactory.moduleExit();
            }
            return true;
        }
    };
}

test "entry context follows platform entry signatures" {
    if (builtin.os.tag == .windows) {
        try @import("std").testing.expectEqual(void, EntryContext);
    } else {
        try @import("std").testing.expectEqual(?*anyopaque, EntryContext);
    }
}
