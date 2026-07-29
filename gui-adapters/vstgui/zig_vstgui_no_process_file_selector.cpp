#include "vstgui/lib/platform/linux/x11fileselector.h"

namespace VSTGUI::X11 {

PlatformFileSelectorPtr createFileSelector(
    PlatformFileSelectorStyle,
    Frame*)
{
    return nullptr;
}

}
