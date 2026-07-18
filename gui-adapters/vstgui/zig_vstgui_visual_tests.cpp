#include "zig_vstgui_assets.h"
#include "zig_vstgui_action_menu.h"
#include "zig_vstgui_controls.h"
#include "zig_vstgui_graphs.h"
#include "zig_vstgui_meters.h"
#include "zig_vstgui_preset_browser.h"
#include "zig_vstgui_theme.h"
#include "zig_vstgui_xy_pad.h"

#include "pluginterfaces/base/keycodes.h"
#include "vstgui/lib/cbitmap.h"
#include "vstgui/lib/coffscreencontext.h"
#include "vstgui/lib/cviewcontainer.h"
#include "vstgui/lib/platform/platformfactory.h"
#include "vstgui/lib/vstguiinit.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <functional>
#include <string>

namespace {

constexpr uint8_t channel_tolerance = 80;
constexpr uint64_t mismatch_per_thousand = 20;

constexpr uint8_t png[] = {
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
    0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41,
    0x54, 0x08, 0xd7, 0x63, 0xf8, 0xcf, 0xc0, 0xf0, 0x1f,
    0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d,
    0x1d, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e,
    0x44, 0xae, 0x42, 0x60, 0x82,
};

constexpr char svg[] =
    "<svg viewBox=\"0 0 24 24\">"
    "<path d=\"M2 12 L9 19 L22 4\" fill=\"none\" stroke=\"#7ce8c5\" stroke-width=\"3\"/>"
    "</svg>";

using DrawSnapshot = std::function<void(VSTGUI::CDrawContext&)>;

struct Snapshot {
    const char* name;
    uint32_t width;
    uint32_t height;
    double scale;
    DrawSnapshot draw;
};

struct MeterValues {
    double values[4] {1.0, 0.68, 0.42, 0.31};
};

double loadMeter(void* userdata, uint32_t source_id) {
    auto* values = static_cast<MeterValues*>(userdata);
    return source_id < 4 ? values->values[source_id] : 0.0;
}

VSTGUI::SharedPointer<VSTGUI::CBitmap> render(const Snapshot& snapshot) {
    return VSTGUI::renderBitmapOffscreen(
        VSTGUI::CPoint(snapshot.width, snapshot.height),
        snapshot.scale,
        snapshot.draw
    );
}

bool writePng(const VSTGUI::SharedPointer<VSTGUI::CBitmap>& bitmap, const std::filesystem::path& path) {
    if (!bitmap || !bitmap->getPlatformBitmap()) return false;
    const auto encoded = VSTGUI::getPlatformFactory().createBitmapMemoryPNGRepresentation(
        bitmap->getPlatformBitmap()
    );
    if (encoded.empty()) return false;
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output) return false;
    output.write(reinterpret_cast<const char*>(encoded.data()), static_cast<std::streamsize>(encoded.size()));
    return output.good();
}

VSTGUI::SharedPointer<VSTGUI::CBitmap> loadPng(const std::filesystem::path& path) {
    const auto platform = VSTGUI::getPlatformFactory().createBitmapFromPath(path.string().c_str());
    if (!platform) return nullptr;
    return VSTGUI::owned(new VSTGUI::CBitmap(platform));
}

VSTGUI::SharedPointer<VSTGUI::CBitmap> normalizePng(
    const VSTGUI::SharedPointer<VSTGUI::CBitmap>& bitmap
) {
    if (!bitmap || !bitmap->getPlatformBitmap()) return nullptr;
    const auto encoded = VSTGUI::getPlatformFactory().createBitmapMemoryPNGRepresentation(
        bitmap->getPlatformBitmap()
    );
    if (encoded.empty()) return nullptr;
    const auto platform = VSTGUI::getPlatformFactory().createBitmapFromMemory(
        encoded.data(),
        static_cast<uint32_t>(encoded.size())
    );
    return platform ? VSTGUI::owned(new VSTGUI::CBitmap(platform)) : nullptr;
}

uint8_t difference(uint8_t first, uint8_t second) {
    return static_cast<uint8_t>(std::abs(static_cast<int>(first) - static_cast<int>(second)));
}

bool compare(
    const VSTGUI::SharedPointer<VSTGUI::CBitmap>& actual,
    const VSTGUI::SharedPointer<VSTGUI::CBitmap>& expected,
    const std::filesystem::path& actual_path,
    const std::filesystem::path& diff_path
) {
    const auto normalized_actual = normalizePng(actual);
    if (!normalized_actual) return false;
    auto actual_pixels = VSTGUI::owned(VSTGUI::CBitmapPixelAccess::create(normalized_actual, false));
    auto expected_pixels = VSTGUI::owned(VSTGUI::CBitmapPixelAccess::create(expected, false));
    if (!actual_pixels || !expected_pixels ||
        actual_pixels->getBitmapWidth() != expected_pixels->getBitmapWidth() ||
        actual_pixels->getBitmapHeight() != expected_pixels->getBitmapHeight()) {
        writePng(actual, actual_path);
        return false;
    }
    auto diff_bitmap = VSTGUI::owned(new VSTGUI::CBitmap(
        actual_pixels->getBitmapWidth(),
        actual_pixels->getBitmapHeight()
    ));
    auto diff_pixels = VSTGUI::owned(VSTGUI::CBitmapPixelAccess::create(diff_bitmap, false));
    if (!diff_pixels) return false;
    uint64_t mismatched = 0;
    const uint64_t total = static_cast<uint64_t>(actual_pixels->getBitmapWidth()) *
        actual_pixels->getBitmapHeight();
    do {
        VSTGUI::CColor actual_color;
        VSTGUI::CColor expected_color;
        actual_pixels->getColor(actual_color);
        expected_pixels->getColor(expected_color);
        const auto maximum = std::max({
            difference(actual_color.red, expected_color.red),
            difference(actual_color.green, expected_color.green),
            difference(actual_color.blue, expected_color.blue),
            difference(actual_color.alpha, expected_color.alpha),
        });
        if (maximum > channel_tolerance) {
            ++mismatched;
            diff_pixels->setColor(VSTGUI::CColor(255, 0, 128, 255));
        } else {
            diff_pixels->setColor(VSTGUI::CColor(0, 0, 0, 255));
        }
        ++(*expected_pixels);
        ++(*diff_pixels);
    } while (++(*actual_pixels));
    const bool accepted = mismatched * 1000 <= total * mismatch_per_thousand;
    if (!accepted) {
        writePng(actual, actual_path);
        writePng(diff_bitmap, diff_path);
        std::fprintf(
            stderr,
            "visual mismatch: %llu of %llu pixels exceed channel tolerance %u\n",
            static_cast<unsigned long long>(mismatched),
            static_cast<unsigned long long>(total),
            channel_tolerance
        );
    }
    return accepted;
}

Snapshot controlStates(double scale) {
    return {
        scale == 1.0 ? "control-states-1x.png" : "control-states-2x.png",
        384,
        64,
        scale,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
            auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 384, 64)));
            container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            constexpr ZigVstgui::VisualState states[] = {
                ZigVstgui::VisualState::normal,
                ZigVstgui::VisualState::hovered,
                ZigVstgui::VisualState::pressed,
                ZigVstgui::VisualState::focused,
                ZigVstgui::VisualState::disabled,
                ZigVstgui::VisualState::editing,
            };
            for (uint32_t index = 0; index < 6; ++index) {
                const double left = 6.0 + index * 64.0;
                auto* slider = new ZigVstgui::GainSlider(
                    VSTGUI::CRect(left, 18.0, left + 52.0, 46.0),
                    nullptr,
                    static_cast<int32_t>(index),
                    styles
                );
                slider->setDrawStyle(
                    VSTGUI::CSlider::kDrawFrame |
                    VSTGUI::CSlider::kDrawBack |
                    VSTGUI::CSlider::kDrawValue
                );
                slider->setValueNormalized(static_cast<float>((index + 1.0) / 7.0));
                slider->forceVisualStateForTesting(states[index]);
                if (states[index] == ZigVstgui::VisualState::disabled) {
                    slider->setAlphaValue(styles.resolve(
                        ZigVstgui::ComponentKind::slider,
                        ZigVstgui::VisualState::disabled
                    ).alpha);
                }
                container->addView(slider);
            }
            container->drawRect(&context, container->getViewSize());
        },
    };
}

Snapshot metersAndAssets() {
    return {
        "meters-assets.png",
        320,
        112,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
            const auto background = styles.resolve(ZigVstgui::ComponentKind::editor).background;
            context.setFillColor(background);
            context.drawRect(VSTGUI::CRect(0, 0, 320, 112), VSTGUI::kDrawFilled);
            const ZigVstguiAssetDescription asset_descriptions[] = {
                {1, reinterpret_cast<const uint8_t*>(svg), sizeof(svg) - 1, ZIG_VSTGUI_ASSET_SVG, ZIG_VSTGUI_ASSET_CONTAIN},
                {2, png, sizeof(png), ZIG_VSTGUI_ASSET_PNG, ZIG_VSTGUI_ASSET_STRETCH},
            };
            ZigVstgui::AssetStore assets;
            if (!assets.load(asset_descriptions, 2)) return;
            assets.draw(1, &context, VSTGUI::CRect(12, 8, 52, 48), 1.f);
            assets.draw(2, &context, VSTGUI::CRect(64, 8, 104, 48), 1.f);
            assets.draw(999, &context, VSTGUI::CRect(116, 8, 156, 48), 1.f);

            MeterValues values;
            ZigVstgui::AccessibilityNode accessibility[3];
            ZigVstgui::MeterView meters[] = {
                {VSTGUI::CRect(172, 8, 208, 104), ZigVstgui::MeterVariant::peak, 0, 0, {&values, loadMeter}, styles, &accessibility[0]},
                {VSTGUI::CRect(220, 8, 268, 104), ZigVstgui::MeterVariant::stereo, 1, 2, {&values, loadMeter}, styles, &accessibility[1]},
                {VSTGUI::CRect(280, 8, 308, 104), ZigVstgui::MeterVariant::gain_reduction, 3, 0, {&values, loadMeter}, styles, &accessibility[2]},
            };
            for (auto& meter : meters) {
                meter.tick(0.0);
                meter.draw(&context);
            }
        },
    };
}

Snapshot productionControls() {
    return {
        "production-controls.png",
        320,
        80,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 320, 80)));
            container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            constexpr ZigVstguiControlKind kinds[] = {
                ZIG_VSTGUI_CONTROL_BIPOLAR_SLIDER,
                ZIG_VSTGUI_CONTROL_DECIBEL_SLIDER,
                ZIG_VSTGUI_CONTROL_BIPOLAR_SLIDER,
            };
            constexpr float values[] = {0.25f, 0.5f, 0.75f};
            for (uint32_t index = 0; index < 3; ++index) {
                const double left = 8.0 + index * 104.0;
                auto* slider = new ZigVstgui::GainSlider(
                    VSTGUI::CRect(left, 24.0, left + 96.0, 56.0),
                    nullptr,
                    static_cast<int32_t>(index),
                    styles,
                    kinds[index]
                );
                slider->setDrawStyle(VSTGUI::CSlider::kDrawFrame | VSTGUI::CSlider::kDrawBack);
                slider->setValueNormalized(values[index]);
                if (index < 2) slider->setModulation(index == 0 ? 0.75 : 0.65);
                container->addView(slider);
            }
            container->drawRect(&context, container->getViewSize());
        },
    };
}

Snapshot graphs() {
    return {
        "graphs.png",
        480,
        180,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
            context.setFillColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            context.drawRect(VSTGUI::CRect(0, 0, 480, 180), VSTGUI::kDrawFilled);
            const ZigVstguiGraphPoint transfer[] = {
                {-2.0, -1.1}, {-1.0, -0.9}, {-0.5, -0.6}, {0.0, 0.0}, {0.5, 0.6}, {1.0, 0.9}, {2.0, 1.1},
            };
            const ZigVstguiGraphPoint waveform[] = {
                {-1.0, 0.0}, {-0.75, 0.8}, {-0.5, 0.0}, {-0.25, -0.8}, {0.0, 0.0}, {0.25, 0.8}, {0.5, 0.0}, {0.75, -0.8}, {1.0, 0.0},
            };
            ZigVstgui::AccessibilityNode nodes[3];
            const ZigVstguiGraphDescription descriptions[] = {
                {"Transfer", ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION, ZIG_VSTGUI_GRAPH_PRIMARY, {-2.0, 2.0, ZIG_VSTGUI_GRAPH_LINEAR, "Input"}, {-1.2, 1.2, ZIG_VSTGUI_GRAPH_LINEAR, "Output"}, transfer, 7, 0, 0, 0},
                {"Waveform", ZIG_VSTGUI_GRAPH_WAVEFORM, ZIG_VSTGUI_GRAPH_MODULATION, {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Time"}, {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Level"}, waveform, 9, 0, 0, 0},
                {"Empty", ZIG_VSTGUI_GRAPH_SPECTRUM, ZIG_VSTGUI_GRAPH_SECONDARY, {20.0, 20000.0, ZIG_VSTGUI_GRAPH_LOGARITHMIC, "Hz"}, {-96.0, 0.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"}, nullptr, 0, 0, 0, 0},
            };
            ZigVstgui::GraphView views[] = {
                {VSTGUI::CRect(8, 8, 152, 172), descriptions[0], styles, &nodes[0]},
                {VSTGUI::CRect(168, 8, 312, 172), descriptions[1], styles, &nodes[1]},
                {VSTGUI::CRect(328, 8, 472, 172), descriptions[2], styles, &nodes[2]},
            };
            for (auto& view : views) view.draw(&context);
        },
    };
}

Snapshot xyPad() {
    return {
        "xy-pad.png",
        220,
        180,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 220, 180)));
            container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            auto* pad = new ZigVstgui::XYPadView(VSTGUI::CRect(12, 12, 208, 168), nullptr, styles);
            pad->setXY(0.72, 0.34);
            container->addView(pad);
            container->drawRect(&context, container->getViewSize());
        },
    };
}

Snapshot editableEnvelope() {
    return {
        "editable-envelope.png",
        480,
        180,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            context.setFillColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            context.drawRect(VSTGUI::CRect(0, 0, 480, 180), VSTGUI::kDrawFilled);
            const ZigVstguiEnvelopePoint points[] = {
                {1, 0.0, 0.0},
                {2, 0.2, 0.9},
                {3, 0.65, 0.55},
                {4, 1.0, 0.0},
            };
            const ZigVstguiGraphDescription populated {
                "Envelope",
                ZIG_VSTGUI_GRAPH_ENVELOPE,
                ZIG_VSTGUI_GRAPH_PRIMARY,
                {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Time"},
                {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Level"},
                nullptr, 0, 0, 0, 0,
                points, 4, 8, 2, 0.05, 0.05,
            };
            auto empty = populated;
            empty.editable_points = nullptr;
            empty.editable_point_count = 0;
            empty.minimum_point_count = 0;
            ZigVstgui::AccessibilityNode nodes[2];
            ZigVstgui::GraphView views[] = {
                {VSTGUI::CRect(8, 8, 232, 172), populated, styles, &nodes[0]},
                {VSTGUI::CRect(248, 8, 472, 172), empty, styles, &nodes[1]},
            };
            views[0].selectPoint(2);
            for (auto& view : views) view.draw(&context);
        },
    };
}

int32_t rejectPreset(void*, uint32_t) {
    return -1;
}

int32_t acceptMenuAction(void*, uint32_t, uint32_t, int32_t) {
    return 0;
}

int32_t rejectMenuAction(void*, uint32_t, uint32_t, int32_t) {
    return -1;
}

Snapshot presetBrowsers() {
    return {
        "preset-browsers.png",
        720,
        180,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            context.setFillColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            context.drawRect(VSTGUI::CRect(0, 0, 720, 180), VSTGUI::kDrawFilled);
            const ZigVstguiPreset presets[] = {
                {1, "Clean Start"}, {2, "Console Push"}, {3, "Peak Limit"}, {4, "Wide Motion"},
            };
            const ZigVstguiPresetBrowserDescription description {
                "Channel Presets", presets, 4, 6, 7, "", 2,
            };
            ZigVstguiCallbacks callbacks {};
            callbacks.load_preset = rejectPreset;
            ZigVstgui::AccessibilityNode nodes[3];
            ZigVstgui::PresetBrowserView views[] = {
                {VSTGUI::CRect(8, 8, 232, 172), description, callbacks, styles, &nodes[0]},
                {VSTGUI::CRect(248, 8, 472, 172), description, callbacks, styles, &nodes[1]},
                {VSTGUI::CRect(488, 8, 712, 172), description, callbacks, styles, &nodes[2]},
            };
            views[1].handleKey('p', 0, 0);
            views[1].handleKey(0, Steinberg::KEY_RETURN, 0);
            for (const char character : std::string("missing")) views[2].handleKey(character, 0, 0);
            for (auto& view : views) view.draw(&context);
        },
    };
}

Snapshot actionMenus() {
    return {
        "action-menus.png",
        720,
        240,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            context.setFillColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            context.drawRect(VSTGUI::CRect(0, 0, 720, 240), VSTGUI::kDrawFilled);
            const ZigVstguiMenuItemDescription items[] = {
                {1, "Reset UI", ZIG_VSTGUI_MENU_ACTION, 1, 0, 0, 0},
                {2, "Export Snapshot", ZIG_VSTGUI_MENU_ACTION, 0, 0, 0, 0},
                {0, nullptr, ZIG_VSTGUI_MENU_SEPARATOR, 0, 0, 0, 0},
                {3, "Show Analyzer", ZIG_VSTGUI_MENU_TOGGLE, 1, 0, 8, 1},
                {4, "Clear Envelope", ZIG_VSTGUI_MENU_ACTION, 1, 1, 0, 0},
            };
            const ZigVstguiActionMenuDescription description {1, "Actions", items, 5};
            ZigVstguiCallbacks accepted {};
            accepted.invoke_menu_action = acceptMenuAction;
            ZigVstguiCallbacks rejected {};
            rejected.invoke_menu_action = rejectMenuAction;
            ZigVstgui::AccessibilityNode nodes[2];
            ZigVstgui::ActionMenuView menus[] = {
                {description, accepted, styles, &nodes[0], nullptr},
                {description, rejected, styles, &nodes[1], nullptr},
            };
            menus[0].setLayout(VSTGUI::CRect(0, 0, 352, 240), VSTGUI::CRect(12, 200, 180, 228));
            menus[0].open();
            menus[0].handleKey(0, Steinberg::KEY_DOWN, 0);
            menus[1].setLayout(VSTGUI::CRect(368, 0, 720, 240), VSTGUI::CRect(380, 200, 548, 228));
            menus[1].open();
            menus[1].handleKey(0, Steinberg::KEY_RETURN, 0);
            for (auto& menu : menus) menu.draw(&context);
        },
    };
}

Snapshot closedActionMenu() {
    return {
        "action-menu-closed.png",
        320,
        72,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 320, 72)));
            container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            const ZigVstguiMenuItemDescription item {
                1, "Reset UI", ZIG_VSTGUI_MENU_ACTION, 1, 0, 0, 0,
            };
            const ZigVstguiActionMenuDescription description {1, "Actions", &item, 1};
            ZigVstguiCallbacks callbacks {};
            callbacks.invoke_menu_action = acceptMenuAction;
            ZigVstgui::ActionMenuControl control;
            if (!control.build(container, description, callbacks, styles)) return;
            control.setBounds(VSTGUI::CRect(12, 20, 180, 52), VSTGUI::CRect(0, 0, 320, 72));
            container->drawRect(&context, container->getViewSize());
            control.clear();
        },
    };
}

int runSnapshot(
    const Snapshot& snapshot,
    const std::filesystem::path& references,
    const std::filesystem::path& output,
    bool update
) {
    const auto actual = render(snapshot);
    if (!actual) return 1;
    const auto reference_path = references / snapshot.name;
    if (update) return writePng(actual, reference_path) ? 0 : 2;
    const auto expected = loadPng(reference_path);
    if (!expected) {
        std::fprintf(stderr, "missing visual reference: %s\n", reference_path.string().c_str());
        return 3;
    }
    return compare(
        actual,
        expected,
        output / (std::string(snapshot.name) + ".actual.png"),
        output / (std::string(snapshot.name) + ".diff.png")
    ) ? 0 : 4;
}

double benchmarkWarmDraw() {
    ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
    auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 480, 140)));
    container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
    auto* slider = new ZigVstgui::GainSlider(
        VSTGUI::CRect(8, 18, 104, 46),
        nullptr,
        1,
        styles
    );
    slider->setDrawStyle(
        VSTGUI::CSlider::kDrawFrame |
        VSTGUI::CSlider::kDrawBack |
        VSTGUI::CSlider::kDrawValue
    );
    slider->setValueNormalized(0.63f);
    container->addView(slider);
    MeterValues values;
    ZigVstgui::AccessibilityNode accessibility;
    auto* meter = new ZigVstgui::MeterView(
        VSTGUI::CRect(120, 6, 148, 58),
        ZigVstgui::MeterVariant::peak,
        0,
        0,
        {&values, loadMeter},
        styles,
        &accessibility
    );
    meter->tick(0.0);
    container->addView(meter);
    const ZigVstguiEnvelopePoint graph_points[] = {{1, -1.0, -0.8}, {2, 0.0, 0.0}, {3, 1.0, 0.8}};
    const ZigVstguiGraphDescription graph_description {
        "Graph", ZIG_VSTGUI_GRAPH_ENVELOPE, ZIG_VSTGUI_GRAPH_PRIMARY,
        {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Input"},
        {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Output"},
        nullptr, 0, 0, 0, 0,
        graph_points, 3, 8, 1, 0.05, 0.05,
    };
    ZigVstgui::AccessibilityNode graph_accessibility;
    container->addView(new ZigVstgui::GraphView(
        VSTGUI::CRect(160, 6, 232, 58), graph_description, styles, &graph_accessibility
    ));
    const ZigVstguiPreset presets[] = {
        {1, "Clean Start"}, {2, "Console Push"}, {3, "Peak Limit"}, {4, "Wide Motion"},
    };
    const ZigVstguiPresetBrowserDescription browser_description {
        "Presets", presets, 4, 6, 7, "", 1,
    };
    ZigVstgui::AccessibilityNode browser_accessibility;
    container->addView(new ZigVstgui::PresetBrowserView(
        VSTGUI::CRect(240, 6, 472, 134),
        browser_description,
        {},
        styles,
        &browser_accessibility
    ));
    const ZigVstguiMenuItemDescription menu_items[] = {
        {1, "Reset", ZIG_VSTGUI_MENU_ACTION, 1, 0, 0, 0},
        {2, "Analyzer", ZIG_VSTGUI_MENU_TOGGLE, 1, 0, 8, 1},
    };
    const ZigVstguiActionMenuDescription menu_description {1, "Actions", menu_items, 2};
    ZigVstguiCallbacks menu_callbacks {};
    menu_callbacks.invoke_menu_action = acceptMenuAction;
    ZigVstgui::AccessibilityNode menu_accessibility;
    auto* menu = new ZigVstgui::ActionMenuView(
        menu_description,
        menu_callbacks,
        styles,
        &menu_accessibility,
        nullptr
    );
    menu->setLayout(VSTGUI::CRect(0, 0, 480, 140), VSTGUI::CRect(360, 104, 472, 132));
    menu->open();
    container->addView(menu);
    const auto offscreen = VSTGUI::COffscreenContext::create(VSTGUI::CPoint(480, 140), 1.0);
    if (!offscreen) return 1e9;
    offscreen->beginDraw();
    container->drawRect(offscreen, container->getViewSize());
    offscreen->endDraw();
    constexpr uint32_t repetitions = 200;
    const auto started = std::chrono::steady_clock::now();
    for (uint32_t index = 0; index < repetitions; ++index) {
        offscreen->beginDraw();
        container->drawRect(offscreen, container->getViewSize());
        offscreen->endDraw();
    }
    return std::chrono::duration<double, std::micro>(
        std::chrono::steady_clock::now() - started
    ).count() / repetitions;
}

}

int main(int argc, char** argv) {
    if (argc < 3) return 64;
    const std::filesystem::path references(argv[1]);
    const std::filesystem::path output(argv[2]);
    const bool update = argc == 4 && std::string(argv[3]) == "--update";
    if (update) std::filesystem::create_directories(references);
    std::filesystem::create_directories(output);
    VSTGUI::init(nullptr);
    const Snapshot snapshots[] = {
        controlStates(1.0),
        controlStates(2.0),
        metersAndAssets(),
        productionControls(),
        graphs(),
        xyPad(),
        editableEnvelope(),
        presetBrowsers(),
        closedActionMenu(),
        actionMenus(),
    };
    int result = 0;
    for (const auto& snapshot : snapshots) {
        result = std::max(result, runSnapshot(snapshot, references, output, update));
    }
    if (!update) {
        const double average = benchmarkWarmDraw();
        std::fprintf(stderr, "visual regression warm render average: %.1f us\n", average);
        if (average > 300.0) result = std::max(result, 6);
    }
    VSTGUI::exit();
    return result;
}
