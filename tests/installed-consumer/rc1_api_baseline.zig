pub const candidate_commit = "7650781a5625c041ec474a5377d859a427a344f3";

pub const plugin_compatibility_ready = [_][]const u8{
    "HostChange",
    "HostRequestSink",
    "Vst3Controller",
    "Vst3ControllerWithParameters",
    "Vst3Effect",
    "Vst3EffectWithParameters",
    "Vst3Processor",
    "Vst3ProcessorWithParameters",
    "dsp",
    "parameters",
    "process",
    "realtime_audit",
    "resource",
    "state",
    "units",
    "version",
    "vst3_adapter",
};

pub const core_compatibility_ready = [_][]const u8{
    "dsp",
    "parameters",
    "process",
    "realtime_audit",
    "resource",
    "state",
    "units",
};
