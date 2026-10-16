#pragma once

namespace phos {

/// 重启本进程：起一个**新实例**（工作目录 = 当前），随后由调用方让主循环正常退出。
/// 用于"改动的 Mod 启用集需要重启才生效"这类场景（见 shell 的 MODS 浮窗）。
///
/// 返回是否成功发起新进程；失败只记日志、返回 false（绝不抛）——调用方照常退出即可，
/// 用户手动重启也能达到同样效果。非 Windows 平台没有可移植的"原样重启"，如实记日志。
bool relaunch_self();

} // namespace phos
