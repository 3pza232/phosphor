#pragma once

#include "core/defaults.hpp"
#include "pack/pack.hpp"

#include <string>
#include <vector>

namespace phos {

/// 字体方案状态（从 App 抽出的内聚子系统）：
/// 内容目录里有哪些方案、当前生效哪一个、当前方案声明的字号与可调范围、字体链路径。
/// 只管状态与解析；把字号推给 Renderer / 调整 Window / 改配置 / 重建字形图集仍归 App。
class FontState {
public:
    /// 出厂默认方案名（字体目录约定，见 pack 的 scan_font_schemes）
    static constexpr const char* kDefaultScheme = "default";

    /// 扫描方案目录（theme/font）：default 排最前；目录缺失 = 空列表。
    /// 目录同时保存下来，供 load_chain 处理"方案不在表里但盘上存在"的兜底
    void scan(const std::string& font_dir);

    /// 选定方案：优先用扫描结果里的声明（字号/范围/回退顺序）；表里没有则现查目录文件。
    /// 字体链为空且不是 default 时退回 default 并告警；仍为空只告警（内容坏了也不该没字可用）
    void load_chain(const std::string& wanted);

    /// 生效字号：用户显式设置优先，否则方案声明，再否则出厂默认（用户值夹进可调范围）
    int effective_px(int configured_px) const;
    /// 夹到当前方案声明的可调范围（设置界面上下调 / 控制通道写值共用）
    int clamp_px(int px) const;

    /// 全部方案名（default 排最前，供设置界面与控制通道 JSON）
    const std::vector<std::string>& names() const { return names_; }
    /// 当前字体链（主字体在前、回退在后；渲染器与截图/基线共用）
    const std::vector<std::string>& files() const { return files_; }
    /// 实际生效的方案名（配置指定不可用时已退回 default）
    const std::string& current() const { return current_; }
    int min_px() const { return min_px_; }
    int max_px() const { return max_px_; }

private:
    std::vector<FontScheme> schemes_;  // 全部方案（含各自声明的字号与回退顺序）
    std::vector<std::string> names_;   // 方案名列表
    std::vector<std::string> files_;   // 当前字体链
    std::string font_dir_;             // 扫描目录（load_chain 兜底现查用）
    std::string current_ = kDefaultScheme;
    int scheme_px_ = 0;                // 当前方案声明的字号（0 = 未声明）
    int min_px_ = kMinFontPx;          // 当前方案声明的可调下限
    int max_px_ = kMaxFontPx;          // 当前方案声明的可调上限（Mod 覆盖 font.lua 即可抬高）
};

} // namespace phos
