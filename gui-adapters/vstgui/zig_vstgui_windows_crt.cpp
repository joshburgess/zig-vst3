#if defined(_WIN32)

#pragma comment(linker, "/ignore:4217")

extern "C" {
extern bool (__cdecl* zig_vstgui_acrt_initialize_import)()
    __asm__("__imp___acrt_initialize");
extern bool (__cdecl* zig_vstgui_acrt_uninitialize_import)(bool)
    __asm__("__imp___acrt_uninitialize");
extern bool (__cdecl* zig_vstgui_acrt_uninitialize_critical_import)(bool)
    __asm__("__imp___acrt_uninitialize_critical");
extern bool (__cdecl* zig_vstgui_acrt_thread_attach_import)()
    __asm__("__imp___acrt_thread_attach");
extern bool (__cdecl* zig_vstgui_acrt_thread_detach_import)()
    __asm__("__imp___acrt_thread_detach");
extern int (__cdecl* zig_vstgui_is_c_termination_complete_import)()
    __asm__("__imp__is_c_termination_complete");
extern bool (__cdecl* zig_vstgui_vcrt_initialize_import)()
    __asm__("__imp___vcrt_initialize");
extern bool (__cdecl* zig_vstgui_vcrt_uninitialize_import)(bool)
    __asm__("__imp___vcrt_uninitialize");
extern bool (__cdecl* zig_vstgui_vcrt_uninitialize_critical_import)(bool)
    __asm__("__imp___vcrt_uninitialize_critical");
extern bool (__cdecl* zig_vstgui_vcrt_thread_attach_import)()
    __asm__("__imp___vcrt_thread_attach");
extern bool (__cdecl* zig_vstgui_vcrt_thread_detach_import)()
    __asm__("__imp___vcrt_thread_detach");
}

extern "C" bool __cdecl __acrt_initialize() {
    return zig_vstgui_acrt_initialize_import();
}

extern "C" bool __cdecl __acrt_uninitialize(bool terminating) {
    return zig_vstgui_acrt_uninitialize_import(terminating);
}

extern "C" bool __cdecl __acrt_uninitialize_critical(bool terminating) {
    return zig_vstgui_acrt_uninitialize_critical_import(terminating);
}

extern "C" bool __cdecl __acrt_thread_attach() {
    return zig_vstgui_acrt_thread_attach_import();
}

extern "C" bool __cdecl __acrt_thread_detach() {
    return zig_vstgui_acrt_thread_detach_import();
}

extern "C" int __cdecl _is_c_termination_complete() {
    return zig_vstgui_is_c_termination_complete_import();
}

extern "C" bool __cdecl __vcrt_initialize() {
    return zig_vstgui_vcrt_initialize_import();
}

extern "C" bool __cdecl __vcrt_uninitialize(bool terminating) {
    return zig_vstgui_vcrt_uninitialize_import(terminating);
}

extern "C" bool __cdecl __vcrt_uninitialize_critical(bool terminating) {
    return zig_vstgui_vcrt_uninitialize_critical_import(terminating);
}

extern "C" bool __cdecl __vcrt_thread_attach() {
    return zig_vstgui_vcrt_thread_attach_import();
}

extern "C" bool __cdecl __vcrt_thread_detach() {
    return zig_vstgui_vcrt_thread_detach_import();
}

#endif
