const std = @import("std");
const adm = @import("adm.zig");

pub const maximum_outputs: usize = 64;

pub const GainVector = struct {
    output_count: usize,
    gains: [maximum_outputs]f64 = @splat(0.0),

    pub fn slice(self: *const GainVector) []const f64 {
        if (!self.valid()) return &.{};
        return self.gains[0..self.output_count];
    }

    pub fn valid(self: *const GainVector) bool {
        if (self.output_count == 0 or self.output_count > maximum_outputs)
            return false;
        var has_gain = false;
        for (self.gains[0..self.output_count]) |gain| {
            if (!std.math.isFinite(gain) or gain < 0.0) return false;
            has_gain = has_gain or gain != 0.0;
        }
        return has_gain;
    }
};

const Layout = enum {
    zero_one_zero,
    zero_two_zero,
    zero_five_zero,
    two_five_zero,
    four_five_zero,
    four_five_one,
    three_seven_zero,
    four_nine_zero,
    nine_ten_three,
    zero_seven_zero,
    four_seven_zero,
};

const Restriction = enum {
    any,
    high_channel,

    fn matchesInput(self: Restriction, layout: Layout) bool {
        return self == .any or
            layout == .nine_ten_three or
            layout == .three_seven_zero;
    }

    fn matchesOutput(self: Restriction, name: []const u8) bool {
        return self == .any or
            std.mem.eql(u8, name, "9+10+3") or
            std.mem.eql(u8, name, "3+7+0");
    }
};

const Term = struct {
    label: []const u8 = "",
    gain: f64 = 0.0,
};

const Rule = struct {
    input_label: []const u8,
    terms: [4]Term,
    term_count: u8,
    input_restriction: Restriction = .any,
    output_restriction: Restriction = .any,
};

const root_half: f64 = @sqrt(1.0 / 2.0);
const root_quarter: f64 = @sqrt(1.0 / 4.0);
const root_third: f64 = @sqrt(1.0 / 3.0);
const root_two_thirds: f64 = @sqrt(2.0 / 3.0);

fn one(
    input: []const u8,
    output: []const u8,
    gain: f64,
) Rule {
    return .{
        .input_label = input,
        .terms = .{ .{ .label = output, .gain = gain }, .{}, .{}, .{} },
        .term_count = 1,
    };
}

fn two(
    input: []const u8,
    first: Term,
    second: Term,
) Rule {
    return .{
        .input_label = input,
        .terms = .{ first, second, .{}, .{} },
        .term_count = 2,
    };
}

fn three(
    input: []const u8,
    first: Term,
    second: Term,
    third: Term,
) Rule {
    return .{
        .input_label = input,
        .terms = .{ first, second, third, .{} },
        .term_count = 3,
    };
}

fn four(
    input: []const u8,
    first: Term,
    second: Term,
    third: Term,
    fourth: Term,
) Rule {
    return .{
        .input_label = input,
        .terms = .{ first, second, third, fourth },
        .term_count = 4,
    };
}

fn restrictedInput(rule: Rule) Rule {
    var result = rule;
    result.input_restriction = .high_channel;
    return result;
}

fn restrictedOutput(rule: Rule) Rule {
    var result = rule;
    result.output_restriction = .high_channel;
    return result;
}

const rules = [_]Rule{
    one("M+000", "M+000", 1.0),
    two("M+000", .{ .label = "M+030", .gain = root_half }, .{ .label = "M-030", .gain = root_half }),

    one("M+060", "M+060", 1.0),
    two("M+060", .{ .label = "M+030", .gain = root_two_thirds }, .{ .label = "M+110", .gain = root_third }),
    two("M+060", .{ .label = "M+030", .gain = root_half }, .{ .label = "M+090", .gain = root_half }),
    one("M+060", "M+030", 1.0),

    one("M+090", "M+090", 1.0),
    restrictedInput(two("M+090", .{ .label = "M+030", .gain = root_third }, .{ .label = "M+110", .gain = root_two_thirds })),
    two("M+090", .{ .label = "M+030", .gain = root_half }, .{ .label = "M+110", .gain = root_half }),
    one("M+090", "M+030", root_half),

    one("M+110", "M+110", 1.0),
    one("M+110", "M+135", 1.0),
    one("M+110", "M+030", root_half),

    one("M+135", "M+135", 1.0),
    one("M+135", "M+110", 1.0),
    one("M+135", "M+030", root_half),

    one("M+180", "M+180", 1.0),
    two("M+180", .{ .label = "M+135", .gain = root_half }, .{ .label = "M-135", .gain = root_half }),
    two("M+180", .{ .label = "M+110", .gain = root_half }, .{ .label = "M-110", .gain = root_half }),
    two("M+180", .{ .label = "M+030", .gain = root_quarter }, .{ .label = "M-030", .gain = root_quarter }),

    one("U+000", "U+000", 1.0),
    two("U+000", .{ .label = "U+030", .gain = root_half }, .{ .label = "U-030", .gain = root_half }),
    two("U+000", .{ .label = "U+045", .gain = root_half }, .{ .label = "U-045", .gain = root_half }),
    one("U+000", "M+000", 1.0),
    two("U+000", .{ .label = "M+030", .gain = root_half }, .{ .label = "M-030", .gain = root_half }),

    one("U+030", "U+030", 1.0),
    one("U+030", "U+045", 1.0),
    one("U+030", "M+030", 1.0),

    one("U+045", "U+045", 1.0),
    one("U+045", "U+030", 1.0),
    one("U+045", "M+030", 1.0),

    one("U+090", "U+090", 1.0),
    restrictedInput(two("U+090", .{ .label = "U+045", .gain = root_two_thirds }, .{ .label = "UH+180", .gain = root_third })),
    two("U+090", .{ .label = "U+030", .gain = root_half }, .{ .label = "U+110", .gain = root_half }),
    two("U+090", .{ .label = "U+045", .gain = root_half }, .{ .label = "U+135", .gain = root_half }),
    one("U+090", "M+090", 1.0),
    two("U+090", .{ .label = "U+030", .gain = root_half }, .{ .label = "M+110", .gain = root_half }),
    two("U+090", .{ .label = "M+030", .gain = root_half }, .{ .label = "M+110", .gain = root_half }),
    one("U+090", "M+030", root_half),

    one("U+110", "U+110", 1.0),
    one("U+110", "U+135", 1.0),
    two("U+110", .{ .label = "U+045", .gain = root_half }, .{ .label = "UH+180", .gain = root_half }),
    one("U+110", "M+110", 1.0),
    one("U+110", "M+135", 1.0),
    one("U+110", "M+030", root_half),

    one("U+135", "U+135", 1.0),
    one("U+135", "U+110", 1.0),
    restrictedInput(two("U+135", .{ .label = "U+045", .gain = root_third }, .{ .label = "UH+180", .gain = root_two_thirds })),
    two("U+135", .{ .label = "U+045", .gain = root_half }, .{ .label = "UH+180", .gain = root_half }),
    one("U+135", "M+135", 1.0),
    one("U+135", "M+110", 1.0),
    one("U+135", "M+030", root_half),

    one("U+180", "U+180", 1.0),
    one("U+180", "UH+180", 1.0),
    two("U+180", .{ .label = "U+135", .gain = root_half }, .{ .label = "U-135", .gain = root_half }),
    two("U+180", .{ .label = "U+110", .gain = root_half }, .{ .label = "U-110", .gain = root_half }),
    two("U+180", .{ .label = "M+135", .gain = root_half }, .{ .label = "M-135", .gain = root_half }),
    two("U+180", .{ .label = "M+110", .gain = root_half }, .{ .label = "M-110", .gain = root_half }),
    two("U+180", .{ .label = "M+030", .gain = root_quarter }, .{ .label = "M-030", .gain = root_quarter }),

    one("UH+180", "UH+180", 1.0),
    one("UH+180", "U+180", 1.0),
    two("UH+180", .{ .label = "U+135", .gain = root_half }, .{ .label = "U-135", .gain = root_half }),
    two("UH+180", .{ .label = "U+110", .gain = root_half }, .{ .label = "U-110", .gain = root_half }),
    two("UH+180", .{ .label = "M+135", .gain = root_half }, .{ .label = "M-135", .gain = root_half }),
    two("UH+180", .{ .label = "M+110", .gain = root_half }, .{ .label = "M-110", .gain = root_half }),
    two("UH+180", .{ .label = "M+030", .gain = root_quarter }, .{ .label = "M-030", .gain = root_quarter }),

    one("T+000", "T+000", 1.0),
    four("T+000", .{ .label = "U+045", .gain = root_quarter }, .{ .label = "U-045", .gain = root_quarter }, .{ .label = "U+135", .gain = root_quarter }, .{ .label = "U-135", .gain = root_quarter }),
    four("T+000", .{ .label = "U+030", .gain = root_quarter }, .{ .label = "U-030", .gain = root_quarter }, .{ .label = "U+110", .gain = root_quarter }, .{ .label = "U-110", .gain = root_quarter }),
    three("T+000", .{ .label = "U+045", .gain = root_third }, .{ .label = "U-045", .gain = root_third }, .{ .label = "UH+180", .gain = root_third }),
    four("T+000", .{ .label = "U+045", .gain = root_quarter }, .{ .label = "U-045", .gain = root_quarter }, .{ .label = "M+135", .gain = root_quarter }, .{ .label = "M-135", .gain = root_quarter }),
    four("T+000", .{ .label = "U+030", .gain = root_quarter }, .{ .label = "U-030", .gain = root_quarter }, .{ .label = "M+110", .gain = root_quarter }, .{ .label = "M-110", .gain = root_quarter }),
    four("T+000", .{ .label = "M+030", .gain = root_quarter }, .{ .label = "M-030", .gain = root_quarter }, .{ .label = "M+135", .gain = root_quarter }, .{ .label = "M-135", .gain = root_quarter }),
    four("T+000", .{ .label = "M+030", .gain = root_quarter }, .{ .label = "M-030", .gain = root_quarter }, .{ .label = "M+110", .gain = root_quarter }, .{ .label = "M-110", .gain = root_quarter }),
    two("T+000", .{ .label = "M+030", .gain = root_quarter }, .{ .label = "M-030", .gain = root_quarter }),

    one("B+000", "B+000", 1.0),
    one("B+000", "M+000", 1.0),
    two("B+000", .{ .label = "M+030", .gain = root_half }, .{ .label = "M-030", .gain = root_half }),

    one("B+045", "B+045", 1.0),
    one("B+045", "M+030", 1.0),

    restrictedOutput(restrictedInput(one("LFE1", "LFE1", 1.0))),
    restrictedOutput(restrictedInput(one("LFE2", "LFE2", 1.0))),
    restrictedInput(one("LFE1", "LFE1", root_half)),
    restrictedInput(one("LFE2", "LFE1", root_half)),
    one("LFE1", "LFE1", 1.0),
};

comptime {
    if (rules.len != 85)
        @compileError("common speaker mapping table must contain 85 rules");
}

pub fn resolve(
    input_pack: adm.Identifier,
    output_layout_name: []const u8,
    input_label: []const u8,
    output_labels: []const []const u8,
) ?GainVector {
    const input_layout = inputLayout(input_pack) orelse return null;
    if (output_labels.len == 0 or output_labels.len > maximum_outputs)
        return null;

    for (rules) |rule| {
        const side = matchSide(input_label, rule.input_label) orelse
            continue;
        if (!rule.input_restriction.matchesInput(input_layout) or
            !rule.output_restriction.matchesOutput(output_layout_name))
        {
            continue;
        }

        var result = GainVector{ .output_count = output_labels.len };
        var complete = true;
        for (rule.terms[0..rule.term_count]) |term| {
            const target_label = switch (side) {
                .direct => term.label,
                .mirrored => oppositeLabel(term.label) orelse {
                    complete = false;
                    break;
                },
            };
            const output_index = findLabel(
                output_labels,
                target_label,
            ) orelse {
                complete = false;
                break;
            };
            result.gains[output_index] = term.gain;
        }
        if (complete and result.valid()) return result;
    }
    return null;
}

fn inputLayout(identifier: adm.Identifier) ?Layout {
    if (identifier.kind != .pack_format or
        identifier.typeLabel() != 0x0001 or
        !identifier.isCommonDefinition())
    {
        return null;
    }
    return switch (identifier.definitionIndex() orelse return null) {
        0x0001 => .zero_one_zero,
        0x0002 => .zero_two_zero,
        0x0003, 0x000c => .zero_five_zero,
        0x0004 => .two_five_zero,
        0x0005 => .four_five_zero,
        0x0010 => .four_five_one,
        0x0007 => .three_seven_zero,
        0x0008 => .four_nine_zero,
        0x0009 => .nine_ten_three,
        0x000f => .zero_seven_zero,
        0x0017 => .four_seven_zero,
        else => null,
    };
}

const Side = enum {
    direct,
    mirrored,
};

fn matchSide(input: []const u8, rule_input: []const u8) ?Side {
    if (std.mem.eql(u8, input, rule_input)) return .direct;
    const opposite = oppositeLabel(rule_input) orelse return null;
    return if (std.mem.eql(u8, input, opposite)) .mirrored else null;
}

fn oppositeLabel(label: []const u8) ?[]const u8 {
    const pairs = [_][2][]const u8{
        .{ "M+030", "M-030" },
        .{ "M+060", "M-060" },
        .{ "M+090", "M-090" },
        .{ "M+110", "M-110" },
        .{ "M+135", "M-135" },
        .{ "U+030", "U-030" },
        .{ "U+045", "U-045" },
        .{ "U+090", "U-090" },
        .{ "U+110", "U-110" },
        .{ "U+135", "U-135" },
        .{ "B+045", "B-045" },
    };
    for (pairs) |pair| {
        if (std.mem.eql(u8, label, pair[0])) return pair[1];
        if (std.mem.eql(u8, label, pair[1])) return pair[0];
    }
    return null;
}

fn findLabel(
    labels: []const []const u8,
    target: []const u8,
) ?usize {
    for (labels, 0..) |label, index| {
        if (std.mem.eql(u8, label, target)) return index;
    }
    return null;
}

fn pack(raw: []const u8) !adm.Identifier {
    return adm.Identifier.parse(raw);
}

test "ADM common speaker mapping follows first matching horizontal rule" {
    const input_pack = try pack("AP_00010005");
    const full = [_][]const u8{ "M+110", "M+030" };
    const full_result =
        resolve(input_pack, "4+5+0", "M+060", &full).?;
    try std.testing.expectApproxEqAbs(
        root_third,
        full_result.gains[0],
        1.0e-15,
    );
    try std.testing.expectApproxEqAbs(
        root_two_thirds,
        full_result.gains[1],
        1.0e-15,
    );

    const alternate = [_][]const u8{ "M+090", "M+030" };
    const alternate_result =
        resolve(input_pack, "4+7+0", "M+060", &alternate).?;
    try std.testing.expectEqualSlices(
        f64,
        &.{ root_half, root_half },
        alternate_result.gains[0..2],
    );
    const reduced = [_][]const u8{"M+030"};
    try std.testing.expectEqual(
        @as(f64, 1.0),
        resolve(input_pack, "0+5+0", "M+060", &reduced).?.gains[0],
    );
}

test "ADM common speaker gain views reject malformed retained values" {
    var gains = GainVector{ .output_count = 2 };
    gains.gains[0] = 1.0;
    try std.testing.expect(gains.valid());
    try std.testing.expectEqual(@as(usize, 2), gains.slice().len);

    gains.output_count = maximum_outputs + 1;
    try std.testing.expect(!gains.valid());
    try std.testing.expectEqual(@as(usize, 0), gains.slice().len);

    gains.output_count = 2;
    gains.gains[0] = std.math.nan(f64);
    try std.testing.expect(!gains.valid());
    try std.testing.expectEqual(@as(usize, 0), gains.slice().len);
}

test "ADM common speaker mapping mirrors lateral rules" {
    const labels = [_][]const u8{ "M-030", "M-110" };
    const result =
        resolve(try pack("AP_00010009"), "4+5+0", "M-090", &labels).?;
    try std.testing.expectApproxEqAbs(
        root_third,
        result.gains[0],
        1.0e-15,
    );
    try std.testing.expectApproxEqAbs(
        root_two_thirds,
        result.gains[1],
        1.0e-15,
    );
}

test "ADM common speaker mapping covers upper top and bottom families" {
    const input_pack = try pack("AP_00010017");
    const upper_labels = [_][]const u8{ "U+045", "UH+180" };
    const upper =
        resolve(input_pack, "4+7+0", "U+110", &upper_labels).?;
    try std.testing.expectEqualSlices(
        f64,
        &.{ root_half, root_half },
        upper.gains[0..2],
    );

    const top_labels = [_][]const u8{
        "U+045",
        "U-045",
        "U+135",
        "U-135",
    };
    const top =
        resolve(input_pack, "4+7+0", "T+000", &top_labels).?;
    try std.testing.expectEqualSlices(
        f64,
        &.{ root_quarter, root_quarter, root_quarter, root_quarter },
        top.gains[0..4],
    );

    const bottom_labels = [_][]const u8{ "M-030", "M+030" };
    const bottom =
        resolve(input_pack, "0+5+0", "B+000", &bottom_labels).?;
    try std.testing.expectEqualSlices(
        f64,
        &.{ root_half, root_half },
        bottom.gains[0..2],
    );
}

test "ADM common speaker mapping applies high-channel LFE restrictions" {
    const high_pack = try pack("AP_00010009");
    const two_lfe = [_][]const u8{ "LFE1", "LFE2" };
    const retained =
        resolve(high_pack, "9+10+3", "LFE2", &two_lfe).?;
    try std.testing.expectEqual(@as(f64, 1.0), retained.gains[1]);

    const one_lfe = [_][]const u8{"LFE1"};
    const folded =
        resolve(high_pack, "4+5+0", "LFE2", &one_lfe).?;
    try std.testing.expectApproxEqAbs(
        root_half,
        folded.gains[0],
        1.0e-15,
    );
    try std.testing.expect(
        resolve(
            try pack("AP_00010005"),
            "4+5+0",
            "LFE2",
            &one_lfe,
        ) == null,
    );
}

test "ADM common speaker mapping rejects noncommon and incomplete rules" {
    const labels = [_][]const u8{"M+030"};
    try std.testing.expect(
        resolve(
            try pack("AP_00011001"),
            "0+5+0",
            "M+060",
            &labels,
        ) == null,
    );
    try std.testing.expect(
        resolve(
            try pack("AP_00010006"),
            "0+5+0",
            "M+060",
            &labels,
        ) == null,
    );
    try std.testing.expect(
        resolve(
            try pack("AP_00010005"),
            "0+5+0",
            "M+SC",
            &labels,
        ) == null,
    );
}
