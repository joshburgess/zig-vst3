const std = @import("std");
const audio_block = @import("audio_block.zig");

pub const ProcessSpec = struct {
    sample_rate: f64,
    maximum_frames: usize,
    channel_count: usize,

    pub fn validate(self: ProcessSpec) !void {
        if (!std.math.isFinite(self.sample_rate) or
            self.sample_rate < 1_000.0 or
            self.sample_rate > 768_000.0 or
            self.maximum_frames == 0 or
            self.channel_count == 0)
            return error.InvalidProcessSpec;
    }

    pub fn valid(self: ProcessSpec) bool {
        self.validate() catch return false;
        return true;
    }
};

pub fn ProcessContextReplacing(
    comptime Sample: type,
    comptime maximum_channels: usize,
) type {
    return struct {
        const Block = audio_block.AudioBlock(Sample, maximum_channels);

        block: Block,
        bypassed: bool = false,

        pub fn init(block: Block) !@This() {
            if (!block.valid()) return error.InvalidAudioBlock;
            return .{ .block = block };
        }

        pub fn input(self: *const @This()) audio_block.ConstAudioBlock(
            Sample,
            maximum_channels,
        ) {
            return self.block.asConst();
        }

        pub fn output(self: *@This()) *Block {
            return &self.block;
        }
    };
}

pub fn ProcessContextNonReplacing(
    comptime Sample: type,
    comptime maximum_channels: usize,
) type {
    return struct {
        const ConstBlock = audio_block.ConstAudioBlock(
            Sample,
            maximum_channels,
        );
        const Block = audio_block.AudioBlock(Sample, maximum_channels);

        input_block: ConstBlock,
        output_block: Block,
        bypassed: bool = false,

        pub fn init(input_block: ConstBlock, output_block: Block) !@This() {
            if (!input_block.valid() or !output_block.valid())
                return error.InvalidAudioBlock;
            if (input_block.channel_count != output_block.channel_count or
                input_block.frame_count != output_block.frame_count)
                return error.ProcessContextShapeMismatch;
            return .{
                .input_block = input_block,
                .output_block = output_block,
            };
        }

        pub fn input(self: *const @This()) *const ConstBlock {
            return &self.input_block;
        }

        pub fn output(self: *@This()) *Block {
            return &self.output_block;
        }

        pub fn bypassCopy(self: *@This()) !void {
            try self.output_block.copyFrom(self.input_block);
        }
    };
}

test "process specs reject impossible preparation contracts" {
    const valid = ProcessSpec{
        .sample_rate = 48_000.0,
        .maximum_frames = 512,
        .channel_count = 2,
    };
    try valid.validate();
    try std.testing.expect(valid.valid());
    var invalid = valid;
    invalid.maximum_frames = 0;
    try std.testing.expectError(error.InvalidProcessSpec, invalid.validate());
    try std.testing.expect(!invalid.valid());
}

test "replacing process context aliases its input and output" {
    var samples = [_]f32{ 0.25, 0.5 };
    const Block = audio_block.AudioBlock(f32, 1);
    var context = try ProcessContextReplacing(f32, 1).init(
        try Block.init(&.{samples[0..]}),
    );
    var output = context.output();
    try output.multiply(2.0);
    const input = context.input();
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.5, 1.0 },
        try input.channel(0),
    );
}

test "non-replacing process context validates shape and copies bypass" {
    const source = [_]f64{ 0.25, 0.75 };
    var destination = [_]f64{ 0.0, 0.0 };
    const ConstBlock = audio_block.ConstAudioBlock(f64, 1);
    const Block = audio_block.AudioBlock(f64, 1);
    var context = try ProcessContextNonReplacing(f64, 1).init(
        try ConstBlock.init(&.{source[0..]}),
        try Block.init(&.{destination[0..]}),
    );
    try context.bypassCopy();
    try std.testing.expectEqualSlices(f64, &source, &destination);

    var larger = [_]f64{ 0.0, 0.0, 0.0 };
    try std.testing.expectError(
        error.ProcessContextShapeMismatch,
        ProcessContextNonReplacing(f64, 1).init(
            try ConstBlock.init(&.{source[0..]}),
            try Block.init(&.{larger[0..]}),
        ),
    );
}
