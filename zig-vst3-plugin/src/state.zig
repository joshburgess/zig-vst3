const std = @import("std");
const format = @import("state/format.zig");
const codec = @import("state/codec.zig");
const migrations = @import("state/migrations.zig");

pub const format_version = format.format_version;
pub const encoded_header_size = format.encoded_header_size;
pub const encoded_entry_size = format.encoded_entry_size;

pub const ParameterStateHeader = format.ParameterStateHeader;
pub const ParameterIdMigration = format.ParameterIdMigration;
pub const ReadParameterStateClassification = format.ReadParameterStateClassification;
pub const ReadParameterStateReport = format.ReadParameterStateReport;

pub const encodedSize = format.encodedSize;
pub const encodedSizeForCount = format.encodedSizeForCount;
pub const encodedSizeForCountChecked = format.encodedSizeForCountChecked;
pub const encodedEntryOffset = format.encodedEntryOffset;
pub const encodedEntryOffsetChecked = format.encodedEntryOffsetChecked;
pub const encodedEntryValueOffset = format.encodedEntryValueOffset;
pub const encodedEntryValueOffsetChecked = format.encodedEntryValueOffsetChecked;

pub const writeParameterState = codec.writeParameterState;
pub const writeParameterStateHeaderForCount = codec.writeParameterStateHeaderForCount;
pub const readParameterStateHeader = codec.readParameterStateHeader;
pub const writeParameterStateJson = codec.writeParameterStateJson;
pub const readParameterState = codec.readParameterState;
pub const readParameterStateWithMigrations = codec.readParameterStateWithMigrations;
pub const readParameterStateReport = codec.readParameterStateReport;
pub const readParameterStateWithMigrationsReport = codec.readParameterStateWithMigrationsReport;

pub const validateParameterIdMigrations = migrations.validateParameterIdMigrations;
pub const identityParameterMigrationIndex = migrations.identityParameterMigrationIndex;
pub const duplicateParameterMigrationIndex = migrations.duplicateParameterMigrationIndex;
pub const cyclicParameterMigrationIndex = migrations.cyclicParameterMigrationIndex;
pub const ambiguousParameterMigrationIndex = migrations.ambiguousParameterMigrationIndex;
pub const migratedParameterId = migrations.migratedParameterId;

test {
    std.testing.refAllDecls(@import("state/tests.zig"));
}
