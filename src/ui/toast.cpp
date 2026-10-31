#include "ui/toast.hpp"

#include "core/screen.hpp"
#include "core/surface.hpp"
#include "core/text.hpp"
#include "ui/theme.hpp"

#include <algorithm>

namespace phos::ui {

namespace {
constexpr int kMaxEntries = 4;   // 连发多条时只留最近几条，避免堆积
constexpr int kMaxTextCols = 60; // 再长就截断：toast 是提示，不是文档
} // namespace

void Toasts::push(std::string text, float seconds) {
    if (text.empty()) return;
    if (seconds <= 0.0f) seconds = 1.6f;
    entries_.push_back(Entry{std::move(text), seconds});
    if (entries_.size() > kMaxEntries)
        entries_.erase(entries_.begin(),
                       entries_.begin() + static_cast<long>(entries_.size() - kMaxEntries));
}

void Toasts::update(float dt) {
    if (dt <= 0.0f) return;
    for (Entry& entry : entries_) entry.ttl -= dt;
    entries_.erase(std::remove_if(entries_.begin(), entries_.end(),
                                  [](const Entry& entry) { return entry.ttl <= 0.0f; }),
                   entries_.end());
}

void Toasts::clear() { entries_.clear(); }

void Toasts::paint(Screen& screen, const Theme& theme, Rect area) const {
    if (entries_.empty()) return;
    const std::string& text = entries_.back().text;
    const int want = text::display_width(text) + 4;
    const int width = std::min({want, kMaxTextCols + 4, std::max(0, area.w)});
    if (width < 8) return;
    const std::string shown = text::truncate(text, width - 4);
    const int height = 3;
    const int x = area.x + std::max(0, (area.w - width) / 2);
    const int y = area.y + std::max(0, area.h - height);
    if (y < area.y) return;

    Surface surface(screen, x, y, width, height);
    const Color bg = theme.surface;
    surface.fill(0, 0, width, height, U' ', theme.text, bg);
    // 边框：与组件层同字形，看起来像"系统的提示"而不是卡带随手画的
    for (int i = 1; i < width - 1; ++i) {
        surface.put(i, 0, theme.glyphs.h, theme.border, bg);
        surface.put(i, height - 1, theme.glyphs.h, theme.border, bg);
    }
    for (int row = 1; row < height - 1; ++row) {
        surface.put(0, row, theme.glyphs.v, theme.border, bg);
        surface.put(width - 1, row, theme.glyphs.v, theme.border, bg);
    }
    surface.put(0, 0, theme.glyphs.tl, theme.border, bg);
    surface.put(width - 1, 0, theme.glyphs.tr, theme.border, bg);
    surface.put(0, height - 1, theme.glyphs.bl, theme.border, bg);
    surface.put(width - 1, height - 1, theme.glyphs.br, theme.border, bg);

    const int text_x = 2 + std::max(0, (width - 4 - text::display_width(shown)) / 2);
    surface.print(text_x, 1, shown, theme.text, bg);
}

} // namespace phos::ui
