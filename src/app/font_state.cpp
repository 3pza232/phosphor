#include "app/font_state.hpp"

#include "core/font_files.hpp"
#include "core/log.hpp"

#include <string>

namespace phos {

void FontState::scan(const std::string& font_dir) {
    font_dir_ = font_dir;
    schemes_ = scan_font_schemes(font_dir);
    names_.clear();
    names_.reserve(schemes_.size());
    for (const FontScheme& scheme : schemes_) names_.push_back(scheme.name);
}

void FontState::load_chain(const std::string& wanted) {
    // 方案表里已含声明的回退顺序与字号；不查目录文件系统，避免"表里/盘上"两套排序
    const auto find = [this](const std::string& name) -> const FontScheme* {
        for (const FontScheme& scheme : schemes_)
            if (scheme.name == name) return &scheme;
        return nullptr;
    };
    const auto use = [this, &find](const std::string& name) {
        current_ = name;
        scheme_px_ = 0;
        min_px_ = kMinFontPx;
        max_px_ = kMaxFontPx;
        if (const FontScheme* scheme = find(name)) {
            files_ = scheme->files;
            scheme_px_ = scheme->size;
            min_px_ = scheme->min_size;
            max_px_ = scheme->max_size;  // 方案（或其 Mod 覆盖）声明的可调上限
        } else {
            // 方案不在表里（目录被删 / 名字写错）：现取一次，取不到再由下面兜底
            files_ = font_files_in_scheme(font_dir_ + "/" + name);
        }
    };

    use(wanted);
    // 方案不可用（目录被删、名字写错、里面没有字体）：退回出厂默认并告警。内容坏了不该没字可用
    if (files_.empty() && current_ != kDefaultScheme) {
        log::warn("font scheme unusable, falling back to default: " + current_);
        use(kDefaultScheme);
    }
    if (files_.empty()) log::warn("no font file in " + font_dir_ + "/" + current_);
}

int FontState::effective_px(int configured_px) const {
    if (configured_px > 0) return clamp_px(configured_px);              // 用户显式选择优先
    return scheme_px_ > 0 ? scheme_px_ : kDefaultFontPx;               // 否则方案声明，再否则出厂默认
}

int FontState::clamp_px(int px) const {
    return px < min_px_ ? min_px_ : (px > max_px_ ? max_px_ : px);
}

} // namespace phos
