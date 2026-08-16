const std = @import("std");

const accessibility = @import("gui/accessibility.zig");
const composition = @import("gui/composition.zig");
const graphs = @import("gui/graphs.zig");
const importer = @import("gui/importer.zig");
const lifecycle = @import("gui/lifecycle.zig");

test {
    std.testing.refAllDecls(accessibility);
    std.testing.refAllDecls(composition);
    std.testing.refAllDecls(graphs);
    std.testing.refAllDecls(importer);
    std.testing.refAllDecls(lifecycle);
}
