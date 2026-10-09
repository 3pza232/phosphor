#include "api/assets_api.hpp"

#include "api/host_api.hpp"
#include "cart/cart_files.hpp"

#include <sol/sol.hpp>

#include <sstream>

namespace phos {

namespace {

/// 按行切分（去掉行尾 \r，保留行首空格与空行）
std::vector<std::string> split_lines(const std::string& text) {
    std::vector<std::string> lines;
    std::istringstream stream(text);
    std::string line;
    while (std::getline(stream, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        lines.push_back(std::move(line));
    }
    return lines;
}

} // namespace

void register_assets_api(sol::state& lua, HostContext& host) {
    sol::table phos = lua["phos"];
    sol::table assets = phos.create_named("assets");

    // 文本资源：不存在返回 nil —— 缺失由卡带自行决定怎么处理，不抛异常
    assets["text"] = [&host, &lua](const std::string& path) -> sol::object {
        if (!host.cart_files) return sol::nil;
        auto data = host.cart_files->read(path);
        if (!data) return sol::nil;
        return sol::make_object(lua.lua_state(), *data);
    };

    // 按行读取：表数组（1 基），常用于地图 / 关卡 / 对话
    assets["rows"] = [&host, &lua](const std::string& path) -> sol::object {
        if (!host.cart_files) return sol::nil;
        auto data = host.cart_files->read(path);
        if (!data) return sol::nil;
        sol::table rows = lua.create_table();
        int index = 1;
        for (auto& line : split_lines(*data)) rows[index++] = std::move(line);
        return rows;
    };

    assets["exists"] = [&host](const std::string& path) {
        return host.cart_files != nullptr && host.cart_files->exists(path);
    };

    assets["size"] = [&host](const std::string& path) -> int {
        if (!host.cart_files) return 0;
        auto data = host.cart_files->read(path);
        return data ? static_cast<int>(data->size()) : 0;
    };

    // 列出包内文件（可按前缀过滤），便于工具与调试
    assets["list"] = [&host, &lua](sol::object prefix) {
        sol::table out = lua.create_table();
        if (!host.cart_files) return out;
        const std::string filter = prefix.is<std::string>() ? prefix.as<std::string>() : "";
        int index = 1;
        for (auto& entry : host.cart_files->entries(filter)) out[index++] = std::move(entry);
        return out;
    };
}

} // namespace phos
