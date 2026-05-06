const std = @import("std");
const speaker = @import("vst3-zig").pluginterfaces.vst.vstspeaker;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("kSpeakerL {}\n", .{speaker.kSpeakerL});
    try stdout.print("kSpeakerR {}\n", .{speaker.kSpeakerR});
    try stdout.print("kSpeakerLfe {}\n", .{speaker.kSpeakerLfe});
    try stdout.print("kSpeakerTfl {}\n", .{speaker.kSpeakerTfl});
    try stdout.print("kSpeakerBfl {}\n", .{speaker.kSpeakerBfl});
    try stdout.print("kSpeakerACN24 {}\n", .{speaker.kSpeakerACN24});
    try stdout.print("kSpeakerRw {}\n", .{speaker.kSpeakerRw});
    try stdout.print("kStereo {}\n", .{speaker.SpeakerArr.kStereo});
    try stdout.print("k51 {}\n", .{speaker.SpeakerArr.k51});
    try stdout.print("k71Music {}\n", .{speaker.SpeakerArr.k71Music});
    try stdout.print("kAmbi1stOrderACN {}\n", .{speaker.SpeakerArr.kAmbi1stOrderACN});
    try stdout.print("kAmbi7thOrderACN {}\n", .{speaker.SpeakerArr.kAmbi7thOrderACN});
    try stdout.print("k50_4 {}\n", .{speaker.SpeakerArr.k50_4});
    try stdout.print("k71_4 {}\n", .{speaker.SpeakerArr.k71_4});
    try stdout.print("getChannelCount.k51 {}\n", .{speaker.getChannelCount(speaker.SpeakerArr.k51)});
    try stdout.print("getSpeakerIndex.R.stereo {}\n", .{speaker.getSpeakerIndex(speaker.kSpeakerR, speaker.SpeakerArr.kStereo)});
    try stdout.print("getSpeaker.k51.2 {}\n", .{speaker.getSpeaker(speaker.SpeakerArr.k51, 2)});
    try stdout.print("isSubsetOf.stereo.51 {}\n", .{@intFromBool(speaker.isSubsetOf(speaker.SpeakerArr.kStereo, speaker.SpeakerArr.k51))});
    try stdout.print("hasTopSpeakers.50_4 {}\n", .{@intFromBool(speaker.hasTopSpeakers(speaker.SpeakerArr.k50_4))});
    try stdout.print("hasBottomSpeakers.50_4 {}\n", .{@intFromBool(speaker.hasBottomSpeakers(speaker.SpeakerArr.k50_4))});
    try stdout.print("hasMiddleSpeakers.50_4 {}\n", .{@intFromBool(speaker.hasMiddleSpeakers(speaker.SpeakerArr.k50_4))});
    try stdout.print("hasLfe.51 {}\n", .{@intFromBool(speaker.hasLfe(speaker.SpeakerArr.k51))});
    try stdout.print("is3D.50_4 {}\n", .{@intFromBool(speaker.is3D(speaker.SpeakerArr.k50_4))});
    try stdout.print("isAmbisonics.ambi1 {}\n", .{@intFromBool(speaker.isAmbisonics(speaker.SpeakerArr.kAmbi1stOrderACN))});
    var speaker_array = speaker.SpeakerArray.init(speaker.SpeakerArr.k51);
    try stdout.print("SpeakerArray.total.51 {}\n", .{speaker_array.total()});
    try stdout.print("SpeakerArray.at.51.0 {}\n", .{speaker_array.at(0)});
    try stdout.print("SpeakerArray.at.51.3 {}\n", .{speaker_array.at(3)});
    try stdout.print("SpeakerArray.getArrangement.51 {}\n", .{speaker_array.getArrangement()});
    try stdout.print("SpeakerArray.getSpeakerIndex.Lfe {}\n", .{speaker_array.getSpeakerIndex(speaker.kSpeakerLfe)});
    speaker_array.setArrangement(speaker.SpeakerArr.k50_4);
    try stdout.print("SpeakerArray.total.50_4 {}\n", .{speaker_array.total()});
    try stdout.print("SpeakerArray.getArrangement.50_4 {}\n", .{speaker_array.getArrangement()});
}
