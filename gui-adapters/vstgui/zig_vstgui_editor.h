#ifndef ZIG_VSTGUI_EDITOR_H
#define ZIG_VSTGUI_EDITOR_H

#include "zig_vstgui_adapter.h"
#include "zig_vstgui_accessibility_bridge.h"
#include "zig_vstgui_action_button.h"
#include "zig_vstgui_action_menu.h"
#include "zig_vstgui_assets.h"
#include "zig_vstgui_component.h"
#include "zig_vstgui_controls.h"
#include "zig_vstgui_graphs.h"
#include "zig_vstgui_file_drop.h"
#include "zig_vstgui_meters.h"
#include "zig_vstgui_piano.h"
#include "zig_vstgui_preset_browser.h"
#include "zig_vstgui_step_sequencer.h"
#include "zig_vstgui_theme.h"
#include "zig_vstgui_text_progress.h"
#include "zig_vstgui_xy_pad.h"

#include "vstgui/lib/cframe.h"
#include "vstgui/lib/cscrollview.h"
#include "vstgui/lib/cvstguitimer.h"
#include "vstgui/lib/controls/ctextlabel.h"

#include <array>
#include <atomic>
#include <cstddef>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace ZigVstgui {

class RuntimeGuard {
public:
    RuntimeGuard();
    ~RuntimeGuard();
    RuntimeGuard(const RuntimeGuard&) = delete;
    RuntimeGuard& operator=(const RuntimeGuard&) = delete;

private:
    bool com_initialized {false};
};

}

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
        ZigVstguiGraphCallbacks graph_callbacks = {},
        const ZigVstguiXYPadDescription* xy_pads = nullptr,
        uint32_t xy_pad_count = 0,
        const ZigVstguiPresetBrowserDescription* preset_browsers = nullptr,
        uint32_t preset_browser_count = 0,
        const ZigVstguiActionMenuDescription* action_menus = nullptr,
        uint32_t action_menu_count = 0,
        const ZigVstguiPianoDescription* pianos = nullptr,
        uint32_t piano_count = 0,
        const ZigVstguiStepSequencerDescription* step_sequencers = nullptr,
        uint32_t step_sequencer_count = 0,
        const ZigVstguiFileDropDescription* file_drops = nullptr,
        uint32_t file_drop_count = 0,
        const ZigVstguiActionButtonDescription* action_buttons = nullptr,
        uint32_t action_button_count = 0,
        const ZigVstguiEditableLabelDescription* editable_labels = nullptr,
        uint32_t editable_label_count = 0,
        const ZigVstguiProgressIndicatorDescription* progress_indicators = nullptr,
        uint32_t progress_indicator_count = 0
    );
    ~ZigVstguiEditor();

    bool open(void* parent, ZigVstguiPlatform platform);
    void close();
    bool resize(uint32_t width, uint32_t height);
    bool setScale(double scale);
    bool valid() const;
    bool setParameter(uint32_t parameter_id, double normalized);
    void flushParameterUpdates();
    bool setModulation(uint32_t parameter_id, double normalized);
    bool refreshParameters(const ZigVstguiParameterValue* parameters, uint32_t parameter_count);
    bool parameterValue(uint32_t parameter_id, double& value) const;
    const ZigVstgui::AccessibilityNode* parameterAccessibility(uint32_t parameter_id, bool exact_value) const;
    const ZigVstgui::AccessibilityNode& resizeAccessibility() const;
    const ZigVstgui::AccessibilityNode* meterAccessibility(uint32_t index) const;
    const ZigVstgui::AccessibilityNode* graphAccessibility(uint32_t index) const;
    const ZigVstgui::AccessibilityNode* xyPadAccessibility(uint32_t index, uint32_t axis) const;
    const ZigVstgui::AccessibilityNode* presetBrowserAccessibility(uint32_t index) const;
    const ZigVstgui::AccessibilityNode* actionMenuAccessibility(uint32_t index) const;
    const ZigVstgui::AccessibilityNode* pianoAccessibility(uint32_t index) const;
    const ZigVstgui::AccessibilityNode* stepSequencerAccessibility(uint32_t index) const;
    const ZigVstgui::AccessibilityNode* fileDropAccessibility(uint32_t index) const;
    const ZigVstgui::AccessibilityNode* actionButtonAccessibility(uint32_t index) const;
    VSTGUI::CRect actionButtonBounds(uint32_t index) const;
    double parameterControlValueGap(uint32_t parameter_id) const;
    bool parameterControlBounds(
        uint32_t parameter_id,
        VSTGUI::CRect& label_bounds,
        VSTGUI::CRect& primary_bounds,
        VSTGUI::CRect& value_bounds
    ) const;
    VSTGUI::CRect groupBounds(uint32_t index) const;
    VSTGUI::CRect graphBounds(uint32_t index) const;
    const ZigVstgui::AccessibilityNode* editableLabelAccessibility(uint32_t index) const;
    const ZigVstgui::AccessibilityNode* progressAccessibility(uint32_t index) const;
    bool tickMeter(uint32_t index, double elapsed_ms);
    bool refreshGraph(uint32_t index);
    uint32_t graphPointCount(uint32_t index) const;
    double meterLevel(uint32_t index, uint32_t channel) const;
    double meterPeak(uint32_t index, uint32_t channel) const;
    bool resetMeterPeaks(uint32_t index);
    int32_t focusPosition() const;
    bool keyDown(uint16_t key, int16_t key_code, int16_t modifiers);
    bool keyUp(uint16_t key, int16_t key_code, int16_t modifiers);
    void setFocus(bool focused);
    void setPlugFrame(void* frame);
    void setWaylandHost(void* host);
    void setResizeCallbacks(ZigVstguiResizeCallbacks callbacks);
    ZigVstguiThemeKind themeKind() const;
    ZigVstguiLayoutKind layoutKind() const;
    uint32_t groupCount() const;
    bool nativeAccessibilityActive() const;
    std::size_t nativeAccessibilityElementCount() const;
    bool contentScrollingActive() const;
    double contentHeight() const;
    bool setVerticalScrollOffset(double offset);
    double verticalScrollOffset() const;
    double visibleContentTop() const;
    VSTGUI::CFrame* frameView() const;

private:
    void buildFrame();
    void clearControls();
    void clearFrameReferences();
    void layout();
    void layoutParameterWorkspace(
        double margin,
        double right,
        double content_bottom,
        double footer_control_top,
        double footer_bottom
    );
    void layoutPresetBrowsers(double left, double top, double right, double bottom);
    void layoutActionMenus(double left, double top, double right, double bottom);
    void layoutPianos(double left, double top, double right, double bottom);
    void layoutStepSequencers(double left, double top, double right, double bottom);
    void layoutFileDrops(double left, double top, double right, double bottom);
    void layoutActionButtons(double left, double top, double right, double bottom);
    void layoutEditableLabels(double left, double top, double right, double bottom);
    void layoutProgressIndicators(double left, double top, double right, double bottom);
    void reportMetrics() const;
    bool focusNext(bool reverse);
    void focusFileImporter(uint32_t importer_id);
    void actionAccepted(uint32_t importer_id);
    void updateActionButtonStates();
    static void importStateChanged(void* userdata, uint32_t importer_id, ZigVstguiFileImportStatus status);
    const ZigVstgui::ThemeResolver& stylesForParameter(uint32_t index) const;
    const ZigVstgui::ThemeResolver& stylesForMeter(uint32_t index) const;
    const ZigVstgui::ThemeResolver& stylesForGraph(uint32_t index) const;
    const ZigVstgui::ThemeResolver& stylesForXYPad(uint32_t index) const;
    static void actionMenuWillOpen(void* userdata, ZigVstgui::ActionMenuControl* opening);
    void closeOtherActionMenus(ZigVstgui::ActionMenuControl* opening);
    static void graphSelectionChanged(void* userdata, uint32_t group_index);
    void updateSelectedGroup(uint32_t group_index);
    std::vector<ZigVstgui::AccessibilityEntry> accessibilityEntries() const;
    double minimumContentHeight() const;
    double actionButtonAreaWidth() const;
    uint32_t actionButtonColumnCount(double available) const;
    double footerHeight() const;
    uint32_t workspacePanelColumns(double available) const;
    double workspaceHeroHeight() const;
    double workspacePanelHeight() const;
    double workspaceTop() const;
    ZigVstgui::ParameterControl* findControl(uint32_t parameter_id);
    const ZigVstgui::ParameterControl* findControl(uint32_t parameter_id) const;
    bool applyParameter(uint32_t parameter_id, double normalized);
    uint32_t findParameterIndex(uint32_t parameter_id) const;

    ZigVstgui::RuntimeGuard runtime;
    VSTGUI::CFrame* frame {nullptr};
    VSTGUI::CScrollView* scroll_view {nullptr};
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
    uint32_t selected_group_index {UINT32_MAX};
    std::array<std::unique_ptr<ZigVstgui::ParameterControl>, ZIG_VSTGUI_MAX_PARAMETERS> parameter_controls;
    std::array<ZigVstguiParameterInfo, ZIG_VSTGUI_MAX_PARAMETERS> parameter_info {};
    std::array<std::string, ZIG_VSTGUI_MAX_PARAMETERS> parameter_titles;
    std::array<std::string, ZIG_VSTGUI_MAX_PARAMETERS> parameter_units;
    std::array<std::string, ZIG_VSTGUI_MAX_PARAMETERS> parameter_tooltips;
    std::array<ZigVstguiControlKind, ZIG_VSTGUI_MAX_PARAMETERS> parameter_control_kinds {};
    std::array<std::atomic<double>, ZIG_VSTGUI_MAX_PARAMETERS> pending_parameter_values {};
    std::array<std::atomic<bool>, ZIG_VSTGUI_MAX_PARAMETERS> pending_parameter_dirty {};
    uint32_t parameter_count {0};
    std::thread::id parameter_thread;
    VSTGUI::CVSTGUITimer* parameter_update_timer {nullptr};
    ZigVstguiCallbacks parameter_callbacks {};
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
    std::array<std::vector<ZigVstguiEnvelopePoint>, ZIG_VSTGUI_MAX_GRAPHS> graph_editable_points;
    uint32_t graph_count {0};
    ZigVstguiGraphCallbacks graph_callbacks {};
    std::array<std::unique_ptr<ZigVstgui::XYPadControl>, ZIG_VSTGUI_MAX_XY_PADS> xy_pad_controls;
    std::array<ZigVstguiXYPadDescription, ZIG_VSTGUI_MAX_XY_PADS> xy_pad_descriptions {};
    std::array<std::string, ZIG_VSTGUI_MAX_XY_PADS> xy_pad_titles;
    std::array<std::string, ZIG_VSTGUI_MAX_XY_PADS> xy_pad_x_labels;
    std::array<std::string, ZIG_VSTGUI_MAX_XY_PADS> xy_pad_y_labels;
    uint32_t xy_pad_count {0};
    std::array<std::unique_ptr<ZigVstgui::PresetBrowserControl>, ZIG_VSTGUI_MAX_PRESET_BROWSERS> preset_browser_controls;
    std::array<ZigVstguiPresetBrowserDescription, ZIG_VSTGUI_MAX_PRESET_BROWSERS> preset_browser_descriptions {};
    std::array<std::string, ZIG_VSTGUI_MAX_PRESET_BROWSERS> preset_browser_titles;
    std::array<std::string, ZIG_VSTGUI_MAX_PRESET_BROWSERS> preset_browser_searches;
    std::array<std::vector<ZigVstguiPreset>, ZIG_VSTGUI_MAX_PRESET_BROWSERS> preset_browser_presets;
    std::array<std::vector<std::string>, ZIG_VSTGUI_MAX_PRESET_BROWSERS> preset_browser_names;
    uint32_t preset_browser_count {0};
    std::array<std::unique_ptr<ZigVstgui::ActionMenuControl>, ZIG_VSTGUI_MAX_ACTION_MENUS> action_menu_controls;
    std::array<ZigVstguiActionMenuDescription, ZIG_VSTGUI_MAX_ACTION_MENUS> action_menu_descriptions {};
    std::array<std::string, ZIG_VSTGUI_MAX_ACTION_MENUS> action_menu_titles;
    std::array<std::vector<ZigVstguiMenuItemDescription>, ZIG_VSTGUI_MAX_ACTION_MENUS> action_menu_items;
    std::array<std::vector<std::string>, ZIG_VSTGUI_MAX_ACTION_MENUS> action_menu_labels;
    uint32_t action_menu_count {0};
    std::array<std::unique_ptr<ZigVstgui::PianoControl>, ZIG_VSTGUI_MAX_PIANOS> piano_controls;
    std::array<ZigVstguiPianoDescription, ZIG_VSTGUI_MAX_PIANOS> piano_descriptions {};
    std::array<std::string, ZIG_VSTGUI_MAX_PIANOS> piano_titles;
    uint32_t piano_count {0};
    std::array<std::unique_ptr<ZigVstgui::StepSequencerControl>, ZIG_VSTGUI_MAX_STEP_SEQUENCERS> step_sequencer_controls;
    std::array<ZigVstguiStepSequencerDescription, ZIG_VSTGUI_MAX_STEP_SEQUENCERS> step_sequencer_descriptions {};
    std::array<std::string, ZIG_VSTGUI_MAX_STEP_SEQUENCERS> step_sequencer_titles;
    std::array<std::array<uint32_t, ZIG_VSTGUI_MAX_STEPS>, ZIG_VSTGUI_MAX_STEP_SEQUENCERS> step_sequencer_parameter_ids {};
    uint32_t step_sequencer_count {0};
    std::array<std::unique_ptr<ZigVstgui::FileDropControl>, ZIG_VSTGUI_MAX_FILE_DROPS> file_drop_controls;
    std::array<ZigVstguiFileDropDescription, ZIG_VSTGUI_MAX_FILE_DROPS> file_drop_descriptions {};
    std::array<std::string, ZIG_VSTGUI_MAX_FILE_DROPS> file_drop_titles;
    std::array<std::string, ZIG_VSTGUI_MAX_FILE_DROPS> file_drop_prompts;
    std::array<std::string, ZIG_VSTGUI_MAX_FILE_DROPS> file_drop_picker_labels;
    std::array<std::string, ZIG_VSTGUI_MAX_FILE_DROPS> file_drop_picker_titles;
    std::array<std::array<std::string, ZIG_VSTGUI_MAX_DROP_EXTENSIONS>, ZIG_VSTGUI_MAX_FILE_DROPS> file_drop_extensions;
    std::array<std::array<const char*, ZIG_VSTGUI_MAX_DROP_EXTENSIONS>, ZIG_VSTGUI_MAX_FILE_DROPS> file_drop_extension_pointers {};
    uint32_t file_drop_count {0};
    std::array<std::unique_ptr<ZigVstgui::ActionButtonControl>, ZIG_VSTGUI_MAX_ACTION_BUTTONS> action_button_controls;
    std::array<ZigVstguiActionButtonDescription, ZIG_VSTGUI_MAX_ACTION_BUTTONS> action_button_descriptions {};
    std::array<std::string, ZIG_VSTGUI_MAX_ACTION_BUTTONS> action_button_labels;
    std::array<std::string, ZIG_VSTGUI_MAX_ACTION_BUTTONS> action_button_accessible_labels;
    std::array<std::string, ZIG_VSTGUI_MAX_ACTION_BUTTONS> action_button_tooltips;
    std::array<std::string, ZIG_VSTGUI_MAX_ACTION_BUTTONS> action_button_confirmation_labels;
    std::array<std::string, ZIG_VSTGUI_MAX_ACTION_BUTTONS> action_button_failure_labels;
    uint32_t action_button_count {0};
    std::array<std::unique_ptr<ZigVstgui::EditableLabelControl>, ZIG_VSTGUI_MAX_EDITABLE_LABELS> editable_label_controls;
    std::array<ZigVstguiEditableLabelDescription, ZIG_VSTGUI_MAX_EDITABLE_LABELS> editable_label_descriptions {};
    std::array<std::string, ZIG_VSTGUI_MAX_EDITABLE_LABELS> editable_label_labels;
    std::array<std::string, ZIG_VSTGUI_MAX_EDITABLE_LABELS> editable_label_accessible_labels;
    std::array<std::string, ZIG_VSTGUI_MAX_EDITABLE_LABELS> editable_label_placeholders;
    std::array<std::string, ZIG_VSTGUI_MAX_EDITABLE_LABELS> editable_label_errors;
    std::array<std::string, ZIG_VSTGUI_MAX_EDITABLE_LABELS> editable_label_initial_text;
    uint32_t editable_label_count {0};
    std::array<std::unique_ptr<ZigVstgui::ProgressIndicatorControl>, ZIG_VSTGUI_MAX_PROGRESS_INDICATORS> progress_controls;
    std::array<ZigVstguiProgressIndicatorDescription, ZIG_VSTGUI_MAX_PROGRESS_INDICATORS> progress_descriptions {};
    std::array<std::string, ZIG_VSTGUI_MAX_PROGRESS_INDICATORS> progress_labels;
    std::array<std::string, ZIG_VSTGUI_MAX_PROGRESS_INDICATORS> progress_accessible_labels;
    std::array<std::string, ZIG_VSTGUI_MAX_PROGRESS_INDICATORS> progress_idle_text;
    std::array<std::string, ZIG_VSTGUI_MAX_PROGRESS_INDICATORS> progress_running_text;
    std::array<std::string, ZIG_VSTGUI_MAX_PROGRESS_INDICATORS> progress_complete_text;
    std::array<std::string, ZIG_VSTGUI_MAX_PROGRESS_INDICATORS> progress_failure_text;
    uint32_t progress_indicator_count {0};
    ZigVstgui::AssetStore asset_store;
    ZigVstguiDrawingCallbacks drawing_callbacks {};
    ZigVstgui::ResizeControl resize_control;
    ZigVstgui::NativeAccessibilityBridge accessibility_bridge;
    ZigVstgui::ThemeResolver theme_resolver;
    ZigVstguiThemeKind theme_kind {ZIG_VSTGUI_THEME_DEFAULT};
    ZigVstguiLayoutKind layout_kind {ZIG_VSTGUI_LAYOUT_ADAPTIVE};
    uint32_t width {400};
    uint32_t height {300};
    double content_height {300.0};
    void* plug_frame {nullptr};
    void* wayland_host {nullptr};
    ZigVstgui::RenderMetrics metrics;
    bool profile_enabled {false};
    int32_t focus_position {-1};
};

#endif
