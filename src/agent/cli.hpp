#pragma once

#include <optional>
#include <string>

namespace phos {

/// 命令行选项。解析见 agent-interface.md 规范。
struct CliOptions {
    std::optional<std::string> cart;    // 启动后直接加载的卡带
    std::optional<std::string> scan;    // 扫描目录列出卡带后退出
    std::optional<std::string> pack;    // 打包卡带目录为 .phos 后退出（DevKit）
    std::optional<std::string> out;     // 打包输出路径（缺省 <id>.phos）
    std::optional<std::string> create;  // 从模板新建卡带目录（DevKit）
    std::optional<std::string> save_dir;  // 存档目录（默认 saves/；工具脚本据此隔离）
    bool check_api = false;             // 校验 API 注解与实装是否一致
    std::optional<std::string> id;      // 新建卡带的 id（缺省取目录名）
    std::optional<std::string> name;    // 新建卡带的显示名（缺省与 id 相同）
    std::optional<std::string> author;  // 新建卡带的作者（缺省沿用模板里的占位作者）
    std::optional<int> control;         // 控制通道端口（本地 TCP，NDJSON）
    std::optional<std::string> log_file;  // 主机日志落盘路径（含时间戳与帧号）
    bool json = false;                  // 机器可读输出使用 JSON
    bool headless = false;              // 无窗口纯逻辑运行
    int frames = -1;                    // 运行 N 个逻辑帧后退出（-1 = 不限）
    bool dump_screen = false;           // 退出时打印屏幕文本
    std::optional<std::string> screenshot;  // 退出时把画面写成 PNG
    int dump_every = 0;                 // 每 N 帧打印一次屏幕（0 = 关闭）
    std::optional<unsigned> seed;       // 固定随机种子
};

/// --help 的哨兵返回值：解析本身没出错，但调用方应打印用法后退出
inline constexpr const char* kHelpRequest = "help";

/// 解析命令行。返回 nullopt = 成功；有值 = 失败（值即错误信息）；
/// 请求用法时返回 kHelpRequest
std::optional<std::string> parse_cli(int argc, char** argv, CliOptions& out);

} // namespace phos
