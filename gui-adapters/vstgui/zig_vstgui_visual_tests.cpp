#include "zig_vstgui_assets.h"
#include "zig_vstgui_action_button.h"
#include "zig_vstgui_action_menu.h"
#include "zig_vstgui_controls.h"
#include "zig_vstgui_drawing.h"
#include "zig_vstgui_editor.h"
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
#include "vstgui/lib/cframe.h"
#include "vstgui/lib/coffscreencontext.h"
#include "vstgui/lib/cviewcontainer.h"
#include "vstgui/lib/platform/platformfactory.h"
#include "vstgui/lib/vstguiinit.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <ctime>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <functional>
#include <memory>
#include <stdexcept>
#include <string>

namespace {

constexpr uint8_t channel_tolerance = 80;
constexpr uint64_t mismatch_per_thousand = 20;
constexpr double warm_draw_budget_us = 300.0;
constexpr double signal_views_budget_us = 450.0;
constexpr double sample_lifecycle_budget_us = 75'000.0;

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

uint32_t loadChannelGraph(void*, uint32_t source_id, ZigVstguiGraphPoint* output, uint32_t capacity) {
    if (!output || capacity == 0) return 0;
    const uint32_t count = std::min<uint32_t>(capacity, 64);
    for (uint32_t index = 0; index < count; ++index) {
        const double normalized = count > 1
            ? static_cast<double>(index) / static_cast<double>(count - 1)
            : 0.0;
        if (source_id == 1) {
            output[index] = {
                20.0 * std::pow(1200.0, normalized),
                -88.0 + 64.0 * std::exp(-3.0 * normalized) * std::abs(std::sin(18.0 * normalized)),
            };
        } else {
            const double decay = source_id == 2 ? std::exp(-4.0 * normalized) : 1.0;
            output[index] = {normalized, std::sin(25.1327412287 * normalized) * 0.72 * decay};
        }
    }
    return count;
}

uint32_t loadIrGraph(void*, uint32_t, ZigVstguiGraphPoint* output, uint32_t capacity) {
    if (!output || capacity == 0) return 0;
    const uint32_t count = std::min<uint32_t>(capacity, 96);
    for (uint32_t index = 0; index < count; ++index) {
        const double normalized = count > 1
            ? static_cast<double>(index) / static_cast<double>(count - 1)
            : 0.0;
        output[index] = {
            normalized,
            std::sin(62.8318530718 * normalized) * std::exp(-5.0 * normalized),
        };
    }
    return count;
}

void acceptBegin(void*, uint32_t) {}
int32_t acceptEdit(void*, uint32_t, double) { return 0; }
void acceptEnd(void*, uint32_t) {}
int32_t acceptIndex(void*, uint32_t, uint32_t) { return 0; }
int32_t rejectDrop(void*, uint32_t, const char* const*, uint32_t) { return -1; }
int32_t acceptAction(void*, uint32_t, uint32_t) { return 0; }
int32_t rejectAction(void*, uint32_t, uint32_t) { return -1; }
int32_t acceptPreset(void*, uint32_t) { return 0; }
int32_t throwDuringDraw(void*, const ZigVstguiDrawRequest*, ZigVstguiCanvas*) {
    throw std::runtime_error("drawing callback failure");
}
int32_t acceptImport(
    void*,
    uint32_t,
    ZigVstguiFileImportEntryPoint,
    const char* const*,
    uint32_t
) { return 0; }
int32_t acceptImportCommand(void*, uint32_t, ZigVstguiFileImportCommand) { return 0; }
int32_t formatEqValue(void*, uint32_t parameter_id, double normalized, char* output, uint32_t capacity) {
    if (!output || capacity == 0) return -1;
    const bool type_parameter = parameter_id == 4 || parameter_id == 9 || parameter_id == 14;
    if (type_parameter) {
        const char* value = normalized < 0.25 ? "low_shelf" :
            normalized < 0.75 ? "bell" : "high_shelf";
        const int written = std::snprintf(output, capacity, "%s", value);
        return written >= 0 && static_cast<uint32_t>(written) < capacity ? written : -1;
    }
    const int written = std::snprintf(output, capacity, "%.3f", normalized);
    return written >= 0 && static_cast<uint32_t>(written) < capacity ? written : -1;
}

int32_t formatFilterValue(void*, uint32_t parameter_id, double normalized, char* output, uint32_t capacity) {
    if (!output || capacity == 0) return -1;
    if (parameter_id == 1) {
        const char* value = normalized < 1.0 / 6.0 ? "low_pass" :
            normalized < 0.5 ? "high_pass" : normalized < 5.0 / 6.0 ? "band_pass" : "notch";
        const int written = std::snprintf(output, capacity, "%s", value);
        return written >= 0 && static_cast<uint32_t>(written) < capacity ? written : -1;
    }
    const int written = std::snprintf(output, capacity, "%.3f", normalized);
    return written >= 0 && static_cast<uint32_t>(written) < capacity ? written : -1;
}

int32_t formatChannelValue(void*, uint32_t parameter_id, double normalized, char* output, uint32_t capacity) {
    if (!output || capacity == 0) return -1;
    if (parameter_id == 1) {
        const int written = std::snprintf(output, capacity, "%s", normalized < 0.5 ? "Off" : "On");
        return written >= 0 && static_cast<uint32_t>(written) < capacity ? written : -1;
    }
    if (parameter_id == 2) {
        const char* value = normalized < 0.25 ? "clean" : normalized < 0.75 ? "boost" : "mute";
        const int written = std::snprintf(output, capacity, "%s", value);
        return written >= 0 && static_cast<uint32_t>(written) < capacity ? written : -1;
    }
    const int written = std::snprintf(output, capacity, "%.3f", normalized);
    return written >= 0 && static_cast<uint32_t>(written) < capacity ? written : -1;
}

int32_t formatIrValue(void*, uint32_t parameter_id, double normalized, char* output, uint32_t capacity) {
    if (!output || capacity == 0) return -1;
    if (parameter_id == 2) {
        const int written = std::snprintf(output, capacity, "%s", normalized < 0.5 ? "Off" : "On");
        return written >= 0 && static_cast<uint32_t>(written) < capacity ? written : -1;
    }
    const int written = parameter_id == 0
        ? std::snprintf(output, capacity, "%.1f", normalized * 100.0)
        : std::snprintf(output, capacity, "%.3f", (normalized - 2.0 / 3.0) * 36.0);
    return written >= 0 && static_cast<uint32_t>(written) < capacity ? written : -1;
}

int32_t formatSampleValue(void*, uint32_t parameter_id, double normalized, char* output, uint32_t capacity) {
    if (!output || capacity == 0) return -1;
    if (parameter_id == 15) {
        const int written = std::snprintf(output, capacity, "%s", normalized < 0.5 ? "gate" : "one_shot");
        return written >= 0 && static_cast<uint32_t>(written) < capacity ? written : -1;
    }
    if (parameter_id == 14) {
        const char* values[] = {"mono", "two", "four", "eight"};
        const auto index = static_cast<std::size_t>(std::clamp(std::round(normalized * 3.0), 0.0, 3.0));
        const int written = std::snprintf(output, capacity, "%s", values[index]);
        return written >= 0 && static_cast<uint32_t>(written) < capacity ? written : -1;
    }
    const int written = std::snprintf(output, capacity, "%.3f", normalized);
    return written >= 0 && static_cast<uint32_t>(written) < capacity ? written : -1;
}

struct TextProgressVisualState {
    std::string text {"Studio Plate"};
    bool reject {false};
    ZigVstguiProgressSnapshot progress {};
    ZigVstguiFileImportSnapshot import {};
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

int32_t loadVisualImport(void* userdata, uint32_t, ZigVstguiFileImportSnapshot* output) {
    if (!userdata || !output) return -1;
    *output = static_cast<TextProgressVisualState*>(userdata)->import;
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
        const auto started = std::clock();
        for (uint32_t index = 0; index < repetitions; ++index) {
            offscreen->beginDraw();
            container->drawRect(offscreen, container->getViewSize());
            offscreen->endDraw();
        }
        const auto elapsed = std::clock() - started;
        best = std::min(
            best,
            static_cast<double>(elapsed) * 1'000'000.0 /
                static_cast<double>(CLOCKS_PER_SEC) / repetitions
        );
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

Snapshot rotaryControls() {
    return {
        "rotary-controls.png",
        480,
        96,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
            auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 480, 96)));
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
                const double left = 8.0 + index * 78.0;
                auto* knob = new ZigVstgui::RotaryKnob(
                    VSTGUI::CRect(left, 10.0, left + 68.0, 78.0),
                    nullptr,
                    static_cast<int32_t>(index),
                    styles,
                    0.5
                );
                knob->setValueNormalized(static_cast<float>((index + 1.0) / 7.0));
                if (index == 1) knob->setModulation(0.82);
                knob->forceVisualStateForTesting(states[index]);
                if (states[index] == ZigVstgui::VisualState::disabled) {
                    knob->setAlphaValue(styles.resolve(
                        ZigVstgui::ComponentKind::knob,
                        ZigVstgui::VisualState::disabled
                    ).alpha);
                }
                container->addView(knob);
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

Snapshot linkedEqResponse() {
    return {
        "linked-eq-response.png",
        640,
        220,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            context.setFillColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            context.drawRect(VSTGUI::CRect(0, 0, 640, 220), VSTGUI::kDrawFilled);
            std::array<ZigVstguiGraphPoint, 97> response {};
            std::array<ZigVstguiGraphPoint, 97> low_response {};
            std::array<ZigVstguiGraphPoint, 97> mid_response {};
            std::array<ZigVstguiGraphPoint, 97> high_response {};
            std::array<ZigVstguiGraphPoint, 64> spectrum {};
            for (std::size_t index = 0; index < response.size(); ++index) {
                const double normalized = static_cast<double>(index) / static_cast<double>(response.size() - 1);
                const double frequency = 20.0 * std::pow(1000.0, normalized);
                const double low = 7.0 / (1.0 + std::exp((normalized - 0.25) * 24.0));
                const double mid = -8.0 * std::exp(-std::pow((normalized - 0.57) / 0.09, 2.0));
                const double high = 5.0 / (1.0 + std::exp(-(normalized - 0.82) * 28.0));
                response[index] = {frequency, low + mid + high};
                low_response[index] = {frequency, low};
                mid_response[index] = {frequency, mid};
                high_response[index] = {frequency, high};
            }
            for (std::size_t index = 0; index < spectrum.size(); ++index) {
                const double normalized = static_cast<double>(index) / static_cast<double>(spectrum.size() - 1);
                spectrum[index] = {
                    20.0 * std::pow(1000.0, normalized),
                    -82.0 + 52.0 * std::exp(-std::pow((normalized - 0.58) / 0.24, 2.0)),
                };
            }
            const ZigVstguiGraphHandleDescription handles[] = {
                {1, "Low", 10, 11, 0.25, 0.65, 0, 0, 1, 12, "Q", 0.35, 0.01, 1, 13, 1, 1},
                {2, "Mid", 20, 21, 0.57, 0.33, 0, 0, 1, 22, "Q", 0.72, 0.01, 1, 23, 1, 2},
                {3, "High", 30, 31, 0.82, 0.60, 0, 0, 1, 32, "Q", 0.42, 0.01, 1, 33, 0, 3},
            };
            ZigVstguiGraphDescription description {
                "EQ Response", ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION, ZIG_VSTGUI_GRAPH_PRIMARY,
                {20.0, 20'000.0, ZIG_VSTGUI_GRAPH_LOGARITHMIC, "Hz"},
                {-24.0, 24.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"},
                response.data(), static_cast<uint32_t>(response.size()), 0, 0, 0,
            };
            description.handles = handles;
            description.handle_count = 3;
            const ZigVstguiGraphLayerDescription layers[] = {
                {ZIG_VSTGUI_GRAPH_SECONDARY, low_response.data(), static_cast<uint32_t>(low_response.size()), 0},
                {ZIG_VSTGUI_GRAPH_MODULATION, mid_response.data(), static_cast<uint32_t>(mid_response.size()), 0},
                {ZIG_VSTGUI_GRAPH_SECONDARY, high_response.data(), static_cast<uint32_t>(high_response.size()), 0},
                {
                    ZIG_VSTGUI_GRAPH_SECONDARY,
                    spectrum.data(),
                    static_cast<uint32_t>(spectrum.size()),
                    0,
                    ZIG_VSTGUI_GRAPH_SPECTRUM,
                    0,
                    0,
                    1,
                    {-96.0, 0.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"},
                    0,
                },
            };
            description.layers = layers;
            description.layer_count = 4;
            ZigVstgui::AccessibilityNode accessibility;
            ZigVstgui::GraphView graph(VSTGUI::CRect(12, 12, 628, 208), description, styles, &accessibility);
            graph.selectPoint(2);
            graph.draw(&context);
        },
    };
}

Snapshot resonantFilterResponse() {
    return {
        "resonant-filter-response.png",
        640,
        220,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
            context.setFillColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            context.drawRect(VSTGUI::CRect(0, 0, 640, 220), VSTGUI::kDrawFilled);
            std::array<ZigVstguiGraphPoint, 97> response {};
            std::array<ZigVstguiGraphPoint, 64> spectrum {};
            for (std::size_t index = 0; index < response.size(); ++index) {
                const double normalized = static_cast<double>(index) / static_cast<double>(response.size() - 1);
                const double frequency = 20.0 * std::pow(1000.0, normalized);
                const double ratio = frequency / 1'000.0;
                const double rolloff = -10.0 * std::log10(1.0 + std::pow(ratio, 4.0));
                response[index] = {frequency, rolloff};
            }
            for (std::size_t index = 0; index < spectrum.size(); ++index) {
                const double normalized = static_cast<double>(index) / static_cast<double>(spectrum.size() - 1);
                spectrum[index] = {
                    20.0 * std::pow(1000.0, normalized),
                    -88.0 + 58.0 * std::exp(-std::pow((normalized - 0.46) / 0.26, 2.0)),
                };
            }
            const ZigVstguiGraphHandleDescription handle {
                1, "Cutoff and resonance", 2, 3, 0.566, 0.377, 0, 0,
                0, 0, "", 0.0, 0.01, 0, 0, 1, 1,
            };
            ZigVstguiGraphDescription description {
                "Filter Response", ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION, ZIG_VSTGUI_GRAPH_PRIMARY,
                {20.0, 20'000.0, ZIG_VSTGUI_GRAPH_LOGARITHMIC, "Hz"},
                {-20.0, 25.105450102, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"},
                response.data(), static_cast<uint32_t>(response.size()), 1, 0, 30,
            };
            description.handles = &handle;
            description.handle_count = 1;
            const ZigVstguiGraphLayerDescription layer {
                ZIG_VSTGUI_GRAPH_SECONDARY,
                spectrum.data(),
                static_cast<uint32_t>(spectrum.size()),
                0,
                ZIG_VSTGUI_GRAPH_SPECTRUM,
                0,
                0,
                1,
                {-96.0, 0.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"},
                0,
            };
            description.layers = &layer;
            description.layer_count = 1;
            ZigVstgui::AccessibilityNode accessibility;
            ZigVstgui::GraphView graph(VSTGUI::CRect(12, 12, 628, 208), description, styles, &accessibility);
            graph.selectPoint(1);
            graph.draw(&context);
        },
    };
}

Snapshot eqAnalyzerStates() {
    return {
        "eq-analyzer-states.png",
        640,
        180,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            context.setFillColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
            context.drawRect(VSTGUI::CRect(0, 0, 640, 180), VSTGUI::kDrawFilled);
            const ZigVstguiGraphPoint response[] = {
                {20.0, 0.0}, {200.0, 4.0}, {2'000.0, -3.0}, {20'000.0, 0.0},
            };
            const ZigVstguiGraphPoint spectrum[] = {
                {40.0, -72.0}, {160.0, -48.0}, {640.0, -24.0}, {2'560.0, -38.0}, {10'240.0, -64.0},
            };
            ZigVstgui::AccessibilityNode nodes[3];
            const char* titles[] = {"Analyzer Off", "No Signal", "Analyzer Active"};
            for (uint32_t index = 0; index < 3; ++index) {
                ZigVstguiGraphLayerDescription layer {
                    ZIG_VSTGUI_GRAPH_SECONDARY,
                    index == 2 ? spectrum : nullptr,
                    index == 2 ? 5u : 0u,
                    9,
                    ZIG_VSTGUI_GRAPH_SPECTRUM,
                    index == 2 ? 0 : 1,
                    0,
                    1,
                    {-96.0, 0.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"},
                    index == 0 ? 1 : 0,
                };
                ZigVstguiGraphDescription description {
                    titles[index], ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION, ZIG_VSTGUI_GRAPH_PRIMARY,
                    {20.0, 20'000.0, ZIG_VSTGUI_GRAPH_LOGARITHMIC, "Hz"},
                    {-24.0, 24.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"},
                    response, 4, 0, 0, 30,
                };
                description.layers = &layer;
                description.layer_count = 1;
                ZigVstgui::GraphView graph(
                    VSTGUI::CRect(8.0 + index * 212.0, 8.0, 208.0 + index * 212.0, 172.0),
                    description,
                    styles,
                    &nodes[index]
                );
                graph.draw(&context);
            }
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
            full.secondary_range_selection = {1, 0.32, 0.62, 0.01, 0.01, 0, 0};
            auto detail = full;
            detail.title = "Zoomed IR";
            detail.viewport.initial_zoom = 4.0;
            detail.viewport.initial_x_offset = 0.2;
            detail.range_selection.initial_start = 0.28;
            detail.range_selection.initial_end = 0.42;
            detail.secondary_range_selection.initial_start = 0.31;
            detail.secondary_range_selection.initial_end = 0.38;
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

Snapshot irWorkflowStates() {
    return {
        "ir-workflow-states.png",
        1240,
        500,
        1.0,
        [](VSTGUI::CDrawContext& context) {
            ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
            auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 1240, 500)));
            const auto editor_style = styles.resolve(ZigVstgui::ComponentKind::editor);
            const auto label_style = styles.resolve(ZigVstgui::ComponentKind::help);
            container->setBackgroundColor(editor_style.background);
            const char* names[] = {
                "Empty", "Importing", "Ready", "Editing",
                "Confirming", "Success", "Recoverable Error",
            };
            for (uint32_t index = 0; index < 7; ++index) {
                const double left = 8.0 + (index % 4) * 308.0;
                const double top = 8.0 + (index / 4) * 244.0;
                auto* label = new VSTGUI::CTextLabel(
                    VSTGUI::CRect(left, top, left + 292.0, top + 30.0), names[index]);
                label->setFont(styles.font(ZigVstgui::TypographyRole::body));
                label->setFontColor(label_style.foreground);
                label->setBackColor(label_style.background);
                container->addView(label);
            }

            const char* extensions[] = {".wav"};
            const ZigVstguiFileDropDescription importer {
                1, "Impulse Response", "Drop a PCM WAV impulse response here", extensions, 1, 1, 1,
                "Choose IR", "Choose an Impulse Response",
            };
            ZigVstgui::AccessibilityNode importer_nodes[4];
            auto* empty = new ZigVstgui::FileDropView(
                VSTGUI::CRect(8, 46, 300, 190), importer, {}, styles, &importer_nodes[0]);
            auto* importing = new ZigVstgui::FileDropView(
                VSTGUI::CRect(316, 46, 608, 190), importer, {}, styles, &importer_nodes[1]);
            auto* ready = new ZigVstgui::FileDropView(
                VSTGUI::CRect(624, 46, 916, 190), importer, {}, styles, &importer_nodes[2]);
            auto* failed = new ZigVstgui::FileDropView(
                VSTGUI::CRect(624, 290, 916, 434), importer, {}, styles, &importer_nodes[3]);
            importing->applyImportSnapshot({
                ZIG_VSTGUI_FILE_IMPORT_IMPORTING, ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE,
                ZIG_VSTGUI_FILE_IMPORT_PICKER, 0.42, 2, 48000, 2, 4096, 0,
            });
            ready->applyImportSnapshot({
                ZIG_VSTGUI_FILE_IMPORT_READY, ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE,
                ZIG_VSTGUI_FILE_IMPORT_PICKER, 1.0, 3, 48000, 2, 4096, 256,
            });
            failed->applyImportSnapshot({
                ZIG_VSTGUI_FILE_IMPORT_FAILED, ZIG_VSTGUI_FILE_IMPORT_FAILURE_TRUNCATED,
                ZIG_VSTGUI_FILE_IMPORT_PICKER, 0.67, 4, 0, 0, 0, 0,
            });
            container->addView(empty);
            container->addView(importing);
            container->addView(ready);
            container->addView(failed);

            const ZigVstguiGraphPoint waveform[] = {
                {0.0, 0.0}, {0.08, 0.9}, {0.16, -0.55}, {0.3, 0.36},
                {0.48, -0.2}, {0.68, 0.1}, {0.84, -0.04}, {1.0, 0.0},
            };
            ZigVstguiGraphDescription graph {
                "Impulse Response", ZIG_VSTGUI_GRAPH_WAVEFORM, ZIG_VSTGUI_GRAPH_MODULATION,
                {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Time"},
                {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Level"}, waveform, 8, 0, 0, 0,
            };
            graph.viewport = {
                1, ZIG_VSTGUI_VIEWPORT_HORIZONTAL, 1.0, 128.0, 3.0, 0.1, 0.0, 1.25, 0.1, 0, 0, 0,
            };
            graph.range_selection = {1, 0.18, 0.72, 0.01, 0.01, 0, 0};
            ZigVstgui::AccessibilityNode graph_node;
            container->addView(new ZigVstgui::GraphView(
                VSTGUI::CRect(932, 46, 1224, 180), graph, styles, &graph_node));

            const ZigVstguiActionButtonDescription trim_description {
                1, 1, "Trim", "Trim to selection", nullptr, nullptr,
                "Trim failed. Adjust the selection and retry", ZIG_VSTGUI_ACTION_PRIMARY,
                ZIG_VSTGUI_ACTION_ICON_NONE, 1,
            };
            ZigVstguiCallbacks action_callbacks {};
            action_callbacks.invoke_action = acceptAction;
            ZigVstgui::ActionButtonControl trim;
            trim.build(container, trim_description, action_callbacks, styles);
            trim.setBounds(VSTGUI::CRect(944, 190, 1212, 230));

            const ZigVstguiActionButtonDescription clear_description {
                2, 1, nullptr, "Clear impulse response", "Remove the loaded impulse response",
                "Confirm Clear IR", "Clear failed. Try again", ZIG_VSTGUI_ACTION_DESTRUCTIVE,
                ZIG_VSTGUI_ACTION_ICON_CLEAR, 1,
            };
            ZigVstgui::ActionButtonControl clear;
            clear.build(container, clear_description, action_callbacks, styles);
            clear.setBounds(VSTGUI::CRect(20, 330, 288, 374));
            clear.activate();

            const ZigVstguiProgressIndicatorDescription progress {
                1, "Import", "Impulse response import progress", "Choose an IR to begin",
                "Importing IR", "IR ready", "Import failed", 20,
            };
            TextProgressVisualState success_state;
            success_state.progress = {
                ZIG_VSTGUI_PROGRESS_DETERMINATE, ZIG_VSTGUI_PROGRESS_COMPLETE, 1.0, 5,
            };
            ZigVstguiCallbacks progress_callbacks {};
            progress_callbacks.userdata = &success_state;
            progress_callbacks.load_progress = loadVisualProgress;
            ZigVstgui::AccessibilityNode progress_node;
            auto* success = new ZigVstgui::ProgressView(
                VSTGUI::CRect(328, 330, 596, 390), progress, progress_callbacks, styles, &progress_node);
            success->tick();
            container->addView(success);

            container->drawRect(&context, container->getViewSize());
            trim.clear();
            clear.clear();
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
            const ZigVstguiEditableLabelDescription read_only {
                2, "Format", "Impulse response format", "", "Value unavailable",
                "48 kHz, stereo", 48, 1, 1, 10,
            };
            TextProgressVisualState accepted_state;
            TextProgressVisualState rejected_state;
            rejected_state.reject = true;
            TextProgressVisualState live_state;
            live_state.text = "48 kHz, stereo";
            ZigVstguiCallbacks accepted_callbacks {};
            accepted_callbacks.userdata = &accepted_state;
            accepted_callbacks.store_editor_text = storeVisualText;
            accepted_callbacks.load_editor_text = loadVisualText;
            ZigVstguiCallbacks rejected_callbacks = accepted_callbacks;
            rejected_callbacks.userdata = &rejected_state;
            ZigVstguiCallbacks live_callbacks = accepted_callbacks;
            live_callbacks.userdata = &live_state;
            live_callbacks.store_editor_text = nullptr;
            ZigVstgui::EditableLabelControl labels[3];
            labels[0].build(container, editable, accepted_callbacks, styles);
            labels[1].build(container, editable, rejected_callbacks, styles);
            labels[2].build(container, read_only, live_callbacks, styles);
            labels[0].setBounds(VSTGUI::CRect(8, 8, 64, 40), VSTGUI::CRect(72, 8, 232, 40),
                VSTGUI::CRect(72, 40, 232, 64));
            labels[1].setBounds(VSTGUI::CRect(244, 8, 308, 40), VSTGUI::CRect(316, 8, 468, 40),
                VSTGUI::CRect(316, 40, 468, 64));
            labels[2].setBounds(VSTGUI::CRect(480, 8, 536, 40), VSTGUI::CRect(544, 8, 712, 40),
                VSTGUI::CRect(544, 40, 712, 64));
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

std::shared_ptr<ZigVstguiEditor> buildParameterWorkspace(
    uint32_t width,
    uint32_t height,
    ZigVstguiThemeKind theme = ZIG_VSTGUI_THEME_DEFAULT
) {
    const char* titles[] = {
        "Bypass", "Output", "Enable", "Type", "Freq", "Gain", "Q",
        "Enable", "Type", "Freq", "Gain", "Q",
        "Enable", "Type", "Freq", "Gain", "Q",
    };
    const char* units[] = {
        "", "dB", "", "", "Hz", "dB", "",
        "", "", "Hz", "dB", "",
        "", "", "Hz", "dB", "",
    };
    const int32_t steps[] = {1, 0, 1, 2, 0, 0, 0, 1, 2, 0, 0, 0, 1, 2, 0, 0, 0};
    const ZigVstguiControlKind kinds[] = {
        ZIG_VSTGUI_CONTROL_TOGGLE, ZIG_VSTGUI_CONTROL_DECIBEL_SLIDER,
        ZIG_VSTGUI_CONTROL_TOGGLE, ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN,
        ZIG_VSTGUI_CONTROL_ROTARY_KNOB, ZIG_VSTGUI_CONTROL_ROTARY_KNOB,
        ZIG_VSTGUI_CONTROL_ROTARY_KNOB,
        ZIG_VSTGUI_CONTROL_TOGGLE, ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN,
        ZIG_VSTGUI_CONTROL_ROTARY_KNOB, ZIG_VSTGUI_CONTROL_ROTARY_KNOB,
        ZIG_VSTGUI_CONTROL_ROTARY_KNOB,
        ZIG_VSTGUI_CONTROL_TOGGLE, ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN,
        ZIG_VSTGUI_CONTROL_ROTARY_KNOB, ZIG_VSTGUI_CONTROL_ROTARY_KNOB,
        ZIG_VSTGUI_CONTROL_ROTARY_KNOB,
    };
    const double values[] = {
        0.0, 0.5, 1.0, 0.0, 0.26, 0.58, 0.30,
        1.0, 0.5, 0.57, 0.42, 0.42,
        1.0, 1.0, 0.87, 0.54, 0.30,
    };
    std::array<ZigVstguiParameterDescription, 17> parameters {};
    for (uint32_t index = 0; index < parameters.size(); ++index) {
        parameters[index] = {
            index + 1,
            values[index],
            {titles[index], units[index], steps[index], values[index]},
            kinds[index],
        };
    }
    const ZigVstguiGraphPoint response[] = {
        {20.0, 0.0}, {120.0, 4.0}, {1'000.0, -3.0}, {8'000.0, 2.0}, {20'000.0, 0.0},
    };
    const ZigVstguiGraphHandleDescription handles[] = {
        {1, "Low", 5, 6, 0.26, 0.58, 0, 0, 1, 7, "Q", 0.30, 0.1, 1, 3, 1, 1},
        {2, "Mid", 10, 11, 0.57, 0.42, 0, 0, 1, 12, "Q", 0.42, 0.1, 1, 8, 1, 2},
        {3, "High", 15, 16, 0.87, 0.54, 0, 0, 1, 17, "Q", 0.30, 0.1, 1, 13, 1, 3},
    };
    ZigVstguiGraphDescription graph {
        "EQ Response",
        ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION,
        ZIG_VSTGUI_GRAPH_PRIMARY,
        {20.0, 20'000.0, ZIG_VSTGUI_GRAPH_LOGARITHMIC, "Hz"},
        {-24.0, 24.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"},
        response,
        5,
        0,
        0,
        30,
    };
    graph.handles = handles;
    graph.handle_count = 3;
    graph.initial_selected_point_id = 2;
    const ZigVstguiGroupDescription groups[] = {
        {"Output", 0, 2, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0x75b9f0ff}, 0, 1, 0, 0},
        {"Low", 2, 5, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0x4ed9b4ff}, 1, 0, 0, 0},
        {"Mid", 7, 5, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0xb58ce8ff}, 1, 0, 0, 0},
        {"High", 12, 5, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0xf0ad65ff}, 1, 0, 0, 0},
    };
    ZigVstguiSkinDescription skin {};
    skin.theme = theme;
    skin.layout = ZIG_VSTGUI_LAYOUT_PARAMETER_WORKSPACE;
    skin.editor_title = "Parametric EQ";
    skin.groups = groups;
    skin.group_count = 4;
    skin.editor_style = theme == ZIG_VSTGUI_THEME_ALTERNATE ? ZigVstguiStyleOverride {
        ZIG_VSTGUI_STYLE_BACKGROUND | ZIG_VSTGUI_STYLE_FOREGROUND,
        0xf9f7f1ff,
        0x2d2822ff,
        0,
        0,
    } : ZigVstguiStyleOverride {
        ZIG_VSTGUI_STYLE_BACKGROUND | ZIG_VSTGUI_STYLE_FOREGROUND,
        0x101720ff,
        0xe9f1f5ff,
        0,
        0,
    };
    ZigVstguiCallbacks callbacks {};
    callbacks.begin_edit = acceptBegin;
    callbacks.perform_edit = acceptEdit;
    callbacks.end_edit = acceptEnd;
    callbacks.format_value = formatEqValue;
    auto editor = std::make_shared<ZigVstguiEditor>(
        parameters.data(),
        static_cast<uint32_t>(parameters.size()),
        callbacks,
        nullptr,
        0,
        ZigVstguiMeterCallbacks {},
        skin,
        &graph,
        1
    );
    if (!editor->valid() || !editor->resize(width, height) || !editor->frameView()) return {};
    return editor;
}

Snapshot parameterWorkspace(
    const char* name,
    uint32_t width,
    uint32_t height,
    double scale = 1.0,
    ZigVstguiThemeKind theme = ZIG_VSTGUI_THEME_DEFAULT
) {
    auto editor = buildParameterWorkspace(width, height, theme);
    return {
        name,
        width,
        height,
        scale,
        [editor](VSTGUI::CDrawContext& context) {
            if (!editor || !editor->frameView()) return;
            editor->frameView()->drawRect(&context, editor->frameView()->getViewSize());
        },
    };
}

std::shared_ptr<ZigVstguiEditor> buildResonantFilterWorkspace(
    uint32_t width,
    uint32_t height,
    ZigVstguiThemeKind theme = ZIG_VSTGUI_THEME_DEFAULT
) {
    const uint32_t ids[] = {0, 6, 1, 2, 3, 4, 5};
    const char* titles[] = {"Bypass", "Output", "Mode", "Cutoff", "Resonance", "Drive", "Mix"};
    const char* units[] = {"", "dB", "", "Hz", "", "dB", "%"};
    const int32_t steps[] = {1, 0, 3, 0, 0, 0, 0};
    const double values[] = {0.0, 0.5, 0.0, 0.566, 0.377, 0.0, 1.0};
    const ZigVstguiControlKind kinds[] = {
        ZIG_VSTGUI_CONTROL_TOGGLE,
        ZIG_VSTGUI_CONTROL_DECIBEL_SLIDER,
        ZIG_VSTGUI_CONTROL_SEGMENTED_ENUM,
        ZIG_VSTGUI_CONTROL_ROTARY_KNOB,
        ZIG_VSTGUI_CONTROL_ROTARY_KNOB,
        ZIG_VSTGUI_CONTROL_ROTARY_KNOB,
        ZIG_VSTGUI_CONTROL_LINEAR_SLIDER,
    };
    std::array<ZigVstguiParameterDescription, 7> parameters {};
    for (uint32_t index = 0; index < parameters.size(); ++index) {
        parameters[index] = {
            ids[index],
            values[index],
            {titles[index], units[index], steps[index], values[index]},
            kinds[index],
        };
    }
    std::array<ZigVstguiGraphPoint, 97> response {};
    std::array<ZigVstguiGraphPoint, 64> spectrum {};
    for (std::size_t index = 0; index < response.size(); ++index) {
        const double normalized = static_cast<double>(index) / static_cast<double>(response.size() - 1);
        const double frequency = 20.0 * std::pow(1000.0, normalized);
        response[index] = {frequency, -10.0 * std::log10(1.0 + std::pow(frequency / 1'000.0, 4.0))};
    }
    for (std::size_t index = 0; index < spectrum.size(); ++index) {
        const double normalized = static_cast<double>(index) / static_cast<double>(spectrum.size() - 1);
        spectrum[index] = {
            20.0 * std::pow(1000.0, normalized),
            -86.0 + 54.0 * std::exp(-std::pow((normalized - 0.48) / 0.26, 2.0)),
        };
    }
    const ZigVstguiGraphHandleDescription handle {
        1, "Cutoff and resonance", 2, 3, 0.566, 0.377, 0, 0,
        0, 0, "", 0.0, 0.01, 0, 0, 1, 1,
    };
    ZigVstguiGraphDescription graph {
        "Filter Response", ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION, ZIG_VSTGUI_GRAPH_PRIMARY,
        {20.0, 20'000.0, ZIG_VSTGUI_GRAPH_LOGARITHMIC, "Hz"},
        {-20.0, 25.105450102, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"},
        response.data(), static_cast<uint32_t>(response.size()), 1, 0, 30,
    };
    graph.handles = &handle;
    graph.handle_count = 1;
    graph.initial_selected_point_id = 1;
    const ZigVstguiGraphLayerDescription layer {
        ZIG_VSTGUI_GRAPH_SECONDARY,
        spectrum.data(),
        static_cast<uint32_t>(spectrum.size()),
        0,
        ZIG_VSTGUI_GRAPH_SPECTRUM,
        0,
        0,
        1,
        {-96.0, 0.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"},
        0,
    };
    graph.layers = &layer;
    graph.layer_count = 1;
    const ZigVstguiGroupDescription groups[] = {
        {"Response", 0, 2, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0x79baf2ff}, 0, 1, 0, 0},
        {"Filter", 2, 3, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0x52d5b0ff}, 1, 0, 0, 0},
        {"Color", 5, 2, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0xf0ad65ff}, 1, 0, 0, 0},
    };
    ZigVstguiSkinDescription skin {};
    skin.theme = theme;
    skin.layout = ZIG_VSTGUI_LAYOUT_PARAMETER_WORKSPACE;
    skin.editor_title = "Resonant Filter";
    skin.groups = groups;
    skin.group_count = 3;
    skin.editor_style = theme == ZIG_VSTGUI_THEME_ALTERNATE ? ZigVstguiStyleOverride {
        ZIG_VSTGUI_STYLE_BACKGROUND | ZIG_VSTGUI_STYLE_FOREGROUND,
        0xf9f7f1ff,
        0x2d2822ff,
        0,
        0,
    } : ZigVstguiStyleOverride {
        ZIG_VSTGUI_STYLE_BACKGROUND | ZIG_VSTGUI_STYLE_FOREGROUND,
        0x111922ff,
        0xeaf3f6ff,
        0,
        0,
    };
    const ZigVstguiPreset presets[] = {
        {1, "Smooth Low Pass"}, {2, "Resonant High Pass"},
        {3, "Band Focus"}, {4, "Notch Cleanup"},
    };
    const ZigVstguiPresetBrowserDescription browser {
        "Filter Presets", presets, 4, 1, 2, "", 1,
    };
    ZigVstguiCallbacks callbacks {};
    callbacks.begin_edit = acceptBegin;
    callbacks.perform_edit = acceptEdit;
    callbacks.end_edit = acceptEnd;
    callbacks.format_value = formatFilterValue;
    callbacks.load_preset = acceptPreset;
    auto editor = std::make_shared<ZigVstguiEditor>(
        parameters.data(),
        static_cast<uint32_t>(parameters.size()),
        callbacks,
        nullptr,
        0,
        ZigVstguiMeterCallbacks {},
        skin,
        &graph,
        1,
        ZigVstguiGraphCallbacks {},
        nullptr,
        0,
        &browser,
        1
    );
    if (!editor->valid() || !editor->resize(width, height) || !editor->frameView()) return {};
    editor->setModulation(2, 0.62);
    return editor;
}

Snapshot resonantFilterWorkspace(
    const char* name,
    uint32_t width,
    uint32_t height,
    double scale = 1.0,
    ZigVstguiThemeKind theme = ZIG_VSTGUI_THEME_DEFAULT
) {
    auto editor = buildResonantFilterWorkspace(width, height, theme);
    return {
        name,
        width,
        height,
        scale,
        [editor, width, height](VSTGUI::CDrawContext& context) {
            if (!editor || !editor->frameView()) return;
            auto frame = VSTGUI::owned(new VSTGUI::CFrame(
                VSTGUI::CRect(0, 0, width, height), nullptr));
            auto* view = editor->frameView();
            view->attached(frame);
            view->drawRect(&context, view->getViewSize());
            view->removed(frame);
        },
    };
}

struct ChannelWorkspace {
    std::shared_ptr<MeterValues> meters;
    std::shared_ptr<ZigVstguiEditor> editor;
};

ChannelWorkspace buildChannelWorkspace(
    uint32_t width,
    uint32_t height,
    ZigVstguiThemeKind theme = ZIG_VSTGUI_THEME_ALTERNATE
) {
    const ZigVstguiParameterDescription parameters[] = {
        {0, 0.5, {"Gain", "dB", 0, 0.5}, ZIG_VSTGUI_CONTROL_DECIBEL_SLIDER},
        {3, 0.5, {"Drive", "dB", 0, 0.5}, ZIG_VSTGUI_CONTROL_BIPOLAR_SLIDER},
        {1, 0.0, {"Bypass", "", 1, 0.0}, ZIG_VSTGUI_CONTROL_TOGGLE},
        {2, 0.0, {"Mode", "", 2, 0.0}, ZIG_VSTGUI_CONTROL_ENUM_DROPDOWN},
    };
    const ZigVstguiXYPadDescription pad {"Gain and Drive", 0, 3, "Gain", "Drive"};
    const ZigVstguiMeterDescription meters[] = {
        {"Stereo", ZIG_VSTGUI_METER_STEREO, 0, 1},
        {"Reduction", ZIG_VSTGUI_METER_GAIN_REDUCTION, 2, 0},
    };
    const ZigVstguiGraphPoint transfer[] = {
        {-2.0, -0.96}, {-1.0, -0.76}, {0.0, 0.0}, {1.0, 0.76}, {2.0, 0.96},
    };
    const ZigVstguiEnvelopePoint envelope[] = {
        {1, 0.0, 0.0}, {2, 0.5, 0.72}, {3, 1.0, 0.0},
    };
    const ZigVstguiGraphDescription graphs[] = {
        {"Console Transfer", ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION, ZIG_VSTGUI_GRAPH_PRIMARY,
            {-2.0, 2.0, ZIG_VSTGUI_GRAPH_LINEAR, "Input"},
            {-1.2, 1.2, ZIG_VSTGUI_GRAPH_LINEAR, "Output"}, transfer, 5, 0, 0, 0},
        {"Dynamics Envelope", ZIG_VSTGUI_GRAPH_ENVELOPE, ZIG_VSTGUI_GRAPH_PRIMARY,
            {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Time"},
            {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Level"}, nullptr, 0, 0, 0, 0,
            envelope, 3, 8, 2, 0.05, 0.05, 1, 2, 2},
        {"Output Waveform", ZIG_VSTGUI_GRAPH_WAVEFORM, ZIG_VSTGUI_GRAPH_MODULATION,
            {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Frame"},
            {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Level"}, nullptr, 0, 0, 1, 30},
        {"Output Spectrum", ZIG_VSTGUI_GRAPH_SPECTRUM, ZIG_VSTGUI_GRAPH_PRIMARY,
            {20.0, 24'000.0, ZIG_VSTGUI_GRAPH_LOGARITHMIC, "Hz"},
            {-96.0, 0.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"}, nullptr, 0, 1, 1, 30},
        {"Imported Waveform", ZIG_VSTGUI_GRAPH_WAVEFORM, ZIG_VSTGUI_GRAPH_SECONDARY,
            {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "File"},
            {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Level"}, nullptr, 0, 2, 1, 20},
    };
    const ZigVstguiGroupDescription groups[] = {
        {"Input", 0, 2, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT | ZIG_VSTGUI_STYLE_BORDER, 0, 0, 0x7994aaff, 0x3578baff}, 0, 0, 0, 1},
        {"Character", 2, 2, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT | ZIG_VSTGUI_STYLE_BORDER, 0, 0, 0xac8b73ff, 0xb96b32ff}, 0, 0, 1, 0},
        {"Output", 4, 0, 0, 2, {ZIG_VSTGUI_STYLE_ACCENT | ZIG_VSTGUI_STYLE_BORDER, 0, 0, 0x719789ff, 0x35866aff}, 0, 5, 1, 0},
    };
    ZigVstguiSkinDescription skin {};
    skin.theme = theme;
    skin.layout = ZIG_VSTGUI_LAYOUT_COMPACT_STRIP;
    skin.editor_title = "Channel Strip";
    skin.groups = groups;
    skin.group_count = 3;
    if (theme == ZIG_VSTGUI_THEME_ALTERNATE) {
        skin.editor_style = {ZIG_VSTGUI_STYLE_BACKGROUND | ZIG_VSTGUI_STYLE_FOREGROUND,
            0xeeeae0ff, 0x25231fff, 0, 0};
    }
    const char* extensions[] = {".wav"};
    const ZigVstguiFileDropDescription importer {
        1, "Audio Reference", "Drop a PCM WAV file here", extensions, 1, 1, 1,
        "Choose Audio File", "Choose a PCM WAV File",
    };
    const ZigVstguiPreset presets[] = {
        {1, "Clean Start"}, {2, "Console Push"}, {3, "Peak Limit"},
    };
    const ZigVstguiPresetBrowserDescription browser {
        "Channel Presets", presets, 3, 1, 2, "", 1,
    };
    const ZigVstguiMenuItemDescription menu_items[] = {
        {1, "Reset Channel", ZIG_VSTGUI_MENU_ACTION, 1, 0, 0, 0},
        {2, "Show Analyzer", ZIG_VSTGUI_MENU_TOGGLE, 1, 0, 3, 1},
        {3, "Export Preset", ZIG_VSTGUI_MENU_ACTION, 0, 0, 0, 0},
        {0, "", ZIG_VSTGUI_MENU_SEPARATOR, 0, 0, 0, 0},
        {4, "Reset UI", ZIG_VSTGUI_MENU_ACTION, 1, 1, 0, 0},
    };
    const ZigVstguiActionMenuDescription menu {1, "Options", menu_items, 5};
    ZigVstguiCallbacks callbacks {};
    callbacks.begin_edit = acceptBegin;
    callbacks.perform_edit = acceptEdit;
    callbacks.end_edit = acceptEnd;
    callbacks.format_value = formatChannelValue;
    callbacks.load_preset = acceptPreset;
    callbacks.invoke_menu_action = acceptMenuAction;
    callbacks.import_files = acceptImport;
    auto meter_state = std::make_shared<MeterValues>();
    ZigVstguiMeterCallbacks meter_callbacks {meter_state.get(), loadMeter};
    auto editor = std::make_shared<ZigVstguiEditor>(
        parameters, 4, callbacks, meters, 2, meter_callbacks, skin, graphs, 5,
        ZigVstguiGraphCallbacks {nullptr, loadChannelGraph}, &pad, 1, &browser, 1, &menu, 1,
        nullptr, 0, nullptr, 0, &importer, 1
    );
    if (!editor->valid() || !editor->resize(width, height) || !editor->frameView()) return {};
    return {meter_state, editor};
}

Snapshot channelWorkspace(
    const char* name,
    uint32_t width,
    uint32_t height,
    double scale = 1.0,
    ZigVstguiThemeKind theme = ZIG_VSTGUI_THEME_ALTERNATE
) {
    auto workspace = buildChannelWorkspace(width, height, theme);
    return {name, width, height, scale, [workspace, width, height](VSTGUI::CDrawContext& context) {
        if (!workspace.editor || !workspace.editor->frameView()) return;
        auto frame = VSTGUI::owned(new VSTGUI::CFrame(VSTGUI::CRect(0, 0, width, height), nullptr));
        auto* view = workspace.editor->frameView();
        view->attached(frame);
        view->drawRect(&context, view->getViewSize());
        view->removed(frame);
    }};
}

struct IrWorkspace {
    std::shared_ptr<TextProgressVisualState> state;
    std::shared_ptr<ZigVstguiEditor> editor;
};

IrWorkspace buildIrWorkspace(
    uint32_t width,
    uint32_t height,
    ZigVstguiThemeKind theme = ZIG_VSTGUI_THEME_ALTERNATE
) {
    const ZigVstguiParameterDescription parameters[] = {
        {0, 1.0, {"Wet", "%", 0, 1.0}, ZIG_VSTGUI_CONTROL_LINEAR_SLIDER},
        {1, 2.0 / 3.0, {"Output", "dB", 0, 2.0 / 3.0}, ZIG_VSTGUI_CONTROL_DECIBEL_SLIDER},
        {2, 0.0, {"Bypass", "", 1, 0.0}, ZIG_VSTGUI_CONTROL_TOGGLE},
    };
    ZigVstguiGraphDescription graph {
        "Impulse Response", ZIG_VSTGUI_GRAPH_WAVEFORM, ZIG_VSTGUI_GRAPH_MODULATION,
        {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Time"},
        {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Level"}, nullptr, 0, 1, 1, 20,
    };
    graph.viewport = {1, ZIG_VSTGUI_VIEWPORT_HORIZONTAL, 1.0, 128.0, 1.0, 0.0, 0.0, 1.25, 0.1, 1, 2, 0};
    graph.range_selection = {1, 0.1, 0.9, 1.0 / 131'072.0, 1.0 / 1024.0, 3, 4};
    const ZigVstguiGroupDescription groups[] = {
        {"Impulse Response", 0, 0, 0, 0, {}, 0, 1, 0, 0},
        {"Mix", 0, 3, 0, 0, {}, 1, 0, 0, 0},
    };
    ZigVstguiSkinDescription skin {};
    skin.theme = theme;
    skin.layout = ZIG_VSTGUI_LAYOUT_ADAPTIVE;
    skin.editor_title = "IR Loader";
    skin.groups = groups;
    skin.group_count = 2;
    const char* extensions[] = {".wav"};
    const ZigVstguiFileDropDescription importer {
        1, "Impulse Response", "Drop a PCM WAV impulse response here", extensions, 1, 1, 1,
        "Choose IR", "Choose an Impulse Response",
    };
    const ZigVstguiActionButtonDescription actions[] = {
        {1, 1, "Trim", "Trim to selection", "Load an IR to enable trimming", nullptr, "Trim failed", ZIG_VSTGUI_ACTION_PRIMARY, ZIG_VSTGUI_ACTION_ICON_NONE, 1, 0, 1},
        {1, 2, "Normalize", "Normalize selection", "Load an IR to enable normalization", nullptr, "Normalize failed", ZIG_VSTGUI_ACTION_SECONDARY, ZIG_VSTGUI_ACTION_ICON_NONE, 1, 0, 1},
        {1, 3, "Reverse", "Reverse selection", "Load an IR to enable reversing", nullptr, "Reverse failed", ZIG_VSTGUI_ACTION_SECONDARY, ZIG_VSTGUI_ACTION_ICON_REVERSE, 1, 0, 1},
        {1, 4, "Fade In", "Fade in selection", "Load an IR to enable fades", nullptr, "Fade in failed", ZIG_VSTGUI_ACTION_SECONDARY, ZIG_VSTGUI_ACTION_ICON_NONE, 1, 0, 1},
        {1, 5, "Fade Out", "Fade out selection", "Load an IR to enable fades", nullptr, "Fade out failed", ZIG_VSTGUI_ACTION_SECONDARY, ZIG_VSTGUI_ACTION_ICON_NONE, 1, 0, 1},
        {1, 6, "Reset", "Reset all impulse response edits", "Load an IR to enable reset", nullptr, "Nothing to reset", ZIG_VSTGUI_ACTION_SECONDARY, ZIG_VSTGUI_ACTION_ICON_RESET, 1, 0, 1},
        {2, 7, nullptr, "Clear impulse response", "Remove the imported impulse response", "Confirm Clear IR", "Clear failed", ZIG_VSTGUI_ACTION_DESTRUCTIVE, ZIG_VSTGUI_ACTION_ICON_CLEAR, 1, 1, 1},
    };
    const ZigVstguiEditableLabelDescription labels[] = {
        {1, "IR Name", "Impulse response name", "Name this impulse response", "Enter an IR name", "Studio Plate", 64, 1, 0, 10},
        {2, "Format", "Impulse response format", "", "Value unavailable", "48 kHz, stereo", 48, 1, 1, 10},
        {3, "Original", "Original duration", "", "Value unavailable", "1.250 s", 48, 1, 1, 10},
        {4, "Edited", "Edited duration", "", "Value unavailable", "1.000 s", 48, 1, 1, 10},
        {5, "Peak", "Original and edited peak", "", "Value unavailable", "0.875", 48, 1, 1, 10},
        {6, "State", "Impulse response publication state", "", "Value unavailable", "Ready", 48, 1, 1, 10},
    };
    const ZigVstguiProgressIndicatorDescription progress {
        1, "Import", "Impulse response import progress", "Choose an IR to begin",
        "Importing IR", "IR ready", "Import failed", 20,
    };
    auto state = std::make_shared<TextProgressVisualState>();
    state->text = "Studio Plate";
    state->progress = {ZIG_VSTGUI_PROGRESS_DETERMINATE, ZIG_VSTGUI_PROGRESS_COMPLETE, 1.0, 1};
    state->import = {ZIG_VSTGUI_FILE_IMPORT_READY, ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE,
        ZIG_VSTGUI_FILE_IMPORT_PICKER, 1.0, 1, 48'000, 2, 60'000, 0};
    ZigVstguiCallbacks callbacks {};
    callbacks.userdata = state.get();
    callbacks.begin_edit = acceptBegin;
    callbacks.perform_edit = acceptEdit;
    callbacks.end_edit = acceptEnd;
    callbacks.format_value = formatIrValue;
    callbacks.import_files = acceptImport;
    callbacks.load_file_import = loadVisualImport;
    callbacks.invoke_action = acceptAction;
    callbacks.store_editor_text = storeVisualText;
    callbacks.load_editor_text = loadVisualText;
    callbacks.load_progress = loadVisualProgress;
    auto editor = std::make_shared<ZigVstguiEditor>(
        parameters, 3, callbacks, nullptr, 0, ZigVstguiMeterCallbacks {}, skin,
        &graph, 1, ZigVstguiGraphCallbacks {nullptr, loadIrGraph}, nullptr, 0, nullptr, 0, nullptr, 0,
        nullptr, 0, nullptr, 0, &importer, 1, actions, 7, labels, 6, &progress, 1
    );
    if (!editor->valid() || !editor->resize(width, height) || !editor->frameView()) return {};
    return {state, editor};
}

Snapshot irWorkspace(
    const char* name,
    uint32_t width,
    uint32_t height,
    double scale = 1.0,
    ZigVstguiThemeKind theme = ZIG_VSTGUI_THEME_ALTERNATE
) {
    auto workspace = buildIrWorkspace(width, height, theme);
    return {name, width, height, scale, [workspace, width, height](VSTGUI::CDrawContext& context) {
        if (!workspace.editor || !workspace.editor->frameView()) return;
        auto frame = VSTGUI::owned(new VSTGUI::CFrame(VSTGUI::CRect(0, 0, width, height), nullptr));
        auto* view = workspace.editor->frameView();
        view->attached(frame);
        view->drawRect(&context, view->getViewSize());
        view->removed(frame);
    }};
}

enum class SampleVisualMode { empty, importing, ready, error };

struct SampleWorkspace {
    std::shared_ptr<TextProgressVisualState> state;
    std::shared_ptr<ZigVstguiEditor> editor;
};

SampleWorkspace buildSamplePlayerWorkspace(
    uint32_t width,
    uint32_t height,
    SampleVisualMode mode = SampleVisualMode::ready,
    ZigVstguiThemeKind theme = ZIG_VSTGUI_THEME_DEFAULT
) {
    const char* titles[] = {
        "Start", "End", "Loop Start", "Loop End", "Gain", "Pan", "Coarse", "Fine",
        "Loop", "Reverse", "Playback", "Voices", "Attack", "Decay", "Sustain", "Release",
    };
    const char* units[] = {
        "%", "%", "%", "%", "dB", "%", "st", "cent", "", "", "", "", "ms", "ms", "%", "ms",
    };
    const int32_t steps[] = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 3, 0, 0, 0, 0};
    const double values[] = {
        0.08, 0.92, 0.24, 0.68, 0.833, 0.5, 0.5, 0.5, 1.0, 0.0, 0.0, 1.0, 0.36, 0.62, 0.8, 0.64,
    };
    const uint32_t parameter_ids[] = {4, 5, 6, 7, 0, 1, 2, 3, 8, 9, 15, 14, 10, 11, 12, 13};
    const ZigVstguiControlKind kinds[] = {
        ZIG_VSTGUI_CONTROL_LINEAR_SLIDER, ZIG_VSTGUI_CONTROL_LINEAR_SLIDER,
        ZIG_VSTGUI_CONTROL_LINEAR_SLIDER, ZIG_VSTGUI_CONTROL_LINEAR_SLIDER,
        ZIG_VSTGUI_CONTROL_DECIBEL_SLIDER, ZIG_VSTGUI_CONTROL_BIPOLAR_SLIDER,
        ZIG_VSTGUI_CONTROL_ROTARY_KNOB, ZIG_VSTGUI_CONTROL_ROTARY_KNOB,
        ZIG_VSTGUI_CONTROL_TOGGLE, ZIG_VSTGUI_CONTROL_TOGGLE,
        ZIG_VSTGUI_CONTROL_SEGMENTED_ENUM, ZIG_VSTGUI_CONTROL_SEGMENTED_ENUM,
        ZIG_VSTGUI_CONTROL_ROTARY_KNOB, ZIG_VSTGUI_CONTROL_ROTARY_KNOB,
        ZIG_VSTGUI_CONTROL_ROTARY_KNOB, ZIG_VSTGUI_CONTROL_ROTARY_KNOB,
    };
    std::array<ZigVstguiParameterDescription, 16> parameters {};
    for (uint32_t index = 0; index < parameters.size(); ++index) {
        parameters[index] = {
            parameter_ids[index],
            values[index],
            {titles[index], units[index], steps[index], values[index]},
            kinds[index],
        };
    }
    std::array<ZigVstguiGraphPoint, 97> waveform {};
    for (std::size_t index = 0; index < waveform.size(); ++index) {
        const double x = static_cast<double>(index) / static_cast<double>(waveform.size() - 1);
        waveform[index] = {x, std::sin(x * 31.4159265359) * std::exp(-2.4 * x)};
    }
    const ZigVstguiGraphPoint playhead[] = {{0.46, -1.0}, {0.46, 1.0}};
    const ZigVstguiGraphLayerDescription playhead_layer {
        ZIG_VSTGUI_GRAPH_WARNING, playhead, 2, 0, ZIG_VSTGUI_GRAPH_WAVEFORM, 0, 0, 0, {}, 0,
    };
    ZigVstguiGraphDescription graph {
        "Sample Waveform", ZIG_VSTGUI_GRAPH_WAVEFORM, ZIG_VSTGUI_GRAPH_MODULATION,
        {0.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Time"},
        {-1.0, 1.0, ZIG_VSTGUI_GRAPH_LINEAR, "Level"},
        waveform.data(), static_cast<uint32_t>(waveform.size()), 0, 0, 30,
    };
    graph.viewport = {
        1, ZIG_VSTGUI_VIEWPORT_HORIZONTAL, 1.0, 128.0, 2.0, 0.18, 0.0, 1.25, 0.1, 0, 0, 0,
    };
    graph.range_selection = {1, 0.08, 0.92, 0.001, 0.001, 0, 0, 1, 4, 5, 0, 0};
    graph.secondary_range_selection = {1, 0.24, 0.68, 0.001, 0.001, 0, 0, 1, 6, 7, 0, 0};
    graph.layers = &playhead_layer;
    graph.layer_count = 1;
    if (mode != SampleVisualMode::ready) {
        graph.points = nullptr;
        graph.point_count = 0;
        graph.layers = nullptr;
        graph.layer_count = 0;
    }
    const ZigVstguiGroupDescription groups[] = {
        {"Waveform", 0, 2, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0x79baf2ff}, 0, 1, 0, 0},
        {"Loop Range", 2, 2, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0x79baf2ff}, 1, 0, 0, 0},
        {"Playback", 4, 4, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0x52d5b0ff}, 1, 0, 0, 0},
        {"Mode and Voices", 8, 4, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0xf0ad65ff}, 1, 0, 0, 0},
        {"Envelope", 12, 4, 0, 0, {ZIG_VSTGUI_STYLE_ACCENT, 0, 0, 0, 0xc58be8ff}, 1, 0, 0, 0},
    };
    ZigVstguiSkinDescription skin {};
    skin.theme = theme;
    skin.layout = ZIG_VSTGUI_LAYOUT_INSTRUMENT_WORKSPACE;
    skin.editor_title = "Sample Player";
    skin.groups = groups;
    skin.group_count = 5;
    skin.editor_style = theme == ZIG_VSTGUI_THEME_ALTERNATE ? ZigVstguiStyleOverride {
        ZIG_VSTGUI_STYLE_BACKGROUND | ZIG_VSTGUI_STYLE_FOREGROUND | ZIG_VSTGUI_STYLE_ACCENT,
        0xf9f7f1ff, 0x2d2822ff, 0x236a77ff, 0,
    } : ZigVstguiStyleOverride {
        ZIG_VSTGUI_STYLE_BACKGROUND | ZIG_VSTGUI_STYLE_FOREGROUND | ZIG_VSTGUI_STYLE_ACCENT,
        0x111922ff, 0xeaf3f6ff, 0x52d5b0ff, 0,
    };
    const char* extensions[] = {".wav", ".aif", ".aiff"};
    const ZigVstguiFileDropDescription importer {
        1, "Sample", "Drop a PCM WAV or AIFF sample here", extensions, 3, 1, 1,
        "Choose Sample", "Choose a Sample",
    };
    const ZigVstguiActionButtonDescription clear {
        1, 1, nullptr, "Clear sample", "Remove the imported sample", "Confirm Clear Sample",
        "Clear failed. Try again", ZIG_VSTGUI_ACTION_DESTRUCTIVE, ZIG_VSTGUI_ACTION_ICON_CLEAR, 1, 1, 1,
    };
    const ZigVstguiMenuItemDescription view_items[] = {
        {1, "Show Entire Sample", ZIG_VSTGUI_MENU_ACTION, 1, 0, 0, 0},
        {2, "Zoom to Playback Range", ZIG_VSTGUI_MENU_ACTION, 1, 0, 0, 0},
        {3, "Zoom to Loop Range", ZIG_VSTGUI_MENU_ACTION, 1, 0, 0, 0},
    };
    const ZigVstguiActionMenuDescription view_menu {1, "View", view_items, 3};
    const ZigVstguiPianoDescription piano {"Sample Keyboard", 48, 25, 0, 0.8, 60};
    const ZigVstguiProgressIndicatorDescription progress {
        1, "Import", "Sample import progress", "Choose a sample to begin", "Importing sample",
        "Sample ready", "Import failed. Retry or choose another file", 30,
    };
    const ZigVstguiEditableLabelDescription last_import {
        3, "Last Import", "Last imported sample", "No previous sample", "Import name unavailable",
        "Studio Piano.aiff", 64, 1, 1, 10,
    };
    auto visual_state = std::make_shared<TextProgressVisualState>();
    visual_state->text = mode == SampleVisualMode::ready ? "Studio Piano.aiff" : "";
    switch (mode) {
        case SampleVisualMode::empty:
            visual_state->import = {
                ZIG_VSTGUI_FILE_IMPORT_IDLE, ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE,
                ZIG_VSTGUI_FILE_IMPORT_PICKER, 0.0, 0, 0, 0, 0, 0,
            };
            visual_state->progress = {
                ZIG_VSTGUI_PROGRESS_DETERMINATE, ZIG_VSTGUI_PROGRESS_IDLE, 0.0, 0,
            };
            break;
        case SampleVisualMode::importing:
            visual_state->import = {
                ZIG_VSTGUI_FILE_IMPORT_IMPORTING, ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE,
                ZIG_VSTGUI_FILE_IMPORT_DROP, 0.45, 2, 48'000, 2, 48'000, 0,
            };
            visual_state->progress = {
                ZIG_VSTGUI_PROGRESS_DETERMINATE, ZIG_VSTGUI_PROGRESS_RUNNING, 0.45, 2,
            };
            break;
        case SampleVisualMode::ready:
            visual_state->import = {
                ZIG_VSTGUI_FILE_IMPORT_READY, ZIG_VSTGUI_FILE_IMPORT_FAILURE_NONE,
                ZIG_VSTGUI_FILE_IMPORT_PICKER, 1.0, 1, 48'000, 2, 48'000, 256,
            };
            visual_state->progress = {
                ZIG_VSTGUI_PROGRESS_DETERMINATE, ZIG_VSTGUI_PROGRESS_COMPLETE, 1.0, 1,
            };
            break;
        case SampleVisualMode::error:
            visual_state->import = {
                ZIG_VSTGUI_FILE_IMPORT_FAILED, ZIG_VSTGUI_FILE_IMPORT_FAILURE_MALFORMED,
                ZIG_VSTGUI_FILE_IMPORT_PICKER, 0.0, 3, 0, 0, 0, 0,
            };
            visual_state->progress = {
                ZIG_VSTGUI_PROGRESS_DETERMINATE, ZIG_VSTGUI_PROGRESS_FAILED, 0.0, 3,
            };
            break;
    }
    ZigVstguiCallbacks callbacks {};
    callbacks.userdata = visual_state.get();
    callbacks.begin_edit = acceptBegin;
    callbacks.perform_edit = acceptEdit;
    callbacks.end_edit = acceptEnd;
    callbacks.format_value = formatSampleValue;
    callbacks.invoke_action = acceptAction;
    callbacks.invoke_menu_action = acceptMenuAction;
    callbacks.send_note = acceptNote;
    callbacks.import_files = acceptImport;
    callbacks.load_file_import = loadVisualImport;
    callbacks.command_file_import = acceptImportCommand;
    callbacks.load_editor_text = loadVisualText;
    callbacks.load_progress = loadVisualProgress;
    auto editor = std::make_shared<ZigVstguiEditor>(
        parameters.data(), static_cast<uint32_t>(parameters.size()), callbacks,
        nullptr, 0, ZigVstguiMeterCallbacks {}, skin, &graph, 1, ZigVstguiGraphCallbacks {},
        nullptr, 0, nullptr, 0, &view_menu, 1, &piano, 1, nullptr, 0, &importer, 1,
        &clear, 1, &last_import, 1, &progress, 1
    );
    if (!editor->valid() || !editor->resize(width, height) || !editor->frameView()) return {};
    return {visual_state, editor};
}

Snapshot samplePlayerWorkspace(
    const char* name,
    uint32_t width,
    uint32_t height,
    SampleVisualMode mode = SampleVisualMode::ready,
    double scale = 1.0,
    ZigVstguiThemeKind theme = ZIG_VSTGUI_THEME_DEFAULT
) {
    auto workspace = buildSamplePlayerWorkspace(width, height, mode, theme);
    return {
        name,
        width,
        height,
        scale,
        [workspace, width, height](VSTGUI::CDrawContext& context) {
            const auto& editor = workspace.editor;
            if (!editor || !editor->frameView()) return;
            auto frame = VSTGUI::owned(new VSTGUI::CFrame(VSTGUI::CRect(0, 0, width, height), nullptr));
            auto* view = editor->frameView();
            view->attached(frame);
            view->drawRect(&context, view->getViewSize());
            view->removed(frame);
        },
    };
}

double benchmarkSamplePlayerLifecycle() {
    constexpr uint32_t repetitions = 50;
    double best = 1e9;
    for (uint32_t sample = 0; sample < 3; ++sample) {
        const auto started = std::clock();
        for (uint32_t index = 0; index < repetitions; ++index) {
            auto workspace = buildSamplePlayerWorkspace(720, 660);
            if (!workspace.editor || !workspace.editor->valid()) return 1e9;
        }
        const auto elapsed = std::clock() - started;
        best = std::min(
            best,
            static_cast<double>(elapsed) * 1'000'000.0 /
                static_cast<double>(CLOCKS_PER_SEC) / repetitions
        );
    }
    return best;
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

int smokeSnapshot(const Snapshot& snapshot) {
    const auto actual = render(snapshot);
    if (!actual || !actual->getPlatformBitmap()) return 1;
    const auto actual_pixels = VSTGUI::owned(
        VSTGUI::CBitmapPixelAccess::create(actual, false)
    );
    if (!actual_pixels) return 2;
    const auto width = actual_pixels->getBitmapWidth();
    const auto height = actual_pixels->getBitmapHeight();
    if (width == 0 || height == 0) return 3;

    const auto decoded = normalizePng(actual);
    if (!decoded) return 4;
    const auto decoded_pixels = VSTGUI::owned(
        VSTGUI::CBitmapPixelAccess::create(decoded, false)
    );
    if (!decoded_pixels ||
        decoded_pixels->getBitmapWidth() != width ||
        decoded_pixels->getBitmapHeight() != height) return 5;

    VSTGUI::CColor first;
    decoded_pixels->getColor(first);
    bool varied = false;
    while (++(*decoded_pixels)) {
        VSTGUI::CColor current;
        decoded_pixels->getColor(current);
        if (current != first) {
            varied = true;
            break;
        }
    }
    if (!varied) {
        std::fprintf(stderr, "uniform visual smoke output: %s\n", snapshot.name);
        return 6;
    }
    return 0;
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

bool drawingCallbackExceptionsRestoreContextState() {
    const auto offscreen = VSTGUI::COffscreenContext::create(VSTGUI::CPoint(96, 96), 1.0);
    if (!offscreen) return false;
    ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
    ZigVstgui::RotaryKnob source(VSTGUI::CRect(8, 8, 88, 88), nullptr, 1, styles, 0.5);
    ZigVstguiDrawingCallbacks callbacks {};
    callbacks.draw_parameter = throwDuringDraw;
    ZigVstgui::DrawingOverlay overlay(
        1,
        ZIG_VSTGUI_DRAW_KNOB,
        &source,
        nullptr,
        callbacks
    );
    overlay.setViewSize(VSTGUI::CRect(8, 8, 88, 88));

    const VSTGUI::CRect original_clip(3, 4, 91, 92);
    offscreen->beginDraw();
    offscreen->setClipRect(original_clip);
    bool escaped = false;
    try {
        overlay.draw(offscreen);
    } catch (...) {
        escaped = true;
    }
    VSTGUI::CRect restored_clip;
    offscreen->getClipRect(restored_clip);
    offscreen->endDraw();
    return !escaped &&
        restored_clip.left == original_clip.left &&
        restored_clip.top == original_clip.top &&
        restored_clip.right == original_clip.right &&
        restored_clip.bottom == original_clip.bottom &&
        !overlay.isDirty();
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

double benchmarkRotaryDraw() {
    ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
    auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 96, 96)));
    container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
    auto* knob = new ZigVstgui::RotaryKnob(
        VSTGUI::CRect(12, 12, 84, 84), nullptr, 1, styles, 0.5
    );
    knob->setValueNormalized(0.67f);
    knob->setModulation(0.82);
    container->addView(knob);
    const auto offscreen = VSTGUI::COffscreenContext::create(VSTGUI::CPoint(96, 96), 1.0);
    if (!offscreen) return 1e9;
    return benchmarkDraw(container, offscreen);
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

double benchmarkLinkedEqResponseDraw() {
    ZigVstgui::ThemeResolver styles(ZigVstgui::alternateTheme());
    auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 640, 220)));
    container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
    std::array<ZigVstguiGraphPoint, 97> response {};
    std::array<ZigVstguiGraphPoint, 64> spectrum {};
    for (std::size_t index = 0; index < response.size(); ++index) {
        const double normalized = static_cast<double>(index) / static_cast<double>(response.size() - 1);
        response[index] = {20.0 * std::pow(1000.0, normalized), 12.0 * std::sin(normalized * 6.28318530718)};
    }
    for (std::size_t index = 0; index < spectrum.size(); ++index) {
        const double normalized = static_cast<double>(index) / static_cast<double>(spectrum.size() - 1);
        spectrum[index] = {
            20.0 * std::pow(1000.0, normalized),
            -86.0 + 58.0 * std::abs(std::sin(normalized * 9.42477796077)),
        };
    }
    const ZigVstguiGraphHandleDescription handles[] = {
        {1, "Low", 10, 11, 0.25, 0.65, 0, 0, 1, 12, "Q", 0.35, 0.01, 1, 13, 1, 1},
        {2, "Mid", 20, 21, 0.57, 0.33, 0, 0, 1, 22, "Q", 0.72, 0.01, 1, 23, 1, 2},
        {3, "High", 30, 31, 0.82, 0.60, 0, 0, 1, 32, "Q", 0.42, 0.01, 1, 33, 0, 3},
    };
    ZigVstguiGraphDescription description {
        "EQ Response", ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION, ZIG_VSTGUI_GRAPH_PRIMARY,
        {20.0, 20'000.0, ZIG_VSTGUI_GRAPH_LOGARITHMIC, "Hz"},
        {-24.0, 24.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"},
        response.data(), static_cast<uint32_t>(response.size()), 0, 0, 0,
    };
    description.handles = handles;
    description.handle_count = 3;
    const ZigVstguiGraphLayerDescription layers[] = {
        {ZIG_VSTGUI_GRAPH_SECONDARY, response.data(), static_cast<uint32_t>(response.size()), 0},
        {ZIG_VSTGUI_GRAPH_MODULATION, response.data(), static_cast<uint32_t>(response.size()), 0},
        {ZIG_VSTGUI_GRAPH_SECONDARY, response.data(), static_cast<uint32_t>(response.size()), 0},
        {
            ZIG_VSTGUI_GRAPH_SECONDARY,
            spectrum.data(),
            static_cast<uint32_t>(spectrum.size()),
            0,
            ZIG_VSTGUI_GRAPH_SPECTRUM,
            0,
            0,
            1,
            {-96.0, 0.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"},
            0,
        },
    };
    description.layers = layers;
    description.layer_count = 4;
    ZigVstgui::AccessibilityNode accessibility;
    container->addView(new ZigVstgui::GraphView(
        VSTGUI::CRect(8, 8, 632, 212), description, styles, &accessibility
    ));
    const auto offscreen = VSTGUI::COffscreenContext::create(VSTGUI::CPoint(640, 220), 1.0);
    return benchmarkDraw(container, offscreen);
}

double benchmarkResonantFilterResponseDraw() {
    ZigVstgui::ThemeResolver styles(ZigVstgui::defaultTheme());
    auto container = VSTGUI::owned(new VSTGUI::CViewContainer(VSTGUI::CRect(0, 0, 640, 220)));
    container->setBackgroundColor(styles.resolve(ZigVstgui::ComponentKind::editor).background);
    std::array<ZigVstguiGraphPoint, 97> response {};
    std::array<ZigVstguiGraphPoint, 64> spectrum {};
    for (std::size_t index = 0; index < response.size(); ++index) {
        const double normalized = static_cast<double>(index) / static_cast<double>(response.size() - 1);
        const double frequency = 20.0 * std::pow(1000.0, normalized);
        response[index] = {frequency, -10.0 * std::log10(1.0 + std::pow(frequency / 1'000.0, 4.0))};
    }
    for (std::size_t index = 0; index < spectrum.size(); ++index) {
        const double normalized = static_cast<double>(index) / static_cast<double>(spectrum.size() - 1);
        spectrum[index] = {
            20.0 * std::pow(1000.0, normalized),
            -86.0 + 54.0 * std::exp(-std::pow((normalized - 0.48) / 0.26, 2.0)),
        };
    }
    const ZigVstguiGraphHandleDescription handle {
        1, "Cutoff and resonance", 2, 3, 0.566, 0.377, 0, 0,
        0, 0, "", 0.0, 0.01, 0, 0, 1, 1,
    };
    ZigVstguiGraphDescription description {
        "Filter Response", ZIG_VSTGUI_GRAPH_TRANSFER_FUNCTION, ZIG_VSTGUI_GRAPH_PRIMARY,
        {20.0, 20'000.0, ZIG_VSTGUI_GRAPH_LOGARITHMIC, "Hz"},
        {-20.0, 25.105450102, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"},
        response.data(), static_cast<uint32_t>(response.size()), 1, 0, 30,
    };
    description.handles = &handle;
    description.handle_count = 1;
    const ZigVstguiGraphLayerDescription layer {
        ZIG_VSTGUI_GRAPH_SECONDARY,
        spectrum.data(),
        static_cast<uint32_t>(spectrum.size()),
        0,
        ZIG_VSTGUI_GRAPH_SPECTRUM,
        0,
        0,
        1,
        {-96.0, 0.0, ZIG_VSTGUI_GRAPH_DECIBELS, "dB"},
        0,
    };
    description.layers = &layer;
    description.layer_count = 1;
    ZigVstgui::AccessibilityNode accessibility;
    container->addView(new ZigVstgui::GraphView(
        VSTGUI::CRect(12, 12, 628, 208), description, styles, &accessibility
    ));
    const auto offscreen = VSTGUI::COffscreenContext::create(VSTGUI::CPoint(640, 220), 1.0);
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
    if (with_selection) {
        description.range_selection = {1, 0.35, 0.65, 0.001, 0.001, 0, 0};
        description.secondary_range_selection = {1, 0.45, 0.55, 0.001, 0.001, 0, 0};
    }
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
    bool update = false;
    bool smoke = false;
    bool enforce_performance = true;
    for (int index = 3; index < argc; ++index) {
        const std::string option(argv[index]);
        if (option == "--update") update = true;
        else if (option == "--platform-smoke") {
            smoke = true;
            enforce_performance = false;
        }
        else if (option == "--skip-performance") enforce_performance = false;
        else return 64;
    }
    if (update && smoke) return 64;
    if (update) std::filesystem::create_directories(references);
    std::filesystem::create_directories(output);
    ZigVstgui::RuntimeGuard runtime;
    int result = 0;
    if (!drawingCallbackExceptionsRestoreContextState()) result = std::max(result, 7);
    {
        const Snapshot snapshots[] = {
            controlStates(1.0),
            controlStates(2.0),
            rotaryControls(),
            metersAndAssets(),
            productionControls(),
            graphs(),
            graphViewports(),
            signalViews(),
            linkedEqResponse(),
            resonantFilterResponse(),
            eqAnalyzerStates(),
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
            irWorkflowStates(),
        };
        for (const auto& snapshot : snapshots) {
            result = std::max(
                result,
                smoke
                    ? smokeSnapshot(snapshot)
                    : runSnapshot(snapshot, references, output, update)
            );
        }
    }
    if (!update && enforce_performance) {
        const double average = benchmarkWarmDraw();
        const double piano_average = benchmarkPianoDraw();
        const double step_sequencer_average = benchmarkStepSequencerDraw();
        const double file_drop_average = benchmarkFileDropDraw();
        const double action_button_average = benchmarkActionButtonDraw();
        const double rotary_average = benchmarkRotaryDraw();
        const double progress_average = benchmarkProgressDraw();
        const double signal_views_average = benchmarkSignalViewsDraw();
        const double linked_eq_average = benchmarkLinkedEqResponseDraw();
        const double resonant_filter_average = benchmarkResonantFilterResponseDraw();
        const double viewport_average = benchmarkViewportDraw();
        const double range_selection_average = benchmarkRangeSelectionDraw();
        const double sample_lifecycle_average = benchmarkSamplePlayerLifecycle();
        std::fprintf(stderr, "visual regression warm render average: %.1f us\n", average);
        std::fprintf(stderr, "piano warm render average: %.1f us\n", piano_average);
        std::fprintf(stderr, "step sequencer warm render average: %.1f us\n", step_sequencer_average);
        std::fprintf(stderr, "file drop warm render average: %.1f us\n", file_drop_average);
        std::fprintf(stderr, "action button warm render average: %.1f us\n", action_button_average);
        std::fprintf(stderr, "rotary warm render average: %.1f us\n", rotary_average);
        std::fprintf(stderr, "progress warm render average: %.1f us\n", progress_average);
        std::fprintf(stderr, "signal views warm render average: %.1f us\n", signal_views_average);
        std::fprintf(stderr, "linked EQ warm render average: %.1f us\n", linked_eq_average);
        std::fprintf(stderr, "resonant filter warm render average: %.1f us\n", resonant_filter_average);
        std::fprintf(stderr, "viewport warm render average: %.1f us\n", viewport_average);
        std::fprintf(stderr, "range selection warm render average: %.1f us\n", range_selection_average);
        std::fprintf(stderr, "sample player editor create/destroy average: %.1f us\n", sample_lifecycle_average);
        if (average > warm_draw_budget_us || piano_average > warm_draw_budget_us ||
            step_sequencer_average > warm_draw_budget_us || file_drop_average > warm_draw_budget_us ||
            action_button_average > warm_draw_budget_us || rotary_average > warm_draw_budget_us ||
            progress_average > warm_draw_budget_us ||
            signal_views_average > signal_views_budget_us || linked_eq_average > warm_draw_budget_us ||
            resonant_filter_average > warm_draw_budget_us ||
            viewport_average > warm_draw_budget_us ||
            range_selection_average > warm_draw_budget_us ||
            sample_lifecycle_average > sample_lifecycle_budget_us) result = std::max(result, 6);
    }
    {
        const Snapshot workspace_snapshots[] = {
            parameterWorkspace("eq-workspace-compact.png", 400, 360),
            parameterWorkspace("eq-workspace-standard.png", 720, 660),
            parameterWorkspace("eq-workspace-expanded.png", 960, 700),
            parameterWorkspace("eq-workspace-standard-2x.png", 720, 660, 2.0),
            parameterWorkspace(
                "eq-workspace-high-contrast.png", 720, 660, 1.0, ZIG_VSTGUI_THEME_ALTERNATE),
            resonantFilterWorkspace("resonant-filter-compact.png", 480, 480),
            resonantFilterWorkspace("resonant-filter-standard.png", 720, 660),
            resonantFilterWorkspace("resonant-filter-expanded.png", 960, 700),
            resonantFilterWorkspace("resonant-filter-standard-2x.png", 720, 660, 2.0),
            resonantFilterWorkspace(
                "resonant-filter-high-contrast.png", 720, 660, 1.0, ZIG_VSTGUI_THEME_ALTERNATE),
            samplePlayerWorkspace("sample-player-compact.png", 480, 480),
            samplePlayerWorkspace("sample-player-standard.png", 720, 660),
            samplePlayerWorkspace("sample-player-expanded.png", 960, 700),
            samplePlayerWorkspace(
                "sample-player-standard-2x.png", 720, 660, SampleVisualMode::ready, 2.0),
            samplePlayerWorkspace(
                "sample-player-high-contrast.png", 720, 660, SampleVisualMode::ready, 1.0,
                ZIG_VSTGUI_THEME_ALTERNATE),
            samplePlayerWorkspace("sample-player-empty.png", 720, 660, SampleVisualMode::empty),
            samplePlayerWorkspace("sample-player-importing.png", 720, 660, SampleVisualMode::importing),
            samplePlayerWorkspace("sample-player-error.png", 720, 660, SampleVisualMode::error),
            channelWorkspace("channel-strip-compact.png", 480, 480),
            channelWorkspace("channel-strip-standard.png", 720, 660),
            channelWorkspace("channel-strip-expanded.png", 960, 700),
            channelWorkspace("channel-strip-standard-2x.png", 720, 660, 2.0),
            channelWorkspace("channel-strip-high-contrast.png", 720, 660, 1.0, ZIG_VSTGUI_THEME_DEFAULT),
            irWorkspace("ir-loader-compact.png", 480, 480),
            irWorkspace("ir-loader-standard.png", 720, 660),
            irWorkspace("ir-loader-expanded.png", 960, 700),
            irWorkspace("ir-loader-standard-2x.png", 720, 660, 2.0),
            irWorkspace("ir-loader-high-contrast.png", 720, 660, 1.0, ZIG_VSTGUI_THEME_DEFAULT),
        };
        for (const auto& snapshot : workspace_snapshots) {
            result = std::max(
                result,
                smoke
                    ? smokeSnapshot(snapshot)
                    : runSnapshot(snapshot, references, output, update)
            );
        }
    }
    return result;
}
