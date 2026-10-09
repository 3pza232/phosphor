#pragma once

#include <cstddef>
#include <functional>
#include <string>
#include <string_view>

namespace phos::text {

/// 界面文本输入缓冲：**输入事件进入界面的唯一入口**。
///
/// 约定：过滤、退格、限长、计数都在这里，界面只管取 value()。
/// 这样"删除一个字符"只有一处实现（按码点删，中文不会被删成半个序列），
/// 删除事件也只有一处定义（text::kBackspace）。
class TextInput {
public:
    /// 决定某个码点能否进入缓冲（如十六进制过滤器）；传 nullptr 表示全收
    using Filter = std::function<bool(char32_t)>;

public:
    /// 常用过滤器。放在这里而不是各调用点：同一语义只该有一处实现——
    /// 主机界面的磁带码输入与卡带的 `phos.input.field` 都取这一份。
    static bool accept_any(char32_t) { return true; }
    static bool accept_printable(char32_t cp) { return cp >= 32 && cp != 127; }
    static bool accept_ascii(char32_t cp) { return cp < 128; }
    static bool accept_digits(char32_t cp) { return cp >= U'0' && cp <= U'9'; }
    static bool accept_letters(char32_t cp) {
        return (cp >= U'a' && cp <= U'z') || (cp >= U'A' && cp <= U'Z');
    }
    static bool accept_hex(char32_t cp) {
        return accept_digits(cp) || (cp >= U'a' && cp <= U'f') || (cp >= U'A' && cp <= U'F');
    }

    /// max_chars 按**码点**计（不是字节）：中文与半角字符同样算一个；0 = 不限
    explicit TextInput(Filter accept = nullptr, size_t max_chars = 0);

    /// 消费一帧的输入文本：逐码点过滤追加，遇退格则删掉末尾一个码点
    void apply(std::string_view typed);

    void clear() { value_.clear(); count_ = 0; }
    /// 缓冲内容（UTF-8，永远是完整的码点序列）
    const std::string& value() const { return value_; }
    /// 已输入的**码点**数：画面上的"N 位"用它，用字节数会把中文算成 3 位
    size_t count() const { return count_; }
    bool empty() const { return value_.empty(); }

private:
    Filter accept_;
    size_t max_chars_;
    std::string value_;
    size_t count_ = 0;
};

} // namespace phos::text
