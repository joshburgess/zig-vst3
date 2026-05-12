const std = @import("std");
const data_exchange = @import("zig-vst3").pluginterfaces.vst.ivstdataexchange;

pub fn main() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.print("InvalidDataExchangeQueueID {}\n", .{data_exchange.InvalidDataExchangeQueueID});
    try stdout.print("InvalidDataExchangeBlockID {}\n", .{data_exchange.InvalidDataExchangeBlockID});

    try printType(stdout, "DataExchangeBlock", data_exchange.DataExchangeBlock);
    try printOffset(stdout, "DataExchangeBlock", "data", data_exchange.DataExchangeBlock, "data");
    try printOffset(stdout, "DataExchangeBlock", "size", data_exchange.DataExchangeBlock, "size");
    try printOffset(stdout, "DataExchangeBlock", "blockID", data_exchange.DataExchangeBlock, "blockID");

    try printType(stdout, "IDataExchangeHandler", data_exchange.IDataExchangeHandler);
    try printType(stdout, "IDataExchangeReceiver", data_exchange.IDataExchangeReceiver);

    try printTuid(stdout, "IDataExchangeHandler", data_exchange.idata_exchange_handler_iid);
    try printTuid(stdout, "IDataExchangeReceiver", data_exchange.idata_exchange_receiver_iid);
}

fn printType(writer: anytype, comptime name: []const u8, comptime Type: type) !void {
    try writer.print("{s} size {} align {}\n", .{ name, @sizeOf(Type), @alignOf(Type) });
}

fn printOffset(writer: anytype, comptime type_name: []const u8, comptime field_label: []const u8, comptime Type: type, comptime field_name: []const u8) !void {
    try writer.print("{s}.{s} offset {}\n", .{ type_name, field_label, @offsetOf(Type, field_name) });
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
