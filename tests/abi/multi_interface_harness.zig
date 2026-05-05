const multi = @import("vst3-zig").multi_interface;
const funknown = @import("vst3-zig").funknown;

export fn make_multi_test_object(out: *multi.TestObject) *funknown.Header {
    out.* = .{};
    return out.asUnknown();
}

export fn test_a_iid() *const [16]u8 {
    return &multi.test_a_iid;
}

export fn test_b_iid() *const [16]u8 {
    return &multi.test_b_iid;
}

export fn test_c_iid() *const [16]u8 {
    return &multi.test_c_iid;
}

export fn multi_object_a_calls(object: *const multi.TestObject) u32 {
    return object.a_calls;
}

export fn multi_object_b_calls(object: *const multi.TestObject) u32 {
    return object.b_calls;
}

export fn multi_object_c_calls(object: *const multi.TestObject) u32 {
    return object.c_calls;
}
