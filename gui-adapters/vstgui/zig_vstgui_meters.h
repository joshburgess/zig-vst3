#ifndef ZIG_VSTGUI_METERS_H
#define ZIG_VSTGUI_METERS_H

#include "zig_vstgui_component.h"

#include "vstgui/lib/cvstguitimer.h"
#include "vstgui/lib/controls/ctextlabel.h"
#include "vstgui/lib/iviewlistener.h"

#include <cstdint>

namespace ZigVstgui {

enum class MeterVariant {
    peak,
    stereo,
    gain_reduction,
};

struct MeterSource {
    void* userdata {nullptr};
    double (*load)(void*, uint32_t) {nullptr};
};

class MeterBallistics {
public:
    MeterBallistics(double hold_ms = 500.0, double decay_per_second = 1.5);
    bool update(double input, double elapsed_ms);
    void reset();
    void resetPeak();
    double level() const;
    double peak() const;

private:
    double hold_duration_ms;
    double decay_per_ms;
    double displayed_level {0.0};
    double held_peak {0.0};
    double hold_remaining_ms {0.0};
};

class MeterView final : public VSTGUI::CView {
public:
    MeterView(
        const VSTGUI::CRect& size,
        MeterVariant variant,
        uint32_t first_source,
        uint32_t second_source,
        MeterSource source,
        const ThemeResolver& styles,
        AccessibilityNode* accessibility
    );

    bool tick(double elapsed_ms = 33.0);
    void draw(VSTGUI::CDrawContext* context) override;
    double level(uint32_t channel) const;
    double peak(uint32_t channel) const;
    void resetPeaks();
    bool handleKey(uint16_t key, int16_t key_code);
    void onMouseDownEvent(VSTGUI::MouseDownEvent& event) override;
    CLASS_METHODS_NOCOPY(MeterView, VSTGUI::CView)

private:
    void updateAccessibility();
    void drawBar(VSTGUI::CDrawContext* context, const VSTGUI::CRect& bounds, const MeterBallistics& value);
    void drawScale(VSTGUI::CDrawContext* context, const VSTGUI::CRect& bounds);

    MeterVariant variant;
    uint32_t first_source;
    uint32_t second_source;
    MeterSource source;
    const ThemeResolver& styles;
    AccessibilityNode* accessibility;
    MeterBallistics first;
    MeterBallistics second;
};

class MeterControl : public VSTGUI::ViewListenerAdapter {
public:
    ~MeterControl();
    void build(
        VSTGUI::CViewContainer* parent,
        const char* title,
        MeterVariant variant,
        uint32_t first_source,
        uint32_t second_source,
        MeterSource source,
        const ThemeResolver& styles
    );
    void clear();
    void setBounds(const VSTGUI::CRect& label_bounds, const VSTGUI::CRect& meter_bounds);
    void setLabelVisible(bool visible);
    void start();
    void stop();
    bool running() const;
    bool tick(double elapsed_ms = 33.0);
    VSTGUI::CView* focusView() const;
    bool handleKey(uint16_t key, int16_t key_code);
    void resetPeaks();
    const AccessibilityNode& accessibilityNode() const;
    const MeterView* meterView() const;
    void viewLostFocus(VSTGUI::CView* view) override;
    void viewTookFocus(VSTGUI::CView* view) override;

private:
    static bool accessibilityAction(
        void* userdata,
        const AccessibilityNode& node,
        const AccessibilityActionRequest& request
    );
    bool performAccessibilityAction(const AccessibilityActionRequest& request);
    VSTGUI::CTextLabel* label {nullptr};
    MeterView* meter {nullptr};
    VSTGUI::CVSTGUITimer* timer {nullptr};
    Component label_component;
    Component meter_component;
    bool active {false};
};

}

#endif
