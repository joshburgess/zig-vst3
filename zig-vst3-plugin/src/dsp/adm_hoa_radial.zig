const std = @import("std");
const adm = @import("adm.zig");
const adm_time = @import("adm_time.zig");
const adm_hoa_decoder = @import("adm_hoa_decoder.zig");
const adm_xml = @import("adm_xml.zig");
const biquad = @import("biquad.zig");
const polynomial = @import("polynomial.zig");

pub const Normalization = enum {
    high_frequency_unity,
};

pub const Regularization = union(enum) {
    none,
    gain_limit: struct {
        maximum_gain_db: f64,
        transition_hz: f64,
    },
};

pub const Config = struct {
    sample_rate: f64,
    loudspeaker_distance: f64,
    speed_of_sound: f64 = 343.0,
    normalization: Normalization = .high_frequency_unity,
    regularization: Regularization = .none,
    screen_reference_policy: adm_hoa_decoder.ScreenReferencePolicy = .reject,
};

pub fn RadialFilterBank(
    comptime Sample: type,
    comptime maximum_inputs: usize,
    comptime maximum_order: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("RadialFilterBank supports f32 and f64 samples");
    if (maximum_inputs == 0)
        @compileError("RadialFilterBank requires input capacity");
    if (maximum_order == 0 or maximum_order > 16)
        @compileError("RadialFilterBank requires capacity through order 1 to 16");

    const section_capacity = (maximum_order + 1) / 2 + 1;
    const Polynomial = polynomial.Polynomial(f64, maximum_order + 1);
    const Filter = biquad.SmoothedBiquad(Sample);
    const ScaledPolynomial = struct {
        value: Polynomial,
        root_scale: f64,
    };

    return struct {
        const Self = @This();

        input_count: usize,
        reference_distance: f64,
        screen_reference: bool,
        config: Config,
        orders: [maximum_inputs]u8 = undefined,
        section_counts: [maximum_inputs]u8 = @splat(0),
        coefficients: [maximum_inputs][section_capacity]biquad.Coefficients =
            @splat(@splat(.{})),
        filters: [maximum_inputs][section_capacity]Filter =
            @splat(@splat(.{})),

        pub fn init(
            blocks: []const adm_xml.BlockFormat,
            config: Config,
        ) !Self {
            try validateConfig(config);
            if (blocks.len == 0 or blocks.len > maximum_inputs)
                return error.InvalidAdmHoaRadialInputCount;

            const reference_distance =
                blocks[0].hoa_nfc_reference_distance;
            if (!std.math.isFinite(reference_distance) or
                reference_distance <= 0.0)
            {
                return error.InvalidAdmHoaRadialReferenceDistance;
            }

            var result = Self{
                .input_count = blocks.len,
                .reference_distance = reference_distance,
                .screen_reference = blocks[0].screen_ref,
                .config = config,
            };
            var designs: [maximum_order + 1][section_capacity]biquad.Coefficients =
                @splat(@splat(.{}));
            var design_counts: [maximum_order + 1]u8 = @splat(0);
            var designed: [maximum_order + 1]bool = @splat(false);
            designed[0] = true;

            for (blocks, 0..) |block, input_index| {
                try validateBlockKind(block);
                if (block.hoa_equation != null)
                    return error.UnsupportedAdmHoaRadialEquation;
                if (block.screen_ref != result.screen_reference)
                    return error.MixedAdmHoaScreenReference;
                if (block.screen_ref and
                    config.screen_reference_policy == .reject)
                {
                    return error.UnsupportedAdmHoaRadialScreenReference;
                }
                if (block.hoa_nfc_reference_distance !=
                    reference_distance)
                {
                    return error.MixedAdmHoaRadialReferenceDistance;
                }
                const order =
                    block.hoa_order orelse return error.MissingAdmHoaOrder;
                if (order > maximum_order)
                    return error.UnsupportedAdmHoaRadialOrder;
                const degree =
                    block.hoa_degree orelse return error.MissingAdmHoaDegree;
                if (@as(i64, degree) < -@as(i64, order) or
                    @as(i64, degree) > @as(i64, order))
                {
                    return error.InvalidAdmHoaDegree;
                }
                result.orders[input_index] = @intCast(order);

                const order_index: usize = @intCast(order);
                if (!designed[order_index]) {
                    designOrder(
                        order_index,
                        reference_distance,
                        config,
                        &designs[order_index],
                        &design_counts[order_index],
                    ) catch return error.InvalidAdmHoaRadialDesign;
                    designed[order_index] = true;
                }
                const count = design_counts[order_index];
                result.section_counts[input_index] = count;
                @memcpy(
                    result.coefficients[input_index][0..count],
                    designs[order_index][0..count],
                );
                for (0..count) |section| {
                    result.filters[input_index][section].setImmediate(
                        result.coefficients[input_index][section],
                    );
                }
            }
            if (!result.valid())
                return error.InvalidAdmHoaRadialDesign;
            return result;
        }

        pub fn reset(self: *Self) void {
            if (self.input_count == 0 or self.input_count > maximum_inputs)
                return;
            for (0..self.input_count) |input| {
                if (self.section_counts[input] > section_capacity) return;
            }
            for (0..self.input_count) |input| {
                for (0..self.section_counts[input]) |section|
                    self.filters[input][section].reset();
            }
        }

        pub fn process(
            self: *Self,
            inputs: []const []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmHoaRadialState;
            if (inputs.len != self.input_count or
                outputs.len != self.input_count)
            {
                return error.AdmHoaRadialChannelCountMismatch;
            }
            const frame_count = inputs[0].len;
            for (inputs, outputs, 0..) |input, output, output_index| {
                if (input.len != frame_count or output.len != frame_count)
                    return error.AdmHoaRadialBufferLengthMismatch;
                for (outputs[0..output_index]) |previous| {
                    if (slicesOverlap(Sample, input, previous) or
                        slicesOverlap(Sample, output, previous))
                    {
                        return error.AdmHoaRadialAliasedBuffers;
                    }
                }
                for (inputs[output_index + 1 ..]) |later_input| {
                    if (slicesOverlap(Sample, output, later_input))
                        return error.AdmHoaRadialAliasedBuffers;
                }
                if (slicesOverlap(Sample, input, output) and
                    !sameSlice(Sample, input, output))
                {
                    return error.AdmHoaRadialAliasedBuffers;
                }
            }

            for (inputs, outputs, 0..) |input, output, channel| {
                const section_count = self.section_counts[channel];
                var trial = self.filters[channel];
                for (input, output) |raw, *destination| {
                    var value = if (std.math.isFinite(raw)) raw else 0.0;
                    for (0..section_count) |section| {
                        value = trial[section].process(value);
                        if (!std.meta.eql(
                            trial[section].current,
                            self.coefficients[channel][section],
                        )) {
                            trial[section].setImmediate(
                                self.coefficients[channel][section],
                            );
                            trial[section].reset();
                            value = 0.0;
                        }
                    }
                    destination.* = if (std.math.isFinite(value))
                        value
                    else
                        0.0;
                }
                self.filters[channel] = trial;
            }
        }

        pub fn magnitude(
            self: *const Self,
            input_index: usize,
            frequency_hz: f64,
        ) f64 {
            if (!self.valid() or input_index >= self.input_count or
                !std.math.isFinite(frequency_hz) or
                frequency_hz < 0.0 or
                frequency_hz > self.config.sample_rate * 0.5)
            {
                return 0.0;
            }
            var result: f64 = 1.0;
            for (self.coefficients[input_index][0..self.section_counts[input_index]]) |section| {
                result *= section.magnitude(
                    self.config.sample_rate,
                    frequency_hz,
                );
                if (!std.math.isFinite(result)) return 0.0;
            }
            return result;
        }

        pub fn valid(self: *const Self) bool {
            validateConfig(self.config) catch return false;
            if (self.input_count == 0 or
                self.input_count > maximum_inputs or
                !std.math.isFinite(self.reference_distance) or
                self.reference_distance <= 0.0)
            {
                return false;
            }
            for (0..self.input_count) |input| {
                const count = self.section_counts[input];
                if (self.orders[input] > maximum_order or
                    count > section_capacity or
                    (self.orders[input] == 0 and count != 0) or
                    (self.orders[input] != 0 and count == 0))
                {
                    return false;
                }
                for (0..count) |section| {
                    const retained = self.filters[input][section];
                    if (!self.coefficients[input][section].valid() or
                        !std.meta.eql(
                            retained.current,
                            self.coefficients[input][section],
                        ) or
                        !std.meta.eql(
                            retained.target,
                            self.coefficients[input][section],
                        ) or
                        !std.meta.eql(
                            retained.step,
                            biquad.Coefficients{ .b0 = 0.0 },
                        ) or
                        retained.remaining != 0 or
                        !std.math.isFinite(
                            retained.z1,
                        ) or
                        !std.math.isFinite(
                            retained.z2,
                        ))
                    {
                        return false;
                    }
                }
            }
            return true;
        }

        fn designOrder(
            order: usize,
            reference_distance: f64,
            config: Config,
            destination: *[section_capacity]biquad.Coefficients,
            destination_count: *u8,
        ) !void {
            if (order == 0) {
                destination_count.* = 0;
                return;
            }
            const base = try scaledReverseBesselPolynomial(order);
            const roots = try base.value.findRoots(.{
                .tolerance = 1.0e-10,
                .maximum_iterations = 2_048,
            });
            if (!roots.converged or roots.count != order)
                return error.AdmHoaRadialRootFailure;

            var count: usize = 0;
            const tolerance = 1.0e-8;
            for (roots.slice()) |scaled_root| {
                const root = scaled_root.mul(
                    std.math.Complex(f64).init(base.root_scale, 0.0),
                );
                if (root.im < -tolerance) continue;
                if (count == section_capacity)
                    return error.AdmHoaRadialSectionCapacityExceeded;
                const numerator_root = bilinearRoot(
                    root,
                    config.speed_of_sound / reference_distance,
                    config.sample_rate,
                );
                const denominator_root = bilinearRoot(
                    root,
                    config.speed_of_sound /
                        config.loudspeaker_distance,
                    config.sample_rate,
                );
                destination[count] = sectionFromRoots(
                    numerator_root,
                    denominator_root,
                    @abs(root.im) > tolerance,
                );
                count += 1;
            }

            const ideal_dc_gain = std.math.pow(
                f64,
                config.loudspeaker_distance / reference_distance,
                @floatFromInt(order),
            );
            switch (config.regularization) {
                .none => {},
                .gain_limit => |limit| {
                    const maximum_gain =
                        std.math.pow(f64, 10.0, limit.maximum_gain_db / 20.0);
                    if (ideal_dc_gain > maximum_gain) {
                        if (count == section_capacity)
                            return error.AdmHoaRadialSectionCapacityExceeded;
                        destination[count] = regularizationSection(
                            maximum_gain / ideal_dc_gain,
                            limit.transition_hz,
                            config.sample_rate,
                        );
                        count += 1;
                    }
                },
            }
            destination_count.* = @intCast(count);
        }

        fn scaledReverseBesselPolynomial(
            order: usize,
        ) !ScaledPolynomial {
            var coefficients: [maximum_order + 1]f64 = @splat(0.0);
            var value: f64 = 1.0;
            for (0..order + 1) |term| {
                coefficients[order - term] = value;
                if (term == order) break;
                value *=
                    @as(f64, @floatFromInt(order + term + 1)) *
                    @as(f64, @floatFromInt(order - term)) /
                    (2.0 * @as(f64, @floatFromInt(term + 1)));
                if (!std.math.isFinite(value))
                    return error.AdmHoaRadialCoefficientOverflow;
            }

            var root_scale: f64 = 1.0;
            for (coefficients[0..order], 0..) |coefficient, power| {
                const distance = order - power;
                const candidate = std.math.pow(
                    f64,
                    @abs(coefficient),
                    1.0 / @as(f64, @floatFromInt(distance)),
                );
                root_scale = @max(root_scale, candidate);
            }
            for (coefficients[0 .. order + 1], 0..) |*coefficient, power| {
                coefficient.* /= std.math.pow(
                    f64,
                    root_scale,
                    @floatFromInt(order - power),
                );
            }
            return .{
                .value = try Polynomial.init(
                    coefficients[0 .. order + 1],
                ),
                .root_scale = root_scale,
            };
        }
    };
}

fn validateConfig(config: Config) !void {
    if (!std.math.isFinite(config.sample_rate) or
        config.sample_rate < 1_000.0 or
        config.sample_rate > 768_000.0 or
        !std.math.isFinite(config.loudspeaker_distance) or
        config.loudspeaker_distance <= 0.0 or
        !std.math.isFinite(config.speed_of_sound) or
        config.speed_of_sound < 250.0 or
        config.speed_of_sound > 400.0)
    {
        return error.InvalidAdmHoaRadialConfig;
    }
    switch (config.regularization) {
        .none => {},
        .gain_limit => |limit| {
            if (!std.math.isFinite(limit.maximum_gain_db) or
                limit.maximum_gain_db < 0.0 or
                limit.maximum_gain_db > 120.0 or
                !std.math.isFinite(limit.transition_hz) or
                limit.transition_hz < 1.0 or
                limit.transition_hz >= config.sample_rate * 0.49)
            {
                return error.InvalidAdmHoaRadialConfig;
            }
        },
    }
}

fn validateBlockKind(block: adm_xml.BlockFormat) !void {
    if (block.identifier.typeLabel() != 0x0004 or
        block.channel_identifier.typeLabel() != 0x0004)
    {
        return error.AdmHoaRadialFilterRequiresHoaBlock;
    }
}

fn bilinearRoot(
    root: std.math.Complex(f64),
    scale: f64,
    sample_rate: f64,
) std.math.Complex(f64) {
    const analog = root.mul(std.math.Complex(f64).init(scale, 0.0));
    const twice_rate = std.math.Complex(f64).init(
        2.0 * sample_rate,
        0.0,
    );
    return twice_rate.add(analog).div(twice_rate.sub(analog));
}

fn sectionFromRoots(
    numerator: std.math.Complex(f64),
    denominator: std.math.Complex(f64),
    conjugate_pair: bool,
) biquad.Coefficients {
    const numerator_first = -if (conjugate_pair)
        2.0 * numerator.re
    else
        numerator.re;
    const numerator_second = if (conjugate_pair)
        numerator.squaredMagnitude()
    else
        0.0;
    const denominator_first = -if (conjugate_pair)
        2.0 * denominator.re
    else
        denominator.re;
    const denominator_second = if (conjugate_pair)
        denominator.squaredMagnitude()
    else
        0.0;
    const numerator_nyquist =
        1.0 - numerator_first + numerator_second;
    const denominator_nyquist =
        1.0 - denominator_first + denominator_second;
    const gain = denominator_nyquist / numerator_nyquist;
    return .{
        .b0 = gain,
        .b1 = numerator_first * gain,
        .b2 = numerator_second * gain,
        .a1 = denominator_first,
        .a2 = denominator_second,
    };
}

fn regularizationSection(
    dc_gain: f64,
    transition_hz: f64,
    sample_rate: f64,
) biquad.Coefficients {
    const warped =
        2.0 * sample_rate *
        @tan(std.math.pi * transition_hz / sample_rate);
    const rate = 2.0 * sample_rate;
    const denominator = rate + warped;
    return .{
        .b0 = (rate + dc_gain * warped) / denominator,
        .b1 = (dc_gain * warped - rate) / denominator,
        .b2 = 0.0,
        .a1 = (warped - rate) / denominator,
        .a2 = 0.0,
    };
}

fn slicesOverlap(
    comptime Sample: type,
    first: anytype,
    second: anytype,
) bool {
    if (first.len == 0 or second.len == 0) return false;
    const first_start = @intFromPtr(first.ptr);
    const second_start = @intFromPtr(second.ptr);
    const first_bytes = std.math.mul(
        usize,
        first.len,
        @sizeOf(Sample),
    ) catch return true;
    const second_bytes = std.math.mul(
        usize,
        second.len,
        @sizeOf(Sample),
    ) catch return true;
    const first_end = std.math.add(
        usize,
        first_start,
        first_bytes,
    ) catch return true;
    const second_end = std.math.add(
        usize,
        second_start,
        second_bytes,
    ) catch return true;
    return first_start < second_end and second_start < first_end;
}

fn sameSlice(
    comptime Sample: type,
    first: []const Sample,
    second: []Sample,
) bool {
    return first.ptr == second.ptr and first.len == second.len;
}

fn hoaBlock(
    order: u32,
    degree: i32,
    reference_distance: f64,
) !adm_xml.BlockFormat {
    return .{
        .identifier = try adm.Identifier.parse("AB_00041001_00000001"),
        .channel_identifier = try adm.Identifier.parse("AC_00041001"),
        .channel_name = null,
        .rtime = try adm_time.Value.parse("0.00000"),
        .rtime_explicit = false,
        .duration = null,
        .hoa_order = order,
        .hoa_degree = degree,
        .hoa_nfc_reference_distance = reference_distance,
    };
}

test "ADM HOA radial filter follows distance adaptation limits" {
    const blocks = [_]adm_xml.BlockFormat{
        try hoaBlock(0, 0, 1.0),
        try hoaBlock(1, -1, 1.0),
        try hoaBlock(2, 0, 1.0),
    };
    var bank = try RadialFilterBank(f64, 3, 4).init(&blocks, .{
        .sample_rate = 48_000.0,
        .loudspeaker_distance = 2.0,
    });
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        bank.magnitude(0, 0.0),
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0),
        bank.magnitude(1, 0.0),
        1.0e-9,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 4.0),
        bank.magnitude(2, 0.0),
        1.0e-8,
    );
    for (0..3) |channel| {
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            bank.magnitude(channel, 24_000.0),
            1.0e-10,
        );
    }
}

test "ADM HOA radial filter designs every supported order" {
    var blocks = [_]adm_xml.BlockFormat{
        try hoaBlock(1, 0, 1.0),
    };
    for (1..17) |order| {
        blocks[0].hoa_order = @intCast(order);
        var bank = RadialFilterBank(f64, 1, 16).init(&blocks, .{
            .sample_rate = 192_000.0,
            .loudspeaker_distance = 1.25,
            .regularization = .{ .gain_limit = .{
                .maximum_gain_db = 24.0,
                .transition_hz = 80.0,
            } },
        }) catch |err| {
            std.debug.print("radial order {d} failed: {s}\n", .{
                order,
                @errorName(err),
            });
            return err;
        };
        try std.testing.expect(bank.valid());
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            bank.magnitude(0, 96_000.0),
            1.0e-10,
        );
    }
}

test "ADM HOA radial gain regularization caps the dc response" {
    const blocks = [_]adm_xml.BlockFormat{
        try hoaBlock(3, 0, 0.5),
    };
    var bank = try RadialFilterBank(f64, 1, 4).init(&blocks, .{
        .sample_rate = 48_000.0,
        .loudspeaker_distance = 2.0,
        .regularization = .{ .gain_limit = .{
            .maximum_gain_db = 12.0,
            .transition_hz = 120.0,
        } },
    });
    try std.testing.expectApproxEqAbs(
        std.math.pow(f64, 10.0, 12.0 / 20.0),
        bank.magnitude(0, 0.0),
        1.0e-8,
    );
    try std.testing.expect(bank.magnitude(0, 5_000.0) > 0.99);
}

test "ADM HOA radial processing is partition independent and transactional" {
    const blocks = [_]adm_xml.BlockFormat{
        try hoaBlock(1, -1, 1.0),
        try hoaBlock(2, 0, 1.0),
    };
    const config = Config{
        .sample_rate = 48_000.0,
        .loudspeaker_distance = 1.5,
        .regularization = .{ .gain_limit = .{
            .maximum_gain_db = 18.0,
            .transition_hz = 80.0,
        } },
    };
    var whole = try RadialFilterBank(f32, 2, 4).init(&blocks, config);
    var split = whole;
    const first = [_]f32{ 1.0, 0.0, -0.25, 0.5, 0.0, 0.0 };
    const second = [_]f32{ 0.0, 1.0, 0.25, -0.5, 0.0, 0.0 };
    var whole_first: [first.len]f32 = undefined;
    var whole_second: [second.len]f32 = undefined;
    try whole.process(
        &.{ &first, &second },
        &.{ &whole_first, &whole_second },
    );

    var split_first: [first.len]f32 = undefined;
    var split_second: [second.len]f32 = undefined;
    try split.process(
        &.{ first[0..2], second[0..2] },
        &.{ split_first[0..2], split_second[0..2] },
    );
    try split.process(
        &.{ first[2..], second[2..] },
        &.{ split_first[2..], split_second[2..] },
    );
    try std.testing.expectEqualSlices(f32, &whole_first, &split_first);
    try std.testing.expectEqualSlices(f32, &whole_second, &split_second);

    const before = split;
    try std.testing.expectError(
        error.AdmHoaRadialBufferLengthMismatch,
        split.process(
            &.{ &first, &second },
            &.{ split_first[0..5], &split_second },
        ),
    );
    try std.testing.expectEqualDeep(before, split);
}

test "ADM HOA radial filter rejects malformed policy and retained state" {
    var blocks = [_]adm_xml.BlockFormat{
        try hoaBlock(1, 0, 1.0),
    };
    try std.testing.expectError(
        error.InvalidAdmHoaRadialConfig,
        RadialFilterBank(f64, 1, 4).init(&blocks, .{
            .sample_rate = 0.0,
            .loudspeaker_distance = 1.0,
        }),
    );
    blocks[0].screen_ref = true;
    try std.testing.expectError(
        error.UnsupportedAdmHoaRadialScreenReference,
        RadialFilterBank(f64, 1, 4).init(&blocks, .{
            .sample_rate = 48_000.0,
            .loudspeaker_distance = 1.0,
        }),
    );
    const screen_referenced =
        try RadialFilterBank(f64, 1, 4).init(&blocks, .{
            .sample_rate = 48_000.0,
            .loudspeaker_distance = 1.0,
            .screen_reference_policy = .render_unchanged,
        });
    try std.testing.expect(screen_referenced.screen_reference);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        screen_referenced.magnitude(0, 0.0),
        1.0e-12,
    );
    blocks[0].screen_ref = false;
    blocks[0].hoa_degree = 2;
    try std.testing.expectError(
        error.InvalidAdmHoaDegree,
        RadialFilterBank(f64, 1, 4).init(&blocks, .{
            .sample_rate = 48_000.0,
            .loudspeaker_distance = 1.0,
        }),
    );
    blocks[0].hoa_degree = 0;
    var bank = try RadialFilterBank(f64, 1, 4).init(&blocks, .{
        .sample_rate = 48_000.0,
        .loudspeaker_distance = 1.0,
    });
    bank.filters[0][0].z1 = std.math.nan(f64);
    var input = [_]f64{1.0};
    var output = [_]f64{7.0};
    try std.testing.expectError(
        error.InvalidAdmHoaRadialState,
        bank.process(&.{&input}, &.{&output}),
    );
    try std.testing.expectEqual(@as(f64, 7.0), output[0]);

    bank = try RadialFilterBank(f64, 1, 4).init(&blocks, .{
        .sample_rate = 48_000.0,
        .loudspeaker_distance = 1.0,
    });
    bank.filters[0][0].remaining = 1;
    try std.testing.expectError(
        error.InvalidAdmHoaRadialState,
        bank.process(&.{&input}, &.{&output}),
    );
}
