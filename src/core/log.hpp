#pragma once

#include <string>

namespace phos {

/// 主机日志。
///
/// 默认只走 stderr（`warn`/`error` 直接可见，`info` 不刷屏）；
/// 指定 `--log <file>` 后额外落盘，每条带**墙钟时间 + 当前逻辑帧号**，
/// 于是一段 agent 操作事后可以按时间线复盘：哪一帧插了卡、哪一帧改了设置。
///
/// info 只进文件（不刷屏），warn/error 始终同时打到 stderr。
namespace log {

/// 级别：info 只落盘，warn/error 同时打到 stderr
enum class Level { info, warn, error };

/// 打开日志文件（覆盖写入）。失败返回 false，调用方负责提示。
bool open_file(const std::string& path);
/// 关闭日志文件（未打开时为空操作）
void close();
/// 日志文件是否已打开（决定 info 是否落盘）
bool active();

/// 当前逻辑帧号：主机每帧更新一次，日志据此挂到时间线上
void set_frame(long frame);

/// 写一条日志（加锁；每条即时 flush，崩溃也不丢）
void write(Level level, const std::string& message);

/// 把命令行拼成一行（写进日志头部，便于整次运行的复现）
std::string joined_argv(int argc, char** argv);

inline void info(const std::string& message) { write(Level::info, message); }
inline void warn(const std::string& message) { write(Level::warn, message); }
inline void error(const std::string& message) { write(Level::error, message); }

} // namespace log

} // namespace phos
