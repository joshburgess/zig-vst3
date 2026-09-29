#if defined(_WIN32)

extern "C" bool __cdecl __acrt_initialize() {
    return true;
}

extern "C" bool __cdecl __acrt_uninitialize(bool) {
    return true;
}

extern "C" bool __cdecl __acrt_uninitialize_critical(bool) {
    return true;
}

extern "C" bool __cdecl __acrt_thread_attach() {
    return true;
}

extern "C" bool __cdecl __acrt_thread_detach() {
    return true;
}

extern "C" int __cdecl _is_c_termination_complete() {
    return 0;
}

extern "C" bool __cdecl __vcrt_initialize() {
    return true;
}

extern "C" bool __cdecl __vcrt_uninitialize(bool) {
    return true;
}

extern "C" bool __cdecl __vcrt_uninitialize_critical(bool) {
    return true;
}

extern "C" bool __cdecl __vcrt_thread_attach() {
    return true;
}

extern "C" bool __cdecl __vcrt_thread_detach() {
    return true;
}

#endif
