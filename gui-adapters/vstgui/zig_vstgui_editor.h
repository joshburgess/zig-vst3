#ifndef ZIG_VSTGUI_EDITOR_H
#define ZIG_VSTGUI_EDITOR_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_assets.h"
#include "zig_vstgui_component.h"
#include "zig_vstgui_controls.h"
#include "zig_vstgui_graphs.h"
#include "zig_vstgui_meters.h"
#include "zig_vstgui_theme.h"

#include "vstgui/lib/cframe.h"
#include "vstgui/lib/controls/ctextlabel.h"

#include <array>
#include <memory>
#include <string>

struct ZigVstguiEditor {
    ZigVstguiEditor(
        const ZigVstguiParameterDescription* parameters,
        uint32_t parameter_count,
        ZigVstguiCallbacks callbacks,
        const ZigVstguiMeterDescription* meters = nullptr,
        uint32_t meter_count = 0,
        ZigVstguiMeterCallbacks meter_callbacks = {},
        ZigVstguiSkinDescription skin = {},
        const ZigVstguiGraphDescription* graphs = nullptr,
        uint32_t graph_count = 0,
        ZigVstguiGraphCallbacks graph_callbacks = {}
    );
    ~ZigVstguiEditor();

    bool open(void* parent, ZigVstguiPlatform platform);
    void close();
    bool resize(uint32_t width, uint32_t height);
    bool setScale(double scale);
    bool valid() const;
    bool setParameter(uint32_t parameter_id, double normalized);
    bool setModulation(uint32_t parameter_id, double normalized);
    bool refreshParameters(const ZigVstguiParameterValue* parameters, uint32_t parameter_count);
    bool parameterValue(uint32_t parameter_id, double& value) const;
    const ZigVstgui::AccessibilityNode* parameterAccessibility(uint32_t parameter_id, bool exact_value) const;
    const ZigVstgui::AccessibilityNode& resizeAccessibility() const;
    const ZigVstgui::AccessibilityNode* meterAccessibility(uint32_t index) const;
    const ZigVstgui::AccessibilityNode* graphAccessibility(uint32_t index) const;
    bool tickMeter(uint32_t index, double elapsed_ms);
    bool refreshGraph(uint32_t index);
    uint32_t graphPointCount(uint32_t index) const;
    double meterLevel(uint32_t index, uint32_t channel) const;
    double meterPeak(uint32_t index, uint32_t channel) const;
    bool resetMeterPeaks(uint32_t index);
    int32_t focusPosition() const;
    bool keyDown(uint16_t key, int16_t key_code, int16_t modifiers);
    void setFocus(bool focused);
    void setPlugFrame(void* frame);
    void setWaylandHost(void* host);
    void setResizeCallbacks(ZigVstguiResizeCallbacks callbacks);
    ZigVstguiThemeKind themeKind() const;
    ZigVstguiLayoutKind layoutKind() const;
    uint32_t groupCount() const;

private:
    void buildFrame();
    void clearFrameReferences();
    void layout();
    void reportMetrics() const;
    bool focusNext(bool reverse);
    const ZigVstgui::ThemeResolver& stylesForParameter(uint32_t index) const;
    const ZigVstgui::ThemeResolver& stylesForMeter(uint32_t index) const;
    const ZigVstgui::ThemeResolver& stylesForGraph(uint32_t index) const;
    ZigVstgui::ParameterControl* findControl(uint32_t parameter_id);
    const ZigVstgui::ParameterControl* findControl(uint32_t parameter_id) const;

    VSTGUI::CFrame* frame {nullptr};
    ZigVstgui::ProfiledContainer* content {nullptr};
    VSTGUI::CTextLabel* title {nullptr};
    VSTGUI::CTextLabel* help {nullptr};
    ZigVstgui::Component title_component;
    ZigVstgui::Component help_component;
    std::string editor_title;
    std::array<std::string, ZIG_VSTGUI_MAX_GROUPS> group_titles;
    std::array<ZigVstguiGroupDescription, ZIG_VSTGUI_MAX_GROUPS> group_descriptions {};
    std::array<std::unique_ptr<ZigVstgui::ThemeResolver>, ZIG_VSTGUI_MAX_GROUPS> group_styles;
    std::array<VSTGUI::CTextLabel*, ZIG_VSTGUI_MAX_GROUPS> group_labels {};
    std::array<ZigVstgui::Component, ZIG_VSTGUI_MAX_GROUPS> group_components;
    uint32_t group_count {0};
    std::array<std::unique_ptr<ZigVstgui::ParameterControl>, ZIG_VSTGUI_MAX_PARAMETERS> parameter_controls;
    std::array<ZigVstguiParameterInfo, ZIG_VSTGUI_MAX_PARAMETERS> parameter_info {};
    std::array<std::string, ZIG_VSTGUI_MAX_PARAMETERS> parameter_titles;
    std::array<std::string, ZIG_VSTGUI_MAX_PARAMETERS> parameter_units;
    std::array<std::string, ZIG_VSTGUI_MAX_PARAMETERS> parameter_tooltips;
    std::array<ZigVstguiControlKind, ZIG_VSTGUI_MAX_PARAMETERS> parameter_control_kinds {};
    uint32_t parameter_count {0};
    std::array<std::unique_ptr<ZigVstgui::MeterControl>, ZIG_VSTGUI_MAX_METERS> meter_controls;
    std::array<ZigVstguiMeterDescription, ZIG_VSTGUI_MAX_METERS> meter_descriptions {};
    uint32_t meter_count {0};
    ZigVstguiMeterCallbacks meter_callbacks {};
    std::array<std::unique_ptr<ZigVstgui::GraphControl>, ZIG_VSTGUI_MAX_GRAPHS> graph_controls;
    std::array<ZigVstguiGraphDescription, ZIG_VSTGUI_MAX_GRAPHS> graph_descriptions {};
    std::array<std::string, ZIG_VSTGUI_MAX_GRAPHS> graph_titles;
    std::array<std::string, ZIG_VSTGUI_MAX_GRAPHS> graph_x_labels;
    std::array<std::string, ZIG_VSTGUI_MAX_GRAPHS> graph_y_labels;
    std::array<std::vector<ZigVstguiGraphPoint>, ZIG_VSTGUI_MAX_GRAPHS> graph_static_points;
    uint32_t graph_count {0};
    ZigVstguiGraphCallbacks graph_callbacks {};
    ZigVstgui::AssetStore asset_store;
    ZigVstguiDrawingCallbacks drawing_callbacks {};
    ZigVstgui::ResizeControl resize_control;
    ZigVstgui::ThemeResolver theme_resolver;
    ZigVstguiThemeKind theme_kind {ZIG_VSTGUI_THEME_DEFAULT};
    ZigVstguiLayoutKind layout_kind {ZIG_VSTGUI_LAYOUT_ADAPTIVE};
    uint32_t width {400};
    uint32_t height {300};
    void* plug_frame {nullptr};
    void* wayland_host {nullptr};
    ZigVstgui::RenderMetrics metrics;
    bool profile_enabled {false};
    bool initialized {false};
    int32_t focus_position {-1};
};

#endif
