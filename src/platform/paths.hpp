#pragma once

#include <string>

namespace phos::platform {

/// 当前可执行文件所在目录（末尾不带分隔符）。取不到时返回空串。
/// 用途：发行包"绿色免安装"的根目录判定——用户从桌面快捷方式/资源管理器启动时
/// 工作目录往往不是 exe 所在目录，内容包（theme/carts/devkit）应相对 exe 解析。
std::string executable_dir();

} // namespace phos::platform
