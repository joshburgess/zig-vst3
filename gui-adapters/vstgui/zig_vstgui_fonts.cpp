#include "zig_vstgui_fonts.h"

#include "vstgui/lib/platform/platformfactory.h"
#include "vstgui/lib/platform/iplatformfont.h"

#include <algorithm>
#include <utility>

namespace ZigVstgui {

std::string chooseFontFamily(
    const char* preferred,
    const char* fallback,
    const std::vector<std::string>& available
) {
    const auto find = [&available](const char* family) -> std::string {
        if (!family || family[0] == '\0') return {};
        const auto match = std::find(available.begin(), available.end(), family);
        return match == available.end() ? std::string() : *match;
    };
    auto selected = find(preferred);
    if (!selected.empty()) return selected;
    return find(fallback);
}

void applyFontDescription(const ZigVstguiFontDescription& fonts, ThemeResolver& resolver) {
    std::vector<std::string> available;
    VSTGUI::getPlatformFactory().getAllFontFamilies([&available](const std::string& family) {
        available.push_back(family);
        return true;
    });
    const auto apply = [&](TypographyRole role, const char* preferred) {
        const auto family = chooseFontFamily(preferred, fonts.fallback_family, available);
        if (family.empty()) return;
        const auto* base = resolver.font(role);
        const auto size = base ? base->getSize() : 12.0;
        const auto style = base ? base->getStyle() : 0;
        auto font = VSTGUI::owned(new VSTGUI::CFontDesc(family.c_str(), size, style));
        if (!font->getPlatformFont()) return;
        resolver.setFontOverride(role, std::move(font));
    };
    apply(TypographyRole::title, fonts.title_family);
    apply(TypographyRole::body, fonts.body_family);
    apply(TypographyRole::value, fonts.value_family);
}

}
