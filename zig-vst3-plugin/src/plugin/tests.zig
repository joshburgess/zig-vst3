const std = @import("std");
const parameters = @import("../parameters.zig");
const process_api = @import("../process.zig");
const state = @import("../state.zig");
const units_api = @import("../units.zig");
const plugin = @import("../plugin.zig");

const PluginSpec = plugin.PluginSpec;
const PluginInstance = plugin.PluginInstance;
const PrepareConfig = plugin.PrepareConfig;
const validateLifecycle = plugin.validateLifecycle;

const FixedBufferStream = struct {
    buffer: []u8,
    reader_interface: std.Io.Reader,
    writer_interface: std.Io.Writer,

    fn init(buffer: []u8) FixedBufferStream {
        return .{
            .buffer = buffer,
            .reader_interface = std.Io.Reader.fixed(buffer),
            .writer_interface = std.Io.Writer.fixed(buffer),
        };
    }

    fn reader(self: *FixedBufferStream) *std.Io.Reader {
        self.reader_interface = std.Io.Reader.fixed(self.buffer);
        return &self.reader_interface;
    }

    fn writer(self: *FixedBufferStream) *std.Io.Writer {
        self.writer_interface = std.Io.Writer.fixed(self.buffer);
        return &self.writer_interface;
    }

    fn getWritten(self: *const FixedBufferStream) []const u8 {
        return self.writer_interface.buffered();
    }
};

fn expectMigrationErrorPreservesParameter(
    instance: anytype,
    bytes: []u8,
    comptime field_name: []const u8,
    expected_value: f64,
    expected_error: anyerror,
    migrations: []const state.ParameterIdMigration,
) !void {
    var in_stream = FixedBufferStream.init(bytes);
    try std.testing.expectError(expected_error, instance.readParameterStateWithMigrations(in_stream.reader(), migrations));
    try std.testing.expectEqual(expected_value, instance.loadParameterNormalized(field_name));
}

test "plugin spec exposes metadata and parameter defaults" {
    const Gain = struct {
        pub const name = "Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        };
    };
    const Spec = PluginSpec(Gain);
    var spec = Spec.init(.{});

    try spec.validate();
    try std.testing.expectEqualStrings("Gain", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqualStrings("", Spec.url);
    try std.testing.expectEqualStrings("", Spec.email);
    try std.testing.expectEqualStrings("Gain", Spec.component_class_name);
    try std.testing.expectEqualStrings("Gain Controller", Spec.controller_class_name);
    try std.testing.expectEqualStrings("Audio Module Class", Spec.component_category);
    try std.testing.expectEqualStrings("Component Controller Class", Spec.controller_category);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expectEqualStrings("Gain", spec.parameter_set.name(0).?);
    try std.testing.expectEqual(@as(?u32, 0), spec.parameter_set.idByName("Gain"));
    try std.testing.expectEqual(@as(f64, 1.0), spec.values.view(&spec.parameter_set).loadNormalized("gain"));
    try std.testing.expect(spec.values.editor(&spec.parameter_set).storeNormalized("gain", 0.5));
    try std.testing.expectEqual(@as(f64, 0.5), spec.values.view(&spec.parameter_set).loadNormalized("gain"));
}

test "plugin spec and instance surface invalid parameter metadata" {
    const Duplicate = struct {
        pub const name = "Duplicate";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5 },
            mix: parameters.FloatParam = .{ .id = 0, .name = "Mix", .min = 0.0, .max = 1.0, .default = 0.25 },
        };
    };
    const DuplicateName = struct {
        pub const name = "Duplicate Name";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Level", .min = 0.0, .max = 1.0, .default = 0.5 },
            output: parameters.FloatParam = .{ .id = 1, .name = "Level", .min = 0.0, .max = 1.0, .default = 0.25 },
        };
    };
    const Invalid = struct {
        pub const name = "Invalid";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .min = 1.0, .max = 1.0, .default = 1.0 },
        };
    };
    const InvalidDefault = struct {
        pub const name = "Invalid Default";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = std.math.inf(f64) },
        };
    };
    const DuplicateNameSpec = PluginSpec(DuplicateName);
    const duplicate_name_set = DuplicateNameSpec.ParameterSet.init(.{});

    try std.testing.expectError(error.DuplicateParameterId, PluginSpec(Duplicate).initChecked(.{}));
    try std.testing.expectError(error.DuplicateParameterName, PluginSpec(DuplicateName).initChecked(.{}));
    try std.testing.expectEqualStrings("Level", duplicate_name_set.duplicateName().?);
    try std.testing.expectEqual(@as(?usize, 1), duplicate_name_set.duplicateNameIndex());
    try std.testing.expect(duplicate_name_set.hasDuplicateNames());
    try std.testing.expectError(error.InvalidParameterRange, PluginInstance(Invalid).init(std.testing.allocator, .{}));
    try std.testing.expectError(error.InvalidParameterDefault, PluginInstance(InvalidDefault).init(std.testing.allocator, .{}));
}

test "plugin spec rejects invalid plugin metadata" {
    const EmptyName = struct {
        pub const name = "";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    const EmptyVendor = struct {
        pub const name = "Empty Vendor";
        pub const vendor = "";
        pub const Params = struct {};
    };
    const EmptyComponentName = struct {
        pub const name = "Empty Component";
        pub const vendor = "zig-vst3";
        pub const component_class_name = "";
        pub const Params = struct {};
    };
    const EmptyControllerCategory = struct {
        pub const name = "Empty Controller Category";
        pub const vendor = "zig-vst3";
        pub const controller_category = "";
        pub const Params = struct {};
    };
    const InteriorNull = struct {
        pub const name = "Interior Null";
        pub const vendor = "zig-vst3";
        pub const email = "plugins\x00example.test";
        pub const Params = struct {};
    };

    try std.testing.expectError(error.EmptyPluginMetadata, PluginSpec(EmptyName).initChecked(.{}));
    try std.testing.expectError(error.EmptyPluginMetadata, PluginSpec(EmptyVendor).initChecked(.{}));
    try std.testing.expectError(error.EmptyPluginMetadata, PluginSpec(EmptyComponentName).initChecked(.{}));
    try std.testing.expectError(error.EmptyPluginMetadata, PluginSpec(EmptyControllerCategory).initChecked(.{}));
    try std.testing.expectError(error.InvalidPluginMetadata, PluginSpec(InteriorNull).initChecked(.{}));
}

test "plugin instance reports empty parameter metadata" {
    const Empty = struct {
        pub const name = "No Parameters";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    var instance = try PluginInstance(Empty).init(std.testing.allocator, .{});
    const view = instance.parameterView();
    const editor = instance.parameterEditor();

    try std.testing.expectEqual(@as(usize, 0), instance.parameterCount());
    try std.testing.expect(instance.parametersEmpty());
    try std.testing.expect(!instance.hasParameters());
    try std.testing.expectEqual(@as(usize, 0), view.parameterCount());
    try std.testing.expect(view.parametersEmpty());
    try std.testing.expect(!view.hasParameters());
    try std.testing.expectEqual(@as(usize, 0), editor.parameterCount());
    try std.testing.expect(editor.parametersEmpty());
    try std.testing.expect(!editor.hasParameters());
}

var invalid_metadata_init_called = false;

test "plugin instance validates metadata before plugin init hook" {
    invalid_metadata_init_called = false;
    const Invalid = struct {
        pub const name = "";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5 },
        };

        pub fn init(_: std.mem.Allocator) !@This() {
            invalid_metadata_init_called = true;
            return .{};
        }
    };

    try std.testing.expectError(error.EmptyPluginMetadata, PluginInstance(Invalid).init(std.testing.allocator, .{}));
    try std.testing.expect(!invalid_metadata_init_called);
}

test "plugin spec exposes optional plugin metadata overrides" {
    const Custom = struct {
        pub const name = "Custom";
        pub const vendor = "Vendor";
        pub const url = "https://example.test/custom";
        pub const email = "plugins@example.test";
        pub const component_class_name = "Custom Processor";
        pub const controller_class_name = "Custom Editor";
        pub const component_category = "Custom Processor Category";
        pub const controller_category = "Custom Controller Category";
        pub const follow_host_transport = true;
        pub const allow_dynamic_process_mode = true;
        pub const Params = struct {};
    };
    const Spec = PluginSpec(Custom);
    var instance = try PluginInstance(Custom).init(std.testing.allocator, .{});

    try std.testing.expectEqualStrings("Custom", instance.pluginName());
    try std.testing.expectEqualStrings("Vendor", instance.pluginVendor());
    try std.testing.expectEqualStrings("https://example.test/custom", instance.pluginUrl());
    try std.testing.expectEqualStrings("plugins@example.test", instance.pluginEmail());
    try std.testing.expectEqualStrings("Custom Processor", instance.componentClassName());
    try std.testing.expectEqualStrings("Custom Editor", instance.controllerClassName());
    try std.testing.expectEqualStrings("Custom Processor Category", instance.componentCategory());
    try std.testing.expectEqualStrings("Custom Controller Category", instance.controllerCategory());
    try std.testing.expectEqualStrings("https://example.test/custom", Spec.url);
    try std.testing.expectEqualStrings("plugins@example.test", Spec.email);
    try std.testing.expectEqualStrings("Custom Processor", Spec.component_class_name);
    try std.testing.expectEqualStrings("Custom Editor", Spec.controller_class_name);
    try std.testing.expectEqualStrings("Custom Processor Category", Spec.component_category);
    try std.testing.expectEqualStrings("Custom Controller Category", Spec.controller_category);
    try std.testing.expect(Spec.follow_host_transport);
    try std.testing.expect(Spec.allow_dynamic_process_mode);
}

test "plugin spec exposes optional bus topology metadata" {
    const DefaultEffect = struct {
        pub const name = "Default Effect";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    const Analyzer = struct {
        pub const name = "Analyzer";
        pub const vendor = "zig-vst3";
        pub const audio_output = false;
        pub const Params = struct {};
    };
    const Generator = struct {
        pub const name = "Generator";
        pub const vendor = "zig-vst3";
        pub const audio_input = false;
        pub const event_output = true;
        pub const Params = struct {};
    };
    const ControlOnly = struct {
        pub const name = "Control Only";
        pub const vendor = "zig-vst3";
        pub const audio_input = false;
        pub const audio_output = false;
        pub const event_input = false;
        pub const Params = struct {};
    };
    const MonoEffect = struct {
        pub const name = "Mono Effect";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin.AudioBusLayout = .mono;
        pub const Params = struct {};
    };
    const MonoToStereo = struct {
        pub const name = "Mono to Stereo";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin.AudioBusLayout = .stereo;
        pub const Params = struct {};
    };
    const SurroundEffect = struct {
        pub const name = "Surround Effect";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin.AudioBusLayout = .surround_5_1;
        pub const audio_output_layout: plugin.AudioBusLayout = .surround_7_1;
        pub const Params = struct {};
    };

    try std.testing.expect(PluginSpec(DefaultEffect).audio_input);
    try std.testing.expect(PluginSpec(DefaultEffect).audio_output);
    try std.testing.expect(PluginSpec(DefaultEffect).event_input);
    try std.testing.expect(!PluginSpec(DefaultEffect).event_output);
    try std.testing.expect(PluginSpec(Analyzer).audio_input);
    try std.testing.expect(!PluginSpec(Analyzer).audio_output);
    try std.testing.expect(!PluginSpec(Generator).audio_input);
    try std.testing.expect(PluginSpec(Generator).audio_output);
    try std.testing.expect(PluginSpec(Generator).event_output);
    try std.testing.expect(!PluginSpec(ControlOnly).audio_input);
    try std.testing.expect(!PluginSpec(ControlOnly).audio_output);
    try std.testing.expect(!PluginSpec(ControlOnly).event_input);
    try std.testing.expectEqual(plugin.AudioBusLayout.stereo, PluginSpec(DefaultEffect).audio_input_layout);
    try std.testing.expectEqual(plugin.AudioBusLayout.none, PluginSpec(Analyzer).audio_output_layout);
    try std.testing.expectEqual(plugin.AudioBusLayout.mono, PluginSpec(MonoEffect).audio_input_layout);
    try std.testing.expectEqual(@as(u8, 1), PluginSpec(MonoEffect).audio_output_layout.channelCount());
    try std.testing.expectEqual(@as(u8, 1), PluginSpec(MonoToStereo).audio_input_layout.channelCount());
    try std.testing.expectEqual(@as(u8, 2), PluginSpec(MonoToStereo).audio_output_layout.channelCount());
    try std.testing.expectEqual(@as(u8, 3), plugin.AudioBusLayout.surround_3_0.channelCount());
    try std.testing.expectEqual(@as(u8, 4), plugin.AudioBusLayout.quadraphonic.channelCount());
    try std.testing.expectEqual(@as(u8, 4), plugin.AudioBusLayout.ambisonic_first_order.channelCount());
    try std.testing.expectEqual(@as(u8, 9), plugin.AudioBusLayout.ambisonic_second_order.channelCount());
    try std.testing.expectEqual(@as(u8, 16), plugin.AudioBusLayout.ambisonic_third_order.channelCount());
    try std.testing.expectEqual(@as(u8, 12), plugin.AudioBusLayout.surround_7_1_4.channelCount());
    try std.testing.expectEqual(@as(u8, 6), PluginSpec(SurroundEffect).audio_input_layout.channelCount());
    try std.testing.expectEqual(@as(u8, 8), PluginSpec(SurroundEffect).audio_output_layout.channelCount());
}

test "plugin spec exposes default root unit metadata" {
    const Gain = struct {
        pub const name = "Unitless Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    const Spec = PluginSpec(Gain);
    var spec = Spec.init(.{});

    try std.testing.expectEqual(@as(usize, 1), spec.units.unitCount());
    try std.testing.expectEqual(@as(usize, 0), spec.units.programListCount());
    try std.testing.expectEqual(units_api.root_unit_id, spec.units.rootUnit().id);
    try std.testing.expectEqualStrings("Root", spec.units.rootUnit().name);
}

test "plugin spec rejects invalid unit metadata" {
    const InvalidUnits = struct {
        pub const name = "Invalid Units";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const units = units_api.Config{
            .units = &.{
                units_api.Unit.root("Root"),
                .{ .id = 1, .name = "Voice", .parent_id = 99 },
            },
        };
    };

    try std.testing.expectError(error.InvalidUnitParent, PluginSpec(InvalidUnits).initChecked(.{}));
}

test "plugin spec rejects ambiguous unit metadata names" {
    const DuplicateUnitNames = struct {
        pub const name = "Duplicate Unit Names";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const units = units_api.Config{
            .units = &.{
                units_api.Unit.root("Root"),
                .{ .id = 1, .name = "Root", .parent_id = units_api.root_unit_id },
            },
        };
    };
    const DuplicateProgramListNames = struct {
        pub const name = "Duplicate Program List Names";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const units = units_api.Config{
            .program_lists = &.{
                .{ .id = 1, .name = "Programs" },
                .{ .id = 2, .name = "Programs" },
            },
        };
    };

    try std.testing.expectError(error.DuplicateUnitName, PluginSpec(DuplicateUnitNames).initChecked(.{}));
    try std.testing.expectError(error.DuplicateProgramListName, PluginSpec(DuplicateProgramListNames).initChecked(.{}));
}

test "plugin spec rejects reserved unit metadata ids" {
    const ReservedUnit = struct {
        pub const name = "Reserved Unit";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const units = units_api.Config{
            .units = &.{
                units_api.Unit.root("Root"),
                .{ .id = units_api.no_parent_unit_id, .name = "Reserved", .parent_id = units_api.root_unit_id },
            },
        };
    };
    const ReservedProgramList = struct {
        pub const name = "Reserved Program List";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const units = units_api.Config{
            .program_lists = &.{.{ .id = units_api.no_program_list_id, .name = "Reserved" }},
        };
    };

    try std.testing.expectError(error.ReservedUnitId, PluginSpec(ReservedUnit).initChecked(.{}));
    try std.testing.expectError(error.ReservedProgramListId, PluginSpec(ReservedProgramList).initChecked(.{}));
}

test "plugin spec rejects parameters linked to unknown units" {
    const InvalidParameterUnit = struct {
        pub const name = "Invalid Parameter Unit";
        pub const vendor = "zig-vst3";
        pub const units = units_api.Config{};
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5, .unit_id = 99 },
        };
    };

    try std.testing.expectError(error.InvalidParameterUnit, PluginSpec(InvalidParameterUnit).initChecked(.{}));
}

test "plugin instance exposes custom unit and program metadata" {
    const programs = [_]units_api.Program{
        .{
            .name = "Clean",
            .parameters = &.{.{ .parameter_id = 1, .normalized = 0.25 }},
            .info = &.{.{ .key = "category", .value = "Clean" }},
        },
        .{
            .name = "Lead",
            .parameters = &.{.{ .parameter_id = 1, .normalized = 0.75 }},
        },
    };
    const Synth = struct {
        pub const name = "Unit Synth";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            program: parameters.FloatParam = parameters.FloatParam.init(1, "Program", 0.0, 1.0, 0.5),
        };
        pub const units = units_api.Config{
            .units = &.{
                units_api.Unit.root("Main"),
                .{ .id = 1, .name = "Voice", .parent_id = units_api.root_unit_id, .program_list_id = 7 },
            },
            .program_lists = &.{
                .{ .id = 7, .name = "Voice Programs", .programs = &programs },
            },
        };
    };
    const Instance = PluginInstance(Synth);
    var instance = try Instance.init(std.testing.allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), instance.unitCount());
    try std.testing.expect(!instance.unitsEmpty());
    try std.testing.expect(instance.hasUnits());
    try std.testing.expectEqual(@as(?i32, null), instance.duplicateUnitId());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateUnitIdIndex());
    try std.testing.expect(!instance.hasDuplicateUnitIds());
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateUnitName());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateUnitNameIndex());
    try std.testing.expect(!instance.hasDuplicateUnitNames());
    try std.testing.expectEqual(@as(?usize, null), instance.cyclicUnitParentIndex());
    try std.testing.expectEqualStrings("Main", instance.rootUnit().name);
    try std.testing.expectEqual(units_api.root_unit_id, instance.rootUnitId());
    try std.testing.expectEqualStrings("Main", instance.rootUnitName());
    try std.testing.expectEqual(@as(?usize, 1), instance.unitIndexOfId(1));
    try std.testing.expectEqual(@as(?usize, null), instance.unitIndexOfId(99));
    try std.testing.expectEqual(@as(?usize, 1), instance.unitIndexOfName("Voice"));
    try std.testing.expectEqual(@as(?usize, null), instance.unitIndexOfName("Missing"));
    try std.testing.expectEqualStrings("Voice", instance.unitById(1).?.name);
    try std.testing.expectEqual(@as(i32, 1), instance.unitByName("Voice").?.id);
    try std.testing.expectEqual(@as(?units_api.Unit, null), instance.unitByName("Missing"));
    try std.testing.expect(instance.hasUnit(1));
    try std.testing.expect(!instance.hasUnit(99));
    try std.testing.expect(instance.hasUnitName("Voice"));
    try std.testing.expect(!instance.hasUnitName("Missing"));
    try std.testing.expect(instance.unitIsRoot(units_api.root_unit_id));
    try std.testing.expect(instance.unitIsRootByName("Main"));
    try std.testing.expect(!instance.unitIsRoot(1));
    try std.testing.expect(!instance.unitIsRootByName("Voice"));
    try std.testing.expect(!instance.unitIsRootByName("Missing"));
    try std.testing.expect(!instance.unitHasParent(units_api.root_unit_id));
    try std.testing.expect(instance.unitHasParent(1));
    try std.testing.expect(instance.unitHasParentByName("Voice"));
    try std.testing.expect(!instance.unitHasParentByName("Missing"));
    try std.testing.expectEqual(@as(?i32, units_api.root_unit_id), instance.unitParentId(1));
    try std.testing.expectEqual(@as(?i32, units_api.root_unit_id), instance.unitParentIdByName("Voice"));
    try std.testing.expectEqual(@as(?i32, null), instance.unitParentId(units_api.root_unit_id));
    try std.testing.expectEqual(@as(?i32, null), instance.unitParentIdByName("Missing"));
    try std.testing.expect(instance.unitHasProgramList(1));
    try std.testing.expect(instance.unitHasProgramListByName("Voice"));
    try std.testing.expect(!instance.unitHasProgramList(units_api.root_unit_id));
    try std.testing.expect(!instance.unitHasProgramListByName("Missing"));
    try std.testing.expectEqual(@as(usize, 1), instance.programListCount());
    try std.testing.expect(!instance.programListsEmpty());
    try std.testing.expect(instance.hasProgramLists());
    try std.testing.expectEqual(@as(?i32, null), instance.duplicateProgramListId());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramListIdIndex());
    try std.testing.expect(!instance.hasDuplicateProgramListIds());
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramListName());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramListNameIndex());
    try std.testing.expect(!instance.hasDuplicateProgramListNames());
    try std.testing.expectEqual(@as(?usize, 0), instance.programListIndexOfId(7));
    try std.testing.expectEqual(@as(?usize, null), instance.programListIndexOfId(99));
    try std.testing.expectEqual(@as(?usize, 0), instance.programListIndexOfName("Voice Programs"));
    try std.testing.expectEqual(@as(?usize, null), instance.programListIndexOfName("Missing"));
    try std.testing.expectEqualStrings("Voice Programs", instance.programListById(7).?.name);
    try std.testing.expectEqual(@as(i32, 7), instance.programListByName("Voice Programs").?.id);
    try std.testing.expectEqual(@as(?units_api.ProgramList, null), instance.programListByName("Missing"));
    try std.testing.expect(instance.hasProgramList(7));
    try std.testing.expect(!instance.hasProgramList(99));
    try std.testing.expect(instance.hasProgramListName("Voice Programs"));
    try std.testing.expect(!instance.hasProgramListName("Missing"));
    try std.testing.expect(instance.programListHasPrograms(7));
    try std.testing.expect(instance.programListHasProgramsByName("Voice Programs"));
    try std.testing.expect(!instance.programListHasPrograms(99));
    try std.testing.expect(!instance.programListHasProgramsByName("Missing"));
    try std.testing.expect(!instance.programListEmpty(7));
    try std.testing.expect(!instance.programListEmptyByName("Voice Programs"));
    try std.testing.expect(instance.programListEmpty(99));
    try std.testing.expect(instance.programListEmptyByName("Missing"));
    try std.testing.expectEqualStrings("Voice Programs", instance.programListForUnit(1).?.name);
    try std.testing.expectEqualStrings("Voice Programs", instance.programListForUnitName("Voice").?.name);
    try std.testing.expectEqual(@as(?units_api.ProgramList, null), instance.programListForUnitName("Main"));
    try std.testing.expectEqual(@as(?units_api.ProgramList, null), instance.programListForUnitName("Missing"));
    try std.testing.expectEqual(@as(?i32, 7), instance.programListIdForUnit(1));
    try std.testing.expectEqual(@as(?i32, 7), instance.programListIdForUnitName("Voice"));
    try std.testing.expectEqual(@as(?i32, null), instance.programListIdForUnit(units_api.root_unit_id));
    try std.testing.expectEqual(@as(?i32, null), instance.programListIdForUnitName("Missing"));
    try std.testing.expectEqualStrings("Voice Programs", instance.programListNameForUnit(1).?);
    try std.testing.expectEqualStrings("Voice Programs", instance.programListNameForUnitName("Voice").?);
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programListNameForUnit(units_api.root_unit_id));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programListNameForUnitName("Missing"));
    try std.testing.expectEqual(@as(?usize, 2), instance.programCount(7));
    try std.testing.expectEqual(@as(?usize, 2), instance.programCountByName("Voice Programs"));
    try std.testing.expectEqual(@as(?usize, null), instance.programCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.programCountByName("Missing"));
    try std.testing.expectEqualStrings("Lead", instance.programName(7, 1).?);
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programName(7, 99));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programName(99, 0));
    try std.testing.expectEqualStrings("Lead", instance.program(7, 1).?.name);
    try std.testing.expectEqual(@as(?units_api.Program, null), instance.program(7, 99));
    try std.testing.expectEqual(@as(?units_api.Program, null), instance.program(99, 0));
    try std.testing.expectEqualStrings("Lead", instance.programByName(7, "Lead").?.name);
    try std.testing.expectEqual(@as(?units_api.Program, null), instance.programByName(7, "Missing"));
    try std.testing.expectEqual(@as(?units_api.Program, null), instance.programByName(99, "Lead"));
    try std.testing.expectEqual(@as(?usize, 1), instance.programIndexOfName(7, "Lead"));
    try std.testing.expectEqual(@as(?usize, null), instance.programIndexOfName(99, "Lead"));
    try std.testing.expect(instance.hasProgramName(7, "Lead"));
    try std.testing.expect(!instance.hasProgramName(7, "Missing"));
    try std.testing.expect(!instance.hasProgramName(99, "Lead"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramName(7));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramNameIndex(7));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramName(99));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramNameIndex(99));
    try std.testing.expect(!instance.hasDuplicateProgramNames(7));
    try std.testing.expect(!instance.hasDuplicateProgramNames(99));
    try std.testing.expectEqual(@as(?usize, 1), instance.programParameterCount(7, 1));
    try std.testing.expectEqual(@as(?usize, null), instance.programParameterCount(7, 99));
    try std.testing.expectEqual(@as(?usize, null), instance.programParameterCount(99, 0));
    try std.testing.expectEqual(@as(?usize, 1), instance.programParameterCountByName(7, "Lead"));
    try std.testing.expectEqual(@as(?usize, null), instance.programParameterCountByName(99, "Lead"));
    try std.testing.expect(instance.programHasParameters(7, 0));
    try std.testing.expect(instance.programHasParametersByName(7, "Lead"));
    try std.testing.expect(!instance.programHasParameters(7, 99));
    try std.testing.expect(!instance.programHasParametersByName(7, "Missing"));
    try std.testing.expect(!instance.programParametersEmpty(7, 0));
    try std.testing.expect(!instance.programParametersEmptyByName(7, "Lead"));
    try std.testing.expect(instance.programParametersEmpty(7, 99));
    try std.testing.expect(instance.programParametersEmptyByName(7, "Missing"));
    try std.testing.expectEqual(@as(?units_api.ProgramParameter, null), instance.programParameter(7, 1, 99));
    try std.testing.expectEqual(@as(?units_api.ProgramParameter, null), instance.programParameter(99, 0, 0));
    try std.testing.expectEqual(@as(f64, 0.75), instance.programParameterById(7, 1, 1).?.normalized);
    try std.testing.expectEqual(@as(?units_api.ProgramParameter, null), instance.programParameterById(99, 0, 1));
    try std.testing.expectEqual(@as(f64, 0.75), instance.programParameterByName(7, "Lead", 0).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.75), instance.programParameterByNameAndId(7, "Lead", 1).?.normalized);
    try std.testing.expect(instance.hasProgramParameter(7, 1, 1));
    try std.testing.expect(!instance.hasProgramParameter(7, 1, 99));
    try std.testing.expect(!instance.hasProgramParameter(99, 1, 1));
    try std.testing.expectEqual(@as(?u32, null), instance.duplicateProgramParameterId(7, 1));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramParameterIdIndex(7, 1));
    try std.testing.expectEqual(@as(?u32, null), instance.duplicateProgramParameterId(7, 99));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramParameterIdIndex(7, 99));
    try std.testing.expect(!instance.hasDuplicateProgramParameterIds(7, 1));
    try std.testing.expect(!instance.hasDuplicateProgramParameterIds(7, 99));
    try std.testing.expect(instance.hasProgramParameterByName(7, "Lead", 1));
    try std.testing.expect(!instance.hasProgramParameterByName(7, "Lead", 99));
    try std.testing.expect(!instance.hasProgramParameterByName(7, "Missing", 1));
    try std.testing.expectEqual(@as(?u32, null), instance.duplicateProgramParameterIdByName(7, "Lead"));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramParameterIdIndexByName(7, "Lead"));
    try std.testing.expectEqual(@as(?u32, null), instance.duplicateProgramParameterIdByName(7, "Missing"));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramParameterIdIndexByName(7, "Missing"));
    try std.testing.expect(!instance.hasDuplicateProgramParameterIdsByName(7, "Lead"));
    try std.testing.expect(!instance.hasDuplicateProgramParameterIdsByName(7, "Missing"));
    try std.testing.expectEqual(@as(?units_api.ProgramParameter, null), instance.programParameterByName(7, "Missing", 0));
    try std.testing.expectEqual(@as(?units_api.ProgramParameter, null), instance.programParameterByName(99, "Lead", 0));
    try std.testing.expectEqual(@as(?units_api.ProgramParameter, null), instance.programParameterByNameAndId(7, "Lead", 99));
    try std.testing.expectEqual(@as(?units_api.ProgramParameter, null), instance.programParameterByNameAndId(99, "Lead", 1));
    try std.testing.expectEqual(@as(?usize, 0), instance.programParameterIndexOfId(7, 1, 1));
    try std.testing.expectEqual(@as(?usize, null), instance.programParameterIndexOfId(7, 1, 99));
    try std.testing.expectEqual(@as(?usize, null), instance.programParameterIndexOfId(7, 99, 1));
    try std.testing.expectEqual(@as(?usize, 0), instance.programParameterIndexOfIdByName(7, "Lead", 1));
    try std.testing.expectEqual(@as(?usize, null), instance.programParameterIndexOfIdByName(7, "Lead", 99));
    try std.testing.expectEqual(@as(?usize, null), instance.programParameterIndexOfIdByName(7, "Missing", 1));
    try std.testing.expectEqualStrings("Clean", instance.programInfo(7, 0, "category").?);
    try std.testing.expectEqualStrings("category", instance.programInfoEntry(7, 0, 0).?.key);
    try std.testing.expectEqualStrings("Clean", instance.programInfoEntry(7, 0, 0).?.value);
    try std.testing.expectEqualStrings("category", instance.programInfoEntryByKey(7, 0, "category").?.key);
    try std.testing.expectEqualStrings("Clean", instance.programInfoEntryByKey(7, 0, "category").?.value);
    try std.testing.expectEqual(@as(?units_api.ProgramInfo, null), instance.programInfoEntry(7, 0, 1));
    try std.testing.expectEqual(@as(?units_api.ProgramInfo, null), instance.programInfoEntryByKey(7, 0, "missing"));
    try std.testing.expectEqual(@as(?units_api.ProgramInfo, null), instance.programInfoEntry(7, 99, 0));
    try std.testing.expectEqual(@as(?units_api.ProgramInfo, null), instance.programInfoEntryByKey(7, 99, "category"));
    try std.testing.expectEqual(@as(?usize, 0), instance.programInfoIndexOfKey(7, 0, "category"));
    try std.testing.expectEqual(@as(?usize, null), instance.programInfoIndexOfKey(7, 0, "missing"));
    try std.testing.expectEqual(@as(?usize, null), instance.programInfoIndexOfKey(7, 99, "category"));
    try std.testing.expectEqual(@as(?usize, 1), instance.programInfoCount(7, 0));
    try std.testing.expectEqual(@as(?usize, 0), instance.programInfoCountByName(7, "Lead"));
    try std.testing.expectEqual(@as(?usize, null), instance.programInfoCount(7, 99));
    try std.testing.expectEqual(@as(?usize, null), instance.programInfoCountByName(7, "Missing"));
    try std.testing.expect(instance.programHasInfoEntries(7, 0));
    try std.testing.expect(instance.programHasInfoEntriesByName(7, "Clean"));
    try std.testing.expect(!instance.programHasInfoEntries(7, 1));
    try std.testing.expect(!instance.programHasInfoEntriesByName(7, "Lead"));
    try std.testing.expect(!instance.programInfoEmpty(7, 0));
    try std.testing.expect(instance.programInfoEmpty(7, 1));
    try std.testing.expect(instance.programInfoEmpty(7, 99));
    try std.testing.expect(instance.programInfoEmptyByName(7, "Missing"));
    try std.testing.expect(instance.hasProgramInfo(7, 0, "category"));
    try std.testing.expect(!instance.hasProgramInfo(7, 0, "missing"));
    try std.testing.expect(!instance.hasProgramInfo(7, 99, "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramInfoKey(7, 0));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramInfoKeyIndex(7, 0));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramInfoKey(7, 99));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramInfoKeyIndex(7, 99));
    try std.testing.expect(!instance.hasDuplicateProgramInfoKeys(7, 0));
    try std.testing.expect(!instance.hasDuplicateProgramInfoKeys(7, 99));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programInfo(7, 99, "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programInfo(99, 0, "category"));
    try std.testing.expectEqualStrings("Clean", instance.programInfoByName(7, "Clean", "category").?);
    try std.testing.expectEqualStrings("category", instance.programInfoEntryByName(7, "Clean", 0).?.key);
    try std.testing.expectEqualStrings("Clean", instance.programInfoEntryByName(7, "Clean", 0).?.value);
    try std.testing.expectEqualStrings("category", instance.programInfoEntryByNameAndKey(7, "Clean", "category").?.key);
    try std.testing.expectEqualStrings("Clean", instance.programInfoEntryByNameAndKey(7, "Clean", "category").?.value);
    try std.testing.expectEqual(@as(?units_api.ProgramInfo, null), instance.programInfoEntryByName(7, "Clean", 1));
    try std.testing.expectEqual(@as(?units_api.ProgramInfo, null), instance.programInfoEntryByNameAndKey(7, "Clean", "missing"));
    try std.testing.expectEqual(@as(?units_api.ProgramInfo, null), instance.programInfoEntryByName(7, "Missing", 0));
    try std.testing.expectEqual(@as(?units_api.ProgramInfo, null), instance.programInfoEntryByNameAndKey(7, "Missing", "category"));
    try std.testing.expectEqual(@as(?usize, 0), instance.programInfoIndexOfKeyByName(7, "Clean", "category"));
    try std.testing.expectEqual(@as(?usize, null), instance.programInfoIndexOfKeyByName(7, "Clean", "missing"));
    try std.testing.expectEqual(@as(?usize, null), instance.programInfoIndexOfKeyByName(7, "Missing", "category"));
    try std.testing.expect(instance.hasProgramInfoByName(7, "Clean", "category"));
    try std.testing.expect(!instance.hasProgramInfoByName(7, "Clean", "missing"));
    try std.testing.expect(!instance.hasProgramInfoByName(7, "Missing", "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramInfoKeyByName(7, "Clean"));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramInfoKeyIndexByName(7, "Clean"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramInfoKeyByName(7, "Missing"));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramInfoKeyIndexByName(7, "Missing"));
    try std.testing.expect(!instance.hasDuplicateProgramInfoKeysByName(7, "Clean"));
    try std.testing.expect(!instance.hasDuplicateProgramInfoKeysByName(7, "Missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programInfoByName(7, "Missing", "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programInfoByName(99, "Clean", "category"));
}

test "plugin instance applies program parameter snapshots" {
    const programs = [_]units_api.Program{
        .{
            .name = "Low",
            .parameters = &.{.{ .parameter_id = 1, .normalized = 0.25 }},
        },
        .{
            .name = "High",
            .parameters = &.{.{ .parameter_id = 1, .normalized = 0.75 }},
        },
    };
    const Gain = struct {
        pub const name = "Program Gain";
        pub const vendor = "zig-vst3";
        pub const units = units_api.Config{
            .units = &.{
                units_api.Unit.root("Root"),
                .{ .id = 1, .name = "Amp", .parent_id = units_api.root_unit_id, .program_list_id = 7 },
            },
            .program_lists = &.{.{ .id = 7, .name = "Programs", .programs = &programs }},
        };
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
        };
    };
    var instance = try PluginInstance(Gain).init(std.testing.allocator, .{});

    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramCount(7, 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, 0), try instance.applyProgramCount(7, 0));
    try std.testing.expect(try instance.applyProgram(7, 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramByNameCount(7, "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expect(try instance.applyProgramByName(7, "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramForListNameCount("Programs", 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expect(try instance.applyProgramForListName("Programs", 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramByNameForListNameCount("Programs", "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expect(try instance.applyProgramByNameForListName("Programs", "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramCount(7, 99));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramByNameCount(7, "Missing"));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramForListNameCount("Missing", 0));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramByNameForListNameCount("Programs", "Missing"));
    try std.testing.expect(!try instance.applyProgram(7, 99));
    try std.testing.expect(!try instance.applyProgramByName(7, "Missing"));
    try std.testing.expect(!try instance.applyProgramForListName("Missing", 0));
    try std.testing.expect(!try instance.applyProgramByNameForListName("Programs", "Missing"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramForUnitCount(1, 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expect(try instance.applyProgramForUnit(1, 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramByNameForUnitCount(1, "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expect(try instance.applyProgramByNameForUnit(1, "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramForUnitNameCount("Amp", 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expect(try instance.applyProgramForUnitName("Amp", 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramByNameForUnitNameCount("Amp", "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expect(try instance.applyProgramByNameForUnitName("Amp", "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramForUnitCount(99, 0));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramByNameForUnitCount(1, "Missing"));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramForUnitNameCount("Root", 0));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramByNameForUnitNameCount("Missing", "High"));
    try std.testing.expect(!try instance.applyProgramForUnit(99, 0));
    try std.testing.expect(!try instance.applyProgramByNameForUnit(1, "Missing"));
    try std.testing.expect(!try instance.applyProgramForUnitName("Root", 0));
    try std.testing.expect(!try instance.applyProgramByNameForUnitName("Missing", "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramCount(99, 0));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expect(!try instance.applyProgramByName(7, "Missing"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
}

test "plugin instance rejects invalid program snapshots before changing values" {
    const programs = [_]units_api.Program{
        .{
            .name = "Unknown Parameter",
            .parameters = &.{
                .{ .parameter_id = 1, .normalized = 0.25 },
                .{ .parameter_id = 99, .normalized = 0.75 },
            },
        },
        .{
            .name = "Invalid Value",
            .parameters = &.{
                .{ .parameter_id = 1, .normalized = 0.25 },
                .{ .parameter_id = 2, .normalized = 1.5 },
            },
        },
    };
    const Gain = struct {
        pub const name = "Invalid Runtime Program Gain";
        pub const vendor = "zig-vst3";
        pub const units = units_api.Config{
            .program_lists = &.{.{ .id = 7, .name = "Programs", .programs = &programs }},
        };
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
            mix: parameters.FloatParam = parameters.FloatParam.init(2, "Mix", 0.0, 1.0, 0.5),
        };
    };
    const Instance = PluginInstance(Gain);
    const Set = Instance.Spec.ParameterSet;
    const Values = Instance.Spec.ParameterValues;
    const set = Set.init(.{});
    var instance = Instance{
        .spec = .{
            .parameter_set = set,
            .values = Values.init(&set),
        },
        .plugin = .{},
    };

    try std.testing.expectError(error.UnknownProgramParameter, instance.applyProgramCount(7, 0));
    try std.testing.expectEqual(@as(f64, 1.0), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(f64, 0.5), instance.loadParameterNormalized("mix"));

    try std.testing.expectError(error.ProgramParameterOutsideNormalizedRange, instance.applyProgramCount(7, 1));
    try std.testing.expectEqual(@as(f64, 1.0), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(f64, 0.5), instance.loadParameterNormalized("mix"));
}

test "plugin instance unit program accessors mirror unit set selectors" {
    const programs = [_]units_api.Program{
        .{
            .name = "Init",
            .parameters = &.{
                .{ .parameter_id = 1, .normalized = 0.25 },
                .{ .parameter_id = 2, .normalized = 0.50 },
            },
            .info = &.{
                .{ .key = "category", .value = "Clean" },
                .{ .key = "author", .value = "Factory" },
            },
        },
        .{
            .name = "Bright",
            .parameters = &.{.{ .parameter_id = 1, .normalized = 0.75 }},
            .info = &.{.{ .key = "category", .value = "Lead" }},
        },
    };
    const Synth = struct {
        pub const name = "Selector Mirror";
        pub const vendor = "zig-vst3";
        pub const units = units_api.Config{
            .units = &.{
                units_api.Unit.root("Root"),
                .{ .id = 1, .name = "Voice", .parent_id = units_api.root_unit_id, .program_list_id = 7 },
            },
            .program_lists = &.{.{ .id = 7, .name = "Voice Programs", .programs = &programs }},
        };
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
            mix: parameters.FloatParam = parameters.FloatParam.init(2, "Mix", 0.0, 1.0, 0.5),
        };
    };
    const instance = try PluginInstance(Synth).init(std.testing.allocator, .{});
    const source = instance.spec.units;
    const list_id: i32 = 7;
    const list_name = "Voice Programs";
    const unit_id: i32 = 1;
    const unit_name = "Voice";
    const program_names = [_][]const u8{ "Init", "Bright", "Missing" };
    const parameter_ids = [_]u32{ 1, 2, 99 };
    const info_keys = [_][]const u8{ "category", "author", "missing" };

    for (0..programs.len + 1) |program_index| {
        try std.testing.expectEqual(source.programName(list_id, program_index), instance.programName(list_id, program_index));
        try std.testing.expectEqual(source.programNameByListName(list_name, program_index), instance.programNameByListName(list_name, program_index));
        try std.testing.expectEqual(source.programNameForUnit(unit_id, program_index), instance.programNameForUnit(unit_id, program_index));
        try std.testing.expectEqual(source.programNameForUnitName(unit_name, program_index), instance.programNameForUnitName(unit_name, program_index));
        try std.testing.expectEqual(source.program(list_id, program_index), instance.program(list_id, program_index));
        try std.testing.expectEqual(source.programByListName(list_name, program_index), instance.programByListName(list_name, program_index));
        try std.testing.expectEqual(source.programForUnit(unit_id, program_index), instance.programForUnit(unit_id, program_index));
        try std.testing.expectEqual(source.programForUnitName(unit_name, program_index), instance.programForUnitName(unit_name, program_index));

        for (0..3) |parameter_index| {
            try std.testing.expectEqual(source.programParameter(list_id, program_index, parameter_index), instance.programParameter(list_id, program_index, parameter_index));
            try std.testing.expectEqual(source.programParameterByListName(list_name, program_index, parameter_index), instance.programParameterByListName(list_name, program_index, parameter_index));
            try std.testing.expectEqual(source.programParameterForUnit(unit_id, program_index, parameter_index), instance.programParameterForUnit(unit_id, program_index, parameter_index));
            try std.testing.expectEqual(source.programParameterForUnitName(unit_name, program_index, parameter_index), instance.programParameterForUnitName(unit_name, program_index, parameter_index));
        }

        for (parameter_ids) |parameter_id| {
            try std.testing.expectEqual(source.programParameterById(list_id, program_index, parameter_id), instance.programParameterById(list_id, program_index, parameter_id));
            try std.testing.expectEqual(source.programParameterByIdForListName(list_name, program_index, parameter_id), instance.programParameterByIdForListName(list_name, program_index, parameter_id));
            try std.testing.expectEqual(source.programParameterByIdForUnit(unit_id, program_index, parameter_id), instance.programParameterByIdForUnit(unit_id, program_index, parameter_id));
            try std.testing.expectEqual(source.programParameterByIdForUnitName(unit_name, program_index, parameter_id), instance.programParameterByIdForUnitName(unit_name, program_index, parameter_id));
            try std.testing.expectEqual(source.programParameterIndexOfId(list_id, program_index, parameter_id), instance.programParameterIndexOfId(list_id, program_index, parameter_id));
            try std.testing.expectEqual(source.programParameterIndexOfIdByListName(list_name, program_index, parameter_id), instance.programParameterIndexOfIdByListName(list_name, program_index, parameter_id));
            try std.testing.expectEqual(source.programParameterIndexOfIdForUnit(unit_id, program_index, parameter_id), instance.programParameterIndexOfIdForUnit(unit_id, program_index, parameter_id));
            try std.testing.expectEqual(source.programParameterIndexOfIdForUnitName(unit_name, program_index, parameter_id), instance.programParameterIndexOfIdForUnitName(unit_name, program_index, parameter_id));
        }

        for (0..3) |info_index| {
            try std.testing.expectEqual(source.programInfoEntry(list_id, program_index, info_index), instance.programInfoEntry(list_id, program_index, info_index));
            try std.testing.expectEqual(source.programInfoEntryByListName(list_name, program_index, info_index), instance.programInfoEntryByListName(list_name, program_index, info_index));
            try std.testing.expectEqual(source.programInfoEntryForUnit(unit_id, program_index, info_index), instance.programInfoEntryForUnit(unit_id, program_index, info_index));
            try std.testing.expectEqual(source.programInfoEntryForUnitName(unit_name, program_index, info_index), instance.programInfoEntryForUnitName(unit_name, program_index, info_index));
        }

        for (info_keys) |key| {
            try std.testing.expectEqual(source.programInfo(list_id, program_index, key), instance.programInfo(list_id, program_index, key));
            try std.testing.expectEqual(source.programInfoByListName(list_name, program_index, key), instance.programInfoByListName(list_name, program_index, key));
            try std.testing.expectEqual(source.programInfoForUnit(unit_id, program_index, key), instance.programInfoForUnit(unit_id, program_index, key));
            try std.testing.expectEqual(source.programInfoForUnitName(unit_name, program_index, key), instance.programInfoForUnitName(unit_name, program_index, key));
            try std.testing.expectEqual(source.programInfoEntryByKey(list_id, program_index, key), instance.programInfoEntryByKey(list_id, program_index, key));
            try std.testing.expectEqual(source.programInfoEntryByKeyByListName(list_name, program_index, key), instance.programInfoEntryByKeyByListName(list_name, program_index, key));
            try std.testing.expectEqual(source.programInfoEntryByKeyForUnit(unit_id, program_index, key), instance.programInfoEntryByKeyForUnit(unit_id, program_index, key));
            try std.testing.expectEqual(source.programInfoEntryByKeyForUnitName(unit_name, program_index, key), instance.programInfoEntryByKeyForUnitName(unit_name, program_index, key));
            try std.testing.expectEqual(source.programInfoIndexOfKey(list_id, program_index, key), instance.programInfoIndexOfKey(list_id, program_index, key));
            try std.testing.expectEqual(source.programInfoIndexOfKeyByListName(list_name, program_index, key), instance.programInfoIndexOfKeyByListName(list_name, program_index, key));
            try std.testing.expectEqual(source.programInfoIndexOfKeyForUnit(unit_id, program_index, key), instance.programInfoIndexOfKeyForUnit(unit_id, program_index, key));
            try std.testing.expectEqual(source.programInfoIndexOfKeyForUnitName(unit_name, program_index, key), instance.programInfoIndexOfKeyForUnitName(unit_name, program_index, key));
        }
    }

    for (program_names) |program_name| {
        try std.testing.expectEqual(source.programByName(list_id, program_name), instance.programByName(list_id, program_name));
        try std.testing.expectEqual(source.programByNameForListName(list_name, program_name), instance.programByNameForListName(list_name, program_name));
        try std.testing.expectEqual(source.programByNameForUnit(unit_id, program_name), instance.programByNameForUnit(unit_id, program_name));
        try std.testing.expectEqual(source.programByNameForUnitName(unit_name, program_name), instance.programByNameForUnitName(unit_name, program_name));
        try std.testing.expectEqual(source.programIndexOfName(list_id, program_name), instance.programIndexOfName(list_id, program_name));
        try std.testing.expectEqual(source.programIndexOfNameByListName(list_name, program_name), instance.programIndexOfNameByListName(list_name, program_name));
        try std.testing.expectEqual(source.programIndexOfNameForUnit(unit_id, program_name), instance.programIndexOfNameForUnit(unit_id, program_name));
        try std.testing.expectEqual(source.programIndexOfNameForUnitName(unit_name, program_name), instance.programIndexOfNameForUnitName(unit_name, program_name));

        for (parameter_ids) |parameter_id| {
            try std.testing.expectEqual(source.programParameterByNameAndId(list_id, program_name, parameter_id), instance.programParameterByNameAndId(list_id, program_name, parameter_id));
            try std.testing.expectEqual(source.programParameterByNameAndIdForListName(list_name, program_name, parameter_id), instance.programParameterByNameAndIdForListName(list_name, program_name, parameter_id));
            try std.testing.expectEqual(source.programParameterByNameAndIdForUnit(unit_id, program_name, parameter_id), instance.programParameterByNameAndIdForUnit(unit_id, program_name, parameter_id));
            try std.testing.expectEqual(source.programParameterByNameAndIdForUnitName(unit_name, program_name, parameter_id), instance.programParameterByNameAndIdForUnitName(unit_name, program_name, parameter_id));
        }

        for (info_keys) |key| {
            try std.testing.expectEqual(source.programInfoByName(list_id, program_name, key), instance.programInfoByName(list_id, program_name, key));
            try std.testing.expectEqual(source.programInfoByNameForListName(list_name, program_name, key), instance.programInfoByNameForListName(list_name, program_name, key));
            try std.testing.expectEqual(source.programInfoByNameForUnit(unit_id, program_name, key), instance.programInfoByNameForUnit(unit_id, program_name, key));
            try std.testing.expectEqual(source.programInfoByNameForUnitName(unit_name, program_name, key), instance.programInfoByNameForUnitName(unit_name, program_name, key));
            try std.testing.expectEqual(source.programInfoEntryByNameAndKey(list_id, program_name, key), instance.programInfoEntryByNameAndKey(list_id, program_name, key));
            try std.testing.expectEqual(source.programInfoEntryByNameAndKeyForListName(list_name, program_name, key), instance.programInfoEntryByNameAndKeyForListName(list_name, program_name, key));
            try std.testing.expectEqual(source.programInfoEntryByNameAndKeyForUnit(unit_id, program_name, key), instance.programInfoEntryByNameAndKeyForUnit(unit_id, program_name, key));
            try std.testing.expectEqual(source.programInfoEntryByNameAndKeyForUnitName(unit_name, program_name, key), instance.programInfoEntryByNameAndKeyForUnitName(unit_name, program_name, key));
        }
    }
}

test "plugin spec rejects invalid program parameter snapshots" {
    const programs = [_]units_api.Program{
        .{
            .name = "Invalid",
            .parameters = &.{
                .{ .parameter_id = 1, .normalized = 0.25 },
                .{ .parameter_id = 2, .normalized = 1.5 },
            },
        },
    };
    const Gain = struct {
        pub const name = "Invalid Program Gain";
        pub const vendor = "zig-vst3";
        pub const units = units_api.Config{
            .program_lists = &.{.{ .id = 7, .name = "Programs", .programs = &programs }},
        };
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
            mix: parameters.FloatParam = parameters.FloatParam.init(2, "Mix", 0.0, 1.0, 0.5),
        };
    };

    try std.testing.expectError(error.ProgramParameterOutsideNormalizedRange, PluginSpec(Gain).initChecked(.{}));
}

test "plugin spec rejects non-finite program parameter snapshots" {
    const programs = [_]units_api.Program{
        .{
            .name = "Invalid",
            .parameters = &.{
                .{ .parameter_id = 1, .normalized = std.math.inf(f64) },
            },
        },
    };
    const Gain = struct {
        pub const name = "Invalid Program Gain";
        pub const vendor = "zig-vst3";
        pub const units = units_api.Config{
            .program_lists = &.{.{ .id = 7, .name = "Programs", .programs = &programs }},
        };
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
        };
    };

    try std.testing.expectError(error.ProgramParameterOutsideNormalizedRange, PluginSpec(Gain).initChecked(.{}));
}

test "plugin spec rejects unknown program parameter ids" {
    const programs = [_]units_api.Program{
        .{
            .name = "Unknown",
            .parameters = &.{
                .{ .parameter_id = 99, .normalized = 0.75 },
            },
        },
    };
    const Gain = struct {
        pub const name = "Unknown Program Gain";
        pub const vendor = "zig-vst3";
        pub const units = units_api.Config{
            .program_lists = &.{.{ .id = 7, .name = "Programs", .programs = &programs }},
        };
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
        };
    };

    try std.testing.expectError(error.UnknownProgramParameter, PluginSpec(Gain).initChecked(.{}));
}

test "plugin spec detects lifecycle declarations" {
    const Meter = struct {
        pub const name = "Meter";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};

        pub fn init(_: std.mem.Allocator) !@This() {
            return .{};
        }

        pub fn prepare(_: *@This(), _: PrepareConfig) void {}
        pub fn process(_: *@This(), _: *process_api.ProcessContext(f32)) void {}
        pub fn processWithParameters(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
            _: *const parameters.ParameterSet(Params),
            _: *const parameters.ParameterValues(Params),
        ) void {}
        pub fn process64(_: *@This(), _: *process_api.ProcessContext(f64)) void {}
        pub fn process64WithParameters(
            _: *@This(),
            _: *process_api.ProcessContext(f64),
            _: *const parameters.ParameterSet(Params),
            _: *const parameters.ParameterValues(Params),
        ) void {}
        pub fn deinit(_: *@This()) void {}
    };
    const Spec = PluginSpec(Meter);
    validateLifecycle(Meter);

    try std.testing.expect(Spec.has_init);
    try std.testing.expect(Spec.has_prepare);
    try std.testing.expect(Spec.has_process);
    try std.testing.expect(Spec.has_process_with_parameters);
    try std.testing.expect(Spec.has_process64);
    try std.testing.expect(Spec.has_process64_with_parameters);
    try std.testing.expect(Spec.has_process32_hook);
    try std.testing.expect(Spec.has_process64_hook);
    try std.testing.expect(Spec.has_any_process_hook);
    try std.testing.expect(Spec.has_deinit);
}

test "plugin instance exposes bus and lifecycle predicates" {
    const Meter = struct {
        pub const name = "Predicate Meter";
        pub const vendor = "zig-vst3";
        pub const audio_output = false;
        pub const event_output = true;
        pub const Params = struct {};

        pub fn init(_: std.mem.Allocator) !@This() {
            return .{};
        }

        pub fn prepare(_: *@This(), _: PrepareConfig) void {}
        pub fn processWithParameterView(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
            _: parameters.ParameterView(Params),
        ) void {}
        pub fn process64WithParameterView(
            _: *@This(),
            _: *process_api.ProcessContext(f64),
            _: parameters.ParameterView(Params),
        ) void {}
        pub fn deinit(_: *@This()) void {}
    };

    var instance = try PluginInstance(Meter).init(std.testing.allocator, .{});
    defer instance.deinit();

    try std.testing.expect(instance.hasAudioInput());
    try std.testing.expect(!instance.hasAudioSidechainInput());
    try std.testing.expect(!instance.hasAudioAuxiliaryOutput());
    try std.testing.expect(!instance.hasAudioOutput());
    try std.testing.expectEqual(plugin.AudioBusLayout.stereo, instance.audioInputLayout());
    try std.testing.expectEqual(plugin.AudioBusLayout.none, instance.audioSidechainInputLayout());
    try std.testing.expectEqual(plugin.AudioBusLayout.none, instance.audioAuxiliaryOutputLayout());
    try std.testing.expectEqual(plugin.AudioBusLayout.none, instance.audioOutputLayout());
    try std.testing.expectEqual(@as(u8, 2), instance.audioInputChannelCount());
    try std.testing.expectEqual(@as(u8, 0), instance.audioSidechainInputChannelCount());
    try std.testing.expectEqual(@as(u8, 0), instance.audioAuxiliaryOutputChannelCount());
    try std.testing.expectEqual(@as(u8, 0), instance.audioOutputChannelCount());
    try std.testing.expect(instance.hasEventInput());
    try std.testing.expect(instance.hasEventOutput());
    try std.testing.expect(instance.hasInitHook());
    try std.testing.expect(instance.hasPrepareHook());
    try std.testing.expect(instance.hasProcessHook());
    try std.testing.expect(!instance.hasProcessFunctionHook());
    try std.testing.expect(instance.hasProcessWithParameterViewHook());
    try std.testing.expect(!instance.hasProcessWithParametersHook());
    try std.testing.expect(instance.hasProcess64Hook());
    try std.testing.expect(!instance.hasProcess64FunctionHook());
    try std.testing.expect(instance.hasProcess64WithParameterViewHook());
    try std.testing.expect(!instance.hasProcess64WithParametersHook());
    try std.testing.expect(instance.hasAnyProcessHook());
    try std.testing.expect(instance.hasDeinitHook());
}

test "plugin spec and instance expose an optional sidechain input layout" {
    const Ducker = struct {
        pub const name = "Sidechain Ducker";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin.AudioBusLayout = .stereo;
        pub const audio_sidechain_layout: plugin.AudioBusLayout = .mono;
        pub const audio_output_layout: plugin.AudioBusLayout = .stereo;
        pub const Params = struct {};
    };
    const Spec = PluginSpec(Ducker);

    try std.testing.expectEqual(plugin.AudioBusLayout.stereo, Spec.audio_input_layout);
    try std.testing.expectEqual(plugin.AudioBusLayout.mono, Spec.audio_sidechain_layout);
    try std.testing.expectEqual(plugin.AudioBusLayout.stereo, Spec.audio_output_layout);

    var instance = try PluginInstance(Ducker).init(std.testing.allocator, .{});
    defer instance.deinit();

    try std.testing.expect(instance.hasAudioSidechainInput());
    try std.testing.expectEqual(plugin.AudioBusLayout.mono, instance.audioSidechainInputLayout());
    try std.testing.expectEqual(@as(u8, 1), instance.audioSidechainInputChannelCount());
}

test "plugin spec carries a declared dynamic audio topology" {
    const DynamicPlugin = struct {
        pub const name = "Dynamic";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const audio_bus_topology = makeTopology();

        fn makeTopology() plugin.DynamicAudioBusTopology {
            var topology =
                plugin.DynamicAudioBusTopology.init(
                    plugin.DynamicAudioBus.fixed(
                        .stereo,
                        true,
                    ) catch unreachable,
                    plugin.DynamicAudioBus.fixed(
                        .stereo,
                        true,
                    ) catch unreachable,
                ) catch unreachable;
            _ = topology.addAuxiliary(
                .input,
                plugin.DynamicAudioBus.fixed(
                    .mono,
                    false,
                ) catch unreachable,
            ) catch unreachable;
            return topology;
        }
    };
    const Spec = PluginSpec(DynamicPlugin);
    try std.testing.expect(Spec.dynamic_audio_bus_topology != null);
    try std.testing.expectEqual(
        plugin.AudioBusLayout.stereo,
        Spec.audio_input_layout,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        Spec.audio_auxiliary_input_layouts.len,
    );
    try std.testing.expectEqual(
        plugin.AudioBusLayout.mono,
        Spec.audio_auxiliary_input_layouts[0],
    );
}

test "plugin spec preserves a selected dynamic audio topology capacity" {
    const DynamicPlugin = struct {
        pub const name = "Large Dynamic";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const Topology =
            plugin.BoundedDynamicAudioBusTopology(12);
        pub const audio_bus_topology = makeTopology();

        fn makeTopology() Topology {
            var topology = Topology.init(
                plugin.DynamicAudioBus.fixed(
                    .stereo,
                    true,
                ) catch unreachable,
                plugin.DynamicAudioBus.fixed(
                    .stereo,
                    true,
                ) catch unreachable,
            ) catch unreachable;
            for (0..Topology.auxiliary_capacity) |_|
                _ = topology.addAuxiliary(
                    .input,
                    plugin.DynamicAudioBus.fixed(
                        .mono,
                        false,
                    ) catch unreachable,
                ) catch unreachable;
            return topology;
        }
    };
    const Spec = PluginSpec(DynamicPlugin);

    try std.testing.expectEqual(
        DynamicPlugin.Topology,
        Spec.AudioBusTopology,
    );
    try std.testing.expectEqual(
        DynamicPlugin.Topology.SnapshotType,
        Spec.AudioBusSnapshot,
    );
    try std.testing.expectEqual(
        @as(usize, 12),
        Spec.auxiliary_audio_bus_capacity,
    );
    try std.testing.expectEqual(
        @as(usize, 12),
        Spec.audio_auxiliary_input_layouts.len,
    );
    try std.testing.expectEqual(
        plugin.AudioBusLayout.mono,
        Spec.audio_auxiliary_input_layouts[11],
    );
}

test "plugin spec selects capacity for static bus declarations" {
    const StaticPlugin = struct {
        pub const name = "Large Static";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const maximum_auxiliary_audio_buses = 12;
        pub const audio_input_layout: plugin.AudioBusLayout =
            .stereo;
        pub const auxiliary_layouts =
            [_]plugin.AudioBusLayout{.mono} ** 12;
        pub const audio_auxiliary_input_layouts: []const plugin.AudioBusLayout = &auxiliary_layouts;
    };
    const Spec = PluginSpec(StaticPlugin);

    try std.testing.expectEqual(
        @as(usize, 12),
        Spec.auxiliary_audio_bus_capacity,
    );
    try std.testing.expectEqual(
        @as(usize, 12),
        Spec.audio_auxiliary_input_layouts.len,
    );
    try std.testing.expectEqual(
        plugin.BoundedDynamicAudioBusTopology(12),
        Spec.AudioBusTopology,
    );
}

test "plugin spec and instance expose an optional auxiliary output layout" {
    const Splitter = struct {
        pub const name = "Auxiliary Splitter";
        pub const vendor = "zig-vst3";
        pub const audio_auxiliary_output_layout: plugin.AudioBusLayout = .mono;
        pub const Params = struct {};
    };
    const Spec = PluginSpec(Splitter);

    try std.testing.expectEqual(plugin.AudioBusLayout.mono, Spec.audio_auxiliary_output_layout);

    var instance = try PluginInstance(Splitter).init(std.testing.allocator, .{});
    defer instance.deinit();

    try std.testing.expect(instance.hasAudioAuxiliaryOutput());
    try std.testing.expectEqual(plugin.AudioBusLayout.mono, instance.audioAuxiliaryOutputLayout());
    try std.testing.expectEqual(@as(u8, 1), instance.audioAuxiliaryOutputChannelCount());
}

test "plugin spec and instance preserve multiple auxiliary bus layouts" {
    const MultiBus = struct {
        pub const name = "Multi Bus";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: plugin.AudioBusLayout = .stereo;
        pub const audio_output_layout: plugin.AudioBusLayout = .stereo;
        pub const audio_auxiliary_input_layouts: []const plugin.AudioBusLayout = &.{ .mono, .stereo };
        pub const audio_auxiliary_output_layouts: []const plugin.AudioBusLayout = &.{ .stereo, .quadraphonic };
        pub const Params = struct {};
    };
    const Spec = PluginSpec(MultiBus);

    try std.testing.expectEqual(@as(usize, 2), Spec.audio_auxiliary_input_layouts.len);
    try std.testing.expectEqual(@as(usize, 2), Spec.audio_auxiliary_output_layouts.len);
    try std.testing.expectEqual(plugin.AudioBusLayout.mono, Spec.audio_sidechain_layout);
    try std.testing.expectEqual(
        plugin.AudioBusLayout.stereo,
        Spec.audio_auxiliary_output_layout,
    );

    var instance = try PluginInstance(MultiBus).init(std.testing.allocator, .{});
    defer instance.deinit();

    try std.testing.expectEqual(@as(usize, 2), instance.audioAuxiliaryInputBusCount());
    try std.testing.expectEqual(@as(usize, 2), instance.audioAuxiliaryOutputBusCount());
    try std.testing.expectEqual(
        plugin.AudioBusLayout.stereo,
        instance.audioAuxiliaryInputLayout(1).?,
    );
    try std.testing.expectEqual(
        plugin.AudioBusLayout.quadraphonic,
        instance.audioAuxiliaryOutputLayoutAt(1).?,
    );
    try std.testing.expectEqual(
        @as(?plugin.AudioBusLayout, null),
        instance.audioAuxiliaryInputLayout(2),
    );
    try std.testing.expectEqual(
        @as(?plugin.AudioBusLayout, null),
        instance.audioAuxiliaryOutputLayoutAt(2),
    );
}

test "plugin spec allows declaration-only plugin types" {
    const Minimal = struct {
        pub const name = "Minimal";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    const Spec = PluginSpec(Minimal);
    var instance = try PluginInstance(Minimal).init(std.testing.allocator, .{});

    try std.testing.expect(!Spec.has_init);
    try std.testing.expect(!Spec.has_prepare);
    try std.testing.expect(!Spec.has_process);
    try std.testing.expect(!Spec.has_process_with_parameters);
    try std.testing.expect(!Spec.has_process64);
    try std.testing.expect(!Spec.has_process64_with_parameters);
    try std.testing.expect(!Spec.has_process32_hook);
    try std.testing.expect(!Spec.has_process64_hook);
    try std.testing.expect(!Spec.has_any_process_hook);
    try std.testing.expect(!Spec.has_deinit);
    try std.testing.expect(instance.hasAudioInput());
    try std.testing.expect(instance.hasAudioOutput());
    try std.testing.expect(instance.hasEventInput());
    try std.testing.expect(!instance.hasEventOutput());
    try std.testing.expect(!instance.hasInitHook());
    try std.testing.expect(!instance.hasPrepareHook());
    try std.testing.expect(!instance.hasProcessHook());
    try std.testing.expect(!instance.hasProcessFunctionHook());
    try std.testing.expect(!instance.hasProcessWithParameterViewHook());
    try std.testing.expect(!instance.hasProcessWithParametersHook());
    try std.testing.expect(!instance.hasProcess64Hook());
    try std.testing.expect(!instance.hasProcess64FunctionHook());
    try std.testing.expect(!instance.hasProcess64WithParameterViewHook());
    try std.testing.expect(!instance.hasProcess64WithParametersHook());
    try std.testing.expect(!instance.hasAnyProcessHook());
    try std.testing.expect(!instance.hasDeinitHook());
}

test "plugin instance drives declared lifecycle hooks" {
    const Gain = struct {
        prepared: bool = false,
        prepared_mode: process_api.ProcessMode = .realtime,
        processed: bool = false,
        deinitialized: bool = false,

        pub const name = "Instance Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn init(_: std.mem.Allocator) !@This() {
            return .{};
        }

        pub fn prepare(self: *@This(), config: PrepareConfig) void {
            self.prepared = config.sample_rate == 48_000.0 and config.max_block_size == 64;
            self.prepared_mode = config.process_mode;
        }

        pub fn process(self: *@This(), context: *process_api.ProcessContext(f32)) void {
            self.processed = true;
            for (0..context.outputChannelCount()) |channel| {
                const input = context.inputChannel(channel) orelse continue;
                const output = context.outputChannel(channel) orelse continue;
                for (0..context.frameCount()) |sample| {
                    output[sample] = input[sample] * 0.5;
                }
            }
        }

        pub fn deinit(self: *@This()) void {
            self.deinitialized = true;
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    var context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .inputs = try process_api.AudioInputs(f32).init(&input_channels),
        .outputs = try process_api.AudioOutputs(f32).init(&output_channels),
    };

    try std.testing.expectEqual(@as(f64, 0.5), instance.loadParameterNormalized("gain"));
    try std.testing.expect(instance.hasProcessHook());
    try std.testing.expect(instance.hasProcessFunctionHook());
    try std.testing.expect(!instance.hasProcessWithParameterViewHook());
    try std.testing.expect(!instance.hasProcessWithParametersHook());
    instance.prepare(.{ .sample_rate = 48_000.0, .max_block_size = 64 });
    instance.process(&context);
    instance.deinit();

    try std.testing.expect(instance.plugin.prepared);
    try std.testing.expectEqual(process_api.ProcessMode.realtime, instance.plugin.prepared_mode);
    try std.testing.expect(instance.plugin.processed);
    try std.testing.expect(instance.plugin.deinitialized);
    try std.testing.expectEqual(@as(f32, 0.125), output[0]);
    try std.testing.expectEqual(@as(f32, 0.25), output[1]);
    try std.testing.expectEqual(@as(f64, 0.5), instance.loadParameterNormalized("gain"));
}

test "plugin instance validates prepare configuration" {
    const Gain = struct {
        prepared: bool = false,
        prepared_mode: process_api.ProcessMode = .realtime,

        pub const name = "Prepare Validation Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn prepare(self: *@This(), config: PrepareConfig) void {
            self.prepared = true;
            self.prepared_mode = config.process_mode;
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});

    try std.testing.expectError(error.InvalidSampleRate, (PrepareConfig{ .sample_rate = 0.0, .max_block_size = 64 }).validate());
    try std.testing.expectError(error.InvalidSampleRate, (PrepareConfig{ .sample_rate = std.math.inf(f64), .max_block_size = 64 }).validate());
    try std.testing.expectError(error.InvalidMaxBlockSize, (PrepareConfig{ .sample_rate = 48_000.0, .max_block_size = 0 }).validate());
    try std.testing.expectError(error.InvalidSampleRate, instance.prepareChecked(.{ .sample_rate = std.math.nan(f64), .max_block_size = 64 }));
    try std.testing.expect(!instance.plugin.prepared);

    try instance.prepareChecked(.{ .sample_rate = 48_000.0, .max_block_size = 64, .process_mode = .prefetch });
    try std.testing.expect(instance.plugin.prepared);
    try std.testing.expectEqual(process_api.ProcessMode.prefetch, instance.plugin.prepared_mode);
}

test "plugin instance applies parameter changes to owned values" {
    const Gain = struct {
        pub const name = "Instance Parameters";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.25),
        .{ .id = 99, .sample_offset = 0, .normalized = 1.0 },
    };
    const view = try process_api.ParameterChanges.init(&changes, 1);

    try std.testing.expectEqual(@as(usize, 1), instance.applyParameterChangesChangedCount(view));
    try std.testing.expectEqual(@as(usize, 1), instance.applyParameterChangesCount(view));
    try std.testing.expectEqual(@as(usize, 0), instance.applyParameterChangesChangedCount(view));

    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterView().loadById(99));

    try std.testing.expect(instance.storeParameterNormalized("gain", 0.5));
    instance.applyParameterChanges(view);
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
}

test "plugin instance counts only applied automatable parameter changes" {
    const Gain = struct {
        pub const name = "Instance Parameter Apply Count";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
            bypass: parameters.BoolParam = .{ .id = 1, .name = "Bypass", .can_automate = false },
            meter: parameters.FloatParam = .{ .id = 2, .name = "Meter", .is_read_only = true },
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 1, .sample_offset = 0, .normalized = 1.0 },
        .{ .id = 2, .sample_offset = 0, .normalized = 0.75 },
        .{ .id = 99, .sample_offset = 0, .normalized = 0.5 },
    };
    const view = try process_api.ParameterChanges.init(&changes, 1);

    try std.testing.expectEqual(@as(usize, 1), instance.applyParameterChangesChangedCount(view));
    try std.testing.expectEqual(@as(usize, 1), instance.applyParameterChangesCount(view));
    try std.testing.expectEqual(@as(usize, 0), instance.applyParameterChangesChangedCount(view));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(f64, 0.0), instance.loadParameterNormalized("bypass"));
    try std.testing.expectEqual(@as(f64, 0.0), instance.loadParameterNormalized("meter"));
}

test "plugin instance exposes typed parameter field access" {
    const Mode = enum { clean, boost, mute };
    const Gain = struct {
        pub const name = "Instance Field Parameters";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .short_name = "G", .units = "dB", .min = -12.0, .max = 6.0, .default = 0.0 },
            bypass: parameters.BoolParam = .{ .id = 1, .name = "Bypass", .can_automate = false, .is_read_only = true, .is_bypass = true },
            mode: parameters.EnumParam(Mode) = .{ .id = 2, .name = "Mode", .default = .clean },
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});

    try std.testing.expectEqual(@as(?usize, 0), instance.parameterIndexOfId(0));
    try std.testing.expectEqual(@as(?usize, null), instance.parameterIndexOfId(99));
    try std.testing.expectEqual(@as(?usize, 2), instance.parameterIndexOfName("Mode"));
    try std.testing.expectEqual(@as(?usize, null), instance.parameterIndexOfName("Missing"));
    try std.testing.expectEqual(@as(?u32, null), instance.duplicateParameterId());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateParameterIdIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateParameterName());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateParameterNameIndex());
    try std.testing.expect(!instance.hasDuplicateParameterIds());
    try std.testing.expect(!instance.hasDuplicateParameterNames());
    try std.testing.expectEqual(@as(?anyerror, null), instance.firstParameterDescriptorError());
    try std.testing.expectEqual(@as(?usize, null), instance.firstParameterDescriptorErrorIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), instance.firstParameterDescriptorErrorName());
    try std.testing.expect(instance.hasParameterId(0));
    try std.testing.expect(!instance.hasParameterId(99));
    try std.testing.expect(instance.hasParameterName("Mode"));
    try std.testing.expect(!instance.hasParameterName("Missing"));
    try std.testing.expectEqual(@as(usize, 3), instance.parameterCount());
    try std.testing.expect(!instance.parametersEmpty());
    try std.testing.expect(instance.hasParameters());
    try std.testing.expect(instance.parametersAllDefaults());
    try std.testing.expect(!instance.hasNonDefaultParameters());
    try std.testing.expectEqual(@as(usize, 0), instance.parameterNonDefaultCount());
    try std.testing.expectEqual(@as(?u32, 0), instance.parameterId(0));
    try std.testing.expectEqualStrings("Bypass", instance.parameterName(1).?);
    try std.testing.expectEqualStrings("Mode", instance.parameterNameById(2).?);
    try std.testing.expectEqual(@as(?u32, 2), instance.parameterIdByName("Mode"));
    try std.testing.expectEqualStrings("G", instance.parameterShortName(0).?);
    try std.testing.expectEqualStrings("G", instance.parameterShortNameById(0).?);
    try std.testing.expectEqualStrings("G", instance.parameterShortNameByName("Gain").?);
    try std.testing.expectEqualStrings("dB", instance.parameterUnits(0).?);
    try std.testing.expectEqualStrings("dB", instance.parameterUnitsById(0).?);
    try std.testing.expectEqualStrings("dB", instance.parameterUnitsByName("Gain").?);
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultNormalized(2));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultNormalizedById(2));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultNormalizedByName("Mode"));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultPlain(0));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultPlainById(1));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultPlainByName("Mode"));
    try std.testing.expectEqual(@as(?f64, -12.0), instance.parameterPlainMinimum(0));
    try std.testing.expectEqual(@as(?f64, 6.0), instance.parameterPlainMaximumById(0));
    try std.testing.expectEqual(@as(?f64, -12.0), instance.parameterPlainMinimumByName("Gain"));
    try std.testing.expect(instance.parameterHasPlainRange(0));
    try std.testing.expect(instance.parameterHasPlainRangeById(0));
    try std.testing.expect(instance.parameterHasPlainRangeByName("Gain"));
    try std.testing.expect(!instance.parameterHasPlainRange(1));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsBypass(0));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsBypassById(0));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsBypassByName("Bypass"));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterCanAutomate(0));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterCanAutomateById(1));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterCanAutomateByName("Bypass"));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsReadOnly(1));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsReadOnlyById(0));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsReadOnlyByName("Bypass"));
    try std.testing.expectEqual(@as(?i32, 0), instance.parameterUnitId(0));
    try std.testing.expectEqual(@as(?i32, 0), instance.parameterUnitIdById(0));
    try std.testing.expectEqual(@as(?i32, 0), instance.parameterUnitIdByName("Gain"));
    try std.testing.expectEqual(@as(?i32, 2), instance.parameterStepCount(2));
    try std.testing.expectEqual(@as(?i32, 2), instance.parameterStepCountById(2));
    try std.testing.expectEqual(@as(?i32, 2), instance.parameterStepCountByName("Mode"));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsList(2));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsListById(2));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsListByName("Mode"));
    try std.testing.expectEqual(@as(?usize, 3), instance.parameterOptionCount(2));
    try std.testing.expectEqual(@as(?usize, 3), instance.parameterOptionCountById(2));
    try std.testing.expectEqual(@as(?usize, 3), instance.parameterOptionCountByName("Mode"));
    try std.testing.expectEqualStrings("mute", instance.parameterOptionLabel(2, 2).?);
    try std.testing.expectEqualStrings("boost", instance.parameterOptionLabelById(2, 1).?);
    try std.testing.expectEqualStrings("clean", instance.parameterOptionLabelByName("Mode", 0).?);
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterOptionNormalized(2, 2));
    try std.testing.expectEqual(@as(?f64, 0.5), instance.parameterOptionNormalizedById(2, 1));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterOptionNormalizedByName("Mode", 0));
    try std.testing.expect(instance.parameterHasOptions(2));
    try std.testing.expect(!instance.parameterOptionsEmpty(2));
    try std.testing.expect(instance.parameterHasOptionsById(2));
    try std.testing.expect(!instance.parameterOptionsEmptyById(2));
    try std.testing.expect(instance.parameterHasOptionsByName("Mode"));
    try std.testing.expect(!instance.parameterOptionsEmptyByName("Mode"));
    try std.testing.expect(!instance.parameterHasOptions(0));
    try std.testing.expect(instance.parameterOptionsEmpty(0));
    try std.testing.expectEqual(@as(?u32, null), instance.parameterId(99));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterName(99));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterNameById(99));
    try std.testing.expectEqual(@as(?u32, null), instance.parameterIdByName("Missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterShortNameByName("Missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterUnitsByName("Missing"));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterDefaultNormalizedById(99));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterDefaultNormalizedByName("Missing"));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterDefaultPlainById(99));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterDefaultPlainByName("Missing"));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterPlainMinimumById(99));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterPlainMaximumByName("Missing"));
    try std.testing.expect(!instance.parameterHasPlainRangeById(99));
    try std.testing.expect(!instance.parameterHasPlainRangeByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsBypassById(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsBypassByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterCanAutomateById(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterCanAutomateByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsReadOnlyById(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsReadOnlyByName("Missing"));
    try std.testing.expectEqual(@as(?i32, null), instance.parameterUnitIdByName("Missing"));
    try std.testing.expectEqual(@as(?i32, null), instance.parameterStepCountById(99));
    try std.testing.expectEqual(@as(?i32, null), instance.parameterStepCountByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsListById(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsListByName("Missing"));
    try std.testing.expectEqual(@as(?usize, null), instance.parameterOptionCountById(99));
    try std.testing.expectEqual(@as(?usize, null), instance.parameterOptionCountByName("Missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterOptionLabel(2, 3));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterOptionLabelByName("Missing", 0));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterOptionNormalized(2, 3));
    try std.testing.expect(!instance.parameterHasOptionsById(99));
    try std.testing.expect(instance.parameterOptionsEmptyById(99));
    try std.testing.expect(!instance.parameterHasOptionsByName("Missing"));
    try std.testing.expect(instance.parameterOptionsEmptyByName("Missing"));
    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("mute", try instance.formatParameterPlainIndex(2, 1.0, &buffer));
    try std.testing.expectEqualStrings("mute", try instance.formatParameterPlain(2, 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try instance.parseParameterPlainIndex(2, "mute"));
    try std.testing.expectEqual(@as(f64, 1.0), try instance.parseParameterPlain(2, "mute"));
    try std.testing.expectEqual(@as(?f64, 2.0), instance.parameterPlainFromNormalizedIndex(2, 1.0));
    try std.testing.expectEqual(@as(?f64, 2.0), instance.parameterPlainFromNormalized(2, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterNormalizedFromPlainIndex(2, 2.0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterNormalizedFromPlain(2, 2.0));
    try std.testing.expectEqualStrings("mute", try instance.formatParameterPlainById(2, 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try instance.parseParameterPlainById(2, "mute"));
    try std.testing.expectEqual(@as(?f64, 2.0), instance.parameterPlainFromNormalizedById(2, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterNormalizedFromPlainById(2, 2.0));
    try std.testing.expectEqualStrings("mute", try instance.formatParameterPlainByName("Mode", 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try instance.parseParameterPlainByName("Mode", "mute"));
    try std.testing.expectEqual(@as(?f64, 2.0), instance.parameterPlainFromNormalizedByName("Mode", 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterNormalizedFromPlainByName("Mode", 2.0));
    try std.testing.expectError(error.InvalidParameterIndex, instance.formatParameterPlainIndex(99, 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterIndex, instance.parseParameterPlainIndex(99, "1"));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterPlainFromNormalizedIndex(99, 0.0));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterNormalizedFromPlainIndex(99, 0.0));
    try std.testing.expectError(error.InvalidParameterId, instance.formatParameterPlainById(99, 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterId, instance.parseParameterPlainById(99, "1"));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterPlainFromNormalizedById(99, 0.0));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterNormalizedFromPlainById(99, 0.0));
    try std.testing.expectError(error.InvalidParameterName, instance.formatParameterPlainByName("Missing", 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterName, instance.parseParameterPlainByName("Missing", "1"));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterPlainFromNormalizedByName("Missing", 0.0));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterNormalizedFromPlainByName("Missing", 0.0));
    try std.testing.expectEqual(@as(usize, 0), instance.parameterFieldIndex("gain"));
    try std.testing.expectEqual(@as(u32, 0), instance.parameterFieldDescriptor("gain").id);
    try std.testing.expectEqualStrings("Gain", instance.parameterFieldDescriptor("gain").name);
    try std.testing.expectEqual(@as(u32, 2), instance.parameterFieldId("mode"));
    try std.testing.expectEqualStrings("Gain", instance.parameterFieldName("gain"));
    try std.testing.expectEqualStrings("G", instance.parameterFieldShortName("gain"));
    try std.testing.expectEqualStrings("dB", instance.parameterFieldUnits("gain"));
    try std.testing.expectEqual(@as(f64, 0.0), instance.parameterFieldDefaultNormalized("mode"));
    try std.testing.expectEqual(@as(f64, 0.0), instance.parameterFieldDefaultPlain("gain"));
    try std.testing.expectEqual(Mode.clean, instance.parameterFieldDefaultPlain("mode"));
    try std.testing.expectEqual(@as(?f64, -12.0), instance.parameterFieldPlainMinimum("gain"));
    try std.testing.expectEqual(@as(?f64, 6.0), instance.parameterFieldPlainMaximum("gain"));
    try std.testing.expect(instance.parameterFieldHasPlainRange("gain"));
    try std.testing.expect(!instance.parameterFieldHasPlainRange("mode"));
    try std.testing.expect(instance.parameterFieldIsBypass("bypass"));
    try std.testing.expect(instance.parameterFieldCanAutomate("gain"));
    try std.testing.expect(!instance.parameterFieldCanAutomate("bypass"));
    try std.testing.expect(instance.parameterFieldIsReadOnly("bypass"));
    try std.testing.expectEqual(@as(i32, 0), instance.parameterFieldUnitId("gain"));
    try std.testing.expectEqual(@as(i32, 2), instance.parameterFieldStepCount("mode"));
    try std.testing.expect(instance.parameterFieldIsList("mode"));
    try std.testing.expectEqual(@as(?usize, 3), instance.parameterFieldOptionCount("mode"));
    try std.testing.expectEqualStrings("mute", instance.parameterFieldOptionLabel("mode", 2).?);
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterFieldOptionNormalized("mode", 2));
    try std.testing.expect(instance.parameterFieldHasOptions("mode"));
    try std.testing.expect(!instance.parameterFieldOptionsEmpty("mode"));
    try std.testing.expect(!instance.parameterFieldHasOptions("gain"));
    try std.testing.expect(instance.parameterFieldOptionsEmpty("gain"));
    try std.testing.expectEqualStrings("mute", try instance.formatParameterFieldPlain("mode", 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try instance.parseParameterFieldPlain("mode", "mute"));
    try std.testing.expectEqual(Mode.mute, instance.parameterFieldPlainFromNormalized("mode", 1.0));
    try std.testing.expectEqual(@as(f64, 1.0), instance.parameterFieldNormalizedFromPlain("mode", .mute));
    try std.testing.expectEqual(process_api.ParameterChange{
        .id = 2,
        .sample_offset = 4,
        .normalized = 1.0,
    }, instance.parameterChange("mode", 4, .mute));
    try std.testing.expectEqual(process_api.ParameterChange{
        .id = 0,
        .sample_offset = 5,
        .normalized = 0.25,
    }, instance.parameterChangeNormalized("gain", 5, 0.25));

    try std.testing.expect(instance.storeParameter("gain", 6.0));
    try std.testing.expect(instance.storeParameter("bypass", true));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expect(instance.storeParameterNormalized("gain", 0.5));
    try std.testing.expect(instance.storeParameterIndex(0, 0.75));
    try std.testing.expect(instance.storeParameterPlainIndex(0, 6.0));
    try std.testing.expect(instance.storeParameterById(1, 0.0));
    try std.testing.expect(instance.storeParameterPlainById(0, 6.0));
    try std.testing.expect(instance.storeParameterByName("Mode", 0.5));
    try std.testing.expect(instance.storeParameterPlainByName("Gain", 3.0));
    try std.testing.expect(!instance.storeParameterNormalized("gain", std.math.nan(f64)));
    try std.testing.expect(!instance.storeParameter("gain", std.math.inf(f64)));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterCount("gain", -std.math.inf(f64)));
    try std.testing.expect(!instance.storeParameterIndex(0, std.math.inf(f64)));
    try std.testing.expect(!instance.storeParameterById(0, -std.math.inf(f64)));
    try std.testing.expect(!instance.storeParameterByName("Gain", std.math.nan(f64)));
    try std.testing.expect(!instance.storeParameterPlainIndex(0, std.math.inf(f64)));
    try std.testing.expect(!instance.storeParameterPlainById(0, -std.math.inf(f64)));
    try std.testing.expect(!instance.storeParameterPlainByName("Gain", std.math.nan(f64)));
    try std.testing.expect(!instance.storeParameterIndex(99, 1.0));
    try std.testing.expect(!instance.storeParameterPlainIndex(99, 1.0));
    try std.testing.expect(!instance.storeParameterById(99, 1.0));
    try std.testing.expect(!instance.storeParameterPlainById(99, 1.0));
    try std.testing.expect(!instance.storeParameterByName("Missing", 1.0));
    try std.testing.expect(!instance.storeParameterPlainByName("Missing", 1.0));

    const view = instance.parameterView();
    try std.testing.expectEqual(@as(f64, 3.0), instance.loadParameter("gain"));
    try std.testing.expectEqual(false, instance.loadParameter("bypass"));
    try std.testing.expectEqual(Mode.boost, instance.loadParameter("mode"));
    try std.testing.expectEqual(@as(f64, 0.5), instance.loadParameterNormalized("mode"));
    try std.testing.expectApproxEqAbs(0.8333333333333334, instance.loadParameterIndex(0).?, 0.000001);
    try std.testing.expectEqual(@as(?f64, 3.0), instance.loadParameterPlainIndex(0));
    try std.testing.expectEqual(@as(?f64, null), instance.loadParameterIndex(99));
    try std.testing.expectEqual(@as(?f64, null), instance.loadParameterPlainIndex(99));
    try std.testing.expectApproxEqAbs(0.8333333333333334, instance.loadParameterById(0).?, 0.000001);
    try std.testing.expectEqual(@as(?f64, 3.0), instance.loadParameterPlainById(0));
    try std.testing.expectEqual(@as(?f64, null), instance.loadParameterById(99));
    try std.testing.expectEqual(@as(?f64, null), instance.loadParameterPlainById(99));
    try std.testing.expectEqual(@as(?f64, 0.5), instance.loadParameterByName("Mode"));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.loadParameterPlainByName("Mode"));
    try std.testing.expectEqual(@as(?f64, null), instance.loadParameterByName("Missing"));
    try std.testing.expectEqual(@as(?f64, null), instance.loadParameterPlainByName("Missing"));
    try std.testing.expectEqual(@as(f64, 3.0), view.load("gain"));
    try std.testing.expectEqual(false, view.load("bypass"));
    try std.testing.expectEqual(Mode.boost, view.load("mode"));
    try std.testing.expectEqual(@as(f64, 0.5), view.loadNormalized("mode"));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsDefaultIndex(0));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsDefaultById(2));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsDefaultByName("Mode"));
    try std.testing.expect(!instance.parameterIsDefault("mode"));
    try std.testing.expect(!instance.parametersAllDefaults());
    try std.testing.expect(instance.hasNonDefaultParameters());
    try std.testing.expectEqual(@as(usize, 2), instance.parameterNonDefaultCount());
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsDefaultIndex(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsDefaultById(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsDefaultByName("Missing"));

    try std.testing.expectEqual(@as(usize, 2), instance.resetParametersToDefaultsCount());
    try std.testing.expectEqual(@as(usize, 0), instance.resetParametersToDefaultsCount());
    try std.testing.expect(instance.storeParameter("gain", 3.0));
    instance.resetParametersToDefaults();
    try std.testing.expectEqual(@as(f64, 0.0), instance.loadParameter("gain"));
    try std.testing.expectEqual(false, instance.loadParameter("bypass"));
    try std.testing.expectEqual(Mode.clean, instance.loadParameter("mode"));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsDefaultIndex(0));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsDefaultById(2));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsDefaultByName("Mode"));
    try std.testing.expect(instance.parameterIsDefault("mode"));
    try std.testing.expect(instance.parametersAllDefaults());
    try std.testing.expect(!instance.hasNonDefaultParameters());
    try std.testing.expectEqual(@as(usize, 0), instance.parameterNonDefaultCount());

    try std.testing.expect(instance.storeParameter("gain", 6.0));
    try std.testing.expect(instance.storeParameter("bypass", true));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expectEqual(@as(?usize, 0), instance.storeParameterCount("gain", 6.0));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterCount("gain", 3.0));
    try std.testing.expectEqual(@as(?usize, 0), instance.storeParameterNormalizedCount("gain", 0.8333333333333334));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterNormalizedCount("gain", 0.5));
    try std.testing.expectEqual(@as(?usize, 0), instance.storeParameterIndexCount(0, 0.5));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterPlainIndexCount(0, 3.0));
    try std.testing.expectEqual(@as(?usize, 0), instance.storeParameterByIdCount(0, 0.8333333333333334));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterPlainByIdCount(0, 6.0));
    try std.testing.expectEqual(@as(?usize, 0), instance.storeParameterByNameCount("Gain", 1.0));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterPlainByNameCount("Gain", 3.0));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterIndexCount(99, 1.0));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterPlainIndexCount(99, 1.0));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterByIdCount(99, 1.0));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterPlainByIdCount(99, 1.0));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterByNameCount("Missing", 1.0));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterPlainByNameCount("Missing", 1.0));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterPlainIndexCount(0, std.math.inf(f64)));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterPlainByIdCount(0, -std.math.inf(f64)));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterPlainByNameCount("Gain", std.math.nan(f64)));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterToDefaultCount("gain"));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterToDefaultCount("gain"));
    try std.testing.expect(instance.storeParameter("gain", 6.0));
    try std.testing.expect(instance.resetParameterToDefault("gain"));
    try std.testing.expectEqual(@as(f64, 0.0), instance.loadParameter("gain"));
    try std.testing.expectEqual(true, instance.loadParameter("bypass"));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterIndexToDefaultCount(1));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterIndexToDefaultCount(1));
    try std.testing.expect(instance.storeParameter("bypass", true));
    try std.testing.expect(instance.resetParameterIndexToDefault(1));
    try std.testing.expectEqual(false, instance.loadParameter("bypass"));
    try std.testing.expect(instance.storeParameter("bypass", true));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterToDefaultIndexCount(1));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterToDefaultIndexCount(1));
    try std.testing.expect(instance.storeParameter("bypass", true));
    try std.testing.expect(instance.resetParameterToDefaultIndex(1));
    try std.testing.expectEqual(false, instance.loadParameter("bypass"));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterByIdToDefaultCount(2));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterByIdToDefaultCount(2));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expect(instance.resetParameterByIdToDefault(2));
    try std.testing.expectEqual(Mode.clean, instance.loadParameter("mode"));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterToDefaultByIdCount(2));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterToDefaultByIdCount(2));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expect(instance.resetParameterToDefaultById(2));
    try std.testing.expectEqual(Mode.clean, instance.loadParameter("mode"));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterByNameToDefaultCount("Mode"));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterByNameToDefaultCount("Mode"));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expect(instance.resetParameterByNameToDefault("Mode"));
    try std.testing.expectEqual(Mode.clean, instance.loadParameter("mode"));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterToDefaultByNameCount("Mode"));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterToDefaultByNameCount("Mode"));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expect(instance.resetParameterToDefaultByName("Mode"));
    try std.testing.expectEqual(Mode.clean, instance.loadParameter("mode"));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterIndexToDefaultCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterToDefaultIndexCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterByIdToDefaultCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterToDefaultByIdCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterByNameToDefaultCount("Missing"));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterToDefaultByNameCount("Missing"));
    try std.testing.expect(!instance.resetParameterIndexToDefault(99));
    try std.testing.expect(!instance.resetParameterToDefaultIndex(99));
    try std.testing.expect(!instance.resetParameterByIdToDefault(99));
    try std.testing.expect(!instance.resetParameterToDefaultById(99));
    try std.testing.expect(!instance.resetParameterByNameToDefault("Missing"));
    try std.testing.expect(!instance.resetParameterToDefaultByName("Missing"));
}

test "plugin instance copies parameter values from another instance" {
    const Mode = enum { clean, boost, mute };
    const Gain = struct {
        pub const name = "Instance Parameter Copy";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .min = -12.0, .max = 6.0, .default = 0.0 },
            bypass: parameters.BoolParam = .{ .id = 1, .name = "Bypass", .default = false },
            mode: parameters.EnumParam(Mode) = .{ .id = 2, .name = "Mode", .default = .clean },
        };
    };
    const Instance = PluginInstance(Gain);
    var source = try Instance.init(std.testing.allocator, .{});
    var target = try Instance.init(std.testing.allocator, .{});

    try std.testing.expect(source.storeParameter("gain", 6.0));
    try std.testing.expect(source.storeParameter("bypass", true));
    try std.testing.expect(source.storeParameter("mode", .mute));

    try std.testing.expectEqual(@as(usize, 3), target.copyParameterValuesFromCount(&source));
    try std.testing.expectEqual(@as(usize, 0), target.copyParameterValuesFromCount(&source));
    target.resetParametersToDefaults();
    target.copyParameterValuesFrom(&source);
    try std.testing.expectEqual(@as(f64, 6.0), target.loadParameter("gain"));
    try std.testing.expectEqual(true, target.loadParameter("bypass"));
    try std.testing.expectEqual(Mode.mute, target.loadParameter("mode"));
    try std.testing.expectEqual(@as(usize, 3), target.parameterNonDefaultCount());

    try std.testing.expect(target.storeParameter("gain", 0.0));
    try std.testing.expectEqual(@as(f64, 6.0), source.loadParameter("gain"));
}

test "plugin instance exposes parameter editor" {
    const Mode = enum { clean, boost, mute };
    const Gain = struct {
        pub const name = "Instance Parameter Editor";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .short_name = "G", .units = "dB", .min = -12.0, .max = 6.0, .default = 0.0 },
            bypass: parameters.BoolParam = .{ .id = 1, .name = "Bypass", .default = false, .is_bypass = true },
            mode: parameters.EnumParam(Mode) = .{ .id = 2, .name = "Mode", .default = .clean },
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});

    const editor = instance.parameterEditor();
    try std.testing.expectEqual(@as(usize, 3), editor.parameterCount());
    try std.testing.expect(!editor.parametersEmpty());
    try std.testing.expect(editor.hasParameters());
    try std.testing.expectEqual(@as(?u32, 0), editor.id(0));
    try std.testing.expectEqualStrings("Gain", editor.name(0).?);
    try std.testing.expectEqualStrings("G", editor.shortNameById(0).?);
    try std.testing.expectEqualStrings("dB", editor.unitsByName("Gain").?);
    try std.testing.expectEqual(@as(?f64, 0.0), editor.defaultNormalizedByName("Mode"));
    try std.testing.expectEqual(@as(?bool, true), editor.isBypassByName("Bypass"));
    try std.testing.expectEqual(@as(?i32, 2), editor.stepCountByName("Mode"));
    try std.testing.expectEqual(@as(?bool, true), editor.isListById(2));
    try std.testing.expectEqual(@as(?usize, 2), editor.indexOfName("Mode"));
    try std.testing.expect(editor.hasId(1));
    try std.testing.expect(!editor.hasName("Missing"));

    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("mute", try editor.formatPlainByName("Mode", 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try editor.parsePlainByName("Mode", "mute"));
    try std.testing.expectEqual(@as(?f64, 2.0), editor.plainFromNormalizedByName("Mode", 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.normalizedFromPlainByName("Mode", 2.0));

    try std.testing.expect(editor.store("gain", 6.0));
    try std.testing.expect(editor.storePlainById(1, 1.0));
    try std.testing.expect(editor.storeByName("Mode", 1.0));
    try std.testing.expectEqual(@as(f64, 6.0), editor.load("gain"));
    try std.testing.expectEqual(true, editor.load("bypass"));
    try std.testing.expectEqual(Mode.mute, editor.load("mode"));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.loadById(2));
    try std.testing.expectEqual(@as(?f64, 2.0), editor.loadPlainByName("Mode"));

    try std.testing.expect(!editor.storeIndex(99, 1.0));
    try std.testing.expect(!editor.storePlainByName("Missing", 1.0));
    try std.testing.expectEqual(@as(?f64, null), editor.loadIndex(99));
    try std.testing.expectEqual(@as(?f64, null), editor.loadPlainByName("Missing"));

    try std.testing.expect(editor.resetToDefaultById(1));
    try std.testing.expectEqual(false, editor.load("bypass"));
    editor.resetToDefaults();
    try std.testing.expectEqual(@as(f64, 0.0), editor.load("gain"));
    try std.testing.expectEqual(Mode.clean, editor.load("mode"));

    const view = instance.parameterView();
    try std.testing.expectEqual(@as(f64, 0.0), view.load("gain"));
    try std.testing.expectEqual(false, view.load("bypass"));
    try std.testing.expectEqual(Mode.clean, view.load("mode"));
}

test "plugin instance applies process parameter changes before dispatch" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance Process Parameters";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process(self: *@This(), context: *process_api.ProcessContext(f32)) void {
            self.observed = context.latestParameterNormalized(0);
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.25),
    };
    var context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process(&context);

    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?f64, 0.25), instance.plugin.observed);
}

test "plugin instance applies process parameter changes without process hooks" {
    const Gain = struct {
        pub const name = "Instance Process Parameters Without Hooks";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.25),
    };
    var context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    try std.testing.expect(!instance.hasAnyProcessHook());
    instance.process(&context);

    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
}

test "plugin instance passes input events to process hooks" {
    const Monitor = struct {
        event_count: usize = 0,
        note_offset: ?usize = null,
        note_pitch: i16 = -1,

        pub const name = "Instance Process Events";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};

        pub fn process(self: *@This(), context: *process_api.ProcessContext(f32)) void {
            self.event_count = context.inputEventCount();
            if (context.firstEvent(.note_on)) |event| {
                self.note_offset = event.sample_offset;
                self.note_pitch = event.pitch;
            }
        }
    };
    const Instance = PluginInstance(Monitor);
    var instance = try Instance.init(std.testing.allocator, .{});
    const events = [_]process_api.Event{
        process_api.Event.noteOn(2, 0, 64, 0.5),
    };
    var context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .events = try process_api.Events.init(&events, 4),
    };

    instance.process(&context);

    try std.testing.expectEqual(@as(usize, 1), instance.plugin.event_count);
    try std.testing.expectEqual(@as(?usize, 2), instance.plugin.note_offset);
    try std.testing.expectEqual(@as(i16, 64), instance.plugin.note_pitch);
}

test "plugin instance passes output event writers to process hooks" {
    const Emitter = struct {
        pub const name = "Instance Process Output Events";
        pub const vendor = "zig-vst3";
        pub const event_output = true;
        pub const Params = struct {};

        pub fn process(_: *@This(), context: *process_api.ProcessContext(f32)) void {
            _ = context.appendOutputEventIfPossible(process_api.Event.noteOff(1, 0, 64, 0.0));
        }
    };
    const Instance = PluginInstance(Emitter);
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.0, 0.0 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    var output_event_storage: [1]process_api.Event = undefined;
    var output_events = process_api.EventWriter.init(&output_event_storage, input.len);
    var context = try process_api.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .output_events = &output_events,
    });

    instance.process(&context);

    try std.testing.expect(instance.hasEventOutput());
    try std.testing.expectEqual(@as(usize, 1), context.outputEventCount());
    try std.testing.expectEqual(process_api.EventKind.note_off, context.firstOutputEvent(.note_off).?.kind);
    try std.testing.expectEqual(@as(usize, 1), context.firstOutputEvent(.note_off).?.sample_offset);
    try std.testing.expectEqual(@as(i16, 64), context.firstOutputEvent(.note_off).?.pitch);
}

test "plugin instance passes reflected parameters to state-aware process hooks" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance State Aware Process";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn processWithParameters(
            self: *@This(),
            _: *process_api.ProcessContext(f32),
            set: *const parameters.ParameterSet(Params),
            values: *const parameters.ParameterValues(Params),
        ) void {
            self.observed = values.view(set).loadNormalized("gain");
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.25),
    };
    var context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process(&context);

    try std.testing.expectEqual(@as(?f64, 0.25), instance.plugin.observed);
}

test "plugin instance passes parameter view to state-aware process hooks" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance View Aware Process";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn processWithParameterView(
            self: *@This(),
            _: *process_api.ProcessContext(f32),
            view: parameters.ParameterView(Params),
        ) void {
            self.observed = view.loadNormalized("gain");
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.25),
    };
    var context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process(&context);

    try std.testing.expectEqual(@as(?f64, 0.25), instance.plugin.observed);
}

test "plugin instance parameter view does not anticipate later block changes" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance Block Parameter View";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn processWithParameterView(
            self: *@This(),
            _: *process_api.ProcessContext(f32),
            view: parameters.ParameterView(Params),
        ) void {
            self.observed = view.loadNormalized("gain");
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const later_changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 1, 0.25),
    };
    var later_context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&later_changes, 2),
    };

    instance.process(&later_context);
    try std.testing.expectEqual(@as(?f64, 0.5), instance.plugin.observed);
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));

    var quiet_context = process_api.ProcessContext(f32){ .sample_rate = 48_000.0 };
    instance.process(&quiet_context);
    try std.testing.expectEqual(@as(?f64, 0.25), instance.plugin.observed);
}

test "plugin instance prefers parameter-view process hook over other process hooks" {
    const Gain = struct {
        called: enum { none, raw, parameters, view } = .none,

        pub const name = "Instance Process Hook Priority";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process(self: *@This(), _: *process_api.ProcessContext(f32)) void {
            self.called = .raw;
        }

        pub fn processWithParameters(
            self: *@This(),
            _: *process_api.ProcessContext(f32),
            _: *const parameters.ParameterSet(Params),
            _: *const parameters.ParameterValues(Params),
        ) void {
            self.called = .parameters;
        }

        pub fn processWithParameterView(
            self: *@This(),
            _: *process_api.ProcessContext(f32),
            _: parameters.ParameterView(Params),
        ) void {
            self.called = .view;
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    var context = process_api.ProcessContext(f32){ .sample_rate = 48_000.0 };

    instance.process(&context);

    try std.testing.expectEqual(.view, instance.plugin.called);
}

test "plugin instance applies process64 parameter changes before dispatch" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance Process64 Parameters";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process64(self: *@This(), context: *process_api.ProcessContext(f64)) void {
            self.observed = context.latestParameterNormalized(0);
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.75),
    };
    var context = process_api.ProcessContext(f64){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process64(&context);

    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?f64, 0.75), instance.plugin.observed);
}

test "plugin instance applies process64 parameter changes without process64 hooks" {
    const Gain = struct {
        pub const name = "Instance Process64 Parameters Without Hooks";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.75),
    };
    var context = process_api.ProcessContext(f64){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    try std.testing.expect(!instance.hasAnyProcessHook());
    instance.process64(&context);

    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
}

test "plugin instance passes events to process64 hooks" {
    const Echo = struct {
        event_count: usize = 0,
        note_pitch: i16 = -1,

        pub const name = "Instance Process64 Events";
        pub const vendor = "zig-vst3";
        pub const event_output = true;
        pub const Params = struct {};

        pub fn process64(self: *@This(), context: *process_api.ProcessContext(f64)) void {
            self.event_count = context.inputEventCount();
            if (context.firstEvent(.note_on)) |event| {
                self.note_pitch = event.pitch;
                _ = context.appendOutputEventIfPossible(process_api.Event.noteOff(event.sample_offset + 1, event.channel, event.pitch, 0.0));
            }
        }
    };
    const Instance = PluginInstance(Echo);
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f64{ 0.0, 0.0, 0.0 };
    var output = [_]f64{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f64{&input};
    const output_channels = [_][]f64{&output};
    const events = [_]process_api.Event{
        process_api.Event.noteOn(1, 0, 67, 0.5),
    };
    var output_event_storage: [1]process_api.Event = undefined;
    var output_events = process_api.EventWriter.init(&output_event_storage, input.len);
    var context = try process_api.ProcessContext(f64).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
        .output_events = &output_events,
    });

    instance.process64(&context);

    try std.testing.expect(instance.hasEventOutput());
    try std.testing.expectEqual(@as(usize, 1), instance.plugin.event_count);
    try std.testing.expectEqual(@as(i16, 67), instance.plugin.note_pitch);
    try std.testing.expectEqual(@as(usize, 1), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 2), context.firstOutputEvent(.note_off).?.sample_offset);
    try std.testing.expectEqual(@as(i16, 67), context.firstOutputEvent(.note_off).?.pitch);
}

test "plugin instance passes reflected parameters to state-aware process64 hooks" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance State Aware Process64";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process64WithParameters(
            self: *@This(),
            _: *process_api.ProcessContext(f64),
            set: *const parameters.ParameterSet(Params),
            values: *const parameters.ParameterValues(Params),
        ) void {
            self.observed = values.view(set).loadNormalized("gain");
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.75),
    };
    var context = process_api.ProcessContext(f64){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process64(&context);

    try std.testing.expectEqual(@as(?f64, 0.75), instance.plugin.observed);
}

test "plugin instance parameter values apply only offset zero changes to the current block" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance Block Parameter Values64";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process64WithParameters(
            self: *@This(),
            _: *process_api.ProcessContext(f64),
            set: *const parameters.ParameterSet(Params),
            values: *const parameters.ParameterValues(Params),
        ) void {
            self.observed = values.view(set).loadNormalized("gain");
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.75),
        instance.parameterChange("gain", 1, 0.25),
    };
    var context = process_api.ProcessContext(f64){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 2),
    };

    instance.process64(&context);

    try std.testing.expectEqual(@as(?f64, 0.75), instance.plugin.observed);
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
}

test "plugin instance passes parameter view to state-aware process64 hooks" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance View Aware Process64";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process64WithParameterView(
            self: *@This(),
            _: *process_api.ProcessContext(f64),
            view: parameters.ParameterView(Params),
        ) void {
            self.observed = view.loadNormalized("gain");
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.75),
    };
    var context = process_api.ProcessContext(f64){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process64(&context);

    try std.testing.expectEqual(@as(?f64, 0.75), instance.plugin.observed);
}

test "plugin instance prefers parameter-view process64 hook over other process64 hooks" {
    const Gain = struct {
        called: enum { none, raw, parameters, view } = .none,

        pub const name = "Instance Process64 Hook Priority";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process64(self: *@This(), _: *process_api.ProcessContext(f64)) void {
            self.called = .raw;
        }

        pub fn process64WithParameters(
            self: *@This(),
            _: *process_api.ProcessContext(f64),
            _: *const parameters.ParameterSet(Params),
            _: *const parameters.ParameterValues(Params),
        ) void {
            self.called = .parameters;
        }

        pub fn process64WithParameterView(
            self: *@This(),
            _: *process_api.ProcessContext(f64),
            _: parameters.ParameterView(Params),
        ) void {
            self.called = .view;
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    var context = process_api.ProcessContext(f64){ .sample_rate = 48_000.0 };

    instance.process64(&context);

    try std.testing.expectEqual(.view, instance.plugin.called);
}

test "plugin instance round-trips owned parameter state" {
    const Gain = struct {
        pub const name = "Instance State";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
            mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 1.0),
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    var restored = try Instance.init(std.testing.allocator, .{});
    var bytes: [state.encodedSize(Gain.Params)]u8 = undefined;
    var header_bytes: [state.encoded_header_size]u8 = undefined;

    try std.testing.expectEqual(@as(usize, state.encodedSize(Gain.Params)), Instance.Spec.encoded_parameter_state_size);
    try std.testing.expectEqual(@as(usize, state.encodedSize(Gain.Params)), instance.encodedParameterStateSize());
    try std.testing.expectEqual(@as(usize, state.encodedSize(Gain.Params)), instance.parameterStateEncodedSize());
    try std.testing.expectEqual(@as(usize, state.encodedSize(Gain.Params)), instance.encodedParameterStateSizeForCount(2));
    try std.testing.expectEqual(@as(usize, state.encodedSize(Gain.Params)), instance.parameterStateEncodedSizeForCount(2));
    try std.testing.expectEqual(@as(usize, state.encodedSize(Gain.Params)), try instance.encodedParameterStateSizeForCountChecked(2));
    try std.testing.expectEqual(@as(usize, state.encodedSize(Gain.Params)), try instance.parameterStateEncodedSizeForCountChecked(2));
    try std.testing.expectEqual(std.math.maxInt(usize), instance.parameterStateEncodedSizeForCount(std.math.maxInt(usize)));
    try std.testing.expectError(error.Overflow, instance.parameterStateEncodedSizeForCountChecked(std.math.maxInt(usize)));
    try std.testing.expectEqual(@as(usize, 2), instance.parameterStateEntryCount());
    try std.testing.expect(instance.storeParameterNormalized("gain", 0.25));
    try std.testing.expect(instance.storeParameterNormalized("mix", 0.75));

    var header_out_stream = FixedBufferStream.init(&header_bytes);
    try instance.writeParameterStateHeader(header_out_stream.writer());
    var header_in_stream = FixedBufferStream.init(&header_bytes);
    try std.testing.expectEqual(
        state.ParameterStateHeader{ .version = state.format_version, .entry_count = 2 },
        try instance.readParameterStateHeader(header_in_stream.reader()),
    );

    var counted_header_out_stream = FixedBufferStream.init(&header_bytes);
    try instance.writeParameterStateHeaderForCount(1, counted_header_out_stream.writer());
    var counted_header_in_stream = FixedBufferStream.init(&header_bytes);
    try std.testing.expectEqual(
        state.ParameterStateHeader{ .version = state.format_version, .entry_count = 1 },
        try instance.readParameterStateHeader(counted_header_in_stream.reader()),
    );
    try std.testing.expectError(
        error.ParameterStateTooLarge,
        instance.writeParameterStateHeaderForCount(@as(usize, std.math.maxInt(u16)) + 1, counted_header_out_stream.writer()),
    );

    var out_stream = FixedBufferStream.init(&bytes);
    try instance.writeParameterState(out_stream.writer());

    var header_stream = FixedBufferStream.init(&bytes);
    const header = try instance.readParameterStateHeader(header_stream.reader());
    const older_header = state.ParameterStateHeader{ .version = state.format_version, .entry_count = 1 };
    const newer_header = state.ParameterStateHeader{ .version = state.format_version, .entry_count = 3 };
    try std.testing.expect(header.isCurrentVersion());
    try std.testing.expect(header.matchesEntryCount(instance.parameterStateEntryCount()));
    try std.testing.expect(!header.hasFewerEntriesThan(instance.parameterStateEntryCount()));
    try std.testing.expect(!header.hasMoreEntriesThan(instance.parameterStateEntryCount()));
    try std.testing.expect(instance.parameterStateHeaderMatchesEntryCount(header));
    try std.testing.expect(!instance.parameterStateHeaderHasFewerEntries(header));
    try std.testing.expect(!instance.parameterStateHeaderHasMoreEntries(header));
    try std.testing.expectEqual(@as(usize, 0), instance.parameterStateHeaderMissingEntryCount(header));
    try std.testing.expectEqual(@as(usize, 0), instance.parameterStateHeaderExtraEntryCount(header));
    try std.testing.expect(!instance.parameterStateHeaderMatchesEntryCount(older_header));
    try std.testing.expect(instance.parameterStateHeaderHasFewerEntries(older_header));
    try std.testing.expect(!instance.parameterStateHeaderHasMoreEntries(older_header));
    try std.testing.expectEqual(@as(usize, 1), instance.parameterStateHeaderMissingEntryCount(older_header));
    try std.testing.expectEqual(@as(usize, 0), instance.parameterStateHeaderExtraEntryCount(older_header));
    try std.testing.expect(!instance.parameterStateHeaderMatchesEntryCount(newer_header));
    try std.testing.expect(!instance.parameterStateHeaderHasFewerEntries(newer_header));
    try std.testing.expect(instance.parameterStateHeaderHasMoreEntries(newer_header));
    try std.testing.expectEqual(@as(usize, 0), instance.parameterStateHeaderMissingEntryCount(newer_header));
    try std.testing.expectEqual(@as(usize, 1), instance.parameterStateHeaderExtraEntryCount(newer_header));

    var in_stream = FixedBufferStream.init(&bytes);
    const report = try restored.readParameterStateReport(in_stream.reader());
    const partial_report = state.ReadParameterStateReport{ .entry_count = 1, .restored_count = 1, .ignored_count = 0 };
    const newer_report = state.ReadParameterStateReport{ .entry_count = 3, .restored_count = 2, .ignored_count = 1 };
    const over_restored_report = state.ReadParameterStateReport{ .entry_count = 3, .restored_count = 3, .ignored_count = 0 };

    try std.testing.expectEqual(state.ReadParameterStateReport{ .entry_count = 2, .restored_count = 2, .ignored_count = 0 }, report);
    try std.testing.expectEqual(@as(usize, 2), report.decodedCount());
    try std.testing.expectEqual(@as(usize, 2), report.restoredCount());
    try std.testing.expectEqual(@as(usize, 0), report.ignoredCount());
    try std.testing.expect(report.hasDecodedEntries());
    try std.testing.expect(report.hasRestoredEntries());
    try std.testing.expect(!report.hasNoRestoredEntries());
    try std.testing.expect(!report.hasIgnoredEntries());
    try std.testing.expect(report.hasNoIgnoredEntries());
    try std.testing.expect(report.hasAccountedEntries());
    try std.testing.expect(!report.hasNoAccountedEntries());
    try std.testing.expect(!report.accountedEntriesEmpty());
    try std.testing.expect(report.restoredAllEntries());
    try std.testing.expect(!report.restoredPartialEntries());
    try std.testing.expect(!report.ignoredAllEntries());
    try std.testing.expect(restored.parameterStateReportMatchesDecodedCount(report));
    try std.testing.expect(!restored.parameterStateReportHasFewerDecodedEntries(report));
    try std.testing.expect(!restored.parameterStateReportHasMoreDecodedEntries(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportMissingDecodedEntryCount(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraDecodedEntryCount(report));
    try std.testing.expect(restored.parameterStateReportMatchesRestoredCount(report));
    try std.testing.expect(!restored.parameterStateReportHasFewerRestoredEntries(report));
    try std.testing.expect(!restored.parameterStateReportHasMoreRestoredEntries(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportMissingRestoredEntryCount(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraRestoredEntryCount(report));
    try std.testing.expect(restored.parameterStateReportHasAccountedEntries(report));
    try std.testing.expect(!restored.parameterStateReportHasNoAccountedEntries(report));
    try std.testing.expect(!restored.parameterStateReportAccountedEntriesEmpty(report));
    try std.testing.expect(!restored.parameterStateReportMatchesDecodedCount(partial_report));
    try std.testing.expect(restored.parameterStateReportHasFewerDecodedEntries(partial_report));
    try std.testing.expect(!restored.parameterStateReportHasMoreDecodedEntries(partial_report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportMissingDecodedEntryCount(partial_report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraDecodedEntryCount(partial_report));
    try std.testing.expect(!restored.parameterStateReportMatchesRestoredCount(partial_report));
    try std.testing.expect(restored.parameterStateReportHasFewerRestoredEntries(partial_report));
    try std.testing.expect(!restored.parameterStateReportHasMoreRestoredEntries(partial_report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportMissingRestoredEntryCount(partial_report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraRestoredEntryCount(partial_report));
    try std.testing.expect(!restored.parameterStateReportMatchesDecodedCount(newer_report));
    try std.testing.expect(!restored.parameterStateReportHasFewerDecodedEntries(newer_report));
    try std.testing.expect(restored.parameterStateReportHasMoreDecodedEntries(newer_report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportMissingDecodedEntryCount(newer_report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportExtraDecodedEntryCount(newer_report));
    try std.testing.expect(restored.parameterStateReportMatchesRestoredCount(newer_report));
    try std.testing.expect(!restored.parameterStateReportHasFewerRestoredEntries(newer_report));
    try std.testing.expect(!restored.parameterStateReportHasMoreRestoredEntries(newer_report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportMissingRestoredEntryCount(newer_report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraRestoredEntryCount(newer_report));
    try std.testing.expect(!restored.parameterStateReportMatchesRestoredCount(over_restored_report));
    try std.testing.expect(!restored.parameterStateReportHasFewerRestoredEntries(over_restored_report));
    try std.testing.expect(restored.parameterStateReportHasMoreRestoredEntries(over_restored_report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportMissingRestoredEntryCount(over_restored_report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportExtraRestoredEntryCount(over_restored_report));
    try std.testing.expectEqual(@as(f64, 0.25), restored.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(f64, 0.75), restored.loadParameterNormalized("mix"));
}

test "plugin instance writes parameter state debug json" {
    const Gain = struct {
        pub const name = "Instance State JSON";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
            mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 1.0),
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    var bytes: [160]u8 = undefined;

    try std.testing.expect(instance.storeParameterNormalized("gain", 0.25));
    try std.testing.expect(instance.storeParameterNormalized("mix", 0.75));

    var out_stream = FixedBufferStream.init(&bytes);
    try instance.writeParameterStateJson(out_stream.writer());

    try std.testing.expectEqualStrings(
        "{\"version\":1,\"parameters\":[{\"id\":0,\"name\":\"Gain\",\"normalized\":0.25},{\"id\":1,\"name\":\"Mix\",\"normalized\":0.75}]}",
        out_stream.getWritten(),
    );
}

test "plugin instance reads parameter state with migrations" {
    const OldGain = struct {
        pub const name = "Old Instance State";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(7, "Gain", 0.0, 1.0, 0.5),
        };
    };
    const NewGain = struct {
        pub const name = "New Instance State";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            output: parameters.FloatParam = parameters.FloatParam.init(11, "Output", 0.0, 1.0, 0.5),
        };
    };
    const OldInstance = PluginInstance(OldGain);
    const NewInstance = PluginInstance(NewGain);
    var old_instance = try OldInstance.init(std.testing.allocator, .{});
    var new_instance = try NewInstance.init(std.testing.allocator, .{});
    var bytes: [state.encodedSize(OldGain.Params)]u8 = undefined;

    try std.testing.expect(old_instance.storeParameterNormalized("gain", 0.25));
    var out_stream = FixedBufferStream.init(&bytes);
    try old_instance.writeParameterState(out_stream.writer());

    var in_stream = FixedBufferStream.init(&bytes);
    const report = try new_instance.readParameterStateWithMigrationsReport(in_stream.reader(), &.{
        .{ .old_id = 7, .new_id = 9 },
        .{ .old_id = 9, .new_id = 11 },
    });

    try std.testing.expectEqual(state.ReadParameterStateReport{ .entry_count = 1, .restored_count = 1, .ignored_count = 0 }, report);
    try std.testing.expect(report.isRestoredAllClassification());
    try std.testing.expectEqual(@as(f64, 0.25), new_instance.loadParameterNormalized("output"));
}

test "plugin instance rejects invalid parameter state migrations before changing values" {
    const OldGain = struct {
        pub const name = "Old Instance State Invalid Migration";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(7, "Gain", 0.0, 1.0, 0.5),
        };
    };
    const NewGain = struct {
        pub const name = "New Instance State Invalid Migration";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            output: parameters.FloatParam = parameters.FloatParam.init(11, "Output", 0.0, 1.0, 0.5),
        };
    };
    const OldInstance = PluginInstance(OldGain);
    const NewInstance = PluginInstance(NewGain);
    var old_instance = try OldInstance.init(std.testing.allocator, .{});
    var new_instance = try NewInstance.init(std.testing.allocator, .{});
    var bytes: [state.encodedSize(OldGain.Params)]u8 = undefined;

    try std.testing.expect(old_instance.storeParameterNormalized("gain", 0.25));
    try std.testing.expect(new_instance.storeParameterNormalized("output", 0.8));
    var out_stream = FixedBufferStream.init(&bytes);
    try old_instance.writeParameterState(out_stream.writer());

    try expectMigrationErrorPreservesParameter(&new_instance, &bytes, "output", 0.8, error.DuplicateParameterMigration, &.{
        .{ .old_id = 7, .new_id = 9 },
        .{ .old_id = 7, .new_id = 11 },
    });

    try expectMigrationErrorPreservesParameter(&new_instance, &bytes, "output", 0.8, error.AmbiguousParameterMigration, &.{
        .{ .old_id = 7, .new_id = 11 },
        .{ .old_id = 9, .new_id = 11 },
    });

    try expectMigrationErrorPreservesParameter(&new_instance, &bytes, "output", 0.8, error.IdentityParameterMigration, &.{
        .{ .old_id = 7, .new_id = 7 },
    });

    try expectMigrationErrorPreservesParameter(&new_instance, &bytes, "output", 0.8, error.CyclicParameterMigration, &.{
        .{ .old_id = 7, .new_id = 9 },
        .{ .old_id = 9, .new_id = 7 },
    });
}

test "plugin instance exposes parameter migration diagnostics" {
    const Gain = struct {
        pub const name = "Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 0.5),
        };
    };

    var instance = try PluginInstance(Gain).init(std.testing.allocator, .{});
    defer instance.deinit();

    const valid = [_]state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 9 },
        .{ .old_id = 9, .new_id = 1 },
    };
    const identity = [_]state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 7 },
    };
    const duplicate = [_]state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 9 },
        .{ .old_id = 7, .new_id = 1 },
    };
    const ambiguous = [_]state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 1 },
        .{ .old_id = 9, .new_id = 1 },
    };
    const cycle = [_]state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 9 },
        .{ .old_id = 9, .new_id = 7 },
    };

    try instance.validateParameterIdMigrations(&valid);
    try std.testing.expectEqual(@as(?usize, null), instance.identityParameterMigrationIndex(&valid));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateParameterMigrationIndex(&valid));
    try std.testing.expectEqual(@as(?usize, null), instance.cyclicParameterMigrationIndex(&valid));
    try std.testing.expectEqual(@as(?usize, null), instance.ambiguousParameterMigrationIndex(&valid));
    try std.testing.expectEqual(@as(u32, 1), instance.migratedParameterId(7, &valid));
    try std.testing.expectEqual(@as(u32, 1), instance.migratedParameterId(9, &valid));
    try std.testing.expectEqual(@as(u32, 12), instance.migratedParameterId(12, &valid));
    try std.testing.expectEqual(@as(?usize, 0), instance.identityParameterMigrationIndex(&identity));
    try std.testing.expectError(error.IdentityParameterMigration, instance.validateParameterIdMigrations(&identity));
    try std.testing.expectEqual(@as(?usize, 1), instance.duplicateParameterMigrationIndex(&duplicate));
    try std.testing.expectError(error.DuplicateParameterMigration, instance.validateParameterIdMigrations(&duplicate));
    try std.testing.expectEqual(@as(?usize, 0), instance.cyclicParameterMigrationIndex(&cycle));
    try std.testing.expectError(error.CyclicParameterMigration, instance.validateParameterIdMigrations(&cycle));
    try std.testing.expectEqual(@as(?usize, 1), instance.ambiguousParameterMigrationIndex(&ambiguous));
    try std.testing.expectError(error.AmbiguousParameterMigration, instance.validateParameterIdMigrations(&ambiguous));
}

test "plugin instance accepts metadata-only plugins" {
    const Minimal = struct {
        pub const name = "Minimal";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    const Instance = PluginInstance(Minimal);
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f64{0.25};
    var output = [_]f64{0.0};
    const input_channels = [_][]const f64{&input};
    const output_channels = [_][]f64{&output};
    var context = process_api.ProcessContext(f64){
        .sample_rate = 48_000.0,
        .inputs = try process_api.AudioInputs(f64).init(&input_channels),
        .outputs = try process_api.AudioOutputs(f64).init(&output_channels),
    };

    instance.prepare(.{ .sample_rate = 48_000.0, .max_block_size = 1 });
    instance.process64(&context);
    instance.deinit();

    try std.testing.expectEqualStrings("Minimal", Instance.Spec.name);
    try std.testing.expectEqual(@as(f64, 0.0), output[0]);
}
