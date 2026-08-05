const shared = @import("../common.zig");

pub const isNormalized = shared.isNormalized;
pub const clampNormalized = shared.clampNormalized;
pub const clampBipolarNormalized = shared.clampBipolarNormalized;
pub const clampNormalizedNonZero = shared.clampNormalizedNonZero;
pub const normalizedFromBipolar = shared.normalizedFromBipolar;
pub const bipolarFromNormalized = shared.bipolarFromNormalized;
pub const isFinite = shared.isFinite;
pub const isFiniteInRange = shared.isFiniteInRange;
pub const isValidRange = shared.isValidRange;
