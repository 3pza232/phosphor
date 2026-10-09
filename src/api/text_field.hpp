#pragma once

#include "core/text_input.hpp"

#include <cstddef>
#include <string>
#include <utility>

namespace phos {

/// 卡带可见的文本输入框（Lua 侧 `phos.input.field`）。
///
/// 与主机界面（磁带码输入）共用同一套 `text::TextInput`：过滤、按码点退格、
/// 限长都在主机侧完成，卡带只读 `value()`。于是"删掉一个字符"全机只有一处实现——
/// 按码点删，中文不会被删成半个序列。
///
/// 卡带侧用法：
///   local field = phos.input.field({ filter = "hex", max = 64 })
///   function update(dt) field:feed() end   -- 同一帧多次调用是幂等的
///   ... field.value / field.count / field:clear()
class CartTextField {
public:
    CartTextField(text::TextInput::Filter accept, std::size_t max_chars)
        : input_(std::move(accept), max_chars) {}

    /// 消费"本帧"输入文本。`now` 是主机的卡带运行秒数：同一帧内重复调用幂等
    /// （`Input::text()` 的语义本来就是"本帧文本"），卡带不必小心调用次数。
    void feed(double now, const std::string& typed) {
        if (last_feed_time_ == now) return;
        last_feed_time_ = now;
        input_.apply(typed);
    }

    void clear() { input_.clear(); }
    const std::string& value() const { return input_.value(); }
    std::size_t count() const { return input_.count(); }

private:
    text::TextInput input_;
    double last_feed_time_ = -1.0;
};

} // namespace phos
