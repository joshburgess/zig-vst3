#ifndef ZIG_VSTGUI_THEME_H
#define ZIG_VSTGUI_THEME_H

#include "vstgui/lib/ccolor.h"

namespace ZigVstgui {

struct Theme {
    VSTGUI::CColor surface;
    VSTGUI::CColor surface_raised;
    VSTGUI::CColor control_track;
    VSTGUI::CColor control_fill;
    VSTGUI::CColor control_fill_highlighted;
    VSTGUI::CColor text_primary;
    VSTGUI::CColor text_secondary;
    VSTGUI::CColor focus_ring;
    VSTGUI::CColor button_top;
    VSTGUI::CColor button_bottom;
    VSTGUI::CColor button_top_highlighted;
    VSTGUI::CColor button_bottom_highlighted;
};

const Theme& defaultTheme();

}

#endif
