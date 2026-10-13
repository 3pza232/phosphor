#include "agent/cart_json.hpp"
#include "agent/cli.hpp"
#include "core/json_lite.hpp"
#include "cart/cart_scanner.hpp"
#include "core/app.hpp"
#include "core/log.hpp"
#include "core/version.hpp"
#include "devkit/api_check.hpp"
#include "devkit/packer.hpp"

#include <cstdio>
#include <string>

/// --scan：列出目录下的卡带（人读或 JSON）
static int run_scan(const std::string& dir, bool json) {
    auto carts = phos::scan_carts(dir);
    if (json) {
        // 字段集与控制通道共用一份实现（agent/cart_json.hpp）
        std::printf("{\"carts\":%s}\n", phos::cart_list_json(carts).c_str());
    } else {
        for (const auto& c : carts) {
            if (c.error.empty())
                std::printf("%-16s %-20s %s\n", c.id.c_str(), c.name.get(false).c_str(),
                            c.version.c_str());
            else
                std::printf("%-16s [损坏] %s\n", c.id.c_str(), c.error.c_str());
        }
    }
    return 0;
}

/// --pack：把卡带目录打包成 .phos
static int run_pack(const std::string& dir, const std::string& output, bool json) {
    phos::devkit::PackResult result;
    const bool ok = phos::devkit::pack_cart(dir, output, result);

    if (json) {
        std::printf("{\"ok\":%s,\"id\":\"%s\",\"output\":\"%s\",\"files\":%d,\"error\":%s%s%s}\n",
                    ok ? "true" : "false", phos::json::escape(result.cart_id).c_str(),
                    phos::json::escape(result.output_path).c_str(), result.file_count,
                    ok ? "null" : "\"", ok ? "" : phos::json::escape(result.error).c_str(),
                    ok ? "" : "\"");
    } else if (ok) {
        std::printf("packed %d files -> %s\n", result.file_count, result.output_path.c_str());
    } else {
        std::fprintf(stderr, "ERROR: %s\n", result.error.c_str());
    }
    return ok ? 0 : 2;
}

/// --check-api：校验注解文件与实装是否一致
static int run_check_api(const std::string& annotation_path, bool json) {
    const phos::devkit::ApiCheckResult result = phos::devkit::check_api(annotation_path);
    if (!result.error.empty()) {
        std::fprintf(stderr, "ERROR: %s\n", result.error.c_str());
        return 2;
    }

    if (json) {
        auto list = [](const std::vector<std::string>& items) {
            std::string out = "[";
            for (size_t i = 0; i < items.size(); ++i)
                out += (i ? "," : "") + phos::json::quote(items[i]);
            return out + "]";
        };
        std::printf("{\"ok\":%s,\"annotation\":\"%s\",\"implemented\":%d,\"documented\":%d,"
                    "\"undocumented\":%s,\"unimplemented\":%s}\n",
                    result.consistent() ? "true" : "false",
                    phos::json::escape(annotation_path).c_str(), result.implemented,
                    result.documented, list(result.undocumented).c_str(),
                    list(result.unimplemented).c_str());
    } else {
        std::printf("注解文件: %s（已注册 %d 项，注解里写了 %d 项）\n", annotation_path.c_str(),
                    result.implemented, result.documented);
        if (!result.undocumented.empty()) {
            std::printf("已实现但注解里没有：\n");
            for (const auto& name : result.undocumented)
                std::printf("  - %s\n", name.c_str());
        }
        if (!result.unimplemented.empty()) {
            std::printf("注解里写了但没实现：\n");
            for (const auto& name : result.unimplemented) std::printf("  - %s\n", name.c_str());
        }
        if (result.consistent()) std::printf("一致：OK\n");
    }
    return result.consistent() ? 0 : 2;
}

/// --new：从 DevKit 模板生成卡带骨架（--id / --name / --author 在这里一次命名）
static int run_create(const phos::CliOptions& opts, const std::string& template_dir) {
    // 卡带默认落在"当前目录下的 carts/"里——正常启动（双击或从安装目录运行）时，
    // 当前目录就是 exe 所在目录，于是 `--new mygame` 等价于 `--new carts/mygame`。
    // 只给名字就够，不必自己拼 carts/；要放到别处就传带路径的形式。
    std::string target = *opts.create;
    const bool bare_name = target.find('/') == std::string::npos &&
                           target.find('\\') == std::string::npos;
    if (bare_name) target = "carts/" + target;

    // 建卡时能定的身份一次填好：id / 标题 / 作者；留空的走默认值
    phos::devkit::ScaffoldInfo info;
    info.id = opts.id.value_or("");
    info.name = opts.name.value_or("");
    info.author = opts.author.value_or("");

    std::string error;
    int files = 0;
    const bool ok = phos::devkit::scaffold_cart(template_dir, target, info, files, error);

    if (opts.json) {
        std::printf("{\"ok\":%s,\"target\":\"%s\",\"template\":\"%s\",\"files\":%d,\"error\":%s%s%s}\n",
                    ok ? "true" : "false", phos::json::escape(target).c_str(),
                    phos::json::escape(template_dir).c_str(), files, ok ? "null" : "\"",
                    ok ? "" : phos::json::escape(error).c_str(), ok ? "" : "\"");
    } else if (ok) {
        std::printf("created cart skeleton at %s   (%d file(s))\n", target.c_str(), files);
    } else {
        std::fprintf(stderr, "ERROR: %s\n", error.c_str());
    }
    return ok ? 0 : 2;
}

#ifdef _WIN32
#include <windows.h>

/// GUI 子系统下双击启动无控制台；从终端启动时附加父终端，保留 CLI 输出。
/// 注意：stdout 已被重定向（管道/文件）时不得附加，否则输出丢失。
static void attach_parent_console() {
    HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD type = out ? GetFileType(out) : FILE_TYPE_UNKNOWN;
    bool redirected = (type == FILE_TYPE_PIPE || type == FILE_TYPE_DISK);
    if (!redirected && AttachConsole(ATTACH_PARENT_PROCESS)) {
        std::freopen("CONOUT$", "w", stdout);
        std::freopen("CONOUT$", "w", stderr);
        std::freopen("CONIN$", "r", stdin);
    }
}
#else
static void attach_parent_console() {}
#endif

int main(int argc, char** argv) {
    attach_parent_console();

    phos::CliOptions opts;
    if (auto err = phos::parse_cli(argc, argv, opts)) {
        if (*err == phos::kVersionRequest) {
            std::printf("%s %s\n", phos::kProductName, phos::kVersion);
            return 0;
        }
        if (*err == phos::kHelpRequest) {
            std::printf(
                "PHOSPHOR —— ASCII 幻想游戏机\n"
                "用法：phosphor [选项]\n"
                "\n"
                "运行：\n"
                "  --cart <路径>        直接载入卡带（目录或 .phos）\n"
                "  --headless           不开窗口运行\n"
                "  --frames <N>         跑完 N 个逻辑帧后退出\n"
                "  --dump-screen        退出时打印屏幕文本\n"
                "  --dump-every <N>     每 N 帧打印一次屏幕\n"
                "  --screenshot <路径>  退出时把画面存成 PNG（无头模式同样可用）\n"
                "  --seed <n>           固定随机种子\n"
                "  --control <端口>     打开控制通道（本地 TCP 上的 NDJSON）\n"
                "  --log <文件>         写主机日志（时间戳 + 帧号）\n"
                "\n"
                "开发套件：\n"
                "  --scan <目录>        列出卡带后退出\n"
                "  --pack <目录>        把卡带目录打包成 .phos 后退出\n"
                "  --out <文件>         打包输出路径（默认 dist/<id>.phos）\n"
                "  --new <名字|目录>    生成卡带骨架（只给名字时落在 carts/<名字>）\n"
                "  --id <名字>          --new 的卡带 id（默认取目录名）\n"
                "  --name <标题>        --new 的卡带标题（默认与 id 相同）\n"
                "  --author <作者>      --new 的卡带作者（默认取模板里的值）\n"
                "  --save-dir <目录>    存档目录（默认 saves）\n"
                "  --config <文件>      配置路径（默认 config.json；测试据此隔离实测配置）\n"
                "  --check-api          核对 devkit/phos.lua 与已注册 API 是否一致\n"
                "  --json               机器可读输出\n"
                "\n"
                "信息：\n"
                "  --version            打印版本后退出\n"
                "  --help, -h           打印本说明\n"
                "\n"
                "退出码：0 正常 | 1 参数错误 | 2 载入/校验失败 | 3 内部错误\n");
            return 0;
        }
        std::fprintf(stderr, "ERROR: %s\n(--help for usage)\n", err->c_str());
        return 1;
    }

    // 日志：所有命令（含 devkit）共用。落盘失败不致命——日志是辅助，不该挡住正事
    if (opts.log_file && !phos::log::open_file(*opts.log_file))
        std::fprintf(stderr, "WARN: cannot write log file %s\n", opts.log_file->c_str());
    phos::log::info("argv: " + phos::log::joined_argv(argc, argv));

    if (opts.scan) return run_scan(*opts.scan, opts.json);
    if (opts.pack) return run_pack(*opts.pack, opts.out.value_or(""), opts.json);
    if (opts.create) return run_create(opts, "devkit/template");
    if (opts.check_api) return run_check_api("devkit/phos.lua", opts.json);

    phos::App app;
    return app.run(opts);
}
