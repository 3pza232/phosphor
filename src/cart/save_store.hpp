#pragma once

#include "core/json_lite.hpp"

#include <map>
#include <optional>
#include <string>

namespace phos {

/// 卡带存档：saves/<卡带id>.sav，带版本/校验和的容器（格式 v2）。
///
/// 写入即落盘且**整份原子替换**：先写 <path>.tmp，flush/close 成功后再 rename 覆盖。
/// 掉电只会留下旧档或一份半成品 .tmp，不会把旧档截断成半份；写盘失败时内存回滚，
/// 保证"读到的 = 磁盘上的"，卡带不会被骗。
///
/// 值支持文本 / 数字 / 布尔 / 对象 / 数组（v2 正文就是一份 JSON 对象）；旧格式存档
/// （每行 key=value、无头部）继续可读，首次打开自动升级并保留 .v1 备份。
class SaveStore {
public:
    /// 存档值 = 通用 JSON 值：对象/数组可嵌套（Lua 表由 API 边界负责构造与拆解），
    /// 序列化稳定（对象键升序、数字可无损回读）。null 不是合法存档值。
    using Value = json::Value;

    /// 打开（读取已有存档）；同一对象可复用，先清空上次的内容。
    /// 目录建不出来/临时文件写不进时降级为只读：读取照常，写入返回 false——绝不让卡带
    /// 以为存下了。旧档存在却读不出时也按只读处理，避免用空数据覆盖未知内容。
    /// slot 0 = 默认档 `<id>.sav`；1..9 = `<id>.s{n}.sav`（槽位互相独立）
    bool open(const std::string& save_dir, const std::string& cart_id, int slot = 0);

    /// 文本视图（字符串原样、数字/布尔/对象/数组转 JSON 文本；旧调用方与磁带码用）
    std::optional<std::string> get(const std::string& key) const;

    /// 带类型的值（卡带写数字/布尔/表后原样取回）
    std::optional<Value> get_value(const std::string& key) const;
    size_t size() const { return data_.size(); }
    /// 写入并落盘；返回是否真的写进磁盘（键值越界、非法值、只读、I/O 失败都返回 false）
    bool set(const std::string& key, const Value& value);
    bool set(const std::string& key, const std::string& value) {
        return set(key, Value::of_text(value));
    }
    /// 删除并落盘；返回是否真的写进磁盘
    bool erase(const std::string& key);

    /// 磁带码：全部存档的十六进制编码（跨机器传档的复古载体）。
    /// 结构化值按其 JSON 文本导出，导入后成为文本值——码里只有 key=value 文本语义
    std::string export_code() const;

    /// 从磁带码恢复存档（**整份替换**现有数据）。
    /// 码非法（含非十六进制字符、键值越界、条目过多）或写盘失败时不做任何改动并返回 false。
    bool import_code(const std::string& code);

    static constexpr size_t kMaxKeyLength = 64;
    static constexpr size_t kMaxValueLength = 4096;
    static constexpr size_t kMaxEntries = 256;
    static constexpr int kMaxSlot = 9;

private:
    /// 整份原子写盘（临时文件 + rename）；返回是否成功（调用方据此向卡带回报真实结果）
    bool flush(const std::map<std::string, Value>& data) const;

    std::map<std::string, Value> data_;
    std::string path_;
    std::string cart_id_;
    bool writable_ = false;
};

/// 存档值的文本视图：文本原样，其余取 JSON 文本（磁带码与旧 get() 的语义）
std::string save_text(const SaveStore::Value& value);

} // namespace phos
