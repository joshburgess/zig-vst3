const value = @import("parameters/value.zig");
const smoothing = @import("parameters/smoothing.zig");
const descriptors = @import("parameters/descriptors.zig");
const set_mod = @import("parameters/set.zig");
const access = @import("parameters/access.zig");

pub const NormalizedValue = value.NormalizedValue;
pub const ModulatedValue = value.ModulatedValue;

pub const LinearSmoother = smoothing.LinearSmoother;
pub const ExponentialSmoother = smoothing.ExponentialSmoother;
pub const LogSmoother = smoothing.LogSmoother;

pub const FloatParam = descriptors.FloatParam;
pub const IntParam = descriptors.IntParam;
pub const BoolParam = descriptors.BoolParam;
pub const EnumParam = descriptors.EnumParam;

pub const ParameterSet = set_mod.ParameterSet;
pub const FieldDescriptor = set_mod.FieldDescriptor;
pub const FieldPlainType = set_mod.FieldPlainType;

pub const ParameterValues = access.ParameterValues;
pub const ParameterView = access.ParameterView;
pub const ParameterEditor = access.ParameterEditor;
