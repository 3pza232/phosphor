#pragma once

#include <map>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace phos::json {

/// 极简 JSON 工具：控制通道、联机、配置读取与存档容器共用同一份实现。
/// 取舍：只需要"输出任意 JSON + 解析"，因此刻意不引入第三方 JSON 库，
/// 宿主保持零外部解析依赖。字符串按 **UTF-8 + 标准 JSON 转义**处理：\uXXXX（含代理对）
/// 解码成 UTF-8，输出时控制字符与非法字节一律转义，绝不产出坏 JSON。
/// Value 是完整值树（对象/数组可嵌套，存档与通用读写用）；Object 是只读对象视图
/// （控制通道与配置的既有 API）。两者共用同一套转义、数字文法与递归解析。

/// 字符串转义（不含引号）。输入按 UTF-8 解读：
/// 合法码点原样保留（非 ASCII 不转义），控制字符改写为 \uXXXX，
/// 非法 UTF-8 与孤立代理改写为 \uFFFD——输出永远是合法 JSON。
std::string escape(std::string_view text);

/// 带引号的 JSON 字符串
std::string quote(std::string_view text);

/// 通用 JSON 值：null / 布尔 / 数字 / 文本 / 数组 / 对象。
/// 解析严格（数字文法、转义、嵌套深度上限、整串消费）；序列化稳定（对象键升序、
/// 数字 17 位有效数字可无损回读），因此同一份数据每次落盘的字节完全一致。
struct Value {
    enum class Kind { null, boolean, number, text, array, object };

    Kind kind = Kind::null;
    bool boolean = false;
    double number = 0.0;
    std::string text;                      // Kind::text
    std::vector<Value> items;              // Kind::array
    std::map<std::string, Value> members;  // Kind::object（升序 = 稳定输出）

    /// 解析诊断：该对象节点里重复出现的键（dump 忽略；配置文件据此提醒用户）
    std::vector<std::string> duplicate_keys;

    /// 值嵌套层数上限（含顶层）：不可信输入可能上千层嵌套，递归解析会爆栈
    static constexpr int kMaxDepth = 64;

    static Value of_boolean(bool value) {
        Value out;
        out.kind = Kind::boolean;
        out.boolean = value;
        return out;
    }
    static Value of_number(double value) {
        Value out;
        out.kind = Kind::number;
        out.number = value;
        return out;
    }
    static Value of_text(std::string value) {
        Value out;
        out.kind = Kind::text;
        out.text = std::move(value);
        return out;
    }
    static Value of_array() {
        Value out;
        out.kind = Kind::array;
        return out;
    }
    static Value of_object() {
        Value out;
        out.kind = Kind::object;
        return out;
    }

    /// 解析任意 JSON 值（前后空白允许，必须整串消费）；失败返回 false 并填 err
    bool parse(std::string_view json_text, std::string& err);
    /// 序列化成 JSON 文本
    std::string dump() const;
};

/// JSON 对象视图（控制通道/配置读取用）。值类型为 string / number / bool / null /
/// 嵌套对象（数组只收字符串元素）。数字按 JSON 文法严格校验：`NaN` / `Infinity` /
/// 溢出成无穷的 `1e999` 都判解析错误。
class Object {
public:
    /// 对象嵌套层数上限（含顶层）：与 Value 同一上限
    static constexpr int kMaxDepth = Value::kMaxDepth;

    /// 解析形如 {...} 的对象；失败返回 false 并填 err
    bool parse(std::string_view text, std::string& err);

    bool has(std::string_view key) const;
    bool is_string(std::string_view key) const;
    bool is_number(std::string_view key) const;
    bool is_boolean(std::string_view key) const;
    std::string str(std::string_view key, std::string_view fallback = "") const;

    /// 整数读取：小数向零截断；超出 int 范围的数值钳到端点，非有限数取 fallback。
    /// （double → int 越界是未定义行为，所有窄化都必须先钳）
    int integer(std::string_view key, int fallback = 0) const;

    /// 浮点读取：本协议多数数值是整数，但少数需要小数（如 `debug.set` 的参数值）。
    /// `num` 是它的实现，公开出来给这些调用方用
    double number(std::string_view key, double fallback = 0.0) const;

    /// 布尔读取：接受 true/false，以及字符串 "1"/"true"/"down"/"on"/"yes"（其余算 false）
    bool flag(std::string_view key, bool fallback = false) const;

    /// 嵌套对象；键不存在或不是对象时返回 nullptr
    const Object* object(std::string_view key) const;

    /// 字符串数组读取：键不存在或不是数组时返回空表。
    /// 数组里的数字/布尔/文本按文本收（数字 `1000` → "1000"），嵌套对象/数组跳过
    std::vector<std::string> string_array(std::string_view key) const;

    /// 顶层键名（升序）。需要遍历对象的调用方（如存档容器）用它配合 str() 取值
    std::vector<std::string> keys() const;

    /// 上一次 parse 中重复出现的键。"一个键只写一次"的配置文件据此提醒用户
    const std::vector<std::string>& duplicate_keys() const { return duplicates_; }

private:
    enum class Kind { string, number, boolean, null, object, array };

    struct Entry {
        Kind kind = Kind::null;
        std::string text;
        double number = 0.0;
        bool boolean = false;
        std::shared_ptr<Object> object;  // Kind::object：嵌套对象
        std::vector<std::string> array;  // Kind::array：收集到的文本元素
    };

    /// 把值树折叠成本视图（递归；数组只留文本视图，嵌套对象转成子 Object）
    static void assign(const Value& value, Object& target);

    /// 原样取数（integer / number 的实现基础）
    double num(std::string_view key, double fallback = 0.0) const;

    std::map<std::string, Entry> values_;
    std::vector<std::string> duplicates_;
};

} // namespace phos::json
