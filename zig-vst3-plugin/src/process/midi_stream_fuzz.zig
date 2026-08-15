const std = @import("std");
const flex_text = @import("midi_flex_text.zig");
const mixed_data = @import("midi_mixed_data.zig");
const stream_text = @import("midi_stream_text.zig");
const sysex7 = @import("midi_sysex7.zig");
const sysex8 = @import("midi_sysex8.zig");
const ump = @import("midi_ump.zig");

const fuzz_single = [_]u8{ 0x30, 0x00, 0x00, 0x00 };
const fuzz_data128 = [_]u8{
    0x50, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
};

test "fuzz failure-atomic MIDI segmented assemblers" {
    try std.testing.fuzz({}, fuzzSegmentedAssemblers, .{
        .corpus = &.{ &fuzz_single, &fuzz_data128 },
    });
}

fn fuzzSegmentedAssemblers(_: void, smith: *std.testing.Smith) !void {
    @disableInstrumentation();
    var bytes: [2 * 1024]u8 = undefined;
    const byte_count = smith.slice(&bytes);
    var words: [bytes.len / @sizeOf(u32)]u32 = undefined;
    const word_count = byte_count / @sizeOf(u32);
    for (words[0..word_count], 0..) |*word, index| {
        const offset = index * @sizeOf(u32);
        word.* = std.mem.readInt(
            u32,
            bytes[offset..][0..@sizeOf(u32)],
            .big,
        );
    }

    var sysex7_assembler = sysex7.Reassembler(256){};
    var sysex8_assembler = sysex8.Reassembler(256){};
    var mixed_data_assembler = mixed_data.Reassembler(256){};
    var flex_text_assembler = flex_text.Reassembler(384){};
    var stream_text_assembler = stream_text.Reassembler(128){};

    var cursor: usize = 0;
    while (cursor < word_count) {
        const required: usize = ump.wordCountForType(
            @enumFromInt(words[cursor] >> 28),
        );
        const end = std.math.add(usize, cursor, required) catch return;
        if (end > word_count) return;
        const packet = ump.Packet.init(words[cursor..end]) catch return;
        try pushFailureAtomic(&sysex7_assembler, packet);
        try pushFailureAtomic(&sysex8_assembler, packet);
        try pushFailureAtomic(&mixed_data_assembler, packet);
        try pushFailureAtomic(&flex_text_assembler, packet);
        try pushFailureAtomic(&stream_text_assembler, packet);
        cursor = end;
    }
}

fn pushFailureAtomic(assembler: anytype, packet: ump.Packet) !void {
    const before = assembler.*;
    if (assembler.push(packet)) |_| {
        if (!assembler.valid())
            return error.FuzzAcceptedInvalidMidiAssemblerState;
    } else |_| {
        try std.testing.expectEqualDeep(before, assembler.*);
    }
}
