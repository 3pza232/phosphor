#pragma once

#include "core/defaults.hpp"
#include "core/screen.hpp"

#include <string>
#include <vector>

namespace phos {

/// 一块图层缓冲：与内容区同构的网格，格带 `alpha`（0 = 这一格不存在）。
///
/// 卡带按需创建；不创建时主循环里连一次合并都不会发生（见 App::tick_playing）。
/// 层只描述"叠在底层之上"的缓冲：既不参与既有写入路径，也不进渲染器
struct Layer {
    std::string name;   // 卡带自己起的名字，只在本卡带内有意义
    int z = 0;          // 越大越靠上
    bool visible = true;
    Screen cells;
};

/// 图层栈：合成规则与宽字符归一的唯一实现处。
class LayeredScreen {
public:
    /// 卡带自定义层的上限。层数直接乘进每帧的合并开销，所以它是**上限**：
    /// 达到上限后 create 返回 nullptr，由调用方给出明确报错
    static constexpr int kMaxLayers = 6;

    /// 重建为内容区尺寸并清空所有层（插卡时调用）
    void reset(int w, int h);

    bool active() const { return !layers_.empty(); }
    const std::vector<Layer>& layers() const { return layers_; }

    /// 所有层清成透明。每帧推进前调用一次：层与底层**同一心智**（每帧重画），
    /// 于是"这帧不再画它"就等于它消失，不会在层里留下上一帧的残影
    void clear_all();

    Layer* find(const std::string& name);
    const Layer* find(const std::string& name) const;

    /// 全部层按 z 升序（同 z 保持注册先后）。合成与 `phos.layer.order` 共用这份次序，
    /// 两处各排一次就会出现"画面叠放与 order() 报的不一致"
    std::vector<const Layer*> ordered() const;
    /// 取已有层，没有则新建（重名幂等）；到达上限返回 nullptr
    Layer* create(const std::string& name, int z);
    bool remove(const std::string& name);

    /// 把可见层按 z 升序叠到目标网格的内容区（原点 origin_x / origin_y）。
    /// 无层或全部隐藏时什么都不做并返回 false
    bool merge_over(Screen& target, int origin_x, int origin_y);

private:
    std::vector<Layer> layers_;   // 注册顺序；合并时按 z 稳定排序
    int width_ = kContentW;
    int height_ = kContentH;
};

} // namespace phos
