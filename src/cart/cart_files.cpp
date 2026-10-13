#include "cart/cart_files.hpp"

#include "core/defaults.hpp"
#include "core/log.hpp"

#include <miniz.h>

#include <algorithm>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <sstream>

namespace phos {

namespace {

/// 包根目录名（目录卡带）/ 文件名去扩展名（.phos）——即 mods 目录所用的卡带 id
std::string cart_id_of(const std::string& cart_path) {
    namespace fs = std::filesystem;
    fs::path p(cart_path);
    if (fs::is_directory(p)) return p.filename().string();
    return p.stem().string();
}

std::optional<std::string> read_disk_file(const std::filesystem::path& path) {
    namespace fs = std::filesystem;
    std::error_code ec;
    if (!fs::is_regular_file(path, ec)) return std::nullopt;
    const std::uintmax_t bytes = fs::file_size(path, ec);
    if (ec || bytes > kMaxAssetBytes) {
        log::warn("asset too large, refusing to read: " + path.string());
        return std::nullopt;
    }
    std::ifstream in(path, std::ios::binary);
    if (!in) return std::nullopt;
    std::ostringstream ss;
    ss << in.rdbuf();
    return ss.str();
}

} // namespace

bool CartFiles::path_safe(const std::string& p) {
    // 拒绝越界与绝对路径
    return p.find("..") == std::string::npos && !p.empty() && p[0] != '/' && p[0] != '\\' &&
           p.find(':') == std::string::npos;
}

CartFiles CartFiles::open(const std::string& cart_path) {
    CartFiles cf;
    namespace fs = std::filesystem;
    std::error_code ec;
    if (fs::is_directory(cart_path, ec)) {
        cf.is_zip_ = false;
    } else if (fs::is_regular_file(cart_path, ec)) {
        cf.is_zip_ = true;
    } else {
        return cf;
    }
    cf.cart_path_ = cart_path;

    // 覆盖层 Mod 目录：mods/<卡带id>（与程序包同级）
    const std::string id = cart_id_of(cart_path);
    fs::path mod = fs::path("mods") / id;
    if (!id.empty() && fs::is_directory(mod, ec)) cf.mod_dir_ = mod.generic_string();

    cf.valid_ = true;
    return cf;
}

std::optional<std::string> CartFiles::read(const std::string& inner_path) const {
    if (!valid_ || !path_safe(inner_path)) return std::nullopt;

    // 覆盖层优先：同一路径的文件放 mods/<卡带id>/ 下即可替换（manifest 除外）
    if (!mod_dir_.empty() && inner_path != "manifest.lua") {
        if (auto overridden = read_disk_file(std::filesystem::path(mod_dir_) / inner_path))
            return overridden;
    }
    return read_packed(inner_path);
}

std::optional<std::string> CartFiles::read_packed(const std::string& inner_path) const {
    namespace fs = std::filesystem;

    if (!is_zip_) {
        return read_disk_file(fs::path(cart_path_) / inner_path);
    }

    mz_zip_archive zip{};
    if (!mz_zip_reader_init_file(&zip, cart_path_.c_str(), 0)) return std::nullopt;
    // 先看大小再解压：超过上限就直接拒，别先分配一大块再丢（那正是要防的爆堆）
    const int idx = mz_zip_reader_locate_file(&zip, inner_path.c_str(), nullptr, 0);
    mz_zip_archive_file_stat stat{};
    if (idx < 0 || !mz_zip_reader_file_stat(&zip, idx, &stat)) {
        mz_zip_reader_end(&zip);
        return std::nullopt;
    }
    if (stat.m_uncomp_size > kMaxAssetBytes) {
        log::warn("asset too large, refusing to read: " + inner_path);
        mz_zip_reader_end(&zip);
        return std::nullopt;
    }
    size_t size = 0;
    void* data = mz_zip_reader_extract_file_to_heap(&zip, inner_path.c_str(), &size, 0);
    mz_zip_reader_end(&zip);
    if (!data) return std::nullopt;
    std::string out(static_cast<const char*>(data), size);
    mz_free(data);
    return out;
}

bool CartFiles::exists(const std::string& inner_path) const {
    return size(inner_path).has_value();
}

std::optional<std::size_t> CartFiles::size(const std::string& inner_path) const {
    namespace fs = std::filesystem;
    if (!valid_ || !path_safe(inner_path)) return std::nullopt;

    // 覆盖层优先（与 read 同一套查找）
    if (!mod_dir_.empty() && inner_path != "manifest.lua") {
        std::error_code ec;
        const fs::path p = fs::path(mod_dir_) / inner_path;
        if (fs::is_regular_file(p, ec)) return static_cast<std::size_t>(fs::file_size(p, ec));
    }
    if (!is_zip_) {
        std::error_code ec;
        const fs::path p = fs::path(cart_path_) / inner_path;
        if (!fs::is_regular_file(p, ec)) return std::nullopt;
        return static_cast<std::size_t>(fs::file_size(p, ec));
    }
    mz_zip_archive zip{};
    if (!mz_zip_reader_init_file(&zip, cart_path_.c_str(), 0)) return std::nullopt;
    const int idx = mz_zip_reader_locate_file(&zip, inner_path.c_str(), nullptr, 0);
    mz_zip_archive_file_stat stat{};
    std::optional<std::size_t> out;
    if (idx >= 0 && mz_zip_reader_file_stat(&zip, idx, &stat))
        out = static_cast<std::size_t>(stat.m_uncomp_size);
    mz_zip_reader_end(&zip);
    return out;
}

std::vector<std::string> CartFiles::entries(const std::string& prefix) const {
    namespace fs = std::filesystem;
    std::vector<std::string> out;
    if (!valid_) return out;

    if (!is_zip_) {
        std::error_code ec;
        for (fs::recursive_directory_iterator it(cart_path_, ec), end; it != end && !ec;
             it.increment(ec)) {
            if (!it->is_regular_file(ec)) continue;
            out.push_back(fs::relative(it->path(), cart_path_, ec).generic_string());
        }
    } else {
        mz_zip_archive zip{};
        if (!mz_zip_reader_init_file(&zip, cart_path_.c_str(), 0)) return out;
        const mz_uint count = mz_zip_reader_get_num_files(&zip);
        for (mz_uint i = 0; i < count; ++i) {
            char name[512];
            if (mz_zip_reader_get_filename(&zip, i, name, sizeof(name)) == 0) continue;
            if (name[0] == '\0' || name[strlen(name) - 1] == '/') continue;  // 目录条目
            out.emplace_back(name);
        }
        mz_zip_reader_end(&zip);
    }

    if (!prefix.empty())
        out.erase(std::remove_if(out.begin(), out.end(),
                                 [&prefix](const std::string& path) {
                                     return path.compare(0, prefix.size(), prefix) != 0;
                                 }),
                  out.end());

    std::sort(out.begin(), out.end());
    out.erase(std::unique(out.begin(), out.end()), out.end());
    return out;
}

} // namespace phos
