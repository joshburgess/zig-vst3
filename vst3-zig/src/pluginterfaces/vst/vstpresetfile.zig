const std = @import("std");
const base = @import("../base/types.zig");

pub const ChunkID = [4]base.char8;

pub const ChunkType = enum(base.int32) {
    kHeader = 0,
    kComponentState = 1,
    kControllerState = 2,
    kProgramData = 3,
    kMetaInfo = 4,
    kChunkList = 5,
    kNumPresetChunks = 6,
};

pub const kMaxEntries: base.int32 = 128;

pub const Entry = extern struct {
    id: ChunkID,
    offset: base.TSize,
    size: base.TSize,
};

pub const chunk_ids = struct {
    pub const kHeader: ChunkID = "VST3".*;
    pub const kComponentState: ChunkID = "Comp".*;
    pub const kControllerState: ChunkID = "Cont".*;
    pub const kProgramData: ChunkID = "Prog".*;
    pub const kMetaInfo: ChunkID = "Info".*;
    pub const kChunkList: ChunkID = "List".*;
};

pub fn getChunkID(chunk_type: ChunkType) ChunkID {
    return switch (chunk_type) {
        .kHeader => chunk_ids.kHeader,
        .kComponentState => chunk_ids.kComponentState,
        .kControllerState => chunk_ids.kControllerState,
        .kProgramData => chunk_ids.kProgramData,
        .kMetaInfo => chunk_ids.kMetaInfo,
        .kChunkList => chunk_ids.kChunkList,
        .kNumPresetChunks => [_]base.char8{ 0, 0, 0, 0 },
    };
}

pub fn isEqualID(first: ChunkID, second: ChunkID) bool {
    return std.mem.eql(base.char8, &first, &second);
}

test "preset chunk helpers match expected IDs" {
    try std.testing.expectEqual(ChunkType.kHeader, @as(ChunkType, @enumFromInt(0)));
    try std.testing.expectEqualStrings("VST3", &getChunkID(.kHeader));
    try std.testing.expectEqualStrings("Comp", &getChunkID(.kComponentState));
    try std.testing.expect(isEqualID(chunk_ids.kChunkList, getChunkID(.kChunkList)));
    try std.testing.expect(!isEqualID(chunk_ids.kChunkList, getChunkID(.kMetaInfo)));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(Entry));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(Entry));
}
