#pragma once

#include <map>
#include <optional>
#include <string>

namespace phos {

/// 卡带存档：saves/<卡带id>.sav，键值对文本（既有存档直接可读）。
///
/// 写入即落盘且**整份原子替换**：先写 <path>.tmp，flush/close 成功后再 rename 覆盖。
/// 掉电只会留下旧档或一份半成品 .tmp，不会把旧档截断成半份；写盘失败时内存回滚，
/// 保证"读到的 = 磁盘上的"，卡带不会被骗。
///
/// 入库约束（写入与磁带码导入共用）：键非空、键长 ≤ 64 且不含 '=' 与换行，
/// 值长 ≤ 4096 且不含换行，条目数 ≤ 256。
class SaveStore {
public:
    /// 打开（读取已有存档）；同一对象可复用，先清空上次的内容。
    /// 目录建不出来/临时文件写不进时降级为只读：读取照常，写入返回 false——绝不让卡带
    /// 以为存下了。旧档存在却读不出时也按只读处理，避免用空数据覆盖未知内容。
    bool open(const std::string& save_dir, const std::string& cart_id);

    std::optional<std::string> get(const std::string& key) const;
    size_t size() const { return data_.size(); }
    /// 写入并落盘；返回是否真的写进磁盘（键值越界、只读、I/O 失败都返回 false）
    bool set(const std::string& key, const std::string& value);
    /// 删除并落盘；返回是否真的写进磁盘
    bool erase(const std::string& key);

    /// 磁带码：全部存档的十六进制编码（跨机器传档的复古载体）
    std::string export_code() const;

    /// 从磁带码恢复存档（**整份替换**现有数据）。
    /// 码非法（含非十六进制字符、键值越界、条目过多）或写盘失败时不做任何改动并返回 false。
    bool import_code(const std::string& code);

    static constexpr size_t kMaxKeyLength = 64;
    static constexpr size_t kMaxValueLength = 4096;
    static constexpr size_t kMaxEntries = 256;

private:
    /// 整份原子写盘（临时文件 + rename）；返回是否成功（调用方据此向卡带回报真实结果）
    bool flush(const std::map<std::string, std::string>& data) const;

    std::map<std::string, std::string> data_;
    std::string path_;
    bool writable_ = false;
};

} // namespace phos
