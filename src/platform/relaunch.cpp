#include "platform/relaunch.hpp"

#include "core/log.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <string>
#include <vector>

namespace phos {

bool relaunch_self() {
    // 自身路径：exe 可能被改名、或从别处启动，不能靠固定文件名猜
    std::vector<wchar_t> exe(32768, L'\0');
    const DWORD n = GetModuleFileNameW(nullptr, exe.data(), static_cast<DWORD>(exe.size()));
    if (n == 0 || n >= exe.size()) {
        log::warn("relaunch: cannot determine own executable path");
        return false;
    }

    // 原始命令行（含程序名与全部参数）。CreateProcessW 要求可写缓冲，故拷一份
    const std::wstring line = GetCommandLineW();
    std::vector<wchar_t> cmd(line.begin(), line.end());
    cmd.push_back(L'\0');

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    // 工作目录留空 = 继承当前进程的工作目录：carts/ / theme/ / config.json 这些
    // 相对路径在新实例里照旧解析到同一处
    const BOOL ok = CreateProcessW(exe.data(), cmd.data(), nullptr, nullptr, FALSE, 0, nullptr,
                                   nullptr, &si, &pi);
    if (!ok) {
        log::warn("relaunch: CreateProcessW failed (error " +
                  std::to_string(static_cast<unsigned long>(GetLastError())) + ")");
        return false;
    }
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    log::info("relaunch: new instance started");
    return true;
}

} // namespace phos

#else

namespace phos {

bool relaunch_self() {
    // 非 Windows：拿不到 argv[0]，没有可移植的"原样重启"（execv 需要它）。
    // 如实记日志，由调用方正常退出——用户手动重开即可
    log::warn("relaunch: not implemented on this platform; restart manually");
    return false;
}

} // namespace phos

#endif
