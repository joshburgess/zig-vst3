pub const AudioBusLayout = enum {
    none,
    mono,
    stereo,

    pub fn channelCount(self: AudioBusLayout) u8 {
        return switch (self) {
            .none => 0,
            .mono => 1,
            .stereo => 2,
        };
    }

    pub fn hasBus(self: AudioBusLayout) bool {
        return self != .none;
    }
};
