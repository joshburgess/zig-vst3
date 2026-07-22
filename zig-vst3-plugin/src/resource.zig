const std = @import("std");

pub const job = @import("resource/job.zig");
pub const exchange = @import("resource/exchange.zig");
pub const reference = @import("resource/reference.zig");
pub const recovery = @import("resource/recovery.zig");
pub const BoundedPath = @import("resource/path.zig").BoundedPath;
pub const BoundedMetadata = reference.BoundedMetadata;
pub const Identity = reference.Identity;
pub const IdentityHasher = reference.IdentityHasher;
pub const RecoveryStatus = reference.RecoveryStatus;
pub const Reference = reference.Reference;
pub const ReferenceState = reference.State;
pub const PreparedResource = recovery.Prepared;
pub const ResourceRecovery = recovery.Recovery;

test {
    std.testing.refAllDecls(job);
    std.testing.refAllDecls(exchange);
    std.testing.refAllDecls(reference);
    std.testing.refAllDecls(recovery);
    std.testing.refAllDecls(@import("resource/path.zig"));
}
