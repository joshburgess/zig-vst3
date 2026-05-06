const base = @import("../base/types.zig");
const vsttypes = @import("vsttypes.zig");

pub const kSpeakerL: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 0;
pub const kSpeakerR: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 1;
pub const kSpeakerC: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 2;
pub const kSpeakerLfe: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 3;
pub const kSpeakerLs: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 4;
pub const kSpeakerRs: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 5;
pub const kSpeakerLc: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 6;
pub const kSpeakerRc: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 7;
pub const kSpeakerS: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 8;
pub const kSpeakerCs = kSpeakerS;
pub const kSpeakerSl: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 9;
pub const kSpeakerSr: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 10;
pub const kSpeakerTc: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 11;
pub const kSpeakerTfl: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 12;
pub const kSpeakerTfc: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 13;
pub const kSpeakerTfr: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 14;
pub const kSpeakerTrl: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 15;
pub const kSpeakerTrc: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 16;
pub const kSpeakerTrr: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 17;
pub const kSpeakerLfe2: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 18;
pub const kSpeakerM: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 19;
pub const kSpeakerACN0: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 20;
pub const kSpeakerACN1: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 21;
pub const kSpeakerACN2: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 22;
pub const kSpeakerACN3: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 23;
pub const kSpeakerTsl: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 24;
pub const kSpeakerTsr: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 25;
pub const kSpeakerLcs: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 26;
pub const kSpeakerRcs: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 27;
pub const kSpeakerBfl: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 28;
pub const kSpeakerBfc: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 29;
pub const kSpeakerBfr: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 30;
pub const kSpeakerPl: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 31;
pub const kSpeakerPr: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 32;
pub const kSpeakerBsl: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 33;
pub const kSpeakerBsr: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 34;
pub const kSpeakerBrl: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 35;
pub const kSpeakerBrc: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 36;
pub const kSpeakerBrr: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 37;
pub const kSpeakerACN4: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 38;
pub const kSpeakerACN5: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 39;
pub const kSpeakerACN6: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 40;
pub const kSpeakerACN7: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 41;
pub const kSpeakerACN8: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 42;
pub const kSpeakerACN9: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 43;
pub const kSpeakerACN10: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 44;
pub const kSpeakerACN11: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 45;
pub const kSpeakerACN12: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 46;
pub const kSpeakerACN13: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 47;
pub const kSpeakerACN14: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 48;
pub const kSpeakerACN15: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 49;
pub const kSpeakerACN16: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 50;
pub const kSpeakerACN17: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 51;
pub const kSpeakerACN18: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 52;
pub const kSpeakerACN19: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 53;
pub const kSpeakerACN20: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 54;
pub const kSpeakerACN21: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 55;
pub const kSpeakerACN22: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 56;
pub const kSpeakerACN23: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 57;
pub const kSpeakerACN24: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 58;
pub const kSpeakerLw: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 59;
pub const kSpeakerRw: vsttypes.Speaker = @as(vsttypes.Speaker, 1) << 60;

pub const SpeakerArr = struct {
    pub const kEmpty: vsttypes.SpeakerArrangement = 0;
    pub const kMono: vsttypes.SpeakerArrangement = kSpeakerM;
    pub const kStereo: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR;
    pub const kStereoWide: vsttypes.SpeakerArrangement = kSpeakerLw | kSpeakerRw;
    pub const kStereoSurround: vsttypes.SpeakerArrangement = kSpeakerLs | kSpeakerRs;
    pub const kStereoCenter: vsttypes.SpeakerArrangement = kSpeakerLc | kSpeakerRc;
    pub const kStereoSide: vsttypes.SpeakerArrangement = kSpeakerSl | kSpeakerSr;
    pub const kStereoCLfe: vsttypes.SpeakerArrangement = kSpeakerC | kSpeakerLfe;
    pub const kStereoTF: vsttypes.SpeakerArrangement = kSpeakerTfl | kSpeakerTfr;
    pub const kStereoTS: vsttypes.SpeakerArrangement = kSpeakerTsl | kSpeakerTsr;
    pub const kStereoTR: vsttypes.SpeakerArrangement = kSpeakerTrl | kSpeakerTrr;
    pub const kStereoBF: vsttypes.SpeakerArrangement = kSpeakerBfl | kSpeakerBfr;
    pub const kCineFront: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLc | kSpeakerRc;
    pub const k30Cine: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC;
    pub const k31Cine: vsttypes.SpeakerArrangement = k30Cine | kSpeakerLfe;
    pub const k30Music: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerCs;
    pub const k31Music: vsttypes.SpeakerArrangement = k30Music | kSpeakerLfe;
    pub const k40Cine: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerCs;
    pub const k41Cine: vsttypes.SpeakerArrangement = k40Cine | kSpeakerLfe;
    pub const k40Music: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerLs | kSpeakerRs;
    pub const k41Music: vsttypes.SpeakerArrangement = k40Music | kSpeakerLfe;
    pub const k50: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs;
    pub const k51: vsttypes.SpeakerArrangement = k50 | kSpeakerLfe;
    pub const k60Cine: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerCs;
    pub const k61Cine: vsttypes.SpeakerArrangement = k60Cine | kSpeakerLfe;
    pub const k60Music: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerLs | kSpeakerRs | kSpeakerSl | kSpeakerSr;
    pub const k61Music: vsttypes.SpeakerArrangement = k60Music | kSpeakerLfe;
    pub const k70Cine: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerLc | kSpeakerRc;
    pub const k71Cine: vsttypes.SpeakerArrangement = k70Cine | kSpeakerLfe;
    pub const k71CineFullFront: vsttypes.SpeakerArrangement = k71Cine;
    pub const k70Music: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerSl | kSpeakerSr;
    pub const k71Music: vsttypes.SpeakerArrangement = k70Music | kSpeakerLfe;
    pub const k71CineFullRear: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLfe | kSpeakerLs | kSpeakerRs | kSpeakerLcs | kSpeakerRcs;
    pub const k71CineSideFill: vsttypes.SpeakerArrangement = k71Music;
    pub const k71Proximity: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLfe | kSpeakerLs | kSpeakerRs | kSpeakerPl | kSpeakerPr;
    pub const k80Cine: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerLc | kSpeakerRc | kSpeakerCs;
    pub const k81Cine: vsttypes.SpeakerArrangement = k80Cine | kSpeakerLfe;
    pub const k80Music: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerCs | kSpeakerSl | kSpeakerSr;
    pub const k81Music: vsttypes.SpeakerArrangement = k80Music | kSpeakerLfe;
    pub const k90Cine: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerLc | kSpeakerRc | kSpeakerSl | kSpeakerSr;
    pub const k91Cine: vsttypes.SpeakerArrangement = k90Cine | kSpeakerLfe;
    pub const k100Cine: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerLc | kSpeakerRc | kSpeakerCs | kSpeakerSl | kSpeakerSr;
    pub const k101Cine: vsttypes.SpeakerArrangement = k100Cine | kSpeakerLfe;
    pub const kAmbi1stOrderACN: vsttypes.SpeakerArrangement = kSpeakerACN0 | kSpeakerACN1 | kSpeakerACN2 | kSpeakerACN3;
    pub const kAmbi2cdOrderACN: vsttypes.SpeakerArrangement = kAmbi1stOrderACN | kSpeakerACN4 | kSpeakerACN5 | kSpeakerACN6 | kSpeakerACN7 | kSpeakerACN8;
    pub const kAmbi3rdOrderACN: vsttypes.SpeakerArrangement = kAmbi2cdOrderACN | kSpeakerACN9 | kSpeakerACN10 | kSpeakerACN11 | kSpeakerACN12 | kSpeakerACN13 | kSpeakerACN14 | kSpeakerACN15;
    pub const kAmbi4thOrderACN: vsttypes.SpeakerArrangement = kAmbi3rdOrderACN | kSpeakerACN16 | kSpeakerACN17 | kSpeakerACN18 | kSpeakerACN19 | kSpeakerACN20 | kSpeakerACN21 | kSpeakerACN22 | kSpeakerACN23 | kSpeakerACN24;
    pub const kAmbi5thOrderACN: vsttypes.SpeakerArrangement = 0x000FFFFFFFFF;
    pub const kAmbi6thOrderACN: vsttypes.SpeakerArrangement = 0x0001FFFFFFFFFFFF;
    pub const kAmbi7thOrderACN: vsttypes.SpeakerArrangement = 0xFFFFFFFFFFFFFFFF;
    pub const k80Cube: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerLs | kSpeakerRs | kSpeakerTfl | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr;
    pub const k40_4: vsttypes.SpeakerArrangement = k80Cube;
    pub const k71CineTopCenter: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLfe | kSpeakerLs | kSpeakerRs | kSpeakerCs | kSpeakerTc;
    pub const k71CineCenterHigh: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLfe | kSpeakerLs | kSpeakerRs | kSpeakerCs | kSpeakerTfc;
    pub const k70CineFrontHigh: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerTfl | kSpeakerTfr;
    pub const k70MPEG3D: vsttypes.SpeakerArrangement = k70CineFrontHigh;
    pub const k50_2: vsttypes.SpeakerArrangement = k70CineFrontHigh;
    pub const k71CineFrontHigh: vsttypes.SpeakerArrangement = k70CineFrontHigh | kSpeakerLfe;
    pub const k71MPEG3D: vsttypes.SpeakerArrangement = k71CineFrontHigh;
    pub const k51_2: vsttypes.SpeakerArrangement = k71CineFrontHigh;
    pub const k70CineSideHigh: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerTsl | kSpeakerTsr;
    pub const k50_2_TS: vsttypes.SpeakerArrangement = k70CineSideHigh;
    pub const k71CineSideHigh: vsttypes.SpeakerArrangement = k70CineSideHigh | kSpeakerLfe;
    pub const k51_2_TS: vsttypes.SpeakerArrangement = k71CineSideHigh;
    pub const k81MPEG3D: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerLfe | kSpeakerLs | kSpeakerRs | kSpeakerTfl | kSpeakerTfc | kSpeakerTfr | kSpeakerBfc;
    pub const k41_4_1: vsttypes.SpeakerArrangement = k81MPEG3D;
    pub const k90: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerTfl | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr;
    pub const k50_4: vsttypes.SpeakerArrangement = k90;
    pub const k91: vsttypes.SpeakerArrangement = k90 | kSpeakerLfe;
    pub const k51_4: vsttypes.SpeakerArrangement = k91;
    pub const k50_4_1: vsttypes.SpeakerArrangement = k50_4 | kSpeakerBfc;
    pub const k51_4_1: vsttypes.SpeakerArrangement = k50_4_1 | kSpeakerLfe;
    pub const k70_2: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerSl | kSpeakerSr | kSpeakerTsl | kSpeakerTsr;
    pub const k71_2: vsttypes.SpeakerArrangement = k70_2 | kSpeakerLfe;
    pub const k91Atmos: vsttypes.SpeakerArrangement = k71_2;
    pub const k70_2_TF: vsttypes.SpeakerArrangement = k70Music | kSpeakerTfl | kSpeakerTfr;
    pub const k71_2_TF: vsttypes.SpeakerArrangement = k70_2_TF | kSpeakerLfe;
    pub const k70_3: vsttypes.SpeakerArrangement = k70_2_TF | kSpeakerTrc;
    pub const k72_3: vsttypes.SpeakerArrangement = k70_3 | kSpeakerLfe | kSpeakerLfe2;
    pub const k70_4: vsttypes.SpeakerArrangement = k70_2_TF | kSpeakerTrl | kSpeakerTrr;
    pub const k71_4: vsttypes.SpeakerArrangement = k70_4 | kSpeakerLfe;
    pub const k111MPEG3D: vsttypes.SpeakerArrangement = k71_4;
};

pub fn getChannelCount(arrangement: vsttypes.SpeakerArrangement) base.int32 {
    return @intCast(@popCount(arrangement));
}

pub fn getSpeakerIndex(speaker: vsttypes.Speaker, arrangement: vsttypes.SpeakerArrangement) base.int32 {
    if (speaker == 0) return -1;
    if ((arrangement & speaker) == 0) return -1;
    return @intCast(@popCount(arrangement & (speaker - 1)));
}

pub fn getSpeaker(arrangement: vsttypes.SpeakerArrangement, index: base.int32) vsttypes.Speaker {
    if (index < 0) return 0;
    var remaining = arrangement;
    var current_index: base.int32 = -1;
    var pos: u6 = 0;
    while (remaining != 0) {
        if ((remaining & 1) != 0) current_index += 1;
        if (current_index == index) return @as(vsttypes.Speaker, 1) << pos;
        remaining >>= 1;
        if (remaining == 0) break;
        pos += 1;
    }
    return 0;
}

pub fn isSubsetOf(subset: vsttypes.SpeakerArrangement, arrangement: vsttypes.SpeakerArrangement) bool {
    return subset == (subset & arrangement);
}

pub fn hasTopSpeakers(arrangement: vsttypes.SpeakerArrangement) bool {
    const top = kSpeakerTc | kSpeakerTfl | kSpeakerTfc | kSpeakerTfr | kSpeakerTrl | kSpeakerTrc | kSpeakerTrr | kSpeakerTsl | kSpeakerTsr;
    return (arrangement & top) != 0;
}

pub fn hasBottomSpeakers(arrangement: vsttypes.SpeakerArrangement) bool {
    const bottom = kSpeakerBfl | kSpeakerBfc | kSpeakerBfr | kSpeakerBsl | kSpeakerBsr | kSpeakerBrr | kSpeakerBrl | kSpeakerBrc;
    return (arrangement & bottom) != 0;
}

pub fn hasMiddleSpeakers(arrangement: vsttypes.SpeakerArrangement) bool {
    const middle = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerLc | kSpeakerRc | kSpeakerCs | kSpeakerSl | kSpeakerSr | kSpeakerM | kSpeakerPl | kSpeakerPr | kSpeakerLcs | kSpeakerRcs | kSpeakerLw | kSpeakerRw;
    return (arrangement & middle) != 0;
}

pub fn hasLfe(arrangement: vsttypes.SpeakerArrangement) bool {
    return (arrangement & (kSpeakerLfe | kSpeakerLfe2)) != 0;
}

pub fn is3D(arrangement: vsttypes.SpeakerArrangement) bool {
    const top = hasTopSpeakers(arrangement);
    const bottom = hasBottomSpeakers(arrangement);
    const middle = hasMiddleSpeakers(arrangement);
    return ((top or bottom) and middle) or (top and bottom);
}

pub fn isAmbisonics(arrangement: vsttypes.SpeakerArrangement) bool {
    return arrangement == SpeakerArr.kAmbi1stOrderACN or
        arrangement == SpeakerArr.kAmbi2cdOrderACN or
        arrangement == SpeakerArr.kAmbi3rdOrderACN or
        arrangement == SpeakerArr.kAmbi4thOrderACN or
        arrangement == SpeakerArr.kAmbi5thOrderACN or
        arrangement == SpeakerArr.kAmbi6thOrderACN or
        arrangement == SpeakerArr.kAmbi7thOrderACN;
}

pub const SpeakerArray = struct {
    pub const kMaxSpeakers = 64;
    pub const SpeakerType = base.uint64;

    count: base.int32 = 0,
    speaker: [kMaxSpeakers]SpeakerType = [_]SpeakerType{0} ** kMaxSpeakers,

    pub fn init(arrangement: vsttypes.SpeakerArrangement) SpeakerArray {
        var result = SpeakerArray{};
        result.setArrangement(arrangement);
        return result;
    }

    pub fn total(self: *const SpeakerArray) base.int32 {
        return self.count;
    }

    pub fn at(self: *const SpeakerArray, index: base.int32) SpeakerType {
        return self.speaker[@intCast(index)];
    }

    pub fn setArrangement(self: *SpeakerArray, arrangement: vsttypes.SpeakerArrangement) void {
        self.count = 0;
        self.speaker = [_]SpeakerType{0} ** kMaxSpeakers;

        var index: u6 = 0;
        while (true) {
            const mask: SpeakerType = @as(SpeakerType, 1) << index;
            if ((arrangement & mask) != 0) {
                self.speaker[@intCast(self.count)] = mask;
                self.count += 1;
            }
            if (index == kMaxSpeakers - 1) break;
            index += 1;
        }
    }

    pub fn getArrangement(self: *const SpeakerArray) vsttypes.SpeakerArrangement {
        var arrangement: vsttypes.SpeakerArrangement = 0;
        var index: base.int32 = 0;
        while (index < self.count) : (index += 1) {
            arrangement |= self.speaker[@intCast(index)];
        }
        return arrangement;
    }

    pub fn getSpeakerIndex(self: *const SpeakerArray, which: SpeakerType) base.int32 {
        var index: base.int32 = 0;
        while (index < self.count) : (index += 1) {
            if (self.speaker[@intCast(index)] == which) return index;
        }
        return -1;
    }
};

test "speaker helpers match expected core behavior" {
    try @import("std").testing.expectEqual(@as(base.int32, 2), getChannelCount(SpeakerArr.kStereo));
    try @import("std").testing.expectEqual(@as(base.int32, 1), getSpeakerIndex(kSpeakerR, SpeakerArr.kStereo));
    try @import("std").testing.expectEqual(kSpeakerC, getSpeaker(SpeakerArr.k51, 2));
    try @import("std").testing.expect(isSubsetOf(SpeakerArr.kStereo, SpeakerArr.k51));
    try @import("std").testing.expect(hasTopSpeakers(SpeakerArr.k50_4));
    try @import("std").testing.expect(hasLfe(SpeakerArr.k51));
    try @import("std").testing.expect(is3D(SpeakerArr.k50_4));
    try @import("std").testing.expect(isAmbisonics(SpeakerArr.kAmbi1stOrderACN));
    const speakers = SpeakerArray.init(SpeakerArr.k51);
    try @import("std").testing.expectEqual(@as(base.int32, 6), speakers.total());
    try @import("std").testing.expectEqual(SpeakerArr.k51, speakers.getArrangement());
    try @import("std").testing.expectEqual(@as(base.int32, 3), speakers.getSpeakerIndex(kSpeakerLfe));
}
