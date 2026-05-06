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
    pub const k70_6: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerSl | kSpeakerSr | kSpeakerTfl | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr | kSpeakerTsl | kSpeakerTsr;
    pub const k71_6: vsttypes.SpeakerArrangement = k70_6 | kSpeakerLfe;
    pub const k90_4: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerLc | kSpeakerRc | kSpeakerSl | kSpeakerSr | kSpeakerTfl | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr;
    pub const k91_4: vsttypes.SpeakerArrangement = k90_4 | kSpeakerLfe;
    pub const k90_6: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerLc | kSpeakerRc | kSpeakerSl | kSpeakerSr | kSpeakerTfl | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr | kSpeakerTsl | kSpeakerTsr;
    pub const k91_6: vsttypes.SpeakerArrangement = k90_6 | kSpeakerLfe;
    pub const k90_4_W: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerLw | kSpeakerRw | kSpeakerSl | kSpeakerSr | kSpeakerTfl | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr;
    pub const k91_4_W: vsttypes.SpeakerArrangement = k90_4_W | kSpeakerLfe;
    pub const k90_6_W: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerLw | kSpeakerRw | kSpeakerSl | kSpeakerSr | kSpeakerTfl | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr | kSpeakerTsl | kSpeakerTsr;
    pub const k91_6_W: vsttypes.SpeakerArrangement = k90_6_W | kSpeakerLfe;
    pub const k100: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerTc | kSpeakerTfl | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr;
    pub const k50_5: vsttypes.SpeakerArrangement = k100;
    pub const k101: vsttypes.SpeakerArrangement = k50_5 | kSpeakerLfe;
    pub const k101MPEG3D: vsttypes.SpeakerArrangement = k101;
    pub const k51_5: vsttypes.SpeakerArrangement = k101;
    pub const k102: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLfe | kSpeakerLs | kSpeakerRs | kSpeakerTfl | kSpeakerTfc | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr | kSpeakerLfe2;
    pub const k52_5: vsttypes.SpeakerArrangement = k102;
    pub const k110: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerTc | kSpeakerTfl | kSpeakerTfc | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr;
    pub const k50_6: vsttypes.SpeakerArrangement = k110;
    pub const k111: vsttypes.SpeakerArrangement = k110 | kSpeakerLfe;
    pub const k51_6: vsttypes.SpeakerArrangement = k111;
    pub const k122: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLfe | kSpeakerLs | kSpeakerRs | kSpeakerLc | kSpeakerRc | kSpeakerTfl | kSpeakerTfc | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr | kSpeakerLfe2;
    pub const k72_5: vsttypes.SpeakerArrangement = k122;
    pub const k130: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerSl | kSpeakerSr | kSpeakerTc | kSpeakerTfl | kSpeakerTfc | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr;
    pub const k131: vsttypes.SpeakerArrangement = k130 | kSpeakerLfe;
    pub const k140: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerLs | kSpeakerRs | kSpeakerSl | kSpeakerSr | kSpeakerTfl | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr | kSpeakerBfl | kSpeakerBfr | kSpeakerBrl | kSpeakerBrr;
    pub const k60_4_4: vsttypes.SpeakerArrangement = k140;
    pub const k220: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerLc | kSpeakerRc | kSpeakerCs | kSpeakerSl | kSpeakerSr | kSpeakerTc | kSpeakerTfl | kSpeakerTfc | kSpeakerTfr | kSpeakerTrl | kSpeakerTrc | kSpeakerTrr | kSpeakerTsl | kSpeakerTsr | kSpeakerBfl | kSpeakerBfc | kSpeakerBfr;
    pub const k100_9_3: vsttypes.SpeakerArrangement = k220;
    pub const k222: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLfe | kSpeakerLs | kSpeakerRs | kSpeakerLc | kSpeakerRc | kSpeakerCs | kSpeakerSl | kSpeakerSr | kSpeakerTc | kSpeakerTfl | kSpeakerTfc | kSpeakerTfr | kSpeakerTrl | kSpeakerTrc | kSpeakerTrr | kSpeakerLfe2 | kSpeakerTsl | kSpeakerTsr | kSpeakerBfl | kSpeakerBfc | kSpeakerBfr;
    pub const k102_9_3: vsttypes.SpeakerArrangement = k222;
    pub const k50_5_3: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerTfl | kSpeakerTfc | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr | kSpeakerBfl | kSpeakerBfc | kSpeakerBfr;
    pub const k51_5_3: vsttypes.SpeakerArrangement = k50_5_3 | kSpeakerLfe;
    pub const k50_2_2: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerTsl | kSpeakerTsr | kSpeakerBfl | kSpeakerBfr;
    pub const k50_4_2: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerTfl | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr | kSpeakerBfl | kSpeakerBfr;
    pub const k70_4_2: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerSl | kSpeakerSr | kSpeakerTfl | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr | kSpeakerBfl | kSpeakerBfr;
    pub const k50_5_Sony: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerTfl | kSpeakerTfc | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr;
    pub const k40_2_2: vsttypes.SpeakerArrangement = kSpeakerC | kSpeakerSl | kSpeakerSr | kSpeakerCs | kSpeakerTsl | kSpeakerTsr | kSpeakerBsl | kSpeakerBsr;
    pub const k40_4_2: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerLs | kSpeakerRs | kSpeakerTfl | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr | kSpeakerBfl | kSpeakerBfr;
    pub const k50_3_2: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerTfl | kSpeakerTfc | kSpeakerTfr | kSpeakerBfl | kSpeakerBfr;
    pub const k30_5_2: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerTfl | kSpeakerTfc | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr | kSpeakerBfl | kSpeakerBfr;
    pub const k40_4_4: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerLs | kSpeakerRs | kSpeakerTfl | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr | kSpeakerBfl | kSpeakerBfr | kSpeakerBrl | kSpeakerBrr;
    pub const k50_4_4: vsttypes.SpeakerArrangement = kSpeakerL | kSpeakerR | kSpeakerC | kSpeakerLs | kSpeakerRs | kSpeakerTfl | kSpeakerTfr | kSpeakerTrl | kSpeakerTrr | kSpeakerBfl | kSpeakerBfr | kSpeakerBrl | kSpeakerBrr;
};

pub const SpeakerArrStrings = struct {
    pub const kStringEmpty: vsttypes.CString = "";
    pub const kStringMono: vsttypes.CString = "Mono";
    pub const kStringStereo: vsttypes.CString = "Stereo";
    pub const kStringStereoWide: vsttypes.CString = "Stereo (Lw Rw)";
    pub const kStringStereoR: vsttypes.CString = "Stereo (Ls Rs)";
    pub const kStringStereoC: vsttypes.CString = "Stereo (Lc Rc)";
    pub const kStringStereoSide: vsttypes.CString = "Stereo (Sl Sr)";
    pub const kStringStereoCLfe: vsttypes.CString = "Stereo (C LFE)";
    pub const kStringStereoTF: vsttypes.CString = "Stereo (Tfl Tfr)";
    pub const kStringStereoTS: vsttypes.CString = "Stereo (Tsl Tsr)";
    pub const kStringStereoTR: vsttypes.CString = "Stereo (Trl Trr)";
    pub const kStringStereoBF: vsttypes.CString = "Stereo (Bfl Bfr)";
    pub const kStringCineFront: vsttypes.CString = "Cine Front";
    pub const kString30Cine: vsttypes.CString = "LRC";
    pub const kString30Music: vsttypes.CString = "LRS";
    pub const kString31Cine: vsttypes.CString = "LRC+LFE";
    pub const kString31Music: vsttypes.CString = "LRS+LFE";
    pub const kString40Cine: vsttypes.CString = "LRCS";
    pub const kString40Music: vsttypes.CString = "Quadro";
    pub const kString41Cine: vsttypes.CString = "LRCS+LFE";
    pub const kString41Music: vsttypes.CString = "Quadro+LFE";
    pub const kString50: vsttypes.CString = "5.0";
    pub const kString51: vsttypes.CString = "5.1";
    pub const kString60Cine: vsttypes.CString = "6.0 Cine";
    pub const kString60Music: vsttypes.CString = "6.0 Music";
    pub const kString61Cine: vsttypes.CString = "6.1 Cine";
    pub const kString61Music: vsttypes.CString = "6.1 Music";
    pub const kString70Cine: vsttypes.CString = "7.0 SDDS";
    pub const kString70CineOld: vsttypes.CString = "7.0 Cine (SDDS)";
    pub const kString70Music: vsttypes.CString = "7.0";
    pub const kString70MusicOld: vsttypes.CString = "7.0 Music (Dolby)";
    pub const kString71Cine: vsttypes.CString = "7.1 SDDS";
    pub const kString71CineOld: vsttypes.CString = "7.1 Cine (SDDS)";
    pub const kString71Music: vsttypes.CString = "7.1";
    pub const kString71MusicOld: vsttypes.CString = "7.1 Music (Dolby)";
    pub const kString71CineTopCenter: vsttypes.CString = "7.1 Cine Top Center";
    pub const kString71CineCenterHigh: vsttypes.CString = "7.1 Cine Center High";
    pub const kString71CineFullRear: vsttypes.CString = "7.1 Cine Full Rear";
    pub const kString51_2: vsttypes.CString = "5.1.2";
    pub const kString50_2: vsttypes.CString = "5.0.2";
    pub const kString50_2TopSide: vsttypes.CString = "5.0.2 Top Side";
    pub const kString51_2TopSide: vsttypes.CString = "5.1.2 Top Side";
    pub const kString71Proximity: vsttypes.CString = "7.1 Proximity";
    pub const kString80Cine: vsttypes.CString = "8.0 Cine";
    pub const kString80Music: vsttypes.CString = "8.0 Music";
    pub const kString40_4: vsttypes.CString = "8.0 Cube";
    pub const kString81Cine: vsttypes.CString = "8.1 Cine";
    pub const kString81Music: vsttypes.CString = "8.1 Music";
    pub const kString90Cine: vsttypes.CString = "9.0 Cine";
    pub const kString91Cine: vsttypes.CString = "9.1 Cine";
    pub const kString100Cine: vsttypes.CString = "10.0 Cine";
    pub const kString101Cine: vsttypes.CString = "10.1 Cine";
    pub const kString52_5: vsttypes.CString = "5.2.5";
    pub const kString72_5: vsttypes.CString = "12.2";
    pub const kString50_4: vsttypes.CString = "5.0.4";
    pub const kString51_4: vsttypes.CString = "5.1.4";
    pub const kString50_4_1: vsttypes.CString = "5.0.4.1";
    pub const kString51_4_1: vsttypes.CString = "5.1.4.1";
    pub const kString70_2: vsttypes.CString = "7.0.2";
    pub const kString71_2: vsttypes.CString = "7.1.2";
    pub const kString70_2_TF: vsttypes.CString = "7.0.2 Top Front";
    pub const kString71_2_TF: vsttypes.CString = "7.1.2 Top Front";
    pub const kString70_3: vsttypes.CString = "7.0.3";
    pub const kString72_3: vsttypes.CString = "7.2.3";
    pub const kString70_4: vsttypes.CString = "7.0.4";
    pub const kString71_4: vsttypes.CString = "7.1.4";
    pub const kString70_6: vsttypes.CString = "7.0.6";
    pub const kString71_6: vsttypes.CString = "7.1.6";
    pub const kString90_4: vsttypes.CString = "9.0.4 ITU";
    pub const kString91_4: vsttypes.CString = "9.1.4 ITU";
    pub const kString90_6: vsttypes.CString = "9.0.6 ITU";
    pub const kString91_6: vsttypes.CString = "9.1.6 ITU";
    pub const kString90_4_W: vsttypes.CString = "9.0.4";
    pub const kString91_4_W: vsttypes.CString = "9.1.4";
    pub const kString90_6_W: vsttypes.CString = "9.0.6";
    pub const kString91_6_W: vsttypes.CString = "9.1.6";
    pub const kString50_5: vsttypes.CString = "10.0 Auro-3D";
    pub const kString51_5: vsttypes.CString = "10.1 Auro-3D";
    pub const kString50_6: vsttypes.CString = "11.0 Auro-3D";
    pub const kString51_6: vsttypes.CString = "11.1 Auro-3D";
    pub const kString130: vsttypes.CString = "13.0 Auro-3D";
    pub const kString131: vsttypes.CString = "13.1 Auro-3D";
    pub const kString41_4_1: vsttypes.CString = "8.1 MPEG";
    pub const kString60_4_4: vsttypes.CString = "14.0";
    pub const kString220: vsttypes.CString = "22.0";
    pub const kString222: vsttypes.CString = "22.2";
    pub const kString50_5_3: vsttypes.CString = "5.0.5.3";
    pub const kString51_5_3: vsttypes.CString = "5.1.5.3";
    pub const kString50_2_2: vsttypes.CString = "5.0.2.2";
    pub const kString50_4_2: vsttypes.CString = "5.0.4.2";
    pub const kString70_4_2: vsttypes.CString = "7.0.4.2";
    pub const kString50_5_Sony: vsttypes.CString = "5.0.5 Sony";
    pub const kString40_2_2: vsttypes.CString = "4.0.3.2";
    pub const kString40_4_2: vsttypes.CString = "4.0.4.2";
    pub const kString50_3_2: vsttypes.CString = "5.0.3.2";
    pub const kString30_5_2: vsttypes.CString = "3.0.5.2";
    pub const kString40_4_4: vsttypes.CString = "4.0.4.4";
    pub const kString50_4_4: vsttypes.CString = "5.0.4.4";
    pub const kStringAmbi1stOrder: vsttypes.CString = "1OA";
    pub const kStringAmbi2cdOrder: vsttypes.CString = "2OA";
    pub const kStringAmbi3rdOrder: vsttypes.CString = "3OA";
    pub const kStringAmbi4thOrder: vsttypes.CString = "4OA";
    pub const kStringAmbi5thOrder: vsttypes.CString = "5OA";
    pub const kStringAmbi6thOrder: vsttypes.CString = "6OA";
    pub const kStringAmbi7thOrder: vsttypes.CString = "7OA";
    pub const kStringMonoS: vsttypes.CString = "M";
    pub const kStringStereoS: vsttypes.CString = "L R";
    pub const kStringStereoWideS: vsttypes.CString = "Lw Rw";
    pub const kStringStereoRS: vsttypes.CString = "Ls Rs";
    pub const kStringStereoCS: vsttypes.CString = "Lc Rc";
    pub const kStringStereoSS: vsttypes.CString = "Sl Sr";
    pub const kStringStereoCLfeS: vsttypes.CString = "C LFE";
    pub const kStringStereoTFS: vsttypes.CString = "Tfl Tfr";
    pub const kStringStereoTSS: vsttypes.CString = "Tsl Tsr";
    pub const kStringStereoTRS: vsttypes.CString = "Trl Trr";
    pub const kStringStereoBFS: vsttypes.CString = "Bfl Bfr";
    pub const kStringCineFrontS: vsttypes.CString = "L R C Lc Rc";
    pub const kString30CineS: vsttypes.CString = "L R C";
    pub const kString30MusicS: vsttypes.CString = "L R S";
    pub const kString31CineS: vsttypes.CString = "L R C LFE";
    pub const kString31MusicS: vsttypes.CString = "L R LFE S";
    pub const kString40CineS: vsttypes.CString = "L R C S";
    pub const kString40MusicS: vsttypes.CString = "L R Ls Rs";
    pub const kString41CineS: vsttypes.CString = "L R C LFE S";
    pub const kString41MusicS: vsttypes.CString = "L R LFE Ls Rs";
    pub const kString50S: vsttypes.CString = "L R C Ls Rs";
    pub const kString51S: vsttypes.CString = "L R C LFE Ls Rs";
    pub const kString60CineS: vsttypes.CString = "L R C Ls Rs Cs";
    pub const kString60MusicS: vsttypes.CString = "L R Ls Rs Sl Sr";
    pub const kString61CineS: vsttypes.CString = "L R C LFE Ls Rs Cs";
    pub const kString61MusicS: vsttypes.CString = "L R LFE Ls Rs Sl Sr";
    pub const kString70CineS: vsttypes.CString = "L R C Ls Rs Lc Rc";
    pub const kString70MusicS: vsttypes.CString = "L R C Ls Rs Sl Sr";
    pub const kString71CineS: vsttypes.CString = "L R C LFE Ls Rs Lc Rc";
    pub const kString71MusicS: vsttypes.CString = "L R C LFE Ls Rs Sl Sr";
    pub const kString80CineS: vsttypes.CString = "L R C Ls Rs Lc Rc Cs";
    pub const kString80MusicS: vsttypes.CString = "L R C Ls Rs Cs Sl Sr";
    pub const kString81CineS: vsttypes.CString = "L R C LFE Ls Rs Lc Rc Cs";
    pub const kString81MusicS: vsttypes.CString = "L R C LFE Ls Rs Cs Sl Sr";
    pub const kString40_4S: vsttypes.CString = "L R Ls Rs Tfl Tfr Trl Trr";
    pub const kString71CineTopCenterS: vsttypes.CString = "L R C LFE Ls Rs Cs Tc";
    pub const kString71CineCenterHighS: vsttypes.CString = "L R C LFE Ls Rs Cs Tfc";
    pub const kString71CineFullRearS: vsttypes.CString = "L R C LFE Ls Rs Lcs Rcs";
    pub const kString50_2S: vsttypes.CString = "L R C Ls Rs Tfl Tfr";
    pub const kString51_2S: vsttypes.CString = "L R C LFE Ls Rs Tfl Tfr";
    pub const kString50_2TopSideS: vsttypes.CString = "L R C Ls Rs Tsl Tsr";
    pub const kString51_2TopSideS: vsttypes.CString = "L R C LFE Ls Rs Tsl Tsr";
    pub const kString71ProximityS: vsttypes.CString = "L R C LFE Ls Rs Pl Pr";
    pub const kString90CineS: vsttypes.CString = "L R C Ls Rs Lc Rc Sl Sr";
    pub const kString91CineS: vsttypes.CString = "L R C LFE Ls Rs Lc Rc Sl Sr";
    pub const kString100CineS: vsttypes.CString = "L R C Ls Rs Lc Rc Cs Sl Sr";
    pub const kString101CineS: vsttypes.CString = "L R C LFE Ls Rs Lc Rc Cs Sl Sr";
    pub const kString50_4S: vsttypes.CString = "L R C Ls Rs Tfl Tfr Trl Trr";
    pub const kString51_4S: vsttypes.CString = "L R C LFE Ls Rs Tfl Tfr Trl Trr";
    pub const kString50_4_1S: vsttypes.CString = "L R C Ls Rs Tfl Tfr Trl Trr Bfc";
    pub const kString51_4_1S: vsttypes.CString = "L R C LFE Ls Rs Tfl Tfr Trl Trr Bfc";
    pub const kString70_2S: vsttypes.CString = "L R C Ls Rs Sl Sr Tsl Tsr";
    pub const kString71_2S: vsttypes.CString = "L R C LFE Ls Rs Sl Sr Tsl Tsr";
    pub const kString70_2_TFS: vsttypes.CString = "L R C Ls Rs Sl Sr Tfl Tfr";
    pub const kString71_2_TFS: vsttypes.CString = "L R C LFE Ls Rs Sl Sr Tfl Tfr";
    pub const kString70_3S: vsttypes.CString = "L R C Ls Rs Sl Sr Tfl Tfr Trc";
    pub const kString72_3S: vsttypes.CString = "L R C LFE Ls Rs Sl Sr Tfl Tfr Trc LFE2";
    pub const kString70_4S: vsttypes.CString = "L R C Ls Rs Sl Sr Tfl Tfr Trl Trr";
    pub const kString71_4S: vsttypes.CString = "L R C LFE Ls Rs Sl Sr Tfl Tfr Trl Trr";
    pub const kString70_6S: vsttypes.CString = "L R C Ls Rs Sl Sr Tfl Tfr Trl Trr Tsl Tsr";
    pub const kString71_6S: vsttypes.CString = "L R C LFE Ls Rs Sl Sr Tfl Tfr Trl Trr Tsl Tsr";
    pub const kString90_4S: vsttypes.CString = "L R C Ls Rs Lc Rc Sl Sr Tfl Tfr Trl Trr";
    pub const kString91_4S: vsttypes.CString = "L R C LFE Ls Rs Lc Rc Sl Sr Tfl Tfr Trl Trr";
    pub const kString90_6S: vsttypes.CString = "L R C Ls Rs Lc Rc Sl Sr Tfl Tfr Trl Trr Tsl Tsr";
    pub const kString91_6S: vsttypes.CString = "L R C LFE Ls Rs Lc Rc Sl Sr Tfl Tfr Trl Trr Tsl Tsr";
    pub const kString90_4_WS: vsttypes.CString = "L R C Ls Rs Sl Sr Tfl Tfr Trl Trr Lw Rw";
    pub const kString91_4_WS: vsttypes.CString = "L R C LFE Ls Rs Sl Sr Tfl Tfr Trl Trr Lw Rw";
    pub const kString90_6_WS: vsttypes.CString = "L R C Ls Rs Sl Sr Tfl Tfr Trl Trr Tsl Tsr Lw Rw";
    pub const kString91_6_WS: vsttypes.CString = "L R C LFE Ls Rs Sl Sr Tfl Tfr Trl Trr Tsl Tsr Lw Rw";
    pub const kString50_5S: vsttypes.CString = "L R C Ls Rs Tc Tfl Tfr Trl Trr";
    pub const kString51_5S: vsttypes.CString = "L R C LFE Ls Rs Tc Tfl Tfr Trl Trr";
    pub const kString50_5_SonyS: vsttypes.CString = "L R C Ls Rs Tfl Tfc Tfr Trl Trr";
    pub const kString50_6S: vsttypes.CString = "L R C Ls Rs Tc Tfl Tfc Tfr Trl Trr";
    pub const kString51_6S: vsttypes.CString = "L R C LFE Ls Rs Tc Tfl Tfc Tfr Trl Trr";
    pub const kString130S: vsttypes.CString = "L R C Ls Rs Sl Sr Tc Tfl Tfc Tfr Trl Trr";
    pub const kString131S: vsttypes.CString = "L R C LFE Ls Rs Sl Sr Tc Tfl Tfc Tfr Trl Trr";
    pub const kString52_5S: vsttypes.CString = "L R C LFE Ls Rs Tfl Tfc Tfr Trl Trr LFE2";
    pub const kString72_5S: vsttypes.CString = "L R C LFE Ls Rs Lc Rc Tfl Tfc Tfr Trl Trr LFE2";
    pub const kString41_4_1S: vsttypes.CString = "L R LFE Ls Rs Tfl Tfc Tfr Bfc";
    pub const kString30_5_2S: vsttypes.CString = "L R C Tfl Tfc Tfr Trl Trr Bfl Bfr";
    pub const kString40_2_2S: vsttypes.CString = "C Sl Sr Cs Tfc Tsl Tsr Trc";
    pub const kString40_4_2S: vsttypes.CString = "L R Ls Rs Tfl Tfr Trl Trr Bfl Bfr";
    pub const kString40_4_4S: vsttypes.CString = "L R Ls Rs Tfl Tfr Trl Trr Bfl Bfr Brl Brr";
    pub const kString50_4_4S: vsttypes.CString = "L R C Ls Rs Tfl Tfr Trl Trr Bfl Bfr Brl Brr";
    pub const kString60_4_4S: vsttypes.CString = "L R Ls Rs Sl Sr Tfl Tfr Trl Trr Bfl Bfr Brl Brr";
    pub const kString50_5_3S: vsttypes.CString = "L R C Ls Rs Tfl Tfc Tfr Trl Trr Bfl Bfc Bfr";
    pub const kString51_5_3S: vsttypes.CString = "L R C LFE Ls Rs Tfl Tfc Tfr Trl Trr Bfl Bfc Bfr";
    pub const kString50_2_2S: vsttypes.CString = "L R C Ls Rs Tsl Tsr Bfl Bfr";
    pub const kString50_3_2S: vsttypes.CString = "L R C Ls Rs Tfl Tfc Tfr Bfl Bfr";
    pub const kString50_4_2S: vsttypes.CString = "L R C Ls Rs Tfl Tfr Trl Trr Bfl Bfr";
    pub const kString70_4_2S: vsttypes.CString = "L R C Ls Rs Sl Sr Tfl Tfr Trl Trr Bfl Bfr";
    pub const kString222S: vsttypes.CString = "L R C LFE Ls Rs Lc Rc Cs Sl Sr Tc Tfl Tfc Tfr Trl Trc Trr LFE2 Tsl Tsr Bfl Bfc Bfr";
    pub const kString220S: vsttypes.CString = "L R C Ls Rs Lc Rc Cs Sl Sr Tc Tfl Tfc Tfr Trl Trc Trr Tsl Tsr Bfl Bfc Bfr";
    pub const kStringAmbi1stOrderS: vsttypes.CString = "0 1 2 3";
    pub const kStringAmbi2cdOrderS: vsttypes.CString = "0 1 2 3 4 5 6 7 8";
    pub const kStringAmbi3rdOrderS: vsttypes.CString = "0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15";
    pub const kStringAmbi4thOrderS: vsttypes.CString = "0..24";
    pub const kStringAmbi5thOrderS: vsttypes.CString = "0..35";
    pub const kStringAmbi6thOrderS: vsttypes.CString = "0..48";
    pub const kStringAmbi7thOrderS: vsttypes.CString = "0..63";
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
