#ifndef ZIG_VSTGUI_FONTS_H
#define ZIG_VSTGUI_FONTS_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_theme.h"

#include <string>
#include <vector>

namespace ZigVstgui {

std::string chooseFontFamily(
    const char* preferred,
    const char* fallback,
    const std::vector<std::string>& available
);

void applyFontDescription(const ZigVstguiFontDescription& fonts, ThemeResolver& resolver);

}

#endif
