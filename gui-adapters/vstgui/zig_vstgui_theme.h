#ifndef ZIG_VSTGUI_THEME_H
#define ZIG_VSTGUI_THEME_H

#include "vstgui/lib/ccolor.h"
#include "vstgui/lib/cfont.h"

#include <array>
#include <cstddef>
#include <optional>

namespace ZigVstgui {

enum class VisualState : std::size_t {
    normal,
    hovered,
    pressed,
    focused,
    disabled,
    editing,
    count,
};

enum class ComponentKind : std::size_t {
    editor,
    title,
    help,
    slider,
    knob,
    toggle,
    dropdown,
    segmented,
    value_field,
    resize_button,
    count,
};

struct ColorTokens {
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

struct SpacingTokens {
    double extra_small;
    double small;
    double medium;
    double large;
};

struct TypographyTokens {
    VSTGUI::CFontRef title;
    VSTGUI::CFontRef body;
    VSTGUI::CFontRef value;
};

struct RadiusTokens {
    double control;
    double button;
};

struct ControlMetrics {
    double frame_width;
    double focus_width;
    double thumb_radius;
    double control_height;
    double compact_control_height;
    double value_width;
    double button_width;
};

struct ComponentStyle {
    VSTGUI::CColor background;
    VSTGUI::CColor foreground;
    VSTGUI::CColor border;
    VSTGUI::CColor accent;
    float alpha {1.f};
    double frame_width {0.0};
    double radius {0.0};
    double thumb_radius {0.0};
};

struct StyleOverride {
    std::optional<VSTGUI::CColor> background;
    std::optional<VSTGUI::CColor> foreground;
    std::optional<VSTGUI::CColor> border;
    std::optional<VSTGUI::CColor> accent;
    std::optional<float> alpha;
    std::optional<double> frame_width;
    std::optional<double> radius;
    std::optional<double> thumb_radius;
};

struct Theme {
    ColorTokens colors;
    SpacingTokens spacing;
    TypographyTokens typography;
    RadiusTokens radii;
    ControlMetrics control_metrics;
    std::array<ComponentStyle, static_cast<std::size_t>(ComponentKind::count)> component_styles;
    std::array<
        std::array<StyleOverride, static_cast<std::size_t>(VisualState::count)>,
        static_cast<std::size_t>(ComponentKind::count)
    > state_overrides;
};

class ThemeResolver {
public:
    explicit ThemeResolver(const Theme& theme);

    const Theme& theme() const;
    ComponentStyle resolve(ComponentKind kind, VisualState state = VisualState::normal) const;
    void setEditorOverride(const StyleOverride& style);
    void setComponentOverride(ComponentKind kind, const StyleOverride& style);

private:
    const Theme* selected_theme;
    StyleOverride editor_override;
    std::array<StyleOverride, static_cast<std::size_t>(ComponentKind::count)> component_overrides;
};

const Theme& defaultTheme();
const Theme& alternateTheme();

}

#endif
