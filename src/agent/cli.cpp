#include "agent/cli.hpp"

#include <cstring>

namespace phos {

// 约定：返回 nullopt = 解析成功；**有值 = 出错**（值就是要给用户看的错误信息）。
// 例外是 --help 与 --version：它们返回哨兵，由 main 特判后打印并退出
std::optional<std::string> parse_cli(int argc, char** argv, CliOptions& out) {
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        auto need_value = [&](const char* name) -> std::optional<std::string> {
            if (i + 1 >= argc)
                return std::string("option ") + name + " requires a value";
            return std::nullopt;
        };

        if (arg == "--headless") {
            out.headless = true;
        } else if (arg == "--dump-screen") {
            out.dump_screen = true;
        } else if (arg == "--screenshot") {
            if (auto err = need_value("--screenshot")) return err;
            out.screenshot = argv[++i];
        } else if (arg == "--cart") {
            if (auto err = need_value("--cart")) return err;
            out.cart = argv[++i];
        } else if (arg == "--scan") {
            if (auto err = need_value("--scan")) return err;
            out.scan = argv[++i];
        } else if (arg == "--pack") {
            if (auto err = need_value("--pack")) return err;
            out.pack = argv[++i];
        } else if (arg == "--out") {
            if (auto err = need_value("--out")) return err;
            out.out = argv[++i];
        } else if (arg == "--new") {
            if (auto err = need_value("--new")) return err;
            out.create = argv[++i];
        } else if (arg == "--name") {
            if (auto err = need_value("--name")) return err;
            out.name = argv[++i];
        } else if (arg == "--id") {
            if (auto err = need_value("--id")) return err;
            out.id = argv[++i];
        } else if (arg == "--author") {
            if (auto err = need_value("--author")) return err;
            out.author = argv[++i];
        } else if (arg == "--save-dir") {
            if (auto err = need_value("--save-dir")) return err;
            out.save_dir = argv[++i];
        } else if (arg == "--check-api") {
            out.check_api = true;
        } else if (arg == "--control") {
            if (auto err = need_value("--control")) return err;
            out.control = std::atoi(argv[++i]);
        } else if (arg == "--log") {
            if (auto err = need_value("--log")) return err;
            out.log_file = argv[++i];
        } else if (arg == "--json") {
            out.json = true;
        } else if (arg == "--frames") {
            if (auto err = need_value("--frames")) return err;
            out.frames = std::atoi(argv[++i]);
        } else if (arg == "--dump-every") {
            if (auto err = need_value("--dump-every")) return err;
            out.dump_every = std::atoi(argv[++i]);
        } else if (arg == "--seed") {
            if (auto err = need_value("--seed")) return err;
            out.seed = static_cast<unsigned>(std::strtoul(argv[++i], nullptr, 10));
        } else if (arg == "--version") {
            return std::string(kVersionRequest);
        } else if (arg == "--help" || arg == "-h") {
            return std::string(kHelpRequest);
        } else {
            return "unknown option: " + arg;
        }
    }
    return std::nullopt;
}

} // namespace phos
