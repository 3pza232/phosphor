#pragma once

#include <map>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace phos::json {

/// 极简 JSON 工具：控制通道与配置读取共用同一份实现。
/// 取舍：只需要"输出任意 JSON + 解析对象"，因此刻意不引入第三方 JSON 库，
/// 宿主保持零外部解析依赖。嵌套对象会递归解析（配置文件需要），数组跳过。

/// 字符串转义（不含引号）
std::string escape(std::string_view text);

/// 带引号的 JSON 字符串
std::string quote(std::string_view text);

/// JSON 对象。值类型为 string / number / bool / null / 嵌套对象（数组跳过）。
class Object {
public:
    /// 解析形如 {...} 的对象；失败返回 false 并填 err
    bool parse(std::string_view text, std::string& err);

    bool has(std::string_view key) const;
    std::string str(std::string_view key, std::string_view fallback = "") const;
    double num(std::string_view key, double fallback = 0.0) const;
    int integer(std::string_view key, int fallback = 0) const;

    /// 布尔读取：接受 true/false，以及字符串 "1"/"true"/"down"/"on"/"yes"（其余算 false）
    bool flag(std::string_view key, bool fallback = false) const;

    /// 嵌套对象；键不存在或不是对象时返回 nullptr
    const Object* object(std::string_view key) const;

    /// 上一次 parse 中重复出现的键。"一个键只写一次"的配置文件据此提醒用户
    const std::vector<std::string>& duplicate_keys() const { return duplicates_; }

private:
    enum class Kind { string, number, boolean, null, object };

    struct Entry {
        Kind kind = Kind::null;
        std::string text;
        double number = 0.0;
        bool boolean = false;
        std::shared_ptr<Object> object;  // Kind::object：嵌套对象
    };

    std::map<std::string, Entry> values_;
    std::vector<std::string> duplicates_;
};

} // namespace phos::json
