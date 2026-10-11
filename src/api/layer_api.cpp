#include "api/layer_api.hpp"

#include <algorithm>
#include <stdexcept>
#include <utility>
#include <vector>

namespace phos {

namespace {

/// Lua 侧的层句柄。只记**名字**，每次操作现查——层可以被卡带注销，
/// 缓存 Layer* 会在那之后变成野指针
struct LayerHandle {
    LayeredScreen* layers = nullptr;
    std::string name;
};

Layer* resolve(const LayerHandle& handle) {
    return handle.layers ? handle.layers->find(handle.name) : nullptr;
}

} // namespace

void register_layer_api(sol::state& lua, HostContext& host) {
    lua.new_usertype<LayerHandle>(
        "phos.Layer", sol::no_constructor,
        "name", sol::property([](const LayerHandle& self) { return self.name; }),
        "visible",
        sol::property([](const LayerHandle& self) {
            const Layer* layer = resolve(self);
            return layer ? layer->visible : false;
        },
                      [](LayerHandle& self, bool on) {
                          if (Layer* layer = resolve(self)) layer->visible = on;
                      }),
        "z",
        sol::property([](const LayerHandle& self) {
            const Layer* layer = resolve(self);
            return layer ? layer->z : 0;
        },
                      [](LayerHandle& self, int z) {
                          if (Layer* layer = resolve(self)) layer->z = z;
                      }),
        // 清成透明：上层每帧"从空开始"的写法（下层的画面因此自然透出来）
        "clear", [](LayerHandle& self) {
            if (Layer* layer = resolve(self)) layer->cells.clear_transparent();
        });

    sol::table phos = lua["phos"];
    sol::table layer = phos.create_named("layer");

    layer["create"] = [&host](const std::string& name, sol::optional<sol::table> opts) {
        int z = 0;
        if (opts) {
            sol::object depth = (*opts)["z"];
            if (depth.is<double>() || depth.is<int>()) z = depth.as<int>();
        }
        if (!host.layers.create(name, z))
            throw std::runtime_error("phos.layer.create: 层数已达上限 " +
                                     std::to_string(LayeredScreen::kMaxLayers));
        return LayerHandle{&host.layers, name};
    };

    // 层序：z 升序（同 z 保持注册先后），返回名字数组——检查叠放次序用
    layer["order"] = [&host, &lua]() {
        sol::table out = lua.create_table();
        int index = 1;
        for (const Layer* layer : host.layers.ordered()) out[index++] = layer->name;
        return out;
    };

    layer["remove"] = [&host](const std::string& name) { return host.layers.remove(name); };
}

} // namespace phos
