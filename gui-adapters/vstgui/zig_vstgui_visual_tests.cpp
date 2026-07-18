#include "zig_vstgui_assets.h"
#include "zig_vstgui_action_button.h"
#include "zig_vstgui_action_menu.h"
#include "zig_vstgui_controls.h"
#include "zig_vstgui_graphs.h"
#include "zig_vstgui_meters.h"
#include "zig_vstgui_piano.h"
#include "zig_vstgui_preset_browser.h"
#include "zig_vstgui_step_sequencer.h"
#include "zig_vstgui_file_drop.h"
#include "zig_vstgui_theme.h"
#include "zig_vstgui_text_progress.h"
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
    double values[5] {1.0, 0.68, 0.42, 0.31, 5.0};
};

double loadMeter(void* userdata, uint32_t source_id) {
    auto* values = static_cast<MeterValues*>(userdata);
    return source_id < 5 ? values->values[source_id] : 0.0;
}

void acceptBegin(void*, uint32_t) {}
int32_t acceptEdit(void*, uint32_t, double) { return 0; }
void acceptEnd(void*, uint32_t) {}
int32_t acceptIndex(void*, uint32_t, uint32_t) { return 0; }
int32_t rejectDrop(void*, uint32_t, const char* const*, uint32_t) { return -1; }
int32_t acceptAction(void*, uint32_t, uint32_t) { return 0; }
int32_t rejectAction(void*, uint32_t, uint32_t) { return -1; }

struct TextProgressVisualState {
    std::string text {"Studio Plate"};
    bool reject {false};
    ZigVstguiProgressSnapshot progress {};
};

int32_t storeVisualText(void* userdata, uint32_t, const char* text) {
    auto* state = static_cast<TextProgressVisualState*>(userdata);
    if (state->reject || !text) return -1;
    state->text = text;
    return 0;
}

int32_t loadVisualText(void* userdata, uint32_t, char* output, uint32_t capacity) {
    auto* state = static_cast<TextProgressVisualState*>(userdata);
    if (!output || state->text.size() >= capacity) return -1;
    std::copy(state->text.begin(), state->text.end(), output);
    output[state->text.size()] = 0;
    return static_cast<int32_t>(state->text.size());
}

int32_t loadVisualProgress(void* userdata, uint32_t, ZigVstguiProgressSnapshot* output) {
    if (!userdata || !output) return -1;
    *output = static_cast<TextProgressVisualState*>(userdata)->progress;
    return 0;
}

VSTGUI::SharedPointer<VSTGUI::CBitmap> render(const Snapshot& snapshot) {
    return VSTGUI::renderBitmapOffscreen(
        VSTGUI::CPoint(snapshot.width, snapshot.height),
        snapshot.scale,
        snapshot.draw
    );
}

double benchmarkDraw(
    VSTGUI::CViewContainer* container,
    const VSTGUI::SharedPointer<VSTGUI::COffscreenContext>& offscreen
) {
    if (!container || !offscreen) return 1e9;
    constexpr uint32_t repetitions = 100;
    double best = 1e9;
    for (uint32_t sample = 0; sample < 3; ++sample) {
        const auto started = std::chrono::steady_clock::now();
        for (uint32_t index = 0; index < repetitions; ++index) {
            offscreen->beginDraw();
            container->drawRect(offscreen, container->getViewSize());
            offscreen->endDraw();
        }
        best = std::min(best, std::chrono::duration<double, std::micro>(
            std::chrono::steady_clock::now() - started
        ).count() / repetitions);
    }
    return best;
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

Snapshot signalViews() {
    return {
        "signal-views.png",
        640,
        180,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
            context.setFillColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            context.drawRect(VSTGUI::CRect(0, 0, 640, 180), VSTGUI::kDrawFilled);
            const ZigVstguiGraphPoint waveform[] = {
                {0.0, 0.0}, {0.125, 0.72}, {0.25, 0.1}, {0.375, -0.54}, {0.5, 0.0},
                {0.625, 0.42}, {0.75, -0.08}, {0.875, -0.78}, {1.0, 0.0},
            };
            const ZigVstguiGraphPoint spectrum[] = {
                {46.875, -71.0}, {93.75, -58.0}, {187.5, -42.0}, {375.0, -18.0},
                {750.0, -7.0}, {1500.0, -13.0}, {3000.0, -28.0}, {6000.0, -45.0},
                {12000.0, -62.0}, {20000.0, -78.0},
            };
            ZigVstgui::AccessibilityNode nodes[3];
            const ZigVstguiGraphDescription descriptions[] = {
                {"Output Waveform", ZIG_VSTGUI_GRAPH_WAVEFORM, ZIG_VSTGUI_GRAPH_MODULATION, {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Frame"}, {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Level"}, waveform, 9, 0, 0, 0},
                {"Output Spectrum", ZIG_VSTGUI_GRAPH_SPECTRUM, ZIG_VSTGUI_GRAPH_PRIMARY, {20.0, 20000.0, ZIG_VSTGUI_GRAPH_LOGARITHMIC, "Hz"}, {-96.0, 0.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"}, spectrum, 10, 0, 0, 0},
                {"Waiting", ZIG_VSTGUI_GRAPH_SPECTRUM, ZIG_VSTGUI_GRAPH_SECONDARY, {20.0, 20000.0, ZIG_VSTGUI_GRAPH_LOGARITHMIC, "Hz"}, {-96.0, 0.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"}, nullptr, 0, 0, 0, 0},
            };
            ZigVstgui::GraphView views[] = {
                {VSTGUI::CRect(8, 8, 208, 172), descriptions[0], styles, &nodes[0]},
                {VSTGUI::CRect(220, 8, 420, 172), descriptions[1], styles, &nodes[1]},
                {VSTGUI::CRect(432, 8, 632, 172), descriptions[2], styles, &nodes[2]},
            };
            for (auto& view : views) view.draw(&context);
        },
    };
}

Snapshot graphViewports() {
    return {
        "graph-viewports.png",
        640,
        180,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 640, 180)));
            container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            const ZigVstguiGraphPoint waveform[] = {
                {0.0, 0.0}, {0.0625, 0.82}, {0.125, 0.28}, {0.1875, -0.6},
                {0.25, -0.2}, {0.3125, 0.5}, {0.375, 0.16}, {0.4375, -0.34},
                {0.5, -0.12}, {0.5625, 0.26}, {0.625, 0.08}, {0.6875, -0.18},
                {0.75, -0.05}, {0.8125, 0.12}, {0.875, 0.03}, {0.9375, -0.07}, {1.0, 0.0},
            };
            ZigVstguiGraphDescription full {
                "Full IR", ZIG_VSTGUI_GRAPH_WAVEFORM, ZIG_VSTGUI_GRAPH_MODULATION,
                {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Time"},
                {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Level"}, waveform, 17, 0, 0, 0,
            };
            full.viewport = {
                1, ZIG_VSTGUI_VIEWPORT_HORIZONTAL, 1.0, 16.0, 1.0, 0.0, 0.0, 1.25, 0.1, 0, 0, 0,
            };
            full.range_selection = {1, 0.15, 0.8, 0.01, 0.01, 0, 0};
            auto detail = full;
            detail.title = "Zoomed IR";
            detail.viewport.initial_zoom = 4.0;
            detail.viewport.initial_x_offset = 0.2;
            detail.range_selection.initial_start = 0.28;
            detail.range_selection.initial_end = 0.42;
            ZigVstgui::AccessibilityNode nodes[2];
            container->addView(new ZigVstgui::GraphView(
                VSTGUI::CRect(8, 8, 312, 172), full, styles, &nodes[0]
            ));
            container->addView(new ZigVstgui::GraphView(
                VSTGUI::CRect(328, 8, 632, 172), detail, styles, &nodes[1]
            ));
            container->drawRect(&context, container->getViewSize());
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

int32_t acceptNote(void*, int32_t, int32_t, double, int32_t) {
    return 0;
}

Snapshot pianoKeyboard() {
    return {
        "piano-keyboard.png",
        640,
        180,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 640, 180)));
            container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            ZigVstguiCallbacks callbacks {};
            callbacks.send_note = acceptNote;
            const ZigVstguiPianoDescription description {"Piano Keyboard", 48, 24, 0, 0.8, 60};
            ZigVstgui::PianoControl piano(description, callbacks);
            piano.build(container, styles);
            piano.setBounds(VSTGUI::CRect(12, 8, 628, 30), VSTGUI::CRect(12, 30, 628, 168));
            piano.pointerPress(60, 0.8);
            container->drawRect(&context, container->getViewSize());
            piano.clear();
        },
    };
}

Snapshot stepSequencer() {
    return {
        "step-sequencer.png",
        640,
        120,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 640, 120)));
            container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            const uint32_t ids[] = {100, 101, 102, 103, 104, 105, 106, 107};
            const ZigVstguiStepSequencerDescription description {
                "Eight Step Gate", ids, 8, 9, 0x3c, 0x55, 1, 4, 30,
            };
            MeterValues values;
            ZigVstguiCallbacks callbacks {};
            callbacks.begin_edit = acceptBegin;
            callbacks.perform_edit = acceptEdit;
            callbacks.end_edit = acceptEnd;
            callbacks.store_editor_index = acceptIndex;
            ZigVstgui::StepSequencerControl sequencer(description, callbacks, {&values, loadMeter});
            sequencer.build(container, styles);
            sequencer.setBounds(VSTGUI::CRect(12, 8, 628, 30), VSTGUI::CRect(12, 30, 628, 108));
            sequencer.tick();
            container->drawRect(&context, container->getViewSize());
            sequencer.clear();
        },
    };
}

Snapshot fileDrops() {
    return {
        "file-drops.png",
        720,
        120,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            context.setFillColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            context.drawRect(VSTGUI::CRect(0, 0, 720, 120), VSTGUI::kDrawFilled);
            const char* extensions[] = {".wav", ".aiff"};
            const ZigVstguiFileDropDescription description {
                1, "Audio Import", "Drop WAV or AIFF files here", extensions, 2, 2, 1,
                "Choose Audio File", "Choose Audio File",
            };
            ZigVstguiCallbacks callbacks {};
            callbacks.drop_files = rejectDrop;
            ZigVstgui::AccessibilityNode nodes[3];
            ZigVstgui::FileDropView views[] = {
                {VSTGUI::CRect(8, 8, 232, 112), description, callbacks, styles, &nodes[0]},
                {VSTGUI::CRect(248, 8, 472, 112), description, callbacks, styles, &nodes[1]},
                {VSTGUI::CRect(488, 8, 712, 112), description, callbacks, styles, &nodes[2]},
            };
            const char* acceptable[] = {"/tmp/kick.wav"};
            views[1].inspectPaths(acceptable, 1);
            const char* failed[] = {"/tmp/snare.aiff"};
            views[2].inspectPaths(failed, 1);
            views[2].dispatchInspected();
            for (auto& view : views) view.draw(&context);
        },
    };
}

Snapshot fileImportStates() {
    return {
        "file-import-states.png",
        960,
        360,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            context.setFillColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            context.drawRect(VSTGUI::CRect(0, 0, 960, 360), VSTGUI::kDrawFilled);
            const char* extensions[] = {".wav"};
            const ZigVstguiFileDropDescription description {
                1, "Audio Reference", "Drop a PCM WAV file here", extensions, 1, 1, 1,
                "Choose Audio File", "Choose a PCM WAV File",
            };
            ZigVstgui::AccessibilityNode nodes[9];
            ZigVstgui::FileDropView views[] = {
                {VSTGUI::CRect(8, 8, 312, 112), description, {}, styles, &nodes[0]},
                {VSTGUI::CRect(328, 8, 632, 112), description, {}, styles, &nodes[1]},
                {VSTGUI::CRect(648, 8, 952, 112), description, {}, styles, &nodes[2]},
                {VSTGUI::CRect(8, 128, 312, 232), description, {}, styles, &nodes[3]},
                {VSTGUI::CRect(328, 128, 632, 232), description, {}, styles, &nodes[4]},
                {VSTGUI::CRect(648, 128, 952, 232), description, {}, styles, &nodes[5]},
                {VSTGUI::CRect(8, 248, 312, 352), description, {}, styles, &nodes[6]},
                {VSTGUI::CRect(328, 248, 632, 352), description, {}, styles, &nodes[7]},
                {VSTGUI::CRect(648, 248, 952, 352), description, {}, styles, &nodes[8]},
            };
            ZigVstguiFileImportSnapshot snapshots[] = {
                {ZIG_VSTGUI_FILE_IMPORT_VALIDATING, ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE, ZIG_VSTGUI_FILE_IMPORT_PICKER, 0.0, 1, 0, 0, 0, 0},
                {ZIG_VSTGUI_FILE_IMPORT_IMPORTING, ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE, ZIG_VSTGUI_FILE_IMPORT_DROP, 0.42, 2, 48000, 2, 4096, 0},
                {ZIG_VSTGUI_FILE_IMPORT_READY, ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE, ZIG_VSTGUI_FILE_IMPORT_PICKER, 1.0, 3, 48000, 2, 4096, 256},
                {ZIG_VSTGUI_FILE_IMPORT_EMPTY, ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE, ZIG_VSTGUI_FILE_IMPORT_DROP, 1.0, 4, 48000, 1, 0, 0},
                {ZIG_VSTGUI_FILE_IMPORT_UNSUPPORTED_FILE, ZIG_VSTGUI_FILE_IMPORT_FAILURE_UNSUPPORTED_FORMAT, ZIG_VSTGUI_FILE_IMPORT_PICKER, 0.0, 5, 0, 0, 0, 0},
                {ZIG_VSTGUI_FILE_IMPORT_CAPACITY_LIMIT, ZIG_VSTGUI_FILE_IMPORT_FAILURE_TOO_LARGE, ZIG_VSTGUI_FILE_IMPORT_DROP, 0.0, 6, 0, 0, 0, 0},
                {ZIG_VSTGUI_FILE_IMPORT_INVALID_PATH, ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE, ZIG_VSTGUI_FILE_IMPORT_PICKER, 0.0, 7, 0, 0, 0, 0},
                {ZIG_VSTGUI_FILE_IMPORT_CANCELLED, ZIG_VSTGUI_FILE_IMPORT_FAILURE_CANCELLED, ZIG_VSTGUI_FILE_IMPORT_DROP, 0.25, 8, 0, 0, 0, 0},
                {ZIG_VSTGUI_FILE_IMPORT_FAILED, ZIG_VSTGUI_FILE_IMPORT_FAILURE_TRUNCATED, ZIG_VSTGUI_FILE_IMPORT_PICKER, 0.67, 9, 0, 0, 0, 0},
            };
            for (uint32_t index = 0; index < 9; ++index) {
                views[index].applyImportSnapshot(snapshots[index]);
                views[index].draw(&context);
            }
        },
    };
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

Snapshot actionButtons() {
    return {
        "action-buttons.png",
        640,
        88,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 640, 88)));
            container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            const ZigVstguiActionButtonDescription descriptions[] = {
                {1, 1, "Apply Edit", "Apply edit", nullptr, nullptr, nullptr,
                    ZIG_VSTGUI_ACTION_PRIMARY, ZIG_VSTGUI_ACTION_ICON_NONE, 1},
                {2, 2, nullptr, "Clear impulse response", "Remove the loaded impulse response",
                    "Confirm Clear IR", "Clear failed. Try again",
                    ZIG_VSTGUI_ACTION_DESTRUCTIVE, ZIG_VSTGUI_ACTION_ICON_CLEAR, 1},
                {2, 3, "Normalize", "Normalize impulse response", nullptr, nullptr,
                    "Normalize failed. Try again", ZIG_VSTGUI_ACTION_SECONDARY,
                    ZIG_VSTGUI_ACTION_ICON_NONE, 1},
            };
            ZigVstguiCallbacks accepted {};
            accepted.invoke_action = acceptAction;
            ZigVstguiCallbacks rejected {};
            rejected.invoke_action = rejectAction;
            ZigVstgui::ActionButtonControl controls[3];
            controls[0].build(container, descriptions[0], accepted, styles);
            controls[1].build(container, descriptions[1], accepted, styles);
            controls[2].build(container, descriptions[2], rejected, styles);
            controls[0].setBounds(VSTGUI::CRect(12, 26, 188, 62));
            controls[1].setBounds(VSTGUI::CRect(214, 26, 390, 62));
            controls[2].setBounds(VSTGUI::CRect(408, 26, 628, 62));
            controls[1].activate();
            controls[2].activate();
            container->drawRect(&context, container->getViewSize());
            for (auto& control : controls) control.clear();
        },
    };
}

Snapshot editableLabelsAndProgress() {
    return {
        "editable-labels-progress.png",
        720,
        180,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 720, 180)));
            container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            const ZigVstguiEditableLabelDescription editable {
                1, "IR Name", "Impulse response name", "Name this impulse response",
                "Enter an IR name", "Studio Plate", 48, 1,
            };
            TextProgressVisualState accepted_state;
            TextProgressVisualState rejected_state;
            rejected_state.reject = true;
            ZigVstguiCallbacks accepted_callbacks {};
            accepted_callbacks.userdata = &accepted_state;
            accepted_callbacks.store_editor_text = storeVisualText;
            accepted_callbacks.load_editor_text = loadVisualText;
            ZigVstguiCallbacks rejected_callbacks = accepted_callbacks;
            rejected_callbacks.userdata = &rejected_state;
            ZigVstgui::EditableLabelControl labels[2];
            labels[0].build(container, editable, accepted_callbacks, styles);
            labels[1].build(container, editable, rejected_callbacks, styles);
            labels[0].setBounds(VSTGUI::CRect(8, 8, 96, 40), VSTGUI::CRect(104, 8, 344, 40),
                VSTGUI::CRect(104, 40, 344, 64));
            labels[1].setBounds(VSTGUI::CRect(368, 8, 456, 40), VSTGUI::CRect(464, 8, 712, 40),
                VSTGUI::CRect(464, 40, 712, 64));
            labels[1].accessibilityNode().perform(ZigVstgui::AccessibilityAction::set_value, 0.0, "");

            const ZigVstguiProgressIndicatorDescription progress {
                1, "Import", "Impulse response import progress", "Choose an IR to begin",
                "Importing IR", "IR ready", "Import failed", 20,
            };
            TextProgressVisualState progress_states[4];
            progress_states[0].progress = {ZIG_VSTGUI_PROGRESS_DETERMINATE, ZIG_VSTGUI_PROGRESS_IDLE, 0.0, 1};
            progress_states[1].progress = {ZIG_VSTGUI_PROGRESS_DETERMINATE, ZIG_VSTGUI_PROGRESS_RUNNING, 0.42, 2};
            progress_states[2].progress = {ZIG_VSTGUI_PROGRESS_INDETERMINATE, ZIG_VSTGUI_PROGRESS_RUNNING, 0.0, 3};
            progress_states[3].progress = {ZIG_VSTGUI_PROGRESS_DETERMINATE, ZIG_VSTGUI_PROGRESS_FAILED, 0.67, 4};
            ZigVstgui::AccessibilityNode nodes[4];
            ZigVstgui::ProgressView* views[4] {};
            for (uint32_t index = 0; index < 4; ++index) {
                ZigVstguiCallbacks callbacks {};
                callbacks.userdata = &progress_states[index];
                callbacks.load_progress = loadVisualProgress;
                const double left = 8.0 + index * 178.0;
                views[index] = new ZigVstgui::ProgressView(
                    VSTGUI::CRect(left, 92, left + 168, 140), progress, callbacks, styles, &nodes[index]);
                views[index]->tick();
                container->addView(views[index]);
            }
            container->drawRect(&context, container->getViewSize());
            for (auto& label : labels) label.clear();
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
    return benchmarkDraw(container, offscreen);
}

double benchmarkPianoDraw() {
    ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
    auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 480, 100)));
    container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
    ZigVstguiCallbacks callbacks {};
    callbacks.send_note = acceptNote;
    const ZigVstguiPianoDescription description {"Keyboard", 48, 24, 0, 0.8, 60};
    ZigVstgui::PianoControl piano(description, callbacks);
    piano.build(container, styles);
    piano.setBounds(VSTGUI::CRect(8, 4, 472, 22), VSTGUI::CRect(8, 22, 472, 96));
    piano.pointerPress(60, 0.8);
    const auto offscreen = VSTGUI::COffscreenContext::create(VSTGUI::CPoint(480, 100), 1.0);
    if (!offscreen) return 1e9;
    offscreen->beginDraw();
    container->drawRect(offscreen, container->getViewSize());
    offscreen->endDraw();
    const double average = benchmarkDraw(container, offscreen);
    piano.clear();
    return average;
}

double benchmarkStepSequencerDraw() {
    ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
    auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 480, 90)));
    container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
    const uint32_t ids[] = {100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115};
    const ZigVstguiStepSequencerDescription description {
        "Pattern", ids, 16, 9, 0x33, 0x5555, 1, 0, 30,
    };
    ZigVstguiCallbacks callbacks {};
    callbacks.begin_edit = acceptBegin;
    callbacks.perform_edit = acceptEdit;
    callbacks.end_edit = acceptEnd;
    callbacks.store_editor_index = acceptIndex;
    ZigVstgui::StepSequencerControl sequencer(description, callbacks, {});
    sequencer.build(container, styles);
    sequencer.setBounds(VSTGUI::CRect(8, 4, 472, 22), VSTGUI::CRect(8, 22, 472, 86));
    const auto offscreen = VSTGUI::COffscreenContext::create(VSTGUI::CPoint(480, 90), 1.0);
    if (!offscreen) return 1e9;
    const double average = benchmarkDraw(container, offscreen);
    sequencer.clear();
    return average;
}

double benchmarkFileDropDraw() {
    ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
    auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 480, 120)));
    container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
    const char* extensions[] = {".wav", ".aiff"};
    const ZigVstguiFileDropDescription description {
        1, "Audio Import", "Drop audio here", extensions, 2, 2, 1,
        "Choose Audio File", "Choose Audio File",
    };
    ZigVstgui::AccessibilityNode accessibility;
    auto* view = new ZigVstgui::FileDropView(
        VSTGUI::CRect(8, 8, 472, 112), description, {}, styles, &accessibility
    );
    view->applyImportSnapshot({
        ZIG_VSTGUI_FILE_IMPORT_IMPORTING, ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE,
        ZIG_VSTGUI_FILE_IMPORT_PICKER, 0.42, 2, 48000, 2, 4096, 0,
    });
    container->addView(view);
    const auto offscreen = VSTGUI::COffscreenContext::create(VSTGUI::CPoint(480, 120), 1.0);
    return benchmarkDraw(container, offscreen);
}

double benchmarkActionButtonDraw() {
    ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
    auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 320, 72)));
    container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
    const ZigVstguiActionButtonDescription description {
        1, 1, "Apply Edit", "Apply edit", nullptr, nullptr, nullptr,
        ZIG_VSTGUI_ACTION_PRIMARY, ZIG_VSTGUI_ACTION_ICON_NONE, 1,
    };
    ZigVstguiCallbacks callbacks {};
    callbacks.invoke_action = acceptAction;
    ZigVstgui::ActionButtonControl action;
    action.build(container, description, callbacks, styles);
    action.setBounds(VSTGUI::CRect(8, 16, 180, 56));
    const auto offscreen = VSTGUI::COffscreenContext::create(VSTGUI::CPoint(320, 72), 1.0);
    if (!offscreen) return 1e9;
    const double average = benchmarkDraw(container, offscreen);
    action.clear();
    return average;
}

double benchmarkProgressDraw() {
    ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
    auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 320, 72)));
    container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
    const ZigVstguiProgressIndicatorDescription description {
        1, "Import", "Import progress", "Waiting", "Importing", "Ready", "Failed", 20,
    };
    TextProgressVisualState state;
    state.progress = {ZIG_VSTGUI_PROGRESS_DETERMINATE, ZIG_VSTGUI_PROGRESS_RUNNING, 0.42, 1};
    ZigVstguiCallbacks callbacks {};
    callbacks.userdata = &state;
    callbacks.load_progress = loadVisualProgress;
    ZigVstgui::AccessibilityNode accessibility;
    auto* progress = new ZigVstgui::ProgressView(
        VSTGUI::CRect(8, 16, 312, 56), description, callbacks, styles, &accessibility);
    progress->tick();
    container->addView(progress);
    const auto offscreen = VSTGUI::COffscreenContext::create(VSTGUI::CPoint(320, 72), 1.0);
    return benchmarkDraw(container, offscreen);
}

double benchmarkSignalViewsDraw() {
    ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
    auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 640, 180)));
    container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
    ZigVstguiGraphPoint waveform[256] {};
    ZigVstguiGraphPoint spectrum[256] {};
    for (uint32_t index = 0; index < 256; ++index) {
        const double normalized = static_cast<double>(index) / 255.0;
        waveform[index] = {normalized, std::sin(normalized * 25.1327412287) * 0.8};
        spectrum[index] = {20.0 * std::pow(1000.0, normalized), -84.0 + 72.0 * std::exp(-8.0 * normalized)};
    }
    const ZigVstguiGraphDescription descriptions[] = {
        {"Waveform", ZIG_VSTGUI_GRAPH_WAVEFORM, ZIG_VSTGUI_GRAPH_MODULATION, {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Frame"}, {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Level"}, waveform, 256, 0, 0, 0},
        {"Spectrum", ZIG_VSTGUI_GRAPH_SPECTRUM, ZIG_VSTGUI_GRAPH_PRIMARY, {20.0, 20000.0, ZIG_VSTGUI_GRAPH_LOGARITHMIC, "Hz"}, {-96.0, 0.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"}, spectrum, 256, 0, 0, 0},
    };
    ZigVstgui::AccessibilityNode accessibility[2];
    container->addView(new ZigVstgui::GraphView(
        VSTGUI::CRect(8, 8, 312, 172), descriptions[0], styles, &accessibility[0]
    ));
    container->addView(new ZigVstgui::GraphView(
        VSTGUI::CRect(328, 8, 632, 172), descriptions[1], styles, &accessibility[1]
    ));
    const auto offscreen = VSTGUI::COffscreenContext::create(VSTGUI::CPoint(640, 180), 1.0);
    return benchmarkDraw(container, offscreen);
}

double benchmarkGraphOverlayDraw(bool with_selection) {
    ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
    auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 320, 180)));
    container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
    ZigVstguiGraphPoint waveform[256] {};
    for (uint32_t index = 0; index < 256; ++index) {
        const double normalized = static_cast<double>(index) / 255.0;
        waveform[index] = {normalized, std::sin(normalized * 25.1327412287) * std::exp(-3.0 * normalized)};
    }
    ZigVstguiGraphDescription description {
        "IR Detail", ZIG_VSTGUI_GRAPH_WAVEFORM, ZIG_VSTGUI_GRAPH_MODULATION,
        {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Time"},
        {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Level"}, waveform, 256, 0, 0, 0,
    };
    description.viewport = {
        1, ZIG_VSTGUI_VIEWPORT_HORIZONTAL, 1.0, 128.0, 8.0, 0.4, 0.0, 1.25, 0.1, 0, 0, 0,
    };
    if (with_selection) description.range_selection = {1, 0.45, 0.55, 0.001, 0.001, 0, 0};
    ZigVstgui::AccessibilityNode accessibility;
    container->addView(new ZigVstgui::GraphView(
        VSTGUI::CRect(8, 8, 312, 172), description, styles, &accessibility
    ));
    const auto offscreen = VSTGUI::COffscreenContext::create(VSTGUI::CPoint(320, 180), 1.0);
    return benchmarkDraw(container, offscreen);
}

double benchmarkViewportDraw() { return benchmarkGraphOverlayDraw(false); }
double benchmarkRangeSelectionDraw() { return benchmarkGraphOverlayDraw(true); }

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
        graphViewports(),
        signalViews(),
        xyPad(),
        editableEnvelope(),
        presetBrowsers(),
        closedActionMenu(),
        actionMenus(),
        actionButtons(),
        editableLabelsAndProgress(),
        pianoKeyboard(),
        stepSequencer(),
        fileDrops(),
        fileImportStates(),
    };
    int result = 0;
    for (const auto& snapshot : snapshots) {
        result = std::max(result, runSnapshot(snapshot, references, output, update));
    }
    if (!update) {
        const double average = benchmarkWarmDraw();
        const double piano_average = benchmarkPianoDraw();
        const double step_sequencer_average = benchmarkStepSequencerDraw();
        const double file_drop_average = benchmarkFileDropDraw();
        const double action_button_average = benchmarkActionButtonDraw();
        const double progress_average = benchmarkProgressDraw();
        const double signal_views_average = benchmarkSignalViewsDraw();
        const double viewport_average = benchmarkViewportDraw();
        const double range_selection_average = benchmarkRangeSelectionDraw();
        std::fprintf(stderr, "visual regression warm render average: %.1f us\n", average);
        std::fprintf(stderr, "piano warm render average: %.1f us\n", piano_average);
        std::fprintf(stderr, "step sequencer warm render average: %.1f us\n", step_sequencer_average);
        std::fprintf(stderr, "file drop warm render average: %.1f us\n", file_drop_average);
        std::fprintf(stderr, "action button warm render average: %.1f us\n", action_button_average);
        std::fprintf(stderr, "progress warm render average: %.1f us\n", progress_average);
        std::fprintf(stderr, "signal views warm render average: %.1f us\n", signal_views_average);
        std::fprintf(stderr, "viewport warm render average: %.1f us\n", viewport_average);
        std::fprintf(stderr, "range selection warm render average: %.1f us\n", range_selection_average);
        if (average > 300.0 || piano_average > 300.0 || step_sequencer_average > 300.0 ||
            file_drop_average > 300.0 || action_button_average > 300.0 || progress_average > 300.0 ||
            signal_views_average > 300.0 || viewport_average > 300.0 ||
            range_selection_average > 300.0) result = std::max(result, 6);
    }
    VSTGUI::exit();
    return result;
}
