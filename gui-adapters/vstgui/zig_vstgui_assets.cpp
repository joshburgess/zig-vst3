#include "zig_vstgui_assets.h"

#include "vstgui/lib/cdrawcontext.h"
#include "vstgui/lib/cgraphicstransform.h"
#include "vstgui/lib/platform/platformfactory.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <new>
#include <optional>
#include <string_view>

namespace ZigVstgui {

namespace {

std::optional<std::string> attribute(std::string_view tag, std::string_view name) {
    const std::string key = std::string(name) + "=";
    const auto key_position = tag.find(key);
    if (key_position == std::string_view::npos) return std::nullopt;
    const auto quote_position = key_position + key.size();
    if (quote_position >= tag.size()) return std::nullopt;
    const char quote = tag[quote_position];
    if (quote != '\'' && quote != '"') return std::nullopt;
    const auto value_end = tag.find(quote, quote_position + 1);
    if (value_end == std::string_view::npos) return std::nullopt;
    return std::string(tag.substr(quote_position + 1, value_end - quote_position - 1));
}

bool parseNumberList(const std::string& text, double* values, uint32_t count) {
    const char* cursor = text.c_str();
    for (uint32_t index = 0; index < count; ++index) {
        while (*cursor && (std::isspace(static_cast<unsigned char>(*cursor)) || *cursor == ',')) ++cursor;
        if (!*cursor) return false;
        char* end = nullptr;
        values[index] = std::strtod(cursor, &end);
        if (end == cursor || !std::isfinite(values[index])) return false;
        cursor = end;
    }
    while (*cursor && (std::isspace(static_cast<unsigned char>(*cursor)) || *cursor == ',')) ++cursor;
    return *cursor == '\0';
}

bool parseColor(const std::string& text, VSTGUI::CColor& color) {
    if (text == "none") return false;
    if (text.size() != 7 && text.size() != 9) return false;
    if (text[0] != '#') return false;
    char* end = nullptr;
    const auto value = std::strtoul(text.c_str() + 1, &end, 16);
    if (!end || *end != '\0') return false;
    if (text.size() == 7) {
        color = VSTGUI::CColor(
            static_cast<uint8_t>((value >> 16) & 0xff),
            static_cast<uint8_t>((value >> 8) & 0xff),
            static_cast<uint8_t>(value & 0xff),
            255
        );
    } else {
        color = VSTGUI::CColor(
            static_cast<uint8_t>((value >> 24) & 0xff),
            static_cast<uint8_t>((value >> 16) & 0xff),
            static_cast<uint8_t>((value >> 8) & 0xff),
            static_cast<uint8_t>(value & 0xff)
        );
    }
    return true;
}

bool nextNumber(const char*& cursor, double& value) {
    while (*cursor && (std::isspace(static_cast<unsigned char>(*cursor)) || *cursor == ',')) ++cursor;
    if (!*cursor || std::isalpha(static_cast<unsigned char>(*cursor))) return false;
    char* end = nullptr;
    value = std::strtod(cursor, &end);
    if (end == cursor || !std::isfinite(value)) return false;
    cursor = end;
    return true;
}

VSTGUI::CColor withAlpha(VSTGUI::CColor color, float alpha) {
    const float bounded = boundedAssetAlpha(alpha);
    color.alpha = static_cast<uint8_t>(bounded * color.alpha);
    return color;
}

class GraphicsStateGuard {
public:
    explicit GraphicsStateGuard(VSTGUI::CDrawContext* value_context)
    : context(value_context) {
        context->saveGlobalState();
        saved = true;
    }

    ~GraphicsStateGuard() noexcept {
        if (!saved) return;
        try {
            context->restoreGlobalState();
        } catch (...) {
        }
    }

    GraphicsStateGuard(const GraphicsStateGuard&) = delete;
    GraphicsStateGuard& operator=(const GraphicsStateGuard&) = delete;

private:
    VSTGUI::CDrawContext* context;
    bool saved {false};
};

}

float boundedAssetAlpha(float alpha) {
    return std::isfinite(alpha) ? std::clamp(alpha, 0.f, 1.f) : 0.f;
}

AssetPlacement placeAsset(
    const VSTGUI::CRect& bounds,
    double source_width,
    double source_height,
    ZigVstguiAssetScale scale
) {
    AssetPlacement result {bounds, 1.0, 1.0};
    if (source_width <= 0.0 || source_height <= 0.0 || bounds.isEmpty()) return result;
    const double available_width = bounds.getWidth();
    const double available_height = bounds.getHeight();
    if (scale == ZIG_VSTGUI_ASSET_STRETCH) {
        result.scale_x = available_width / source_width;
        result.scale_y = available_height / source_height;
        return result;
    }
    double uniform = 1.0;
    if (scale == ZIG_VSTGUI_ASSET_CONTAIN) {
        uniform = std::min(available_width / source_width, available_height / source_height);
    } else if (scale == ZIG_VSTGUI_ASSET_COVER) {
        uniform = std::max(available_width / source_width, available_height / source_height);
    }
    const double width = source_width * uniform;
    const double height = source_height * uniform;
    const double left = bounds.left + (available_width - width) / 2.0;
    const double top = bounds.top + (available_height - height) / 2.0;
    result.destination = VSTGUI::CRect(left, top, left + width, top + height);
    result.scale_x = uniform;
    result.scale_y = uniform;
    return result;
}

bool SvgDocument::parse(const uint8_t* data, uint32_t size) {
    parsed_successfully = false;
    paths.clear();
    view_left = 0.0;
    view_top = 0.0;
    view_width = 0.0;
    view_height = 0.0;
    if (!data || size == 0) return false;
    const std::string source(reinterpret_cast<const char*>(data), size);
    for (const auto* unsupported : {
            "<script", "<style", "<text", "<rect", "<circle", "<ellipse", "<line",
            "<polyline", "<polygon", "<image", "<use", "<filter", "<animate",
            " transform=", " style=", " href=", " xlink:href="
        }) {
        if (source.find(unsupported) != std::string::npos) return false;
    }
    const auto svg_start = source.find("<svg");
    const auto svg_end = source.find('>', svg_start);
    if (svg_start == std::string::npos || svg_end == std::string::npos) return false;
    const auto svg_tag = std::string_view(source).substr(svg_start, svg_end - svg_start + 1);
    const auto view_box = attribute(svg_tag, "viewBox");
    double view_values[4] {};
    if (!view_box || !parseNumberList(*view_box, view_values, 4) ||
        view_values[2] <= 0.0 || view_values[3] <= 0.0) return false;
    view_left = view_values[0];
    view_top = view_values[1];
    view_width = view_values[2];
    view_height = view_values[3];

    std::size_t search_position = svg_end + 1;
    while (true) {
        const auto path_start = source.find("<path", search_position);
        if (path_start == std::string::npos) break;
        const auto path_end = source.find('>', path_start);
        if (path_end == std::string::npos) return false;
        const auto path_tag = std::string_view(source).substr(path_start, path_end - path_start + 1);
        const auto data_attribute = attribute(path_tag, "d");
        if (!data_attribute) return false;
        Path path;
        if (const auto fill = attribute(path_tag, "fill")) {
            if (*fill == "none") path.has_fill = false;
            else if (!parseColor(*fill, path.fill)) return false;
        }
        if (const auto stroke = attribute(path_tag, "stroke")) {
            if (*stroke == "none") path.has_stroke = false;
            else {
                if (!parseColor(*stroke, path.stroke)) return false;
                path.has_stroke = true;
            }
        }
        if (const auto stroke_width_value = attribute(path_tag, "stroke-width")) {
            double parsed_width[1] {};
            if (!parseNumberList(*stroke_width_value, parsed_width, 1) || parsed_width[0] < 0.0) return false;
            path.stroke_width = parsed_width[0];
        }

        const char* cursor = data_attribute->c_str();
        char command = 0;
        VSTGUI::CPoint current;
        VSTGUI::CPoint subpath_start;
        while (*cursor) {
            while (*cursor && (std::isspace(static_cast<unsigned char>(*cursor)) || *cursor == ',')) ++cursor;
            if (!*cursor) break;
            if (std::isalpha(static_cast<unsigned char>(*cursor))) command = *cursor++;
            if (!command) return false;
            const bool relative = std::islower(static_cast<unsigned char>(command));
            const char operation = static_cast<char>(std::toupper(static_cast<unsigned char>(command)));
            if (operation == 'Z') {
                path.commands.push_back({CommandKind::close, {}});
                current = subpath_start;
                command = 0;
                continue;
            }
            if (operation == 'M' || operation == 'L') {
                bool first_pair = true;
                while (true) {
                    double x = 0.0;
                    double y = 0.0;
                    if (!nextNumber(cursor, x)) break;
                    if (!nextNumber(cursor, y)) return false;
                    if (relative) {
                        x += current.x;
                        y += current.y;
                    }
                    const bool move = operation == 'M' && first_pair;
                    path.commands.push_back({move ? CommandKind::move : CommandKind::line, {x, y}});
                    current = VSTGUI::CPoint(x, y);
                    if (move) subpath_start = current;
                    first_pair = false;
                    while (*cursor && (std::isspace(static_cast<unsigned char>(*cursor)) || *cursor == ',')) ++cursor;
                    if (!*cursor || std::isalpha(static_cast<unsigned char>(*cursor))) break;
                }
                if (first_pair) return false;
                continue;
            }
            if (operation == 'H' || operation == 'V') {
                bool parsed = false;
                while (true) {
                    double value = 0.0;
                    const char* before = cursor;
                    if (!nextNumber(cursor, value)) {
                        cursor = before;
                        break;
                    }
                    if (operation == 'H') current.x = relative ? current.x + value : value;
                    else current.y = relative ? current.y + value : value;
                    path.commands.push_back({CommandKind::line, {current.x, current.y}});
                    parsed = true;
                    while (*cursor && (std::isspace(static_cast<unsigned char>(*cursor)) || *cursor == ',')) ++cursor;
                    if (!*cursor || std::isalpha(static_cast<unsigned char>(*cursor))) break;
                }
                if (!parsed) return false;
                continue;
            }
            if (operation == 'C') {
                bool parsed = false;
                while (true) {
                    double values[6] {};
                    if (!nextNumber(cursor, values[0])) break;
                    for (uint32_t index = 1; index < 6; ++index) {
                        if (!nextNumber(cursor, values[index])) return false;
                    }
                    if (relative) {
                        values[0] += current.x;
                        values[1] += current.y;
                        values[2] += current.x;
                        values[3] += current.y;
                        values[4] += current.x;
                        values[5] += current.y;
                    }
                    Command curve {CommandKind::cubic, {}};
                    std::copy(std::begin(values), std::end(values), std::begin(curve.values));
                    path.commands.push_back(curve);
                    current = VSTGUI::CPoint(values[4], values[5]);
                    parsed = true;
                    while (*cursor && (std::isspace(static_cast<unsigned char>(*cursor)) || *cursor == ',')) ++cursor;
                    if (!*cursor || std::isalpha(static_cast<unsigned char>(*cursor))) break;
                }
                if (!parsed) return false;
                continue;
            }
            return false;
        }
        if (path.commands.empty() || (!path.has_fill && !path.has_stroke)) return false;
        paths.push_back(std::move(path));
        search_position = path_end + 1;
    }
    parsed_successfully = !paths.empty();
    return parsed_successfully;
}

bool SvgDocument::valid() const {
    return parsed_successfully && view_width > 0.0 && view_height > 0.0 && !paths.empty();
}

uint32_t SvgDocument::pathCount() const {
    return static_cast<uint32_t>(paths.size());
}

double SvgDocument::width() const {
    return view_width;
}

double SvgDocument::height() const {
    return view_height;
}

void SvgDocument::draw(
    VSTGUI::CDrawContext* context,
    const VSTGUI::CRect& bounds,
    ZigVstguiAssetScale scale,
    float alpha
) const {
    if (!context || !valid()) return;
    const auto placement = placeAsset(bounds, view_width, view_height, scale);
    VSTGUI::CGraphicsTransform transform;
    transform.translate(-view_left, -view_top);
    transform.scale(placement.scale_x, placement.scale_y);
    transform.translate(placement.destination.left, placement.destination.top);
    GraphicsStateGuard state(context);
    context->setClipRect(bounds);
    context->setDrawMode(VSTGUI::kAntiAliasing);
    for (const auto& source : paths) {
        auto path = VSTGUI::owned(context->createGraphicsPath());
        if (!path) continue;
        for (const auto& command : source.commands) {
            switch (command.kind) {
                case CommandKind::move:
                    path->beginSubpath(command.values[0], command.values[1]);
                    break;
                case CommandKind::line:
                    path->addLine(command.values[0], command.values[1]);
                    break;
                case CommandKind::cubic:
                    path->addBezierCurve(
                        command.values[0],
                        command.values[1],
                        command.values[2],
                        command.values[3],
                        command.values[4],
                        command.values[5]
                    );
                    break;
                case CommandKind::close:
                    path->closeSubpath();
                    break;
            }
        }
        if (source.has_fill) {
            context->setFillColor(withAlpha(source.fill, alpha));
            context->drawGraphicsPath(path, VSTGUI::CDrawContext::kPathFilled, &transform);
        }
        if (source.has_stroke && source.stroke_width > 0.0) {
            context->setFrameColor(withAlpha(source.stroke, alpha));
            context->setLineWidth(source.stroke_width * std::max(placement.scale_x, placement.scale_y));
            context->drawGraphicsPath(path, VSTGUI::CDrawContext::kPathStroked, &transform);
        }
    }
}

bool AssetResource::load(const ZigVstguiAssetDescription& description) {
    asset_id = description.asset_id;
    format = description.format;
    scale = description.scale;
    byte_count = description.data_size;
    bitmap = nullptr;
    svg = {};
    if (!description.data || description.data_size == 0) return false;
    if (description.format != ZIG_VSTGUI_ASSET_PNG &&
        description.format != ZIG_VSTGUI_ASSET_SVG) return false;
    if (description.scale < ZIG_VSTGUI_ASSET_PIXEL_EXACT ||
        description.scale > ZIG_VSTGUI_ASSET_STRETCH) return false;
    bytes.reset(new (std::nothrow) uint8_t[description.data_size]);
    if (!bytes) return false;
    std::memcpy(bytes.get(), description.data, description.data_size);
    if (format == ZIG_VSTGUI_ASSET_PNG) {
        auto platform_bitmap = VSTGUI::getPlatformFactory().createBitmapFromMemory(bytes.get(), byte_count);
        if (!platform_bitmap) return false;
        bitmap = VSTGUI::owned(new (std::nothrow) VSTGUI::CBitmap(platform_bitmap));
        return bitmap && bitmap->isLoaded();
    }
    if (format == ZIG_VSTGUI_ASSET_SVG) return svg.parse(bytes.get(), byte_count);
    return false;
}

uint32_t AssetResource::id() const {
    return asset_id;
}

bool AssetResource::valid() const {
    return format == ZIG_VSTGUI_ASSET_PNG ? bitmap && bitmap->isLoaded() : svg.valid();
}

void AssetResource::draw(VSTGUI::CDrawContext* context, const VSTGUI::CRect& bounds, float alpha) const {
    if (!context || !valid()) return;
    const float bounded_alpha = boundedAssetAlpha(alpha);
    if (format == ZIG_VSTGUI_ASSET_SVG) {
        svg.draw(context, bounds, scale, bounded_alpha);
        return;
    }
    const auto placement = placeAsset(bounds, bitmap->getWidth(), bitmap->getHeight(), scale);
    GraphicsStateGuard state(context);
    context->setClipRect(bounds);
    context->setBitmapInterpolationQuality(VSTGUI::BitmapInterpolationQuality::kHigh);
    context->fillRectWithBitmap(
        bitmap,
        VSTGUI::CRect(0.0, 0.0, bitmap->getWidth(), bitmap->getHeight()),
        placement.destination,
        bounded_alpha
    );
}

bool AssetStore::load(const ZigVstguiAssetDescription* descriptions, uint32_t asset_count) {
    if (asset_count > ZIG_VSTGUI_MAX_ASSETS || (asset_count > 0 && !descriptions)) return false;
    std::vector<AssetResource> next_resources;
    next_resources.reserve(asset_count);
    for (uint32_t index = 0; index < asset_count; ++index) {
        const auto duplicate = std::find_if(
            next_resources.begin(),
            next_resources.end(),
            [&](const AssetResource& resource) {
                return resource.id() == descriptions[index].asset_id;
            }
        );
        if (duplicate != next_resources.end()) return false;
        AssetResource resource;
        if (!resource.load(descriptions[index])) return false;
        next_resources.push_back(std::move(resource));
    }
    resources = std::move(next_resources);
    return true;
}

const AssetResource* AssetStore::find(uint32_t asset_id) const {
    for (const auto& resource : resources) {
        if (resource.id() == asset_id) return &resource;
    }
    return nullptr;
}

bool AssetStore::draw(
    uint32_t asset_id,
    VSTGUI::CDrawContext* context,
    const VSTGUI::CRect& bounds,
    float alpha
) const {
    const auto* resource = find(asset_id);
    if (!resource || !resource->valid()) {
        drawMissingAsset(context, bounds);
        return false;
    }
    resource->draw(context, bounds, alpha);
    return true;
}

uint32_t AssetStore::count() const {
    return static_cast<uint32_t>(resources.size());
}

void drawMissingAsset(VSTGUI::CDrawContext* context, const VSTGUI::CRect& bounds) {
    if (!context) return;
    GraphicsStateGuard state(context);
    context->setDrawMode(VSTGUI::kAntiAliasing);
    context->setFillColor(VSTGUI::CColor(65, 15, 25, 255));
    context->setFrameColor(VSTGUI::CColor(255, 80, 105, 255));
    context->setLineWidth(std::max(1.0, context->getHairlineSize()));
    context->drawRect(bounds, VSTGUI::kDrawFilledAndStroked);
    context->drawLine(bounds.getTopLeft(), bounds.getBottomRight());
    context->drawLine(VSTGUI::CPoint(bounds.right, bounds.top), VSTGUI::CPoint(bounds.left, bounds.bottom));
}

}
