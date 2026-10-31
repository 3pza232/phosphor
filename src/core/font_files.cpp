#include "core/font_files.hpp"

#include <algorithm>
#include <filesystem>

namespace phos {

namespace {

namespace fs = std::filesystem;

bool has_suffix(const std::string& path, const char* suffix) {
    const std::string s(suffix);
    return path.size() >= s.size() && path.compare(path.size() - s.size(), s.size(), s) == 0;
}

/// 该文件是否是这个方案的主字体：stem 恰为 `font`（font-cn 之类是回退）
bool is_primary_font(const std::string& path) {
    return fs::path(path).stem().string() == kFontPrimaryStem;
}

/// 某个目录下的字体文件（.ttf/.otf/.ttc），按名称排序保证顺序稳定
std::vector<std::string> font_files_in(const std::string& dir) {
    std::vector<std::string> files;
    std::error_code ec;
    if (!fs::is_directory(dir, ec)) return files;
    for (fs::directory_iterator it(dir, ec), end; it != end && !ec; it.increment(ec)) {
        if (!it->is_regular_file(ec)) continue;
        const std::string path = it->path().generic_string();
        if (has_suffix(path, ".ttf") || has_suffix(path, ".otf") || has_suffix(path, ".ttc"))
            files.push_back(path);
    }
    std::sort(files.begin(), files.end());
    return files;
}

} // namespace

std::vector<std::string> font_files_in_scheme(const std::string& scheme_dir) {
    const std::vector<std::string> found = font_files_in(scheme_dir);  // 已按名称排序
    std::vector<std::string> files;
    files.reserve(found.size());
    // 主字体必须排最前：它的 ASCII 字形与像素基线是整机的基准，回退只管补齐它缺的码位
    for (const std::string& path : found)
        if (is_primary_font(path)) files.push_back(path);
    for (const std::string& path : found)
        if (!is_primary_font(path)) files.push_back(path);
    return files;
}

} // namespace phos
