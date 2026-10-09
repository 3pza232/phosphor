#pragma once

#include <map>
#include <optional>
#include <string>

namespace phos {

/// 卡带存档：saves/<卡带id>.sav，键值对文本。
/// 写入即落盘（write-through），卡带崩溃不丢最近一次存档。
///
/// 入库约束（写入与磁带码导入共用）：键非空、键长 ≤ 64 且不含 '=' 与换行，
/// 值长 ≤ 4096 且不含换行，条目数 ≤ 256。
class SaveStore {
public:
    /// 打开（读取已有存档）。
    /// save_dir 建不出来时降级为只读：读取照常，写入返回 false——绝不让卡带以为存下了。
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
    /// 码非法（含非十六进制字符、键值越界、条目过多）时不做任何改动并返回 false。
    bool import_code(const std::string& code);

    static constexpr size_t kMaxKeyLength = 64;
    static constexpr size_t kMaxValueLength = 4096;
    static constexpr size_t kMaxEntries = 256;

private:
    /// 整份写盘；返回是否成功（调用方据此向卡带回报真实结果）
    bool flush() const;

    std::map<std::string, std::string> data_;
    std::string path_;
    bool writable_ = false;
};

} // namespace phos
