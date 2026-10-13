#include "cart/cart_scanner.hpp"

#include "cart/cart_files.hpp"

#include <algorithm>
#include <filesystem>

namespace phos {

std::vector<CartInfo> scan_carts(const std::string& dir) {
    std::vector<CartInfo> out;
    namespace fs = std::filesystem;
    std::error_code ec;
    if (!fs::is_directory(dir, ec)) return out;

    for (const auto& entry : fs::directory_iterator(dir, ec)) {
        const std::string path = entry.path().string();
        bool is_cart = false;
        if (entry.is_directory(ec)) {
            is_cart = fs::is_regular_file(entry.path() / "manifest.lua", ec);
        } else if (entry.is_regular_file(ec) && entry.path().extension() == ".phos") {
            is_cart = true;
        }
        if (!is_cart) continue;

        CartFiles files = CartFiles::open(path);
        auto manifest = files.valid() ? files.read("manifest.lua") : std::nullopt;
        if (!manifest) {
            CartInfo info;
            info.path = path;
            info.id = entry.path().stem().string();
            info.name.zh = info.id;
            info.error = "cannot read manifest.lua";
            out.push_back(std::move(info));
            continue;
        }
        CartInfo info = parse_manifest(*manifest, path);
        if (info.name.empty()) info.name.zh = info.id;
        out.push_back(std::move(info));
    }

    std::sort(out.begin(), out.end(),
              [](const CartInfo& a, const CartInfo& b) { return a.id < b.id; });
    return out;
}

} // namespace phos
