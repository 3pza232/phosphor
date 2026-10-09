#pragma once

#include <string>
#include <vector>

namespace phos::devkit {

/// API 注解一致性校验结果。
///
/// 校验对象是"主机实际注册的 phos.*"与"注解文件声明的 phos.*"。
/// 覆盖函数与子表（双向），并对 `---@class` 配对的 `@field` 做单向核对：
/// 只查"注解承诺了、实现却没有"，避免 `phos.screen.width` 这类空头支票。
struct ApiCheckResult {
    std::vector<std::string> undocumented;   // 已实装但注解缺失
    std::vector<std::string> unimplemented;  // 注解已声明但未实装
    int implemented = 0;
    int documented = 0;
    std::string error;  // 致命问题（注解文件读不到）

    bool consistent() const {
        return error.empty() && undocumented.empty() && unimplemented.empty();
    }
};

/// 在空沙箱中注册主机 API 并与注解文件（devkit/phos.lua）比对
ApiCheckResult check_api(const std::string& annotation_path);

} // namespace phos::devkit
