const std = @import("std");

pub const maximum_outputs: usize = 64;
pub const maximum_vertices: usize = 128;
pub const maximum_regions: usize = 256;
const region_tolerance: f64 = 1.0e-9;

pub const Vector = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,
    z: f64 = 0.0,
};

pub const PolarPosition = struct {
    azimuth_degrees: f64 = 0.0,
    elevation_degrees: f64 = 0.0,
};

pub const Speaker = struct {
    output_index: u8,
    label: []const u8,
    nominal: PolarPosition,
    actual: PolarPosition,
};

const RegionGains = struct {
    count: u8 = 0,
    values: [4]f64 = @splat(0.0),
};

const Region = struct {
    count: u8 = 0,
    vertices: [4]u8 = @splat(0),
};

const Vertex = struct {
    position: Vector = .{},
    output_gains: [maximum_outputs]f64 = @splat(0.0),
};

const PannerMode = enum {
    generic,
    stereo,
};

pub fn Panner(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("ADM polar panner supports f32 and f64 samples");

    return struct {
        const Self = @This();

        mode: PannerMode = .generic,
        output_count: usize = 0,
        panner_output_count: usize = 0,
        stereo_outputs: [2]u8 = @splat(0),
        vertex_count: usize = 0,
        region_count: usize = 0,
        vertices: [maximum_vertices]Vertex = @splat(.{}),
        nominal_positions: [maximum_vertices]Vector = @splat(.{}),
        regions: [maximum_regions]Region = @splat(.{}),

        pub fn init(
            output_count: usize,
            speakers: []const Speaker,
        ) !Self {
            if (output_count == 0 or output_count > maximum_outputs)
                return error.InvalidAdmPolarPannerOutputCount;
            if (speakers.len < 2 or speakers.len > maximum_outputs)
                return error.InvalidAdmPolarPannerSpeakerCount;
            for (speakers, 0..) |speaker, speaker_index| {
                try validateSpeaker(
                    output_count,
                    speakers[0..speaker_index],
                    speaker,
                );
            }
            if (speakers.len == 2) {
                const stereo_outputs = stereoOutputIndices(speakers) orelse
                    return error.InvalidAdmPolarPannerStereoLayout;
                return initStereo(output_count, stereo_outputs);
            }
            return initGeneric(output_count, speakers);
        }

        fn initGeneric(
            output_count: usize,
            speakers: []const Speaker,
        ) !Self {
            var result = Self{
                .mode = .generic,
                .output_count = output_count,
                .panner_output_count = output_count,
                .stereo_outputs = @splat(0),
                .vertex_count = 0,
                .region_count = 0,
            };
            for (speakers, 0..) |speaker, speaker_index| {
                try validateSpeaker(
                    output_count,
                    speakers[0..speaker_index],
                    speaker,
                );
                try result.addMappedVertex(
                    polarVector(speaker.actual),
                    polarVector(adjustedNominalPosition(speaker)),
                    speaker.output_index,
                );
            }
            try result.addVerticalVirtualSpeakers(speakers);

            const bottom_pole = try result.addUnmappedVertex(
                .{ .x = 0, .y = 0, .z = -1 },
                .{ .x = 0, .y = 0, .z = -1 },
            );
            var top_pole: ?u8 = null;
            if (!hasTopSpeaker(speakers)) {
                top_pole = try result.addUnmappedVertex(
                    .{ .x = 0, .y = 0, .z = 1 },
                    .{ .x = 0, .y = 0, .z = 1 },
                );
            }

            var facets: [maximum_regions]Facet = undefined;
            const facet_count = try result.buildHullFacets(&facets);
            try result.configurePole(
                bottom_pole,
                facets[0..facet_count],
            );
            if (top_pole) |pole| {
                try result.configurePole(pole, facets[0..facet_count]);
            }
            try result.buildRegions(
                facets[0..facet_count],
                bottom_pole,
                top_pole,
            );
            if (result.region_count == 0)
                return error.InvalidAdmPolarPannerLayout;
            return result;
        }

        fn initStereo(
            output_count: usize,
            stereo_outputs: [2]u8,
        ) !Self {
            const speakers = [_]Speaker{
                standardSpeaker(0, "M+030", 30),
                standardSpeaker(1, "M-030", -30),
                standardSpeaker(2, "M+000", 0),
                standardSpeaker(3, "M+110", 110),
                standardSpeaker(4, "M-110", -110),
            };
            var result = try initGeneric(speakers.len, &speakers);
            result.mode = .stereo;
            result.output_count = output_count;
            result.stereo_outputs = stereo_outputs;
            return result;
        }

        pub fn calculateGains(
            self: *const Self,
            position: PolarPosition,
            gains: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmPolarPannerState;
            if (gains.len != self.output_count)
                return error.AdmPolarPannerOutputCountMismatch;
            if (!validPolar(position))
                return error.InvalidAdmPolarPannerPosition;
            const direction = polarVector(position);

            var rendered: [maximum_outputs]f64 = @splat(0.0);
            try self.calculateGenericGains(
                direction,
                rendered[0..self.panner_output_count],
            );
            @memset(gains, 0.0);
            switch (self.mode) {
                .generic => for (
                    gains,
                    rendered[0..self.output_count],
                ) |*gain, rendered_gain| {
                    gain.* = @floatCast(rendered_gain);
                },
                .stereo => {
                    const downmixed = stereoDownmix(
                        rendered[0..self.panner_output_count],
                    ) orelse return error.InvalidAdmPolarPannerGain;
                    gains[self.stereo_outputs[0]] =
                        @floatCast(downmixed[0]);
                    gains[self.stereo_outputs[1]] =
                        @floatCast(downmixed[1]);
                },
            }
        }

        fn calculateGenericGains(
            self: *const Self,
            direction: Vector,
            rendered: []f64,
        ) !void {
            if (rendered.len != self.panner_output_count)
                return error.AdmPolarPannerOutputCountMismatch;
            @memset(rendered, 0.0);
            var handled = false;
            for (self.regions[0..self.region_count]) |region| {
                const region_gains = self.regionGains(
                    region,
                    direction,
                ) orelse continue;
                for (0..region.count) |region_index| {
                    const vertex =
                        self.vertices[region.vertices[region_index]];
                    for (
                        rendered,
                        vertex.output_gains[0..self.panner_output_count],
                    ) |*output_gain, mapping_gain| {
                        output_gain.* +=
                            region_gains.values[region_index] *
                            mapping_gain;
                    }
                }
                handled = true;
                break;
            }
            if (!handled or !normalizeNonnegative(rendered)) {
                return error.UnhandledAdmPolarPannerDirection;
            }
        }

        pub fn mix(
            self: *const Self,
            position: PolarPosition,
            input_gain: Sample,
            input: []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmPolarPannerState;
            if (!std.math.isFinite(input_gain))
                return error.InvalidAdmPolarPannerGain;
            try validateMixBuffers(
                Sample,
                input,
                outputs,
                self.output_count,
            );
            var gains: [maximum_outputs]Sample = undefined;
            try self.calculateGains(
                position,
                gains[0..self.output_count],
            );
            for (outputs, gains[0..self.output_count]) |output, gain| {
                if (gain == 0.0) continue;
                const combined_gain = input_gain * gain;
                if (!std.math.isFinite(combined_gain))
                    return error.InvalidAdmPolarPannerGain;
                for (input, output) |input_sample, *output_sample| {
                    if (!std.math.isFinite(input_sample)) continue;
                    if (!std.math.isFinite(output_sample.*)) {
                        output_sample.* = 0.0;
                        continue;
                    }
                    const mixed =
                        output_sample.* + input_sample * combined_gain;
                    output_sample.* = if (std.math.isFinite(mixed))
                        mixed
                    else
                        0.0;
                }
            }
        }

        pub fn valid(self: *const Self) bool {
            if (self.output_count == 0 or
                self.output_count > maximum_outputs or
                self.panner_output_count == 0 or
                self.panner_output_count > maximum_outputs or
                self.vertex_count == 0 or
                self.vertex_count > maximum_vertices or
                self.region_count == 0 or
                self.region_count > maximum_regions)
            {
                return false;
            }
            for (self.vertices[0..self.vertex_count]) |vertex| {
                if (normalize(vertex.position) == null) return false;
                for (
                    vertex.output_gains[0..self.panner_output_count],
                ) |gain| {
                    if (!std.math.isFinite(gain) or gain < 0.0)
                        return false;
                }
            }
            for (self.regions[0..self.region_count]) |region| {
                if (region.count != 3 and region.count != 4)
                    return false;
                for (region.vertices[0..region.count], 0..) |vertex, index| {
                    if (vertex >= self.vertex_count) return false;
                    for (region.vertices[0..index]) |previous| {
                        if (vertex == previous) return false;
                    }
                }
            }
            return switch (self.mode) {
                .generic => self.panner_output_count == self.output_count,
                .stereo => self.panner_output_count == 5 and
                    self.stereo_outputs[0] < self.output_count and
                    self.stereo_outputs[1] < self.output_count and
                    self.stereo_outputs[0] != self.stereo_outputs[1],
            };
        }

        fn addMappedVertex(
            self: *Self,
            actual: Vector,
            nominal: Vector,
            output_index: u8,
        ) !void {
            var mapping: [maximum_outputs]f64 = @splat(0.0);
            mapping[output_index] = 1.0;
            _ = try self.addVertex(actual, nominal, mapping);
        }

        fn addUnmappedVertex(
            self: *Self,
            actual: Vector,
            nominal: Vector,
        ) !u8 {
            return self.addVertex(
                actual,
                nominal,
                @splat(0.0),
            );
        }

        fn addVertex(
            self: *Self,
            actual: Vector,
            nominal: Vector,
            mapping: [maximum_outputs]f64,
        ) !u8 {
            if (self.vertex_count >= maximum_vertices)
                return error.AdmPolarPannerVertexCapacityExceeded;
            const normalized_actual = normalize(actual) orelse
                return error.InvalidAdmPolarPannerSpeakerPosition;
            const normalized_nominal = normalize(nominal) orelse
                return error.InvalidAdmPolarPannerSpeakerPosition;
            for (
                self.vertices[0..self.vertex_count],
                self.nominal_positions[0..self.vertex_count],
            ) |vertex, existing_nominal| {
                if (vectorDistance(
                    vertex.position,
                    normalized_actual,
                ) <= region_tolerance or
                    vectorDistance(
                        existing_nominal,
                        normalized_nominal,
                    ) <= region_tolerance)
                {
                    return error.DuplicateAdmPolarPannerSpeakerPosition;
                }
            }
            const index = self.vertex_count;
            self.vertices[index] = .{
                .position = normalized_actual,
                .output_gains = mapping,
            };
            self.nominal_positions[index] = normalized_nominal;
            self.vertex_count += 1;
            return @intCast(index);
        }

        fn addVerticalVirtualSpeakers(
            self: *Self,
            speakers: []const Speaker,
        ) !void {
            var upper_count: usize = 0;
            var lower_count: usize = 0;
            var upper_elevation_sum: f64 = 0.0;
            var lower_elevation_sum: f64 = 0.0;
            var upper_max_azimuth: f64 = 0.0;
            var lower_max_azimuth: f64 = 0.0;
            for (speakers) |speaker| {
                const nominal = adjustedNominalPosition(speaker);
                const nominal_elevation = nominal.elevation_degrees;
                if (nominal_elevation >= 30.0 and
                    nominal_elevation <= 70.0)
                {
                    upper_count += 1;
                    upper_elevation_sum +=
                        speaker.actual.elevation_degrees;
                    upper_max_azimuth = @max(
                        upper_max_azimuth,
                        @abs(nominal.azimuth_degrees),
                    );
                } else if (nominal_elevation >= -70.0 and
                    nominal_elevation <= -30.0)
                {
                    lower_count += 1;
                    lower_elevation_sum +=
                        speaker.actual.elevation_degrees;
                    lower_max_azimuth = @max(
                        lower_max_azimuth,
                        @abs(nominal.azimuth_degrees),
                    );
                }
            }
            const upper_limit = if (upper_count == 0)
                0.0
            else
                upper_max_azimuth + 40.0;
            const lower_limit = if (lower_count == 0)
                0.0
            else
                lower_max_azimuth + 40.0;
            const actual_upper_elevation = if (upper_count == 0)
                30.0
            else
                upper_elevation_sum / @as(f64, @floatFromInt(upper_count));
            const actual_lower_elevation = if (lower_count == 0)
                -30.0
            else
                lower_elevation_sum / @as(f64, @floatFromInt(lower_count));

            for (speakers) |speaker| {
                const nominal = adjustedNominalPosition(speaker);
                if (nominal.elevation_degrees < -10.0 or
                    nominal.elevation_degrees > 10.0)
                {
                    continue;
                }
                const absolute_azimuth = @abs(nominal.azimuth_degrees);
                if (absolute_azimuth >= upper_limit) {
                    try self.addMappedVertex(
                        polarVector(.{
                            .azimuth_degrees = speaker.actual.azimuth_degrees,
                            .elevation_degrees = actual_upper_elevation,
                        }),
                        polarVector(.{
                            .azimuth_degrees = nominal.azimuth_degrees,
                            .elevation_degrees = 30.0,
                        }),
                        speaker.output_index,
                    );
                }
                if (absolute_azimuth >= lower_limit) {
                    try self.addMappedVertex(
                        polarVector(.{
                            .azimuth_degrees = speaker.actual.azimuth_degrees,
                            .elevation_degrees = actual_lower_elevation,
                        }),
                        polarVector(.{
                            .azimuth_degrees = nominal.azimuth_degrees,
                            .elevation_degrees = -30.0,
                        }),
                        speaker.output_index,
                    );
                }
            }
        }

        fn buildHullFacets(
            self: *const Self,
            facets: *[maximum_regions]Facet,
        ) !usize {
            var facet_count: usize = 0;
            for (0..self.vertex_count) |first| {
                for (first + 1..self.vertex_count) |second| {
                    for (second + 1..self.vertex_count) |third| {
                        const origin = self.nominal_positions[first];
                        var normal = cross(
                            subtract(
                                self.nominal_positions[second],
                                origin,
                            ),
                            subtract(
                                self.nominal_positions[third],
                                origin,
                            ),
                        );
                        const normal_length = length(normal);
                        if (normal_length <= region_tolerance) continue;
                        normal = scale(normal, 1.0 / normal_length);
                        var has_positive = false;
                        var has_negative = false;
                        for (self.nominal_positions[0..self.vertex_count]) |point| {
                            const distance =
                                dot(normal, subtract(point, origin));
                            has_positive = has_positive or
                                distance > 0.000_000_1;
                            has_negative = has_negative or
                                distance < -0.000_000_1;
                        }
                        if (has_positive and has_negative) continue;
                        if (!has_positive and !has_negative) continue;
                        if (has_positive) normal = scale(normal, -1.0);

                        var facet = Facet{
                            .count = 0,
                            .normal = normal,
                            .indices = undefined,
                        };
                        for (
                            self.nominal_positions[0..self.vertex_count],
                            0..,
                        ) |point, point_index| {
                            if (@abs(dot(
                                normal,
                                subtract(point, origin),
                            )) > 0.000_000_1) {
                                continue;
                            }
                            if (facet.count >= facet.indices.len)
                                return error.UnsupportedAdmPolarPannerFacet;
                            facet.indices[facet.count] =
                                @intCast(point_index);
                            facet.count += 1;
                        }
                        if (facet.count != 3 and facet.count != 4)
                            return error.UnsupportedAdmPolarPannerFacet;
                        facet.sort(self.nominal_positions[0..self.vertex_count]);
                        if (containsFacet(facets[0..facet_count], facet))
                            continue;
                        if (facet_count >= facets.len)
                            return error.AdmPolarPannerRegionCapacityExceeded;
                        facets[facet_count] = facet;
                        facet_count += 1;
                    }
                }
            }
            if (facet_count == 0)
                return error.InvalidAdmPolarPannerLayout;
            return facet_count;
        }

        fn configurePole(
            self: *Self,
            pole: u8,
            facets: []const Facet,
        ) !void {
            var adjacent: [maximum_vertices]bool = @splat(false);
            var adjacent_count: usize = 0;
            for (facets) |facet| {
                const pole_offset = facet.indexOf(pole) orelse continue;
                const previous = facet.indices[
                    (pole_offset + facet.count - 1) % facet.count
                ];
                const next = facet.indices[(pole_offset + 1) % facet.count];
                if (!adjacent[previous]) {
                    adjacent[previous] = true;
                    adjacent_count += 1;
                }
                if (!adjacent[next]) {
                    adjacent[next] = true;
                    adjacent_count += 1;
                }
            }
            if (adjacent_count < 3)
                return error.InvalidAdmPolarPannerLayout;
            const downmix_gain =
                1.0 / @sqrt(@as(f64, @floatFromInt(adjacent_count)));
            var mapping: [maximum_outputs]f64 = @splat(0.0);
            for (
                adjacent[0..self.vertex_count],
                self.vertices[0..self.vertex_count],
            ) |is_adjacent, vertex| {
                if (!is_adjacent) continue;
                for (
                    mapping[0..self.output_count],
                    vertex.output_gains[0..self.output_count],
                ) |*output_gain, vertex_gain| {
                    output_gain.* += downmix_gain * vertex_gain;
                }
            }
            self.vertices[pole].output_gains = mapping;
        }

        fn buildRegions(
            self: *Self,
            facets: []const Facet,
            bottom_pole: u8,
            top_pole: ?u8,
        ) !void {
            for (facets) |facet| {
                const pole = if (facet.indexOf(bottom_pole) != null)
                    bottom_pole
                else if (top_pole) |top|
                    if (facet.indexOf(top) != null) top else null
                else
                    null;
                if (pole) |pole_index| {
                    const offset = facet.indexOf(pole_index) orelse
                        return error.InvalidAdmPolarPannerLayout;
                    try self.addRegion(.{
                        .count = 3,
                        .vertices = .{
                            pole_index,
                            facet.indices[
                                (offset + facet.count - 1) % facet.count
                            ],
                            facet.indices[(offset + 1) % facet.count],
                            0,
                        },
                    });
                } else {
                    var vertices: [4]u8 = @splat(0);
                    @memcpy(
                        vertices[0..facet.count],
                        facet.indices[0..facet.count],
                    );
                    try self.addRegion(.{
                        .count = facet.count,
                        .vertices = vertices,
                    });
                }
            }
        }

        fn addRegion(self: *Self, region: Region) !void {
            for (self.regions[0..self.region_count]) |existing| {
                if (sameRegion(existing, region)) return;
            }
            if (self.region_count >= maximum_regions)
                return error.AdmPolarPannerRegionCapacityExceeded;
            self.regions[self.region_count] = region;
            self.region_count += 1;
        }

        fn regionGains(
            self: *const Self,
            region: Region,
            direction: Vector,
        ) ?RegionGains {
            if (region.count == 3) {
                return tripletGains(.{
                    self.vertices[region.vertices[0]].position,
                    self.vertices[region.vertices[1]].position,
                    self.vertices[region.vertices[2]].position,
                }, direction);
            }
            return quadGains(.{
                self.vertices[region.vertices[0]].position,
                self.vertices[region.vertices[1]].position,
                self.vertices[region.vertices[2]].position,
                self.vertices[region.vertices[3]].position,
            }, direction);
        }
    };
}

const Facet = struct {
    count: u8,
    normal: Vector,
    indices: [4]u8,

    fn indexOf(self: Facet, target: u8) ?usize {
        for (self.indices[0..self.count], 0..) |index, offset| {
            if (index == target) return offset;
        }
        return null;
    }

    fn sort(self: *Facet, positions: []const Vector) void {
        var center = Vector{ .x = 0, .y = 0, .z = 0 };
        for (self.indices[0..self.count]) |index| {
            center = add(center, positions[index]);
        }
        center = scale(center, 1.0 / @as(f64, @floatFromInt(self.count)));
        const first_direction = normalize(subtract(
            positions[self.indices[0]],
            center,
        )) orelse return;
        const second_direction = cross(self.normal, first_direction);
        var angles: [4]f64 = @splat(0.0);
        for (self.indices[0..self.count], 0..) |index, offset| {
            const relative = subtract(positions[index], center);
            angles[offset] = std.math.atan2(
                dot(relative, second_direction),
                dot(relative, first_direction),
            );
        }
        for (1..self.count) |index| {
            const held_index = self.indices[index];
            const held_angle = angles[index];
            var destination = index;
            while (destination > 0 and
                angles[destination - 1] > held_angle)
            {
                self.indices[destination] =
                    self.indices[destination - 1];
                angles[destination] = angles[destination - 1];
                destination -= 1;
            }
            self.indices[destination] = held_index;
            angles[destination] = held_angle;
        }
    }
};

fn adjustedNominalPosition(speaker: Speaker) PolarPosition {
    var nominal = speaker.nominal;
    if (!std.mem.eql(u8, speaker.label, "M+SC") and
        !std.mem.eql(u8, speaker.label, "M-SC"))
    {
        return nominal;
    }
    const sign: f64 = if (speaker.actual.azimuth_degrees < 0.0)
        -1.0
    else
        1.0;
    const magnitude: f64 =
        if (@abs(speaker.actual.azimuth_degrees) > 30.0)
            45.0
        else
            15.0;
    nominal.azimuth_degrees = sign * magnitude;
    return nominal;
}

fn standardSpeaker(
    output_index: u8,
    label: []const u8,
    azimuth_degrees: f64,
) Speaker {
    return standardPolarSpeaker(
        output_index,
        label,
        azimuth_degrees,
        0,
    );
}

fn standardPolarSpeaker(
    output_index: u8,
    label: []const u8,
    azimuth_degrees: f64,
    elevation_degrees: f64,
) Speaker {
    const position = PolarPosition{
        .azimuth_degrees = azimuth_degrees,
        .elevation_degrees = elevation_degrees,
    };
    return .{
        .output_index = output_index,
        .label = label,
        .nominal = position,
        .actual = position,
    };
}

fn stereoOutputIndices(speakers: []const Speaker) ?[2]u8 {
    if (speakers.len != 2) return null;
    var left: ?u8 = null;
    var right: ?u8 = null;
    for (speakers) |speaker| {
        if (std.mem.eql(u8, speaker.label, "M+030")) {
            left = speaker.output_index;
        } else if (std.mem.eql(u8, speaker.label, "M-030")) {
            right = speaker.output_index;
        } else {
            return null;
        }
    }
    return .{ left orelse return null, right orelse return null };
}

fn stereoDownmix(gains: []const f64) ?[2]f64 {
    if (gains.len != 5) return null;
    const center_gain = 1.0 / @sqrt(@as(f64, 3.0));
    const rear_gain = std.math.sqrt1_2;
    var result = [2]f64{
        gains[0] + center_gain * gains[2] + rear_gain * gains[3],
        gains[1] + center_gain * gains[2] + rear_gain * gains[4],
    };
    const front = @max(gains[0], @max(gains[1], gains[2]));
    const rear = @max(gains[3], gains[4]);
    const balance_denominator = front + rear;
    if (!std.math.isFinite(balance_denominator) or
        balance_denominator <= region_tolerance)
    {
        return null;
    }
    const power = result[0] * result[0] + result[1] * result[1];
    if (!std.math.isFinite(power) or power <= region_tolerance)
        return null;
    const rear_balance = rear / balance_denominator;
    const attenuation = std.math.pow(f64, 2.0, -rear_balance / 2.0);
    const scale_factor = attenuation / @sqrt(power);
    result[0] *= scale_factor;
    result[1] *= scale_factor;
    return result;
}

fn validateSpeaker(
    output_count: usize,
    previous: []const Speaker,
    speaker: Speaker,
) !void {
    if (speaker.output_index >= output_count or speaker.label.len == 0)
        return error.InvalidAdmPolarPannerSpeaker;
    if (!validPolar(speaker.nominal) or !validPolar(speaker.actual))
        return error.InvalidAdmPolarPannerSpeakerPosition;
    for (previous) |other| {
        if (speaker.output_index == other.output_index)
            return error.DuplicateAdmPolarPannerOutput;
        if (std.mem.eql(u8, speaker.label, other.label))
            return error.DuplicateAdmPolarPannerSpeakerLabel;
    }
}

fn validPolar(position: PolarPosition) bool {
    return std.math.isFinite(position.azimuth_degrees) and
        std.math.isFinite(position.elevation_degrees) and
        position.azimuth_degrees >= -180.0 and
        position.azimuth_degrees <= 180.0 and
        position.elevation_degrees >= -90.0 and
        position.elevation_degrees <= 90.0;
}

fn polarVector(position: PolarPosition) Vector {
    const azimuth =
        -position.azimuth_degrees * std.math.pi / 180.0;
    const elevation =
        position.elevation_degrees * std.math.pi / 180.0;
    const elevation_cosine = @cos(elevation);
    return .{
        .x = @sin(azimuth) * elevation_cosine,
        .y = @cos(azimuth) * elevation_cosine,
        .z = @sin(elevation),
    };
}

fn hasTopSpeaker(speakers: []const Speaker) bool {
    for (speakers) |speaker| {
        if (std.mem.eql(u8, speaker.label, "T+000") or
            std.mem.eql(u8, speaker.label, "UH+180"))
        {
            return true;
        }
    }
    return false;
}

fn containsFacet(facets: []const Facet, candidate: Facet) bool {
    for (facets) |facet| {
        if (facet.count != candidate.count) continue;
        var matches = true;
        for (candidate.indices[0..candidate.count]) |index| {
            matches = matches and facet.indexOf(index) != null;
        }
        if (matches) return true;
    }
    return false;
}

fn sameRegion(left: Region, right: Region) bool {
    if (left.count != right.count) return false;
    for (left.vertices[0..left.count]) |vertex| {
        var found = false;
        for (right.vertices[0..right.count]) |candidate| {
            found = found or vertex == candidate;
        }
        if (!found) return false;
    }
    return true;
}

fn vectorDistance(left: Vector, right: Vector) f64 {
    return length(subtract(left, right));
}

fn validateMixBuffers(
    comptime Sample: type,
    input: []const Sample,
    outputs: []const []Sample,
    expected_output_count: usize,
) !void {
    if (outputs.len != expected_output_count)
        return error.AdmPolarPannerOutputCountMismatch;
    for (outputs, 0..) |output, output_index| {
        if (output.len != input.len)
            return error.AdmPolarPannerBufferLengthMismatch;
        if (slicesOverlap(Sample, input, output))
            return error.AdmPolarPannerAliasedBuffers;
        for (outputs[0..output_index]) |previous| {
            if (slicesOverlap(Sample, previous, output))
                return error.AdmPolarPannerAliasedBuffers;
        }
    }
}

fn slicesOverlap(
    comptime Sample: type,
    input: []const Sample,
    output: []Sample,
) bool {
    if (input.len == 0 or output.len == 0) return false;
    const input_start = @intFromPtr(input.ptr);
    const output_start = @intFromPtr(output.ptr);
    const input_bytes = std.math.mul(
        usize,
        input.len,
        @sizeOf(Sample),
    ) catch return true;
    const output_bytes = std.math.mul(
        usize,
        output.len,
        @sizeOf(Sample),
    ) catch return true;
    const input_end = std.math.add(
        usize,
        input_start,
        input_bytes,
    ) catch return true;
    const output_end = std.math.add(
        usize,
        output_start,
        output_bytes,
    ) catch return true;
    return input_start < output_end and output_start < input_end;
}

fn tripletGains(
    positions: [3]Vector,
    direction: Vector,
) ?RegionGains {
    const determinant = dot(
        positions[0],
        cross(positions[1], positions[2]),
    );
    if (!std.math.isFinite(determinant) or
        @abs(determinant) <= region_tolerance)
    {
        return null;
    }
    var gains = [4]f64{
        dot(direction, cross(positions[1], positions[2])) /
            determinant,
        dot(positions[0], cross(direction, positions[2])) /
            determinant,
        dot(positions[0], cross(positions[1], direction)) /
            determinant,
        0.0,
    };
    if (!normalizeNonnegative(gains[0..3])) return null;
    return .{ .count = 3, .values = gains };
}

fn quadGains(
    positions: [4]Vector,
    direction: Vector,
) ?RegionGains {
    var x_candidates: [3]f64 = undefined;
    var y_candidates: [3]f64 = undefined;
    const x_count = quadAxisCandidates(
        positions,
        direction,
        &x_candidates,
    );
    const rotated = [4]Vector{
        positions[1],
        positions[2],
        positions[3],
        positions[0],
    };
    const y_count = quadAxisCandidates(
        rotated,
        direction,
        &y_candidates,
    );

    var best: ?RegionGains = null;
    var best_error = std.math.inf(f64);
    for (x_candidates[0..x_count]) |x| {
        for (y_candidates[0..y_count]) |y| {
            var values = [4]f64{
                (1.0 - x) * (1.0 - y),
                x * (1.0 - y),
                x * y,
                (1.0 - x) * y,
            };
            if (!normalizeNonnegative(&values)) continue;
            const velocity = add(
                add(
                    scale(positions[0], values[0]),
                    scale(positions[1], values[1]),
                ),
                add(
                    scale(positions[2], values[2]),
                    scale(positions[3], values[3]),
                ),
            );
            const velocity_length = length(velocity);
            if (!std.math.isFinite(velocity_length) or
                velocity_length <= region_tolerance or
                dot(velocity, direction) <= 0.0)
            {
                continue;
            }
            const aligned = scale(velocity, 1.0 / velocity_length);
            const alignment_error = length(cross(aligned, direction));
            if (!std.math.isFinite(alignment_error) or
                alignment_error > 0.000_001 or
                alignment_error >= best_error)
            {
                continue;
            }
            best_error = alignment_error;
            best = .{ .count = 4, .values = values };
        }
    }
    return best;
}

fn quadAxisCandidates(
    positions: [4]Vector,
    direction: Vector,
    candidates: *[3]f64,
) usize {
    const p21 = subtract(positions[1], positions[0]);
    const p34 = subtract(positions[2], positions[3]);
    const constant = dot(
        cross(positions[0], positions[3]),
        direction,
    );
    const linear = dot(
        add(
            cross(positions[0], p34),
            cross(p21, positions[3]),
        ),
        direction,
    );
    const quadratic = dot(cross(p21, p34), direction);
    return boundedPolynomialRoots(
        constant,
        linear,
        quadratic,
        candidates,
    );
}

fn boundedPolynomialRoots(
    constant: f64,
    linear: f64,
    quadratic: f64,
    roots: *[3]f64,
) usize {
    if (@abs(quadratic) <= region_tolerance) {
        if (@abs(linear) <= region_tolerance) {
            if (@abs(constant) > region_tolerance) return 0;
            roots.* = .{ 0.0, 0.5, 1.0 };
            return roots.len;
        }
        const root = -constant / linear;
        if (!boundedUnit(root)) return 0;
        roots[0] = std.math.clamp(root, 0.0, 1.0);
        return 1;
    }
    const discriminant =
        linear * linear - 4.0 * quadratic * constant;
    if (!std.math.isFinite(discriminant) or
        discriminant < -region_tolerance)
    {
        return 0;
    }
    const root_term = @sqrt(@max(discriminant, 0.0));
    const denominator = 2.0 * quadratic;
    var count: usize = 0;
    const first = (-linear - root_term) / denominator;
    if (boundedUnit(first)) {
        roots[count] = std.math.clamp(first, 0.0, 1.0);
        count += 1;
    }
    const second = (-linear + root_term) / denominator;
    if (boundedUnit(second) and
        (count == 0 or @abs(second - roots[0]) > region_tolerance))
    {
        roots[count] = std.math.clamp(second, 0.0, 1.0);
        count += 1;
    }
    return count;
}

fn boundedUnit(value: f64) bool {
    return std.math.isFinite(value) and
        value >= -region_tolerance and
        value <= 1.0 + region_tolerance;
}

fn normalizeNonnegative(values: []f64) bool {
    var power: f64 = 0.0;
    for (values) |*value| {
        if (!std.math.isFinite(value.*) or
            value.* < -region_tolerance)
        {
            return false;
        }
        value.* = @max(value.*, 0.0);
        power += value.* * value.*;
    }
    if (!std.math.isFinite(power) or power <= region_tolerance)
        return false;
    const normalization = 1.0 / @sqrt(power);
    for (values) |*value| value.* *= normalization;
    return true;
}

fn normalize(vector: Vector) ?Vector {
    const magnitude = length(vector);
    if (!std.math.isFinite(magnitude) or magnitude <= region_tolerance)
        return null;
    return scale(vector, 1.0 / magnitude);
}

fn add(left: Vector, right: Vector) Vector {
    return .{
        .x = left.x + right.x,
        .y = left.y + right.y,
        .z = left.z + right.z,
    };
}

fn subtract(left: Vector, right: Vector) Vector {
    return .{
        .x = left.x - right.x,
        .y = left.y - right.y,
        .z = left.z - right.z,
    };
}

fn scale(vector: Vector, amount: f64) Vector {
    return .{
        .x = vector.x * amount,
        .y = vector.y * amount,
        .z = vector.z * amount,
    };
}

fn dot(left: Vector, right: Vector) f64 {
    return left.x * right.x +
        left.y * right.y +
        left.z * right.z;
}

fn cross(left: Vector, right: Vector) Vector {
    return .{
        .x = left.y * right.z - left.z * right.y,
        .y = left.z * right.x - left.x * right.z,
        .z = left.x * right.y - left.y * right.x,
    };
}

fn length(vector: Vector) f64 {
    return @sqrt(dot(vector, vector));
}

test "polar triplet region produces power-normalized VBAP gains" {
    const positions = [3]Vector{
        (normalize(.{ .x = -1, .y = 1, .z = 0 }) orelse
            return error.TestUnexpectedResult),
        (normalize(.{ .x = 1, .y = 1, .z = 0 }) orelse
            return error.TestUnexpectedResult),
        .{ .x = 0, .y = 0, .z = 1 },
    };
    const front = tripletGains(
        positions,
        .{ .x = 0, .y = 1, .z = 0 },
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(
        @as(f64, std.math.sqrt1_2),
        front.values[0],
        0.000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, std.math.sqrt1_2),
        front.values[1],
        0.000_000_001,
    );
    try std.testing.expectEqual(@as(f64, 0.0), front.values[2]);

    const outside = tripletGains(
        positions,
        .{ .x = 0, .y = -1, .z = 0 },
    );
    try std.testing.expectEqual(@as(?RegionGains, null), outside);
}

test "polar quadrilateral region is smooth and matches its edges" {
    const positions = [4]Vector{
        (normalize(.{ .x = -1, .y = 1, .z = -1 }) orelse
            return error.TestUnexpectedResult),
        (normalize(.{ .x = 1, .y = 1, .z = -1 }) orelse
            return error.TestUnexpectedResult),
        (normalize(.{ .x = 1, .y = 1, .z = 1 }) orelse
            return error.TestUnexpectedResult),
        (normalize(.{ .x = -1, .y = 1, .z = 1 }) orelse
            return error.TestUnexpectedResult),
    };
    const center = quadGains(
        positions,
        .{ .x = 0, .y = 1, .z = 0 },
    ) orelse return error.TestUnexpectedResult;
    for (center.values) |gain| {
        try std.testing.expectApproxEqAbs(
            @as(f64, 0.5),
            gain,
            0.000_000_001,
        );
    }

    const left = quadGains(
        positions,
        (normalize(.{ .x = -1, .y = 1, .z = 0 }) orelse
            return error.TestUnexpectedResult),
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(
        @as(f64, std.math.sqrt1_2),
        left.values[0],
        0.000_000_001,
    );
    try std.testing.expectEqual(@as(f64, 0.0), left.values[1]);
    try std.testing.expectEqual(@as(f64, 0.0), left.values[2]);
    try std.testing.expectApproxEqAbs(
        @as(f64, std.math.sqrt1_2),
        left.values[3],
        0.000_000_001,
    );
}

test "generic polar panner covers the standard five-speaker layout" {
    const speakers = [_]Speaker{
        .{
            .output_index = 0,
            .label = "M+030",
            .nominal = .{ .azimuth_degrees = 30, .elevation_degrees = 0 },
            .actual = .{ .azimuth_degrees = 30, .elevation_degrees = 0 },
        },
        .{
            .output_index = 1,
            .label = "M-030",
            .nominal = .{ .azimuth_degrees = -30, .elevation_degrees = 0 },
            .actual = .{ .azimuth_degrees = -30, .elevation_degrees = 0 },
        },
        .{
            .output_index = 2,
            .label = "M+000",
            .nominal = .{ .azimuth_degrees = 0, .elevation_degrees = 0 },
            .actual = .{ .azimuth_degrees = 0, .elevation_degrees = 0 },
        },
        .{
            .output_index = 3,
            .label = "M+110",
            .nominal = .{ .azimuth_degrees = 110, .elevation_degrees = 0 },
            .actual = .{ .azimuth_degrees = 110, .elevation_degrees = 0 },
        },
        .{
            .output_index = 4,
            .label = "M-110",
            .nominal = .{ .azimuth_degrees = -110, .elevation_degrees = 0 },
            .actual = .{ .azimuth_degrees = -110, .elevation_degrees = 0 },
        },
    };
    const panner = try Panner(f64).init(speakers.len, &speakers);

    var gains: [speakers.len]f64 = undefined;
    for (speakers, 0..) |speaker, output_index| {
        try panner.calculateGains(speaker.actual, &gains);
        for (gains, 0..) |gain, gain_index| {
            try std.testing.expectApproxEqAbs(
                @as(f64, if (gain_index == output_index) 1.0 else 0.0),
                gain,
                0.000_000_001,
            );
        }
    }

    const probes = [_]PolarPosition{
        .{ .azimuth_degrees = 0, .elevation_degrees = 90 },
        .{ .azimuth_degrees = 0, .elevation_degrees = -90 },
        .{ .azimuth_degrees = 180, .elevation_degrees = 0 },
        .{ .azimuth_degrees = 65, .elevation_degrees = 25 },
        .{ .azimuth_degrees = -145, .elevation_degrees = -40 },
    };
    for (probes) |probe| {
        try panner.calculateGains(probe, &gains);
        var power: f64 = 0.0;
        for (gains) |gain| {
            try std.testing.expect(std.math.isFinite(gain));
            try std.testing.expect(gain >= 0.0);
            power += gain * gain;
        }
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            power,
            0.000_000_001,
        );
    }

    var speakers_with_top: [speakers.len + 1]Speaker = undefined;
    @memcpy(speakers_with_top[0..speakers.len], &speakers);
    speakers_with_top[speakers.len] =
        standardPolarSpeaker(5, "T+000", 0, 90);
    const panner_with_top = try Panner(f64).init(
        speakers_with_top.len,
        &speakers_with_top,
    );
    var top_gains: [speakers_with_top.len]f64 = undefined;
    try panner_with_top.calculateGains(
        .{ .azimuth_degrees = 0, .elevation_degrees = 90 },
        &top_gains,
    );
    for (top_gains, 0..) |gain, output_index| {
        try std.testing.expectApproxEqAbs(
            @as(f64, if (output_index == 5) 1.0 else 0.0),
            gain,
            0.000_000_001,
        );
    }
}

test "stereo polar panner applies front and rear downmix behavior" {
    const speakers = [_]Speaker{
        .{
            .output_index = 2,
            .label = "M+030",
            .nominal = .{ .azimuth_degrees = 30, .elevation_degrees = 0 },
            .actual = .{ .azimuth_degrees = 24, .elevation_degrees = 0 },
        },
        .{
            .output_index = 0,
            .label = "M-030",
            .nominal = .{ .azimuth_degrees = -30, .elevation_degrees = 0 },
            .actual = .{ .azimuth_degrees = -24, .elevation_degrees = 0 },
        },
    };
    const panner = try Panner(f64).init(3, &speakers);
    try std.testing.expect(panner.valid());

    var gains: [3]f64 = undefined;
    try panner.calculateGains(
        .{ .azimuth_degrees = 30, .elevation_degrees = 0 },
        &gains,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        gains[2],
        0.000_000_001,
    );
    try std.testing.expectEqual(@as(f64, 0.0), gains[0]);
    try std.testing.expectEqual(@as(f64, 0.0), gains[1]);

    try panner.calculateGains(
        .{ .azimuth_degrees = 0, .elevation_degrees = 0 },
        &gains,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, std.math.sqrt1_2),
        gains[0],
        0.000_000_001,
    );
    try std.testing.expectEqual(@as(f64, 0.0), gains[1]);
    try std.testing.expectApproxEqAbs(
        @as(f64, std.math.sqrt1_2),
        gains[2],
        0.000_000_001,
    );

    try panner.calculateGains(
        .{ .azimuth_degrees = 180, .elevation_degrees = 0 },
        &gains,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        gains[0],
        0.000_000_001,
    );
    try std.testing.expectEqual(@as(f64, 0.0), gains[1]);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        gains[2],
        0.000_000_001,
    );

    try panner.calculateGains(
        .{ .azimuth_degrees = 110, .elevation_degrees = 0 },
        &gains,
    );
    try std.testing.expectEqual(@as(f64, 0.0), gains[0]);
    try std.testing.expectEqual(@as(f64, 0.0), gains[1]);
    try std.testing.expectApproxEqAbs(
        @as(f64, std.math.sqrt1_2),
        gains[2],
        0.000_000_001,
    );
}

test "stereo polar panner rejects incomplete stereo labels" {
    const speakers = [_]Speaker{
        standardSpeaker(0, "M+030", 30),
        standardSpeaker(1, "M+000", 0),
    };
    try std.testing.expectError(
        error.InvalidAdmPolarPannerStereoLayout,
        Panner(f32).init(2, &speakers),
    );
}

test "generic polar panner builds and solves quadrilateral facets" {
    const elevation = 35.264_389_682_754_654;
    const speakers = [_]Speaker{
        standardPolarSpeaker(0, "U+045", 45, elevation),
        standardPolarSpeaker(1, "U-045", -45, elevation),
        standardPolarSpeaker(2, "U+135", 135, elevation),
        standardPolarSpeaker(3, "U-135", -135, elevation),
        standardPolarSpeaker(4, "B+045", 45, -elevation),
        standardPolarSpeaker(5, "B-045", -45, -elevation),
        standardPolarSpeaker(6, "B+135", 135, -elevation),
        standardPolarSpeaker(7, "B-135", -135, -elevation),
    };
    const panner = try Panner(f64).init(speakers.len, &speakers);
    var has_quad = false;
    for (panner.regions[0..panner.region_count]) |region| {
        has_quad = has_quad or region.count == 4;
    }
    try std.testing.expect(has_quad);
    for (panner.vertices[panner.vertex_count..]) |vertex| {
        try std.testing.expectEqualDeep(Vector{}, vertex.position);
        try std.testing.expectEqual(
            @as([maximum_outputs]f64, @splat(0.0)),
            vertex.output_gains,
        );
    }
    for (panner.nominal_positions[panner.vertex_count..]) |position|
        try std.testing.expectEqualDeep(Vector{}, position);
    for (panner.regions[panner.region_count..]) |region| {
        try std.testing.expectEqual(@as(u8, 0), region.count);
        try std.testing.expectEqual(@as([4]u8, @splat(0)), region.vertices);
    }

    var gains: [speakers.len]f64 = undefined;
    try panner.calculateGains(
        .{ .azimuth_degrees = 90, .elevation_degrees = 0 },
        &gains,
    );
    for (gains, 0..) |gain, index| {
        const expected: f64 = switch (index) {
            0, 2, 4, 6 => 0.5,
            else => 0.0,
        };
        try std.testing.expectApproxEqAbs(
            expected,
            gain,
            0.000_000_001,
        );
    }
}

test "polar panner rejects invalid state positions and aliases transactionally" {
    const speakers = [_]Speaker{
        standardSpeaker(0, "M+030", 30),
        standardSpeaker(1, "M-030", -30),
        standardSpeaker(2, "M+000", 0),
        standardSpeaker(3, "M+110", 110),
        standardSpeaker(4, "M-110", -110),
    };
    const panner = try Panner(f32).init(speakers.len, &speakers);
    var gains: [speakers.len]f32 = @splat(0.25);
    try std.testing.expectError(
        error.InvalidAdmPolarPannerPosition,
        panner.calculateGains(
            .{
                .azimuth_degrees = std.math.nan(f64),
                .elevation_degrees = 0,
            },
            &gains,
        ),
    );
    try std.testing.expectEqualDeep(
        [_]f32{0.25} ** speakers.len,
        gains,
    );

    var input = [_]f32{ 1.0, 2.0 };
    var storage: [speakers.len - 1][2]f32 = @splat(@splat(0.0));
    var outputs: [speakers.len][]f32 = undefined;
    outputs[0] = &input;
    for (&storage, outputs[1..]) |*channel, *output| output.* = channel;
    try std.testing.expectError(
        error.AdmPolarPannerAliasedBuffers,
        panner.mix(
            .{ .azimuth_degrees = 0, .elevation_degrees = 0 },
            1.0,
            &input,
            &outputs,
        ),
    );
    try std.testing.expectEqualDeep([_]f32{ 1.0, 2.0 }, input);
    for (storage) |channel| {
        try std.testing.expectEqualDeep([_]f32{ 0.0, 0.0 }, channel);
    }

    var invalid_state = panner;
    invalid_state.regions[0].vertices[1] =
        invalid_state.regions[0].vertices[0];
    try std.testing.expect(!invalid_state.valid());
    try std.testing.expectError(
        error.InvalidAdmPolarPannerState,
        invalid_state.calculateGains(
            .{ .azimuth_degrees = 0, .elevation_degrees = 0 },
            &gains,
        ),
    );
}

test "polar panner rejects duplicate nominal and reproduction positions" {
    var speakers = [_]Speaker{
        standardSpeaker(0, "M+030", 30),
        standardSpeaker(1, "M-030", -30),
        standardSpeaker(2, "M+000", 0),
    };
    speakers[1].actual = speakers[0].actual;
    try std.testing.expectError(
        error.DuplicateAdmPolarPannerSpeakerPosition,
        Panner(f64).init(speakers.len, &speakers),
    );

    speakers[1] = standardSpeaker(1, "M-030", -30);
    speakers[1].nominal = speakers[0].nominal;
    try std.testing.expectError(
        error.DuplicateAdmPolarPannerSpeakerPosition,
        Panner(f64).init(speakers.len, &speakers),
    );
}

test "screen speaker nominal correction follows measured azimuth" {
    var speaker = standardSpeaker(0, "M+SC", 15);
    speaker.actual.azimuth_degrees = 35;
    try std.testing.expectEqual(
        @as(f64, 45),
        adjustedNominalPosition(speaker).azimuth_degrees,
    );

    speaker.actual.azimuth_degrees = -35;
    try std.testing.expectEqual(
        @as(f64, -45),
        adjustedNominalPosition(speaker).azimuth_degrees,
    );

    speaker.actual.azimuth_degrees = -30;
    try std.testing.expectEqual(
        @as(f64, -15),
        adjustedNominalPosition(speaker).azimuth_degrees,
    );
}
