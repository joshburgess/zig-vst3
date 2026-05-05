export fn GetPluginFactory() ?*anyopaque {
    return null;
}

export fn ModuleEntry(_: ?*anyopaque) bool {
    return true;
}

export fn ModuleExit() bool {
    return true;
}

export fn bundleEntry(_: ?*anyopaque) bool {
    return true;
}

export fn bundleExit() bool {
    return true;
}

export fn InitDll() bool {
    return true;
}

export fn ExitDll() bool {
    return true;
}
