#pragma once

#include "core/defaults.hpp"

#include <algorithm>
#include <array>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace phos {

/// 内置的十颗"手柄键"。它们**只是预注册的键名**，没有特殊地位——
/// 之所以留一份枚举，是因为主机的界面（确认/取消、开机动画跳过）要用它们。
enum class Key {
    left, right, up, down,
    a, b, x, y,
    start, select,
    count
};

/// 枚举 ↔ 键名
inline constexpr std::array<const char*, 10> kBuiltinKeyNames{{
    "left", "right", "up", "down", "a", "b", "x", "y", "start", "select",
}};
inline const char* key_name(Key key) { return kBuiltinKeyNames[static_cast<size_t>(key)]; }

/// 该键名在键盘上对应的**显示名**（"A" / "SPACE" / "ENTER" / "," …）。
/// 卡带用它写操作提示——主机没有手柄，提示上就该写键盘上的那个键。
std::string key_display_name(std::string_view name);

/// 一条输入动作：虚拟键名，或主机保留键。
/// 唯一的注入通道（agent 的控制通道）经它落地，
/// 于是"能把哪些键按下去"在玩家与 agent 之间必然一致。
struct InputAction {
    std::string key;         // 虚拟键名（空 = 主机保留键）
    bool down = true;
    std::string host_key;    // 主机保留键名（空 = 不是主机键）
};

/// 主机保留键：不进入虚拟手柄，只作用于主机自身，卡带读不到它们。
/// 因此 agent 与玩家在这些键上拥有同等能力。
///   escape    Esc —— 返回 / 暂停 / 关机（跨全部模式）
///   settings  F2  —— 打开设置。**不用字母键**：字母会被卡带的文本输入吃掉
inline constexpr const char* kHostKeyEscape = "escape";
inline constexpr const char* kHostKeySettings = "settings";

/// 名称是否是主机保留键
inline bool is_host_key(const std::string& name) {
    return name == kHostKeyEscape || name == kHostKeySettings;
}

/// 键名 → 输入动作；无法识别时返回 nullopt（调用方负责报错，不静默忽略）
std::optional<InputAction> input_action_from(std::string_view name, bool down);

/// 统一输入状态。多源输入在此汇流，消费者无从分辨来源。
/// 使用方式：每帧末尾调用 next_frame() 推进边沿检测。
///
/// **键是名字，不是枚举**：内置十颗先注册，之后任何名字（"space"/"k"/"z"/"f1"/"1"…）
/// 在第一次被按到或第一次被查询时自动登记。卡带想要新键、甚至想做"自定义按键"，
/// 都不需要动主机代码，更不需要重编译——主机不认识"这个键是干嘛的"，
/// 它只知道"有个键叫这个名字，现在是按下还是松开"。
class Input {
public:
    Input() : names_(kBuiltinKeyNames.begin(), kBuiltinKeyNames.end()) {
        cur_.assign(names_.size(), false);
        prev_.assign(names_.size(), false);
        down_at_.assign(names_.size(), -1.0f);  // 内置键是预注册的，不走 slot()
        down_edge_.assign(names_.size(), false);
        up_edge_.assign(names_.size(), false);
    }

    /// 注入输入（键盘回调、agent 控制通道共用此入口）
    void set_key(std::string_view name, bool down);
    void set_key(Key key, bool down) { set_key(key_name(key), down); }
    /// 注入一段输入文本（UTF-8，可含多字节字符；退格以 '\b' 表示）
    void push_text(std::string text);

    bool down(std::string_view name) const { return at(name, cur_); }
    /// 边沿判定含**帧内锁存**（见 set_key）：一次"按下又松开"若整好落在同一逻辑帧里，
    /// 帧末 cur_ 已回到 false、prev_ 也是 false，仅凭 cur/prev 会整个漏掉这次点按。
    /// 多源输入（键盘回调、控制通道注入）都可能在一帧内完成一次点按，故用锁存兜住。
    bool pressed(std::string_view name) const {
        const int i = find(name);
        if (i < 0) return false;
        const size_t k = static_cast<size_t>(i);
        return (cur_[k] && !prev_[k]) || down_edge_[k];
    }
    bool released(std::string_view name) const {
        const int i = find(name);
        if (i < 0) return false;
        const size_t k = static_cast<size_t>(i);
        return (!cur_[k] && prev_[k]) || up_edge_[k];
    }

    bool down(Key key) const { return down(key_name(key)); }
    bool pressed(Key key) const { return pressed(key_name(key)); }
    bool released(Key key) const { return released(key_name(key)); }

    /// 该键已按住的秒数（松开或没按过 = 0）。按**逻辑帧**累计，
    /// 于是"越按越快"这类手感不必由卡带自己攒计时
    float duration(std::string_view name) const;

    /// 目前见过的所有键名（内置的排在最前）。状态汇报与"按键提示"用它遍历
    const std::vector<std::string>& names() const { return names_; }

    /// 本帧新按下的第一个键名（无则空串）：给"让玩家按一个键来完成绑定"用
    std::string any_pressed() const;

    /// 本帧输入的文本（UTF-8，无则空串）。
    /// 语义是"本帧"：next_frame() 会清空，因此卡带在 update 里读到的就是这一帧新输入的字符。
    /// 可含多字节字符与退格 '\b'。
    const std::string& text() const { return text_; }

    void next_frame() {
        prev_ = cur_;
        std::fill(down_edge_.begin(), down_edge_.end(), false);
        std::fill(up_edge_.begin(), up_edge_.end(), false);
        text_.clear();
        clock_ += 1.0f / static_cast<float>(kLogicFps);
    }
    void release_all();

private:
    /// 查已有槽位，没有返回 -1（查询不该有副作用，否则"读一下状态"会造出新键）
    int find(std::string_view name) const;
    /// 取槽位，没有就建（登记会同步扩容 cur_/prev_）
    int slot(std::string_view name);
    bool at(std::string_view name, const std::vector<bool>& set) const {
        const int i = find(name);
        return i >= 0 && set[static_cast<size_t>(i)];
    }

    std::vector<std::string> names_;
    std::vector<bool> cur_{};
    std::vector<bool> prev_{};
    std::vector<bool> down_edge_{};  // 本帧是否"按下过"（含帧内按下即松开）
    std::vector<bool> up_edge_{};    // 本帧是否"松开过"（含帧内按下即松开）
    std::vector<float> down_at_{};  // 每个键最近一次按下的时刻（<0 = 松着）
    float clock_ = 0.0f;            // 逻辑帧时钟（见 next_frame）
    std::string text_;
};

} // namespace phos
