#include "devkit/packer.hpp"

#include "cart/cart_files.hpp"
#include "cart/cart_info.hpp"
#include "cart/cartridge.hpp"

#include <miniz.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <vector>

namespace phos::devkit {

namespace {

namespace fs = std::filesystem;

/// 收集目录下全部常规文件，返回相对路径（统一使用 '/' 分隔）。
/// 跳过 `.phos`（已有的卡带包不应再被装进新包）
std::vector<fs::path> collect_files(const fs::path& root, std::error_code& ec) {
    std::vector<fs::path> files;
    // 用独立的 ec：调用方传入的 ec 可能带着上一次调用的残留状态，
    // 循环条件里的 !ec 会让它一个文件都收不到
    std::error_code walk_ec;
    for (fs::recursive_directory_iterator it(root, walk_ec), end; it != end;
         it.increment(walk_ec)) {
        if (walk_ec) break;
        if (!it->is_regular_file(walk_ec)) continue;
        if (it->path().extension() == ".phos") continue;
        const fs::path relative = fs::relative(it->path(), root, walk_ec);
        if (walk_ec) break;
        files.push_back(relative);
    }
    if (walk_ec) ec = walk_ec;  // 真实错误才往外报
    // 稳定顺序：同样的输入产出同样的包，便于比对与复现
    std::sort(files.begin(), files.end());
    return files;
}

bool write_zip(const fs::path& source_dir, const std::vector<fs::path>& files,
               const fs::path& output, std::string& error) {
    mz_zip_archive zip{};
    if (!mz_zip_writer_init_file(&zip, output.string().c_str(), 0)) {
        error = "cannot create archive: " + output.string();
        return false;
    }

    for (const auto& relative : files) {
        std::string archive_name = relative.generic_string();  // 统一 '/'
        const std::string full_path = (source_dir / relative).string();
        if (!mz_zip_writer_add_file(&zip, archive_name.c_str(), full_path.c_str(), nullptr, 0,
                                    MZ_DEFAULT_COMPRESSION)) {
            error = "cannot add to archive: " + archive_name;
            mz_zip_writer_end(&zip);
            return false;
        }
    }

    if (!mz_zip_writer_finalize_archive(&zip)) {
        error = "cannot finalize archive";
        mz_zip_writer_end(&zip);
        return false;
    }
    mz_zip_writer_end(&zip);
    return true;
}

/// 目录名（卡带 id 的兜底来源）
std::string directory_id(const fs::path& dir) { return dir.filename().string(); }

} // namespace

bool pack_cart(const std::string& source_dir, const std::string& output_path, PackResult& result) {
    std::error_code ec;
    const fs::path source(source_dir);

    if (!fs::is_directory(source, ec)) {
        result.error = "not a directory: " + source_dir;
        return false;
    }

    // 校验：以"卡带读取路径"的同一套逻辑探测，避免打包器与运行时分叉
    CartFiles files = CartFiles::open(source_dir);
    auto manifest = files.valid() ? files.read("manifest.lua") : std::nullopt;
    if (!manifest) {
        result.error = "cannot read manifest.lua in " + source_dir;
        return false;
    }

    const CartInfo info = parse_manifest(*manifest, source_dir);
    if (!info.error.empty()) {
        result.error = "invalid cart: " + info.error;
        return false;
    }
    result.cart_id = info.id;

    // 入口脚本必须存在，否则卡带插入时必然报错（entry 由 parse_manifest 一并给出）
    const std::string& entry = info.entry;
    if (!files.read(entry)) {
        result.error = "entry script missing: " + entry;
        return false;
    }

    const auto found = collect_files(source, ec);
    if (ec) {
        result.error = "cannot scan source directory: " + ec.message();
        return false;
    }
    if (found.empty()) {
        result.error = "no files to pack in " + source_dir;
        return false;
    }

    // 输出路径统一使用 '/' 分隔（与包内路径、文档示例一致）。
    // 默认产出到 dist/：产出混在 carts/ 里会让卡带架同时列出目录与单文件两份
    fs::path output(output_path.empty() ? fs::path("dist") / (result.cart_id + ".phos")
                                        : fs::path(output_path));
    if (output.extension() != ".phos") output += ".phos";
    output = fs::path(output.generic_string());

    if (auto parent = output.parent_path(); !parent.empty()) {
        fs::create_directories(parent, ec);
        if (ec) {
            result.error = "cannot create output directory: " + parent.string();
            return false;
        }
    }

    if (!write_zip(source, found, output, result.error)) return false;

    result.output_path = output.string();
    result.file_count = static_cast<int>(found.size());
    return true;
}

bool scaffold_cart(const std::string& template_dir, const std::string& target_dir,
                   const ScaffoldInfo& info, int& file_count, std::string& error) {
    std::error_code ec;
    const fs::path from(template_dir);
    const fs::path to(target_dir);

    if (!fs::is_directory(from, ec)) {
        error = "template directory not found: " + template_dir;
        return false;
    }
    if (fs::exists(to, ec)) {
        error = "target already exists: " + target_dir;
        return false;
    }

    std::error_code scan_ec;
    const std::vector<fs::path> files = collect_files(from, scan_ec);
    if (scan_ec) {
        error = "cannot scan template " + template_dir + ": " + scan_ec.message();
        return false;
    }
    if (files.empty()) {
        // 拷 0 个文件却"成功"，会让用户拿到一个装不进主机的空目录——
        // 宁可在这里失败，也不要在几分钟后从"卡带缺 manifest"反推
        error = "template has no files: " + template_dir;
        return false;
    }

    // 占位符的值每个文件都一样，先定下来：id 缺省取目录名，标题缺省与 id 相同
    const std::string id = info.id.empty() ? directory_id(to) : info.id;
    // id 是存档路径与 <id>.phos 的来源，先按同一份规则校验：否则会生成一个装不进主机的卡带，
    // 而错误要等到几分钟后插卡才暴露
    if (!is_valid_cart_id(id)) {
        error = "invalid cart id (use [a-z0-9-], 1..64): " + id;
        return false;
    }
    const std::string name = info.name.empty() ? id : info.name;
    const std::string author = info.author.empty() ? "you" : info.author;

    file_count = 0;
    for (const auto& relative : files) {
        const fs::path destination = to / relative;
        fs::create_directories(destination.parent_path(), ec);
        if (ec) {
            error = "cannot create " + destination.parent_path().string();
            return false;
        }

        std::ifstream in((from / relative).string(), std::ios::binary);
        std::ostringstream buffer;
        buffer << in.rdbuf();
        std::string text = buffer.str();

        // 模板占位符 __ID__ / __NAME__ / __AUTHOR__。替换值按 Lua 字符串转义：目录名或
        // 标题里出现引号时不能写出坏 manifest——那种错要等到几分钟后装卡才暴露，很难查
        auto lua_escape = [](const std::string& value) {
            std::string out;
            out.reserve(value.size());
            for (char ch : value) {
                if (ch == '"' || ch == '\\') out += '\\';
                if (ch == '\n') { out += "\\n"; continue; }
                if (ch == '\r') continue;
                out += ch;
            }
            return out;
        };
        auto replace_all = [&text](const std::string& needle, const std::string& value) {
            for (size_t pos = text.find(needle); pos != std::string::npos;
                 pos = text.find(needle, pos + value.size()))
                text.replace(pos, needle.size(), value);
        };
        replace_all("__ID__", lua_escape(id));
        replace_all("__NAME__", lua_escape(name));
        replace_all("__AUTHOR__", lua_escape(author));

        std::ofstream out(destination.string(), std::ios::binary | std::ios::trunc);
        if (!out) {
            error = "cannot write " + destination.string();
            return false;
        }
        out << text;
        ++file_count;
    }
    return true;
}

} // namespace phos::devkit
