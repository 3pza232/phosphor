#pragma once

#include "cart/cartridge.hpp"
#include "core/screen.hpp"
#include "core/ui.hpp"
#include "shell/shelf_view.hpp"

#include <memory>
#include <string>

namespace phos {

class HostContext;

/// 卡带架样式包脚本 + 动画时钟（S1 阶段三从 App 抽出的内聚子系统）。
/// 只负责：装/卸脚本、推进 update(dt)、把架子状态翻成 ShelfDrawContext 交给 draw(ctx)。
/// 不接管：Shell 画家注册、config 写盘、packs 索引——这些仍是 App 的编排（见 apply_shelf）。
/// 也不碰 HostContext 的清理：脚本卸下后由 App 调 clear_host_cart()（与卡带会话同一出口）。
class ShelfPlayback {
public:
    /// 卸下当前脚本并复位动画时钟（切选择 / 脚本出错回退时调用；无脚本时安全）
    void reset();

    /// 装载一个卡带架样式包目录（shelf.lua 必须存在且定义 draw(ctx)）。
    /// 失败只填 error（脚本就地销毁，不留下半装载状态）；成功接管脚本并把时钟清零
    bool load(const std::string& dir, HostContext& host, std::string& error);

    /// 推进脚本可选的 update(dt)。返回 false 时 error 为脚本错误；脚本留给调用方 reset
    bool tick(float dt, std::string& error);

    /// 画内容区：把 ShelfView + ui::Style + 主题面板色翻成只读 ctx 交给脚本。
    /// panel 由 App 提供（ui::Style 不含面板色，主题面板色来自 packs_.skin().panel）。
    /// 返回 false = 脚本报错（error 已填），调用方负责回退内置样式并收回画家
    bool draw(Screen& screen, const ui::Rect& content, const ShelfView& view,
              const ui::Style& style, Color panel, std::string& error);

    /// 是否有可用脚本（Shell 画家只在有脚本时挂上，两者始终同步）
    bool active() const { return script_ != nullptr; }

private:
    std::unique_ptr<Cartridge> script_;
    /// 卡带架自己的时钟（秒）：供内容包做动画。与 host_.time 分开——
    /// 架子不是卡带，不该借用卡带的时间线（App 在 tick 时另把 dt 加进 host_.time）
    float time_ = 0.0f;
};

} // namespace phos
