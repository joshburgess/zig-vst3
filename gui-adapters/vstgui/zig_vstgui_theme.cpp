#include "zig_vstgui_theme.h"

namespace ZigVstgui {

const Theme& defaultTheme() {
    static const Theme theme {
        VSTGUI::CColor(22, 25, 31, 255),
        VSTGUI::CColor(37, 42, 51, 255),
        VSTGUI::CColor(73, 82, 97, 255),
        VSTGUI::CColor(17, 113, 91, 255),
        VSTGUI::CColor(124, 232, 197, 255),
        VSTGUI::CColor(238, 241, 246, 255),
        VSTGUI::CColor(157, 166, 181, 255),
        VSTGUI::CColor(89, 201, 165, 255),
        VSTGUI::CColor(29, 83, 70, 255),
        VSTGUI::CColor(22, 62, 53, 255),
        VSTGUI::CColor(39, 125, 101, 255),
        VSTGUI::CColor(29, 83, 70, 255),
    };
    return theme;
}

}
