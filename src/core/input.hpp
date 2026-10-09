#pragma once

#include <array>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

namespace phos {

/// 虚拟手柄按键。物理键盘/手柄/Agent 注入的输入统一映射到这里。
enum class Key {
    left, right, up, down,
    a, b, x, y,
    start, select,
    count
};

/// 全部虚拟手柄按键及其键名（顺序即状态汇报与界面遍历的顺序）。
/// "需要遍历所有键"的地方（按键音、状态汇报、held_keys、键名解析）共用这一份：
/// 加一个键只改这里，不会漏掉某处而静默少一个键。
inline constexpr std::array<std::pair<Key, const char*>, 10> kAllKeys{{
    {Key::left, "left"},   {Key::right, "right"}, {Key::up, "up"},     {Key::down, "down"},
    {Key::a, "a"},         {Key::b, "b"},         {Key::x, "x"},       {Key::y, "y"},
    {Key::start, "start"}, {Key::select, "select"},
}};

/// 虚拟键名 → Key 枚举（"left"/"a"/"start" 等），未知名称返回 nullopt
std::optional<Key> key_from_name(const std::string& name);

/// 该按键的**主键名**：键盘上真正该按的那个键（"A"/"ENTER"/"SHIFT"/"LEFT"…）。
/// 卡带用 phos.input.key_name() 取它来写操作提示——主机没有手柄，
/// 界面上要写就写键盘键，否则提示就是在说谎。
/// 与 `platform/window.cpp` 的 map_key 主键一一对应：改那里就要改这里。
std::string key_primary_name(Key key);

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

/// 一条输入动作：虚拟手柄按键，或主机保留键。
/// 唯一的注入通道（agent 的控制通道）经它落地，
/// 于是"能把哪些键按下去"在玩家与 agent 之间必然一致。
struct InputAction {
    std::optional<Key> key;  // 虚拟手柄按键（主机保留键时为空）
    bool down = true;
    std::string host_key;    // 主机保留键名（空 = 不是主机键）
};

/// 键名 → 输入动作；无法识别时返回 nullopt（调用方负责报错，不静默忽略）
std::optional<InputAction> input_action_from(std::string_view name, bool down);

/// 统一输入状态。多源输入在此汇流，消费者无从分辨来源。
/// 使用方式：每帧末尾调用 next_frame() 推进边沿检测。
class Input {
public:
    /// 注入输入（键盘回调、agent 控制通道共用此入口）
    void set_key(Key key, bool down);
    /// 注入一段输入文本（UTF-8，可含多字节字符；退格以 '\b' 表示）
    void push_text(std::string text);

    bool down(Key key) const { return cur_[index(key)]; }
    bool pressed(Key key) const { return cur_[index(key)] && !prev_[index(key)]; }
    bool released(Key key) const { return !cur_[index(key)] && prev_[index(key)]; }

    /// 本帧输入的文本（UTF-8，无则空串）。
    /// 语义是"本帧"：next_frame() 会清空，因此卡带在 update 里读到的就是这一帧新输入的字符。
    /// 可含多字节字符与退格 '\b'。
    const std::string& text() const { return text_; }

    void next_frame() {
        prev_ = cur_;
        text_.clear();
    }
    void release_all();

private:
    static constexpr size_t index(Key key) { return static_cast<size_t>(key); }

    std::array<bool, static_cast<size_t>(Key::count)> cur_{};
    std::array<bool, static_cast<size_t>(Key::count)> prev_{};
    std::string text_;
};

} // namespace phos
