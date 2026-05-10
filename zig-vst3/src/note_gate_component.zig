const ibstream = @import("pluginterfaces/base/ibstream.zig");
const note_gate_controller = @import("note_gate_controller.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0x70E3A630, 0x5EE54F09, 0x94C968A8, 0x22947A9F);

const NoteGateState = struct {
    open: bool = false,
    held_notes: [128]bool = [_]bool{false} ** 128,
    held_note_count: usize = 0,

    fn process(self: *NoteGateState, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        var segments = context.inputEventBlockSegments();
        while (segments.next()) |segment| {
            self.applyEventsAt(Sample, context, segment.start_offset);
            for (0..context.outputChannelCount()) |channel| {
                const input = context.inputChannel(channel) orelse continue;
                const output = context.outputChannel(channel) orelse continue;
                if (self.open) {
                    for (segment.start_offset..segment.end_offset) |sample| {
                        output[sample] = input[sample];
                    }
                } else {
                    @memset(output[segment.start_offset..segment.end_offset], 0);
                }
            }
        }
    }

    fn applyEventsAt(self: *NoteGateState, comptime Sample: type, context: *plug_process.ProcessContext(Sample), sample_offset: usize) void {
        var events = context.inputEventsAtOffset(sample_offset);
        while (events.next()) |event| {
            if (event.asNoteAttack()) |note| {
                self.holdNote(note.pitch);
            } else if (event.asNoteRelease()) |note| {
                self.releaseNote(note.pitch);
            }
        }
    }

    fn holdNote(self: *NoteGateState, pitch: i16) void {
        const index = @as(usize, @intCast(pitch));
        if (!self.held_notes[index]) {
            self.held_notes[index] = true;
            self.held_note_count += 1;
        }
        self.open = true;
    }

    fn releaseNote(self: *NoteGateState, pitch: i16) void {
        const index = @as(usize, @intCast(pitch));
        if (self.held_notes[index]) {
            self.held_notes[index] = false;
            self.held_note_count -= 1;
        }
        self.open = self.held_note_count > 0;
    }
};

var gate = NoteGateState{};

fn resetNoteGateState() void {
    gate = .{};
}

const NoteGateProcessor = struct {
    pub fn process(_: NoteGateProcessor, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        gate.process(Sample, context);
    }
};

const Effect = zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "NoteGateComponent";
    pub const controller_cid = note_gate_controller.cid;
    pub const Processor = NoteGateProcessor;

    pub fn resetProcessState() void {
        resetNoteGateState();
    }

    pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
        note_gate_controller.applyParameterChanges(changes);
    }

    pub fn readState(state: ?*ibstream.IBStream) types.tresult {
        return note_gate_controller.readState(state);
    }

    pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
        return note_gate_controller.writeState(state);
    }
});

pub const create = Effect.create;

test "note gate component can be created as IComponent" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expect(component_iface.vtable.release(component_iface) >= 1);
}

test "note gate processor follows event offsets inside a block" {
    const std = @import("std");

    var local_gate = NoteGateState{};
    const input = [_]f32{ 0.25, -0.5, 1.0, -1.0 };
    var output = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(1, 0, 60, 0.75),
        plug_process.Event.noteOff(3, 0, 60, 0.0),
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    local_gate.process(f32, &context);

    try std.testing.expectEqual(@as(f32, 0.0), output[0]);
    try std.testing.expectEqual(@as(f32, -0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 1.0), output[2]);
    try std.testing.expectEqual(@as(f32, 0.0), output[3]);
    try std.testing.expect(!local_gate.open);
    try std.testing.expectEqual(@as(usize, 0), local_gate.held_note_count);
}

test "note gate processor stays open while overlapping notes are held" {
    const std = @import("std");

    var local_gate = NoteGateState{};
    const input = [_]f32{ 0.25, -0.5, 1.0, -1.0, 0.125 };
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(0, 0, 60, 0.75),
        plug_process.Event.noteOn(1, 0, 64, 0.75),
        plug_process.Event.noteOff(2, 0, 60, 0.0),
        plug_process.Event.noteOff(4, 0, 64, 0.0),
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    local_gate.process(f32, &context);

    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, -0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 1.0), output[2]);
    try std.testing.expectEqual(@as(f32, -1.0), output[3]);
    try std.testing.expectEqual(@as(f32, 0.0), output[4]);
    try std.testing.expect(!local_gate.open);
    try std.testing.expectEqual(@as(usize, 0), local_gate.held_note_count);
}

test "note gate processor treats zero-velocity note-on as note-off" {
    const std = @import("std");

    var local_gate = NoteGateState{};
    const input = [_]f32{ 0.25, -0.5, 1.0, -1.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(0, 0, 60, 0.75),
        plug_process.Event.noteOn(1, 0, 64, 0.75),
        plug_process.Event.noteOn(2, 0, 60, 0.0),
        plug_process.Event.noteOn(3, 0, 64, 0.0),
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    local_gate.process(f32, &context);

    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, -0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 1.0), output[2]);
    try std.testing.expectEqual(@as(f32, 0.0), output[3]);
    try std.testing.expect(!local_gate.open);
    try std.testing.expectEqual(@as(usize, 0), local_gate.held_note_count);
}

test "note gate component resets process state when deactivated" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    resetNoteGateState();
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(0, 0, 60, 0.75),
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });
    (NoteGateProcessor{}).process(f32, &context);
    try std.testing.expect(gate.open);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.setActive(component_iface, 0));
    try std.testing.expect(!gate.open);
    try std.testing.expectEqual(@as(usize, 0), gate.held_note_count);
}
