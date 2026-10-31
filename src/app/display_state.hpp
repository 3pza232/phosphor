#pragma once

#include "core/crt.hpp"
#include "core/display.hpp"
#include "core/skin.hpp"

namespace phos {

/// 主机显示与 CRT 参数（S1 阶段七从 App 抽出的纯状态部分）：
/// 持有三块显示面（screen/base/chrome）与当前 CRT 参数。
/// 合成调用仍走 Display::present，Renderer/窗口交互仍由 App 执行——本类不依赖 render 层。
class DisplayState {
public:
    /// 三块面（卡带纹理视图 / 合成前底图 / 主机 chrome）与合成顺序，见 core/display.hpp
    Display& display() { return display_; }
    const Display& display() const { return display_; }

    /// 换主题：内容区网格按皮肤几何重建（旧行为只 resize screen，base/chrome 随卡带生命周期）
    void resize_screen(const Skin& skin);

    /// 铺满内容区并清空主机 chrome（插卡/换卡时，chrome 每帧重画的起点）
    void reset_chrome(int content_w, int content_h);

    /// 按 CRT 档位与当前色板算出参数；把参数推给 Renderer 仍由 App 做
    void apply_crt(int level, const Palette& palette);

    const CrtParams& crt() const { return crt_; }
    /// 仪表盘可直接调参（见 app_observe 的 DebugInfo.crt），所以给可写引用
    CrtParams& crt() { return crt_; }

private:
    Display display_;
    CrtParams crt_;
};

} // namespace phos
