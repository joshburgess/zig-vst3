const ump = @import("midi_ump.zig");

pub fn byteAt(packet: ump.Packet, index: usize) u8 {
    const word = packet.storage[index / 4];
    const shift: u5 = @intCast(24 - (index % 4) * 8);
    return @intCast((word >> shift) & 0xFF);
}

pub fn setByte(words: *[4]u32, index: usize, value: u8) void {
    const shift: u5 = @intCast(24 - (index % 4) * 8);
    words[index / 4] |= @as(u32, value) << shift;
}
