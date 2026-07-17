#include "zig_vstgui_theme.h"

namespace ZigVstgui {

namespace {

std::size_t index(ComponentKind kind) {
    return static_cast<std::size_t>(kind);
}

std::size_t index(VisualState state) {
    return static_cast<std::size_t>(state);
}

void apply(ComponentStyle& target, const StyleOverride& source) {
    if (source.background) target.background = *source.background;
    if (source.foreground) target.foreground = *source.foreground;
    if (source.border) target.border = *source.border;
    if (source.accent) target.accent = *source.accent;
    if (source.alpha) target.alpha = *source.alpha;
    if (source.frame_width) target.frame_width = *source.frame_width;
    if (source.radius) target.radius = *source.radius;
    if (source.thumb_radius) target.thumb_radius = *source.thumb_radius;
}

Theme makeTheme(const ColorTokens& colors) {
    Theme theme {
        colors,
        SpacingTokens {4.0, 8.0, 16.0, 24.0},
        TypographyTokens {VSTGUI::kNormalFontVeryBig, VSTGUI::kNormalFont, VSTGUI::kNormalFont},
        RadiusTokens {8.0, 8.0},
        ControlMetrics {2.0, 2.0, 8.0, 52.0, 40.0, 148.0, 112.0},
        {},
        {},
    };

    theme.component_styles[index(ComponentKind::editor)] = {
        colors.surface, colors.text_primary, colors.surface, colors.focus_ring, 1.f, 0.0, 0.0, 0.0,
    };
    theme.component_styles[index(ComponentKind::title)] = {
        colors.surface, colors.text_primary, colors.surface, colors.focus_ring, 1.f, 0.0, 0.0, 0.0,
    };
    theme.component_styles[index(ComponentKind::help)] = {
        colors.surface, colors.text_secondary, colors.surface, colors.focus_ring, 1.f, 0.0, 0.0, 0.0,
    };
    theme.component_styles[index(ComponentKind::slider)] = {
        colors.surface_raised,
        colors.text_primary,
        colors.control_track,
        colors.control_fill,
        1.f,
        theme.control_metrics.frame_width,
        theme.radii.control,
        theme.control_metrics.thumb_radius,
    };
    theme.component_styles[index(ComponentKind::value_field)] = {
        colors.surface_raised,
        colors.text_primary,
        colors.focus_ring,
        colors.control_fill,
        1.f,
        theme.control_metrics.frame_width,
        theme.radii.control,
        0.0,
    };
    theme.component_styles[index(ComponentKind::resize_button)] = {
        colors.button_bottom,
        colors.text_primary,
        colors.focus_ring,
        colors.button_top,
        1.f,
        theme.control_metrics.frame_width,
        theme.radii.button,
        0.0,
    };

    for (std::size_t kind = 0; kind < index(ComponentKind::count); ++kind) {
        theme.state_overrides[kind][index(VisualState::hovered)].accent = colors.control_fill_highlighted;
        theme.state_overrides[kind][index(VisualState::pressed)].border = colors.control_fill_highlighted;
        theme.state_overrides[kind][index(VisualState::focused)].border = colors.focus_ring;
        theme.state_overrides[kind][index(VisualState::disabled)].alpha = 0.45f;
        theme.state_overrides[kind][index(VisualState::editing)].border = colors.control_fill_highlighted;
    }
    return theme;
}

}

ThemeResolver::ThemeResolver(const Theme& theme)
: selected_theme(&theme) {}

const Theme& ThemeResolver::theme() const {
    return *selected_theme;
}

ComponentStyle ThemeResolver::resolve(ComponentKind kind, VisualState state) const {
    const auto kind_index = index(kind);
    ComponentStyle result = selected_theme->component_styles[kind_index];
    apply(result, editor_override);
    apply(result, component_overrides[kind_index]);
    apply(result, selected_theme->state_overrides[kind_index][index(state)]);
    return result;
}

void ThemeResolver::setEditorOverride(const StyleOverride& style) {
    editor_override = style;
}

void ThemeResolver::setComponentOverride(ComponentKind kind, const StyleOverride& style) {
    component_overrides[index(kind)] = style;
}

const Theme& defaultTheme() {
    static const Theme theme = makeTheme(ColorTokens {
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
    });
    return theme;
}

const Theme& alternateTheme() {
    static const Theme theme = makeTheme(ColorTokens {
        VSTGUI::CColor(236, 232, 222, 255),
        VSTGUI::CColor(249, 247, 241, 255),
        VSTGUI::CColor(146, 137, 120, 255),
        VSTGUI::CColor(157, 75, 45, 255),
        VSTGUI::CColor(204, 106, 68, 255),
        VSTGUI::CColor(45, 40, 34, 255),
        VSTGUI::CColor(96, 87, 74, 255),
        VSTGUI::CColor(35, 106, 119, 255),
        VSTGUI::CColor(186, 88, 52, 255),
        VSTGUI::CColor(142, 62, 37, 255),
        VSTGUI::CColor(211, 117, 82, 255),
        VSTGUI::CColor(169, 75, 46, 255),
    });
    return theme;
}

}
