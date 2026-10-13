#pragma once

#include <optional>
#include <string>
#include <vector>

namespace phos {

/// 卡带文件访问：统一"目录卡带"（开发期散装）与".phos 卡带"（zip 单文件）。
///
/// 两级查找：覆盖层 Mod（`mods/<任意名>/overrides/<卡带id>/<路径>`）优先，其次包内本体。
/// 覆盖层的解析见 core/mods.hpp（pack/ 与 cart/ 共用同一处）。
/// `manifest.lua` 例外——卡带身份（id/entry）不允许被 mod 改写，否则
/// 扫描、打包与运行时会对同一张卡带产生不同认知。
///
/// 路径越界（`..`、绝对路径、盘符）一律拒绝。
class CartFiles {
public:
    /// cart_path 指向目录或 .phos 文件；非法路径返回空 CartFiles（valid() == false）
    static CartFiles open(const std::string& cart_path);

    bool valid() const { return valid_; }

    /// 读取包内文件全文（经 mods 覆盖层）；不存在、越界、或超过单文件大小上限时返回 nullopt。
    /// 上限见实现里的 kMaxReadBytes——一张超大素材不该无声地把 Lua 堆撑爆
    std::optional<std::string> read(const std::string& inner_path) const;

    /// 文件是否存在（只 stat / 查目录项，**不读全文**，所以超大文件也如实报告存在）
    bool exists(const std::string& inner_path) const;

    /// 文件字节数（只 stat / 查目录项，不读全文）；不存在或越界返回 nullopt
    std::optional<std::size_t> size(const std::string& inner_path) const;

    /// 包内条目列表（'/' 分隔，含前缀过滤，已排序；不含 mods 新增文件）
    std::vector<std::string> entries(const std::string& prefix = "") const;

private:
    static bool path_safe(const std::string& inner_path);
    /// 包内本体读取（不含 mods 覆盖）
    std::optional<std::string> read_packed(const std::string& inner_path) const;

    bool valid_ = false;
    bool is_zip_ = false;
    std::string cart_path_;
    std::string cart_id_;  // 卡带 id：覆盖层按 `mods/<任意名>/overrides/<cart_id>/…` 查找
};

} // namespace phos
