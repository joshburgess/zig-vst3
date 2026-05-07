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

fn WindowsExports(comptime PluginFactory: type) type {
    return struct {
        export fn GetPluginFactory() ?*ipluginbase.IPluginFactory {
            return PluginFactory.getPluginFactory();
        }

        export fn InitDll() bool {
            if (@hasDecl(PluginFactory, "initDll")) {
                return PluginFactory.initDll();
            }
            if (@hasDecl(PluginFactory, "moduleEntry")) {
                return PluginFactory.moduleEntry({});
            }
            return true;
        }

        export fn ExitDll() bool {
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
        export fn GetPluginFactory() ?*ipluginbase.IPluginFactory {
            return PluginFactory.getPluginFactory();
        }

        export fn bundleEntry(context: EntryContext) bool {
            if (@hasDecl(PluginFactory, "bundleEntry")) {
                return PluginFactory.bundleEntry(context);
            }
            if (@hasDecl(PluginFactory, "moduleEntry")) {
                return PluginFactory.moduleEntry(context);
            }
            return true;
        }

        export fn bundleExit() bool {
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
        export fn GetPluginFactory() ?*ipluginbase.IPluginFactory {
            return PluginFactory.getPluginFactory();
        }

        export fn ModuleEntry(context: EntryContext) bool {
            if (@hasDecl(PluginFactory, "moduleEntry")) {
                return PluginFactory.moduleEntry(context);
            }
            return true;
        }

        export fn ModuleExit() bool {
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
