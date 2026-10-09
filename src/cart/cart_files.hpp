#pragma once

#include <optional>
#include <string>
#include <vector>

namespace phos {

/// 卡带文件访问：统一"目录卡带"（开发期散装）与".phos 卡带"（zip 单文件）。
///
/// 两级查找：`mods/<卡带id>/<路径>` 覆盖层优先，其次包内本体。
/// `manifest.lua` 例外——卡带身份（id/entry）不允许被 mod 改写，否则
/// 扫描、打包与运行时会对同一张卡带产生不同认知。
///
/// 路径越界（`..`、绝对路径、盘符）一律拒绝。
class CartFiles {
public:
    /// cart_path 指向目录或 .phos 文件；非法路径返回空 CartFiles（valid() == false）
    static CartFiles open(const std::string& cart_path);

    bool valid() const { return valid_; }

    /// 读取包内文件全文（经 mods 覆盖层）；不存在或越界返回 nullopt
    std::optional<std::string> read(const std::string& inner_path) const;

    /// 文件是否存在
    bool exists(const std::string& inner_path) const;

    /// 包内条目列表（'/' 分隔，含前缀过滤，已排序；不含 mods 新增文件）
    std::vector<std::string> entries(const std::string& prefix = "") const;

    /// 覆盖层目录（`mods/<卡带id>`），无 mods 时为空串
    const std::string& mod_dir() const { return mod_dir_; }

private:
    static bool path_safe(const std::string& inner_path);
    /// 包内本体读取（不含 mods 覆盖）
    std::optional<std::string> read_packed(const std::string& inner_path) const;

    bool valid_ = false;
    bool is_zip_ = false;
    std::string cart_path_;
    std::string mod_dir_;
};

} // namespace phos
