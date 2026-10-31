#pragma once

#include "core/defaults.hpp"

namespace phos {

/// 开机动画时序（S1 阶段八从 App 抽出的纯状态）：
/// 已过时间、本轮目标时长、是否播完。脚本装载/卸载、模式切换（boot→shelf）、
/// 失败回退内置自检、Esc 跳过仍由 App 编排——本类不碰 Cartridge/Shell/Renderer。
class BootSequence {
public:
    /// 最短开机时长：脚本声明成 0/负数时按它兜底（与旧行为一致）
    static constexpr float kMinSeconds = 0.5f;

    /// 回到未开始状态（已过时间清零；目标时长保留上次值，直到下一次 start）
    void reset();

    /// 开始一轮：已过时间清零，duration 小于 kMinSeconds 时钳制（旧 start 的兜底）
    void start(float duration);

    /// 推进时钟；完成判定只看 elapsed >= duration（跳过键由 App 判断）
    void tick(float dt);
    bool finished() const { return elapsed_ >= duration_; }

    float elapsed() const { return elapsed_; }
    float duration() const { return duration_; }

private:
    float elapsed_ = 0.0f;
    float duration_ = kBootDuration;  // 未 start 前的默认 = 出厂时长（旧成员默认）
};

} // namespace phos
