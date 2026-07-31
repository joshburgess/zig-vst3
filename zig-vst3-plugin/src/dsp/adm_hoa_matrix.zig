const std = @import("std");
const adm_hoa_decoder = @import("adm_hoa_decoder.zig");
const adm_xml = @import("adm_xml.zig");
const matrix = @import("matrix.zig");

pub const Loudspeaker = struct {
    azimuth_degrees: f64,
    elevation_degrees: f64,
    is_lfe: bool = false,
};

pub const OrderWeighting = enum {
    basic,
    max_re,
};

pub const GenerationOptions = struct {
    order_weighting: OrderWeighting = .basic,
    screen_reference_policy: adm_hoa_decoder.ScreenReferencePolicy = .reject,
    convergence_tolerance: f64 = 1.0e-12,
    relative_rank_tolerance: f64 = 1.0e-10,
    maximum_sweeps: usize = 128,
};

/// Builds a far-field HOA decode matrix for a caller-defined loudspeaker layout.
///
/// The non-realtime SVD solve matches the supplied real spherical-harmonic
/// components in the minimum-norm sense. LFE outputs remain silent.
pub fn LoudspeakerMatrix(
    comptime Sample: type,
    comptime maximum_inputs: usize,
    comptime maximum_outputs: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("LoudspeakerMatrix supports f32 and f64 coefficients");
    if (maximum_inputs == 0)
        @compileError("LoudspeakerMatrix requires input capacity");
    if (maximum_outputs == 0)
        @compileError("LoudspeakerMatrix requires output capacity");
    if (maximum_inputs >
        std.math.maxInt(usize) / maximum_outputs)
    {
        @compileError("LoudspeakerMatrix coefficient capacity is too large");
    }

    return struct {
        const Self = @This();
        const Basis = matrix.Matrix(
            f64,
            maximum_inputs,
            maximum_outputs,
        );
        const Decomposition = matrix.SvdDecomposition(
            f64,
            maximum_inputs,
            maximum_outputs,
        );

        pub const input_capacity = maximum_inputs;
        pub const output_capacity = maximum_outputs;

        input_count: usize,
        output_count: usize,
        non_lfe_output_count: usize,
        rank: usize,
        maximum_order: u8,
        normalization: adm_xml.HoaNormalization,
        nfc_reference_distance: f64,
        screen_reference: bool,
        order_weighting: OrderWeighting,
        condition_number: f64,
        orders: [maximum_inputs]u8 = undefined,
        degrees: [maximum_inputs]i8 = undefined,
        lfe_outputs: [maximum_outputs]bool = @splat(false),
        coefficients: [maximum_inputs * maximum_outputs]Sample =
            @splat(0.0),

        pub fn init(
            blocks: []const adm_xml.BlockFormat,
            loudspeakers: []const Loudspeaker,
            options: GenerationOptions,
        ) !Self {
            if (blocks.len == 0 or blocks.len > maximum_inputs)
                return error.InvalidAdmHoaInputCount;
            if (loudspeakers.len == 0 or
                loudspeakers.len > maximum_outputs)
            {
                return error.InvalidAdmHoaOutputCount;
            }
            try validateOptions(options);

            const metadata = try analyzeBlocks(
                blocks,
                options.screen_reference_policy,
            );
            var directions: [maximum_outputs][3]f64 =
                @splat(@splat(0.0));
            var non_lfe_count: usize = 0;
            for (loudspeakers, 0..) |loudspeaker, output_index| {
                directions[output_index] =
                    try loudspeakerDirection(loudspeaker);
                if (loudspeaker.is_lfe) continue;
                for (loudspeakers[0..output_index], 0..) |
                    previous,
                    previous_index,
                | {
                    if (previous.is_lfe) continue;
                    if (sameDirection(
                        directions[previous_index],
                        directions[output_index],
                    )) {
                        return error.DuplicateAdmHoaLoudspeakerDirection;
                    }
                }
                non_lfe_count += 1;
            }
            if (non_lfe_count < blocks.len)
                return error.InsufficientAdmHoaLoudspeakers;

            var basis = Basis.zero();
            for (blocks, 0..) |block, input_index| {
                const order =
                    block.hoa_order orelse
                    return error.MissingAdmHoaOrder;
                const degree =
                    block.hoa_degree orelse
                    return error.MissingAdmHoaDegree;
                for (loudspeakers, 0..) |loudspeaker, output_index| {
                    if (loudspeaker.is_lfe) continue;
                    basis.values[input_index][output_index] =
                        try realSphericalHarmonic(
                            metadata.normalization,
                            order,
                            degree,
                            loudspeaker.azimuth_degrees,
                            loudspeaker.elevation_degrees,
                        );
                }
            }

            const decomposition = try Decomposition.init(basis, .{
                .convergence_tolerance = options.convergence_tolerance,
                .relative_rank_tolerance = options.relative_rank_tolerance,
                .maximum_sweeps = options.maximum_sweeps,
            });
            if (!decomposition.converged)
                return error.AdmHoaMatrixDidNotConverge;
            if (decomposition.rank != blocks.len)
                return error.RankDeficientAdmHoaLoudspeakerLayout;
            const smallest =
                decomposition.singular_values[blocks.len - 1];
            const condition_number =
                decomposition.singular_values[0] / smallest;
            if (!std.math.isFinite(condition_number) or
                condition_number < 1.0)
            {
                return error.InvalidAdmHoaMatrixCondition;
            }

            const inverse = try decomposition.pseudoinverse();
            var result = Self{
                .input_count = blocks.len,
                .output_count = loudspeakers.len,
                .non_lfe_output_count = non_lfe_count,
                .rank = decomposition.rank,
                .maximum_order = metadata.maximum_order,
                .normalization = metadata.normalization,
                .nfc_reference_distance = metadata.nfc_reference_distance,
                .screen_reference = metadata.screen_reference,
                .order_weighting = options.order_weighting,
                .condition_number = condition_number,
            };
            for (blocks, 0..) |block, input_index| {
                const order =
                    block.hoa_order orelse
                    return error.MissingAdmHoaOrder;
                const degree =
                    block.hoa_degree orelse
                    return error.MissingAdmHoaDegree;
                result.orders[input_index] =
                    @intCast(order);
                result.degrees[input_index] =
                    @intCast(degree);
            }
            for (loudspeakers, 0..) |loudspeaker, output_index| {
                result.lfe_outputs[output_index] = loudspeaker.is_lfe;
                for (blocks, 0..) |block, input_index| {
                    const order =
                        block.hoa_order orelse
                        return error.MissingAdmHoaOrder;
                    const weight = orderWeight(
                        options.order_weighting,
                        metadata.maximum_order,
                        order,
                    );
                    const value =
                        inverse.values[output_index][input_index] *
                        weight;
                    const converted: Sample = @floatCast(value);
                    if (!std.math.isFinite(converted))
                        return error.InvalidAdmHoaCoefficient;
                    result.coefficients[
                        output_index * blocks.len + input_index
                    ] = converted;
                }
            }
            if (!result.valid())
                return error.InvalidAdmHoaLoudspeakerMatrix;
            return result;
        }

        pub fn coefficient(
            self: *const Self,
            output_index: usize,
            input_index: usize,
        ) !Sample {
            if (!self.valid())
                return error.InvalidAdmHoaLoudspeakerMatrix;
            if (output_index >= self.output_count)
                return error.AdmHoaOutputIndexOutOfRange;
            if (input_index >= self.input_count)
                return error.AdmHoaInputIndexOutOfRange;
            return self.coefficients[
                output_index * self.input_count + input_index
            ];
        }

        pub fn coefficientSlice(self: *const Self) ![]const Sample {
            if (!self.valid())
                return error.InvalidAdmHoaLoudspeakerMatrix;
            return self.coefficients[0 .. self.output_count * self.input_count];
        }

        pub fn decoder(
            self: *const Self,
            blocks: []const adm_xml.BlockFormat,
        ) !adm_hoa_decoder.MatrixDecoder(
            Sample,
            maximum_inputs,
            maximum_outputs,
        ) {
            if (!self.valid())
                return error.InvalidAdmHoaLoudspeakerMatrix;
            if (!self.matchesBlocks(blocks))
                return error.AdmHoaMatrixComponentMismatch;
            return adm_hoa_decoder.MatrixDecoder(
                Sample,
                maximum_inputs,
                maximum_outputs,
            ).init(
                blocks,
                self.output_count,
                try self.coefficientSlice(),
            );
        }

        pub fn valid(self: *const Self) bool {
            if (self.input_count == 0 or
                self.input_count > maximum_inputs or
                self.output_count == 0 or
                self.output_count > maximum_outputs or
                self.non_lfe_output_count < self.input_count or
                self.non_lfe_output_count > self.output_count or
                self.rank != self.input_count or
                self.maximum_order >
                    adm_hoa_decoder.maximum_supported_order or
                !std.math.isFinite(self.nfc_reference_distance) or
                self.nfc_reference_distance < 0.0 or
                !std.math.isFinite(self.condition_number) or
                self.condition_number < 1.0)
            {
                return false;
            }
            var observed_maximum_order: u8 = 0;
            for (
                self.orders[0..self.input_count],
                self.degrees[0..self.input_count],
                0..,
            ) |order, degree, input_index| {
                if (order > adm_hoa_decoder.maximum_supported_order or
                    degree < -@as(i16, order) or
                    degree > @as(i16, order) or
                    (self.normalization == .fuma and order > 3))
                {
                    return false;
                }
                for (
                    self.orders[0..input_index],
                    self.degrees[0..input_index],
                ) |previous_order, previous_degree| {
                    if (previous_order == order and
                        previous_degree == degree)
                    {
                        return false;
                    }
                }
                observed_maximum_order =
                    @max(observed_maximum_order, order);
            }
            if (observed_maximum_order != self.maximum_order)
                return false;
            var counted_non_lfe: usize = 0;
            for (self.lfe_outputs[0..self.output_count], 0..) |
                is_lfe,
                output_index,
            | {
                if (!is_lfe) counted_non_lfe += 1;
                for (0..self.input_count) |input_index| {
                    const value = self.coefficients[
                        output_index * self.input_count + input_index
                    ];
                    if (!std.math.isFinite(value) or
                        (is_lfe and value != 0.0))
                    {
                        return false;
                    }
                }
            }
            return counted_non_lfe == self.non_lfe_output_count;
        }

        fn matchesBlocks(
            self: *const Self,
            blocks: []const adm_xml.BlockFormat,
        ) bool {
            if (blocks.len != self.input_count) return false;
            const metadata = analyzeBlocks(
                blocks,
                .render_unchanged,
            ) catch return false;
            if (metadata.normalization != self.normalization or
                metadata.nfc_reference_distance !=
                    self.nfc_reference_distance or
                metadata.screen_reference != self.screen_reference or
                metadata.maximum_order != self.maximum_order)
            {
                return false;
            }
            for (blocks, 0..) |block, input_index| {
                const order =
                    block.hoa_order orelse return false;
                const degree =
                    block.hoa_degree orelse return false;
                if (order != self.orders[input_index] or
                    degree != self.degrees[input_index])
                {
                    return false;
                }
            }
            return true;
        }
    };
}

pub fn realSphericalHarmonic(
    normalization: adm_xml.HoaNormalization,
    order: u32,
    degree: i32,
    azimuth_degrees: f64,
    elevation_degrees: f64,
) !f64 {
    if (order > adm_hoa_decoder.maximum_supported_order)
        return error.UnsupportedAdmHoaOrder;
    const signed_order: i64 = @intCast(order);
    if (@as(i64, degree) < -signed_order or
        @as(i64, degree) > signed_order)
    {
        return error.InvalidAdmHoaDegree;
    }
    if (normalization == .fuma and order > 3)
        return error.UnsupportedAdmHoaFumaOrder;
    if (!validAngles(azimuth_degrees, elevation_degrees))
        return error.InvalidAdmHoaLoudspeakerDirection;

    const absolute_degree: u32 = @intCast(@abs(degree));
    const elevation_radians =
        elevation_degrees * std.math.pi / 180.0;
    const azimuth_radians =
        azimuth_degrees * std.math.pi / 180.0;
    const legendre = try associatedLegendre(
        order,
        absolute_degree,
        @sin(elevation_radians),
    );
    const angular = if (degree < 0)
        @sin(
            @as(f64, @floatFromInt(absolute_degree)) *
                azimuth_radians,
        )
    else if (degree > 0)
        @cos(
            @as(f64, @floatFromInt(absolute_degree)) *
                azimuth_radians,
        )
    else
        1.0;
    const value =
        try normalizationFactor(
            normalization,
            order,
            absolute_degree,
        ) *
        legendre *
        angular;
    if (!std.math.isFinite(value))
        return error.InvalidAdmHoaBasisValue;
    return value;
}

const BlockMetadata = struct {
    normalization: adm_xml.HoaNormalization,
    nfc_reference_distance: f64,
    screen_reference: bool,
    maximum_order: u8,
};

fn analyzeBlocks(
    blocks: []const adm_xml.BlockFormat,
    screen_reference_policy: adm_hoa_decoder.ScreenReferencePolicy,
) !BlockMetadata {
    const first = blocks[0];
    try validateBlockKind(first);
    if (first.hoa_equation != null)
        return error.UnsupportedAdmHoaEquation;
    if (first.screen_ref and screen_reference_policy == .reject)
        return error.UnsupportedAdmHoaScreenReference;
    if (!std.math.isFinite(first.hoa_nfc_reference_distance) or
        first.hoa_nfc_reference_distance < 0.0)
    {
        return error.InvalidAdmHoaReferenceDistance;
    }

    var result = BlockMetadata{
        .normalization = first.hoa_normalization,
        .nfc_reference_distance = first.hoa_nfc_reference_distance,
        .screen_reference = first.screen_ref,
        .maximum_order = 0,
    };
    for (blocks, 0..) |block, input_index| {
        try validateBlockKind(block);
        if (block.hoa_equation != null)
            return error.UnsupportedAdmHoaEquation;
        if (block.hoa_normalization != result.normalization)
            return error.MixedAdmHoaNormalization;
        if (!std.math.isFinite(block.hoa_nfc_reference_distance) or
            block.hoa_nfc_reference_distance < 0.0)
        {
            return error.InvalidAdmHoaReferenceDistance;
        }
        if (block.hoa_nfc_reference_distance !=
            result.nfc_reference_distance)
        {
            return error.MixedAdmHoaReferenceDistance;
        }
        if (block.screen_ref != result.screen_reference)
            return error.MixedAdmHoaScreenReference;

        const order =
            block.hoa_order orelse return error.MissingAdmHoaOrder;
        const degree =
            block.hoa_degree orelse return error.MissingAdmHoaDegree;
        if (order > adm_hoa_decoder.maximum_supported_order)
            return error.UnsupportedAdmHoaOrder;
        const signed_order: i64 = @intCast(order);
        if (@as(i64, degree) < -signed_order or
            @as(i64, degree) > signed_order)
        {
            return error.InvalidAdmHoaDegree;
        }
        if (result.normalization == .fuma and order > 3)
            return error.UnsupportedAdmHoaFumaOrder;
        for (blocks[0..input_index]) |previous| {
            if (previous.hoa_order == block.hoa_order and
                previous.hoa_degree == block.hoa_degree)
            {
                return error.DuplicateAdmHoaComponent;
            }
        }
        result.maximum_order = @max(
            result.maximum_order,
            @as(u8, @intCast(order)),
        );
    }
    return result;
}

fn validateOptions(options: GenerationOptions) !void {
    if (!std.math.isFinite(options.convergence_tolerance) or
        options.convergence_tolerance <= 0.0 or
        options.convergence_tolerance >= 1.0 or
        !std.math.isFinite(options.relative_rank_tolerance) or
        options.relative_rank_tolerance < 0.0 or
        options.relative_rank_tolerance >= 1.0 or
        options.maximum_sweeps == 0)
    {
        return error.InvalidAdmHoaMatrixGenerationOptions;
    }
}

fn validateBlockKind(block: adm_xml.BlockFormat) !void {
    if (block.identifier.typeLabel() != 0x0004 or
        block.channel_identifier.typeLabel() != 0x0004)
    {
        return error.AdmHoaDecoderRequiresHoaBlock;
    }
}

fn loudspeakerDirection(
    loudspeaker: Loudspeaker,
) ![3]f64 {
    if (!validAngles(
        loudspeaker.azimuth_degrees,
        loudspeaker.elevation_degrees,
    )) {
        return error.InvalidAdmHoaLoudspeakerDirection;
    }
    const azimuth =
        loudspeaker.azimuth_degrees * std.math.pi / 180.0;
    const elevation =
        loudspeaker.elevation_degrees * std.math.pi / 180.0;
    const horizontal = @cos(elevation);
    return .{
        horizontal * @cos(azimuth),
        horizontal * @sin(azimuth),
        @sin(elevation),
    };
}

fn validAngles(
    azimuth_degrees: f64,
    elevation_degrees: f64,
) bool {
    return std.math.isFinite(azimuth_degrees) and
        azimuth_degrees >= -180.0 and
        azimuth_degrees <= 180.0 and
        std.math.isFinite(elevation_degrees) and
        elevation_degrees >= -90.0 and
        elevation_degrees <= 90.0;
}

fn sameDirection(first: [3]f64, second: [3]f64) bool {
    const dot =
        first[0] * second[0] +
        first[1] * second[1] +
        first[2] * second[2];
    return dot >= 1.0 - 1.0e-12;
}

fn associatedLegendre(
    order: u32,
    degree: u32,
    x: f64,
) !f64 {
    if (!std.math.isFinite(x) or x < -1.0 or x > 1.0 or
        degree > order)
    {
        return error.InvalidAdmHoaBasisValue;
    }
    if (degree == 0 and order == 0) return 1.0;

    const radial = @sqrt(@max(0.0, 1.0 - x * x));
    var diagonal: f64 = 1.0;
    for (1..degree + 1) |index| {
        diagonal *=
            @as(f64, @floatFromInt(2 * index - 1)) * radial;
        if (!std.math.isFinite(diagonal))
            return error.InvalidAdmHoaBasisValue;
    }
    if (order == degree) return diagonal;

    var previous_previous = diagonal;
    var previous =
        @as(f64, @floatFromInt(2 * degree + 1)) *
        x *
        diagonal;
    if (!std.math.isFinite(previous))
        return error.InvalidAdmHoaBasisValue;
    if (order == degree + 1) return previous;

    var current_order = degree + 2;
    while (current_order <= order) : (current_order += 1) {
        const current =
            (@as(f64, @floatFromInt(2 * current_order - 1)) *
                x *
                previous -
                @as(
                    f64,
                    @floatFromInt(current_order + degree - 1),
                ) *
                    previous_previous) /
            @as(f64, @floatFromInt(current_order - degree));
        if (!std.math.isFinite(current))
            return error.InvalidAdmHoaBasisValue;
        previous_previous = previous;
        previous = current;
    }
    return previous;
}

fn normalizationFactor(
    normalization: adm_xml.HoaNormalization,
    order: u32,
    degree: u32,
) !f64 {
    var factorial_ratio: f64 = 1.0;
    if (degree != 0) {
        var factor = order - degree + 1;
        while (factor <= order + degree) : (factor += 1)
            factorial_ratio /= @as(f64, @floatFromInt(factor));
    }
    const repeated_degree: f64 = if (degree == 0) 1.0 else 2.0;
    const sn3d = @sqrt(repeated_degree * factorial_ratio);
    const scale: f64 = switch (normalization) {
        .sn3d => 1.0,
        .n3d => @sqrt(
            @as(f64, @floatFromInt(2 * order + 1)),
        ),
        .fuma => try fumaScale(order, degree),
    };
    const result = sn3d * scale;
    if (!std.math.isFinite(result))
        return error.InvalidAdmHoaBasisValue;
    return result;
}

fn fumaScale(order: u32, degree: u32) !f64 {
    return switch (order) {
        0 => 1.0 / @sqrt(2.0),
        1 => 1.0,
        2 => if (degree == 0) 1.0 else 2.0 / @sqrt(3.0),
        3 => switch (degree) {
            0 => 1.0,
            1 => @sqrt(45.0 / 32.0),
            2 => 3.0 / @sqrt(5.0),
            3 => @sqrt(8.0 / 5.0),
            else => return error.InvalidAdmHoaDegree,
        },
        else => error.UnsupportedAdmHoaFumaOrder,
    };
}

fn orderWeight(
    weighting: OrderWeighting,
    maximum_order: u8,
    order: u32,
) f64 {
    return switch (weighting) {
        .basic => 1.0,
        .max_re => if (maximum_order == 0)
            1.0
        else
            legendrePolynomial(
                order,
                @cos(
                    (137.9 /
                        (@as(
                            f64,
                            @floatFromInt(maximum_order),
                        ) +
                            1.51)) *
                        std.math.pi / 180.0,
                ),
            ),
    };
}

fn legendrePolynomial(order: u32, x: f64) f64 {
    if (order == 0) return 1.0;
    if (order == 1) return x;
    var previous_previous: f64 = 1.0;
    var previous = x;
    for (2..order + 1) |current_order| {
        const current =
            (@as(f64, @floatFromInt(2 * current_order - 1)) *
                x *
                previous -
                @as(f64, @floatFromInt(current_order - 1)) *
                    previous_previous) /
            @as(f64, @floatFromInt(current_order));
        previous_previous = previous;
        previous = current;
    }
    return previous;
}

test "HOA basis follows ACN SN3D N3D and FuMa conventions" {
    const root_three = @sqrt(3.0);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        try realSphericalHarmonic(.sn3d, 0, 0, 37.0, -12.0),
        1.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        try realSphericalHarmonic(.sn3d, 1, 1, 0.0, 0.0),
        1.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        root_three,
        try realSphericalHarmonic(.n3d, 1, 1, 0.0, 0.0),
        1.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        1.0 / @sqrt(2.0),
        try realSphericalHarmonic(.fuma, 0, 0, 0.0, 0.0),
        1.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        try realSphericalHarmonic(.sn3d, 1, -1, 90.0, 0.0),
        1.0e-14,
    );

    const azimuth = 30.0;
    const elevation = 20.0;
    const azimuth_radians = azimuth * std.math.pi / 180.0;
    const elevation_radians = elevation * std.math.pi / 180.0;
    const x =
        @cos(elevation_radians) * @cos(azimuth_radians);
    const y =
        @cos(elevation_radians) * @sin(azimuth_radians);
    const z = @sin(elevation_radians);
    try std.testing.expectApproxEqAbs(
        0.5 * (3.0 * z * z - 1.0),
        try realSphericalHarmonic(
            .sn3d,
            2,
            0,
            azimuth,
            elevation,
        ),
        1.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        @sqrt(3.0) * x * z,
        try realSphericalHarmonic(
            .sn3d,
            2,
            1,
            azimuth,
            elevation,
        ),
        1.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        @sqrt(3.0) * y * z,
        try realSphericalHarmonic(
            .sn3d,
            2,
            -1,
            azimuth,
            elevation,
        ),
        1.0e-14,
    );
    for (0..adm_hoa_decoder.maximum_supported_order + 1) |
        order,
    | {
        const signed_order: i32 = @intCast(order);
        var degree = -signed_order;
        while (degree <= signed_order) : (degree += 1) {
            try std.testing.expect(std.math.isFinite(
                try realSphericalHarmonic(
                    .sn3d,
                    @intCast(order),
                    degree,
                    23.0,
                    -17.0,
                ),
            ));
            try std.testing.expect(std.math.isFinite(
                try realSphericalHarmonic(
                    .n3d,
                    @intCast(order),
                    degree,
                    -180.0,
                    90.0,
                ),
            ));
        }
    }
}

test "HOA loudspeaker matrix mode matches a tetrahedron" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
        \\      <order>0</order><degree>0</degree>
        \\      <normalization>SN3D</normalization>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041002">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041002_00000001">
        \\      <order>1</order><degree>-1</degree>
        \\      <normalization>SN3D</normalization>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041003">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041003_00000001">
        \\      <order>1</order><degree>0</degree>
        \\      <normalization>SN3D</normalization>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041004">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041004_00000001">
        \\      <order>1</order><degree>1</degree>
        \\      <normalization>SN3D</normalization>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    var blocks: [4]adm_xml.BlockFormat = undefined;
    for (&blocks) |*block| block.* = (try iterator.next()).?;
    const elevation = 35.264_389_682_754_654;
    const loudspeakers = [_]Loudspeaker{
        .{ .azimuth_degrees = 45.0, .elevation_degrees = elevation },
        .{ .azimuth_degrees = -135.0, .elevation_degrees = elevation },
        .{ .azimuth_degrees = -45.0, .elevation_degrees = -elevation },
        .{ .azimuth_degrees = 135.0, .elevation_degrees = -elevation },
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0, .is_lfe = true },
    };
    const Matrix = LoudspeakerMatrix(f64, 4, 5);
    var generated = try Matrix.init(
        &blocks,
        &loudspeakers,
        .{},
    );
    try std.testing.expect(generated.valid());
    try std.testing.expectEqual(@as(usize, 4), generated.rank);
    try std.testing.expectEqual(
        @as(usize, 4),
        generated.non_lfe_output_count,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, @sqrt(3.0)),
        generated.condition_number,
        1.0e-12,
    );

    const directional = @sqrt(3.0) / 4.0;
    const expected = [_][4]f64{
        .{ 0.25, directional, directional, directional },
        .{ 0.25, -directional, directional, -directional },
        .{ 0.25, -directional, -directional, directional },
        .{ 0.25, directional, -directional, -directional },
        .{ 0.0, 0.0, 0.0, 0.0 },
    };
    for (expected, 0..) |row, output_index| {
        for (row, 0..) |value, input_index| {
            try std.testing.expectApproxEqAbs(
                value,
                try generated.coefficient(output_index, input_index),
                1.0e-12,
            );
        }
    }

    const decoder = try generated.decoder(&blocks);
    const input = [_]f64{ 1.0, 0.0, 0.0, 0.0 };
    var output: [5]f64 = undefined;
    try decoder.processSample(&input, &output);
    try std.testing.expectEqualDeep(
        [_]f64{ 0.25, 0.25, 0.25, 0.25, 0.0 },
        output,
    );
    std.mem.swap(
        adm_xml.BlockFormat,
        &blocks[0],
        &blocks[1],
    );
    try std.testing.expectError(
        error.AdmHoaMatrixComponentMismatch,
        generated.decoder(&blocks),
    );
    std.mem.swap(
        adm_xml.BlockFormat,
        &blocks[0],
        &blocks[1],
    );

    blocks[0].hoa_normalization = .n3d;
    blocks[1].hoa_normalization = .n3d;
    blocks[2].hoa_normalization = .n3d;
    blocks[3].hoa_normalization = .n3d;
    generated = try Matrix.init(&blocks, &loudspeakers, .{});
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.25),
        try generated.coefficient(0, 1),
        1.0e-12,
    );
}

test "HOA loudspeaker matrix applies max-rE order weighting" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
        \\      <order>0</order><degree>0</degree>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041002">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041002_00000001">
        \\      <order>1</order><degree>1</degree>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    const blocks = [_]adm_xml.BlockFormat{
        (try iterator.next()).?,
        (try iterator.next()).?,
    };
    const loudspeakers = [_]Loudspeaker{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 },
        .{ .azimuth_degrees = 180.0, .elevation_degrees = 0.0 },
    };
    const Matrix = LoudspeakerMatrix(f32, 2, 2);
    const basic = try Matrix.init(&blocks, &loudspeakers, .{});
    const weighted = try Matrix.init(
        &blocks,
        &loudspeakers,
        .{ .order_weighting = .max_re },
    );
    const expected_weight = @cos(
        (137.9 / 2.51) * std.math.pi / 180.0,
    );
    try std.testing.expectApproxEqAbs(
        try basic.coefficient(0, 0),
        try weighted.coefficient(0, 0),
        1.0e-6,
    );
    try std.testing.expectApproxEqAbs(
        (try basic.coefficient(0, 1)) *
            @as(f32, @floatCast(expected_weight)),
        try weighted.coefficient(0, 1),
        1.0e-6,
    );
}

test "HOA loudspeaker matrix applies explicit screen reference policy" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
        \\      <order>0</order><degree>0</degree>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041002">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041002_00000001">
        \\      <order>1</order><degree>0</degree>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    var blocks = [_]adm_xml.BlockFormat{
        (try iterator.next()).?,
        (try iterator.next()).?,
    };
    const loudspeakers = [_]Loudspeaker{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 45.0 },
        .{ .azimuth_degrees = 180.0, .elevation_degrees = -45.0 },
    };
    const Matrix = LoudspeakerMatrix(f64, 2, 2);
    const ordinary = try Matrix.init(&blocks, &loudspeakers, .{});

    blocks[0].screen_ref = true;
    blocks[1].screen_ref = true;
    try std.testing.expectError(
        error.UnsupportedAdmHoaScreenReference,
        Matrix.init(&blocks, &loudspeakers, .{}),
    );
    const screen_referenced = try Matrix.init(
        &blocks,
        &loudspeakers,
        .{ .screen_reference_policy = .render_unchanged },
    );
    try std.testing.expect(screen_referenced.screen_reference);
    try std.testing.expectEqualSlices(
        f64,
        try ordinary.coefficientSlice(),
        try screen_referenced.coefficientSlice(),
    );
    const decoder = try screen_referenced.decoder(&blocks);
    try std.testing.expect(decoder.screen_reference);

    blocks[1].screen_ref = false;
    try std.testing.expectError(
        error.MixedAdmHoaScreenReference,
        Matrix.init(
            &blocks,
            &loudspeakers,
            .{ .screen_reference_policy = .render_unchanged },
        ),
    );
}

test "HOA loudspeaker matrix reconstructs an irregular third-order basis" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
        \\      <order>0</order><degree>0</degree>
        \\      <normalization>SN3D</normalization>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    const prototype = (try iterator.next()).?;
    var blocks: [16]adm_xml.BlockFormat = undefined;
    var component_index: usize = 0;
    for (0..4) |order| {
        const signed_order: i32 = @intCast(order);
        var degree = -signed_order;
        while (degree <= signed_order) : (degree += 1) {
            blocks[component_index] = prototype;
            blocks[component_index].hoa_order = @intCast(order);
            blocks[component_index].hoa_degree = degree;
            component_index += 1;
        }
    }

    var loudspeakers: [20]Loudspeaker = undefined;
    const golden_angle = 137.507_764_050_037_85;
    for (&loudspeakers, 0..) |*loudspeaker, index| {
        const z =
            1.0 -
            2.0 *
                (@as(f64, @floatFromInt(index)) + 0.5) /
                @as(f64, @floatFromInt(loudspeakers.len));
        const unwrapped =
            @as(f64, @floatFromInt(index)) * golden_angle;
        loudspeaker.* = .{
            .azimuth_degrees = @mod(unwrapped + 180.0, 360.0) - 180.0,
            .elevation_degrees = std.math.asin(z) * 180.0 / std.math.pi,
        };
    }
    const Matrix = LoudspeakerMatrix(f64, 16, 20);
    const generated = try Matrix.init(
        &blocks,
        &loudspeakers,
        .{},
    );
    try std.testing.expect(generated.condition_number < 4.0);

    for (blocks, 0..) |target, target_index| {
        for (blocks, 0..) |_, source_index| {
            var reconstructed: f64 = 0.0;
            for (loudspeakers, 0..) |loudspeaker, output_index| {
                reconstructed +=
                    try realSphericalHarmonic(
                        .sn3d,
                        target.hoa_order.?,
                        target.hoa_degree.?,
                        loudspeaker.azimuth_degrees,
                        loudspeaker.elevation_degrees,
                    ) *
                    try generated.coefficient(
                        output_index,
                        source_index,
                    );
            }
            try std.testing.expectApproxEqAbs(
                @as(
                    f64,
                    if (target_index == source_index) 1.0 else 0.0,
                ),
                reconstructed,
                1.0e-10,
            );
        }
    }
}

test "HOA loudspeaker matrix rejects malformed layouts transactionally" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
        \\      <order>0</order><degree>0</degree>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041002">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041002_00000001">
        \\      <order>1</order><degree>0</degree>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    var blocks = [_]adm_xml.BlockFormat{
        (try iterator.next()).?,
        (try iterator.next()).?,
    };
    const Matrix = LoudspeakerMatrix(f64, 2, 3);
    const one = [_]Loudspeaker{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 },
    };
    try std.testing.expectError(
        error.InsufficientAdmHoaLoudspeakers,
        Matrix.init(&blocks, &one, .{}),
    );
    const duplicate = [_]Loudspeaker{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 90.0 },
        .{ .azimuth_degrees = 90.0, .elevation_degrees = 90.0 },
    };
    try std.testing.expectError(
        error.DuplicateAdmHoaLoudspeakerDirection,
        Matrix.init(&blocks, &duplicate, .{}),
    );
    const equator = [_]Loudspeaker{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 },
        .{ .azimuth_degrees = 180.0, .elevation_degrees = 0.0 },
    };
    try std.testing.expectError(
        error.RankDeficientAdmHoaLoudspeakerLayout,
        Matrix.init(&blocks, &equator, .{}),
    );
    var invalid = equator;
    invalid[1].azimuth_degrees = std.math.nan(f64);
    try std.testing.expectError(
        error.InvalidAdmHoaLoudspeakerDirection,
        Matrix.init(&blocks, &invalid, .{}),
    );
    try std.testing.expectError(
        error.InvalidAdmHoaMatrixGenerationOptions,
        Matrix.init(
            &blocks,
            &equator,
            .{ .maximum_sweeps = 0 },
        ),
    );

    blocks[0].screen_ref = true;
    try std.testing.expectError(
        error.UnsupportedAdmHoaScreenReference,
        Matrix.init(&blocks, &equator, .{}),
    );
    blocks[0].screen_ref = false;
    const vertical = [_]Loudspeaker{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 45.0 },
        .{ .azimuth_degrees = 180.0, .elevation_degrees = -45.0 },
    };
    var generated = try Matrix.init(&blocks, &vertical, .{});
    try std.testing.expectError(
        error.AdmHoaOutputIndexOutOfRange,
        generated.coefficient(2, 0),
    );
    generated.coefficients[0] = std.math.nan(f64);
    try std.testing.expect(!generated.valid());
    try std.testing.expectError(
        error.InvalidAdmHoaLoudspeakerMatrix,
        generated.decoder(&blocks),
    );
    try std.testing.expectError(
        error.InvalidAdmHoaLoudspeakerMatrix,
        generated.coefficientSlice(),
    );
}
