const std = @import("std");

const half_range = @as(u64, 1) << 63;

pub fn after(candidate: u64, reference: u64) bool {
    if (candidate == 0) return false;
    if (reference == 0) return true;
    const distance = candidate -% reference;
    return distance != 0 and distance < half_range;
}

pub fn atOrAfter(candidate: u64, reference: u64) bool {
    return candidate == reference or after(candidate, reference);
}

pub fn atOrBefore(candidate: u64, reference: u64) bool {
    return candidate == reference or after(reference, candidate);
}

test "serial generations order rollover and reject ambiguous distances" {
    try std.testing.expect(after(1, std.math.maxInt(u64)));
    try std.testing.expect(after(std.math.maxInt(u64), std.math.maxInt(u64) - 1));
    try std.testing.expect(!after(std.math.maxInt(u64) - 1, 1));
    try std.testing.expect(!after(0, std.math.maxInt(u64)));
    try std.testing.expect(!after(7, 7));
    try std.testing.expect(!after(1 +% half_range, 1));
    try std.testing.expect(atOrAfter(1, std.math.maxInt(u64)));
    try std.testing.expect(atOrBefore(std.math.maxInt(u64), 1));
}
