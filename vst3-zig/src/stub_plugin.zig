const entry = @import("entry.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");

const StubFactory = struct {
    pub fn getPluginFactory() ?*ipluginbase.IPluginFactory {
        return null;
    }
};

pub usingnamespace entry.Exports(StubFactory);
