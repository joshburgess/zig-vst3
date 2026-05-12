const std = @import("std");
const preset_file = @import("zig-vst3").pluginterfaces.vst.vstpresetfile;

fn printChunkID(writer: anytype, label: []const u8, id: preset_file.ChunkID) !void {
    try writer.print("{s} {s}\n", .{ label, id });
}

pub fn main() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.print("sizeof.ChunkID {}\n", .{@sizeOf(preset_file.ChunkID)});
    try stdout.print("sizeof.Entry {}\n", .{@sizeOf(preset_file.Entry)});
    try stdout.print("alignof.Entry {}\n", .{@alignOf(preset_file.Entry)});
    try stdout.print("offsetof.Entry.id {}\n", .{@offsetOf(preset_file.Entry, "id")});
    try stdout.print("offsetof.Entry.offset {}\n", .{@offsetOf(preset_file.Entry, "offset")});
    try stdout.print("offsetof.Entry.size {}\n", .{@offsetOf(preset_file.Entry, "size")});
    try stdout.print("PresetFile.kMaxEntries {}\n", .{preset_file.kMaxEntries});
    try stdout.print("PresetFile.kFormatVersion {}\n", .{preset_file.kFormatVersion});
    try stdout.print("PresetFile.kClassIDSize {}\n", .{preset_file.kClassIDSize});
    try stdout.print("PresetFile.kHeaderSize {}\n", .{preset_file.kHeaderSize});
    try stdout.print("PresetFile.kListOffsetPos {}\n", .{preset_file.kListOffsetPos});
    try stdout.print("ChunkType.kHeader {}\n", .{@intFromEnum(preset_file.ChunkType.kHeader)});
    try stdout.print("ChunkType.kComponentState {}\n", .{@intFromEnum(preset_file.ChunkType.kComponentState)});
    try stdout.print("ChunkType.kControllerState {}\n", .{@intFromEnum(preset_file.ChunkType.kControllerState)});
    try stdout.print("ChunkType.kProgramData {}\n", .{@intFromEnum(preset_file.ChunkType.kProgramData)});
    try stdout.print("ChunkType.kMetaInfo {}\n", .{@intFromEnum(preset_file.ChunkType.kMetaInfo)});
    try stdout.print("ChunkType.kChunkList {}\n", .{@intFromEnum(preset_file.ChunkType.kChunkList)});
    try stdout.print("ChunkType.kNumPresetChunks {}\n", .{@intFromEnum(preset_file.ChunkType.kNumPresetChunks)});
    try printChunkID(stdout, "ChunkID.kHeader", preset_file.getChunkID(.kHeader));
    try printChunkID(stdout, "ChunkID.kComponentState", preset_file.getChunkID(.kComponentState));
    try printChunkID(stdout, "ChunkID.kControllerState", preset_file.getChunkID(.kControllerState));
    try printChunkID(stdout, "ChunkID.kProgramData", preset_file.getChunkID(.kProgramData));
    try printChunkID(stdout, "ChunkID.kMetaInfo", preset_file.getChunkID(.kMetaInfo));
    try printChunkID(stdout, "ChunkID.kChunkList", preset_file.getChunkID(.kChunkList));
    try stdout.print("isEqualID.header.header {}\n", .{@intFromBool(preset_file.isEqualID(
        preset_file.getChunkID(.kHeader),
        preset_file.getChunkID(.kHeader),
    ))});
    try stdout.print("isEqualID.header.list {}\n", .{@intFromBool(preset_file.isEqualID(
        preset_file.getChunkID(.kHeader),
        preset_file.getChunkID(.kChunkList),
    ))});
}
