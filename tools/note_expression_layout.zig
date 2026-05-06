const std = @import("std");
const note_expression = @import("vst3-zig").pluginterfaces.vst.ivstnoteexpression;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("NoteExpressionTypeIDs.kVolumeTypeID {}\n", .{@intFromEnum(note_expression.NoteExpressionTypeIDs.kVolumeTypeID)});
    try stdout.print("NoteExpressionTypeIDs.kPanTypeID {}\n", .{@intFromEnum(note_expression.NoteExpressionTypeIDs.kPanTypeID)});
    try stdout.print("NoteExpressionTypeIDs.kTuningTypeID {}\n", .{@intFromEnum(note_expression.NoteExpressionTypeIDs.kTuningTypeID)});
    try stdout.print("NoteExpressionTypeIDs.kVibratoTypeID {}\n", .{@intFromEnum(note_expression.NoteExpressionTypeIDs.kVibratoTypeID)});
    try stdout.print("NoteExpressionTypeIDs.kExpressionTypeID {}\n", .{@intFromEnum(note_expression.NoteExpressionTypeIDs.kExpressionTypeID)});
    try stdout.print("NoteExpressionTypeIDs.kBrightnessTypeID {}\n", .{@intFromEnum(note_expression.NoteExpressionTypeIDs.kBrightnessTypeID)});
    try stdout.print("NoteExpressionTypeIDs.kTextTypeID {}\n", .{@intFromEnum(note_expression.NoteExpressionTypeIDs.kTextTypeID)});
    try stdout.print("NoteExpressionTypeIDs.kPhonemeTypeID {}\n", .{@intFromEnum(note_expression.NoteExpressionTypeIDs.kPhonemeTypeID)});
    try stdout.print("NoteExpressionTypeIDs.kCustomStart {}\n", .{@intFromEnum(note_expression.NoteExpressionTypeIDs.kCustomStart)});
    try stdout.print("NoteExpressionTypeIDs.kCustomEnd {}\n", .{@intFromEnum(note_expression.NoteExpressionTypeIDs.kCustomEnd)});
    try stdout.print("NoteExpressionTypeIDs.kInvalidTypeID {}\n", .{@intFromEnum(note_expression.NoteExpressionTypeIDs.kInvalidTypeID)});
    try stdout.print("NoteExpressionTypeInfo.kIsBipolar {}\n", .{note_expression.NoteExpressionTypeInfo.NoteExpressionTypeFlags.kIsBipolar});
    try stdout.print("NoteExpressionTypeInfo.kIsOneShot {}\n", .{note_expression.NoteExpressionTypeInfo.NoteExpressionTypeFlags.kIsOneShot});
    try stdout.print("NoteExpressionTypeInfo.kIsAbsolute {}\n", .{note_expression.NoteExpressionTypeInfo.NoteExpressionTypeFlags.kIsAbsolute});
    try stdout.print("NoteExpressionTypeInfo.kAssociatedParameterIDValid {}\n", .{note_expression.NoteExpressionTypeInfo.NoteExpressionTypeFlags.kAssociatedParameterIDValid});
    try stdout.print("KeyswitchTypeIDs.kNoteOnKeyswitchTypeID {}\n", .{@intFromEnum(note_expression.KeyswitchTypeIDs.kNoteOnKeyswitchTypeID)});
    try stdout.print("KeyswitchTypeIDs.kOnTheFlyKeyswitchTypeID {}\n", .{@intFromEnum(note_expression.KeyswitchTypeIDs.kOnTheFlyKeyswitchTypeID)});
    try stdout.print("KeyswitchTypeIDs.kOnReleaseKeyswitchTypeID {}\n", .{@intFromEnum(note_expression.KeyswitchTypeIDs.kOnReleaseKeyswitchTypeID)});
    try stdout.print("KeyswitchTypeIDs.kKeyRangeTypeID {}\n", .{@intFromEnum(note_expression.KeyswitchTypeIDs.kKeyRangeTypeID)});

    try printType(stdout, "NoteExpressionValueEvent", note_expression.NoteExpressionValueEvent);
    try printOffset(stdout, "NoteExpressionValueEvent", "typeId", note_expression.NoteExpressionValueEvent, "typeId");
    try printOffset(stdout, "NoteExpressionValueEvent", "noteId", note_expression.NoteExpressionValueEvent, "noteId");
    try printOffset(stdout, "NoteExpressionValueEvent", "value", note_expression.NoteExpressionValueEvent, "value");

    try printType(stdout, "NoteExpressionIntValueEvent", note_expression.NoteExpressionIntValueEvent);
    try printOffset(stdout, "NoteExpressionIntValueEvent", "typeId", note_expression.NoteExpressionIntValueEvent, "typeId");
    try printOffset(stdout, "NoteExpressionIntValueEvent", "noteId", note_expression.NoteExpressionIntValueEvent, "noteId");
    try printOffset(stdout, "NoteExpressionIntValueEvent", "value", note_expression.NoteExpressionIntValueEvent, "value");

    try printType(stdout, "NoteExpressionTextEvent", note_expression.NoteExpressionTextEvent);
    try printOffset(stdout, "NoteExpressionTextEvent", "typeId", note_expression.NoteExpressionTextEvent, "typeId");
    try printOffset(stdout, "NoteExpressionTextEvent", "noteId", note_expression.NoteExpressionTextEvent, "noteId");
    try printOffset(stdout, "NoteExpressionTextEvent", "textLen", note_expression.NoteExpressionTextEvent, "textLen");
    try printOffset(stdout, "NoteExpressionTextEvent", "text", note_expression.NoteExpressionTextEvent, "text");

    try printType(stdout, "NoteExpressionValueDescription", note_expression.NoteExpressionValueDescription);
    try printOffset(stdout, "NoteExpressionValueDescription", "defaultValue", note_expression.NoteExpressionValueDescription, "defaultValue");
    try printOffset(stdout, "NoteExpressionValueDescription", "minimum", note_expression.NoteExpressionValueDescription, "minimum");
    try printOffset(stdout, "NoteExpressionValueDescription", "maximum", note_expression.NoteExpressionValueDescription, "maximum");
    try printOffset(stdout, "NoteExpressionValueDescription", "stepCount", note_expression.NoteExpressionValueDescription, "stepCount");

    try printType(stdout, "NoteExpressionTypeInfo", note_expression.NoteExpressionTypeInfo);
    try printOffset(stdout, "NoteExpressionTypeInfo", "typeId", note_expression.NoteExpressionTypeInfo, "typeId");
    try printOffset(stdout, "NoteExpressionTypeInfo", "title", note_expression.NoteExpressionTypeInfo, "title");
    try printOffset(stdout, "NoteExpressionTypeInfo", "shortTitle", note_expression.NoteExpressionTypeInfo, "shortTitle");
    try printOffset(stdout, "NoteExpressionTypeInfo", "units", note_expression.NoteExpressionTypeInfo, "units");
    try printOffset(stdout, "NoteExpressionTypeInfo", "unitId", note_expression.NoteExpressionTypeInfo, "unitId");
    try printOffset(stdout, "NoteExpressionTypeInfo", "valueDesc", note_expression.NoteExpressionTypeInfo, "valueDesc");
    try printOffset(stdout, "NoteExpressionTypeInfo", "associatedParameterId", note_expression.NoteExpressionTypeInfo, "associatedParameterId");
    try printOffset(stdout, "NoteExpressionTypeInfo", "flags", note_expression.NoteExpressionTypeInfo, "flags");

    try printType(stdout, "KeyswitchInfo", note_expression.KeyswitchInfo);
    try printOffset(stdout, "KeyswitchInfo", "typeId", note_expression.KeyswitchInfo, "typeId");
    try printOffset(stdout, "KeyswitchInfo", "title", note_expression.KeyswitchInfo, "title");
    try printOffset(stdout, "KeyswitchInfo", "shortTitle", note_expression.KeyswitchInfo, "shortTitle");
    try printOffset(stdout, "KeyswitchInfo", "keyswitchMin", note_expression.KeyswitchInfo, "keyswitchMin");
    try printOffset(stdout, "KeyswitchInfo", "keyswitchMax", note_expression.KeyswitchInfo, "keyswitchMax");
    try printOffset(stdout, "KeyswitchInfo", "keyRemapped", note_expression.KeyswitchInfo, "keyRemapped");
    try printOffset(stdout, "KeyswitchInfo", "unitId", note_expression.KeyswitchInfo, "unitId");
    try printOffset(stdout, "KeyswitchInfo", "flags", note_expression.KeyswitchInfo, "flags");

    try printTuid(stdout, "INoteExpressionController", note_expression.inote_expression_controller_iid);
    try printTuid(stdout, "IKeyswitchController", note_expression.ikeyswitch_controller_iid);
}

fn printType(writer: anytype, comptime name: []const u8, comptime Type: type) !void {
    try writer.print("{s} size {} align {}\n", .{ name, @sizeOf(Type), @alignOf(Type) });
}

fn printOffset(writer: anytype, comptime type_name: []const u8, comptime field_label: []const u8, comptime Type: type, comptime field_name: []const u8) !void {
    try writer.print("{s}.{s} offset {}\n", .{ type_name, field_label, @offsetOf(Type, field_name) });
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
