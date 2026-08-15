const adm_polar_extent = @import("../adm_polar_extent.zig");
const adm_xml = @import("../adm_xml.zig");

pub const maximum_input_channels = adm_xml.max_adm_matrix_coefficients;
pub const maximum_output_channels: usize = 64;
pub const polar_extent_spreading_direction_count =
    adm_polar_extent.spreading_direction_count;

pub const PolarPosition = struct {
    azimuth_degrees: f64,
    elevation_degrees: f64,
    distance: f64 = 1.0,
};

pub const CartesianPosition = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,
    z: f64 = 0.0,
};

pub const OutputSpeaker = struct {
    label: []const u8,
    is_lfe: bool = false,
    nominal_polar: PolarPosition,
    reproduction_polar: ?PolarPosition = null,
    allocentric: CartesianPosition,
};

pub const ScreenEdges = struct {
    left_azimuth_degrees: f64,
    right_azimuth_degrees: f64,
    bottom_elevation_degrees: f64,
    top_elevation_degrees: f64,
};
