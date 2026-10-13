#include "agent/cart_json.hpp"

#include "core/json_lite.hpp"

namespace phos {

std::string cart_json(const CartInfo& info, bool english) {
    std::string out = "{\"id\":" + json::quote(info.id);
    out += ",\"name\":" + json::quote(info.name.get(english));
    out += ",\"version\":" + json::quote(info.version);
    out += ",\"author\":" + json::quote(info.author);
    out += ",\"sidebar_w\":" + std::to_string(info.sidebar_w);
    out += ",\"wants_save\":";
    out += info.wants_save ? "true" : "false";
    out += ",\"path\":" + json::quote(info.path);
    out += ",\"error\":";
    out += info.error.empty() ? "null" : json::quote(info.error);
    return out + "}";
}

std::string cart_list_json(const std::vector<CartInfo>& carts, bool english) {
    std::string out = "[";
    for (size_t i = 0; i < carts.size(); ++i) {
        if (i) out += ",";
        out += cart_json(carts[i], english);
    }
    return out + "]";
}

} // namespace phos
