#ifndef ZIG_VSTGUI_ASSETS_H
#define ZIG_VSTGUI_ASSETS_H

#include "zig_vstgui_adapter.h"

#include "vstgui/lib/cbitmap.h"
#include "vstgui/lib/ccolor.h"
#include "vstgui/lib/cgraphicspath.h"
#include "vstgui/lib/crect.h"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace VSTGUI {
class CDrawContext;
}

namespace ZigVstgui {

struct AssetPlacement {
    VSTGUI::CRect destination;
    double scale_x {1.0};
    double scale_y {1.0};
};

AssetPlacement placeAsset(
    const VSTGUI::CRect& bounds,
    double source_width,
    double source_height,
    ZigVstguiAssetScale scale
);

float boundedAssetAlpha(float alpha);

class SvgDocument {
public:
    bool parse(const uint8_t* data, uint32_t size);
    bool valid() const;
    uint32_t pathCount() const;
    double width() const;
    double height() const;
    void draw(
        VSTGUI::CDrawContext* context,
        const VSTGUI::CRect& bounds,
        ZigVstguiAssetScale scale,
        float alpha
    ) const;

private:
    enum class CommandKind {
        move,
        line,
        cubic,
        close,
    };

    struct Command {
        CommandKind kind;
        double values[6] {};
    };

    struct Path {
        std::vector<Command> commands;
        VSTGUI::CColor fill {0, 0, 0, 255};
        VSTGUI::CColor stroke {0, 0, 0, 0};
        double stroke_width {1.0};
        bool has_fill {true};
        bool has_stroke {false};
    };

    double view_left {0.0};
    double view_top {0.0};
    double view_width {0.0};
    double view_height {0.0};
    std::vector<Path> paths;
    bool parsed_successfully {false};
};

class AssetResource {
public:
    bool load(const ZigVstguiAssetDescription& description);
    uint32_t id() const;
    bool valid() const;
    void draw(VSTGUI::CDrawContext* context, const VSTGUI::CRect& bounds, float alpha) const;

private:
    uint32_t asset_id {0};
    ZigVstguiAssetFormat format {ZIG_VSTGUI_ASSET_PNG};
    ZigVstguiAssetScale scale {ZIG_VSTGUI_ASSET_CONTAIN};
    std::unique_ptr<uint8_t[]> bytes;
    uint32_t byte_count {0};
    VSTGUI::SharedPointer<VSTGUI::CBitmap> bitmap;
    SvgDocument svg;
};

class AssetStore {
public:
    bool load(const ZigVstguiAssetDescription* descriptions, uint32_t count);
    const AssetResource* find(uint32_t asset_id) const;
    bool draw(
        uint32_t asset_id,
        VSTGUI::CDrawContext* context,
        const VSTGUI::CRect& bounds,
        float alpha
    ) const;
    uint32_t count() const;

private:
    std::vector<AssetResource> resources;
};

void drawMissingAsset(VSTGUI::CDrawContext* context, const VSTGUI::CRect& bounds);

}

#endif
