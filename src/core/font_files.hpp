#pragma once

#include <string>
#include <vector>

namespace phos {

/// 字体方案内的角色命名：stem 恰为 `font` 的文件是**主字体**（决定 ASCII 与整机字形风格），
/// 其余按名称排序作回退（约定用 `font-cn` 之类补齐它缺的码位）。扩展名 .ttf / .otf / .ttc
inline constexpr const char* kFontPrimaryStem = "font";

/// 一个字体方案目录（`theme/font/<方案>/`）里的字体文件，按**默认回退顺序**：
/// 主字体在最前，其余按名称排序（与文件系统遍历顺序无关，跨机器稳定）。
/// 只枚举路径、不加载字形——于是内容包布局（pack）与字体加载（render）都能用它，
/// 而两者不必互相依赖。目录不存在或没有任何字体文件时返回空表，回退由调用方决定。
std::vector<std::string> font_files_in_scheme(const std::string& scheme_dir);

} // namespace phos
