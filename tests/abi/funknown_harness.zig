const funknown = @import("vst3-zig").funknown;

export fn make_test_object(out: *funknown.TestObject) *funknown.Header {
    out.* = .{};
    return out.asUnknown();
}

export fn funknown_iid() *const [16]u8 {
    return &funknown.iid;
}

export fn test_object_ref_count(object: *const funknown.TestObject) u32 {
    return object.ref_count;
}

export fn test_object_query_count(object: *const funknown.TestObject) u32 {
    return object.query_count;
}
