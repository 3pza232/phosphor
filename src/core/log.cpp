#include "core/log.hpp"

#include <chrono>
#include <cstdio>
#include <ctime>
#include <fstream>
#include <mutex>

namespace phos {
namespace log {
namespace {

std::mutex g_mutex;
std::ofstream g_file;
long g_frame = 0;

/// 当前墙钟时间："2026-10-09 14:03:22.417"
std::string timestamp() {
    const auto now = std::chrono::system_clock::now();
    const auto time = std::chrono::system_clock::to_time_t(now);
    const auto millis =
        std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count() %
        1000;

    std::tm local{};
#ifdef _WIN32
    localtime_s(&local, &time);
#else
    localtime_r(&time, &local);
#endif

    char buffer[48];
    std::snprintf(buffer, sizeof(buffer), "%04d-%02d-%02d %02d:%02d:%02d.%03d",
                  local.tm_year + 1900, local.tm_mon + 1, local.tm_mday, local.tm_hour,
                  local.tm_min, local.tm_sec, static_cast<int>(millis));
    return buffer;
}

const char* level_name(Level level) {
    switch (level) {
        case Level::info: return "INFO ";
        case Level::warn: return "WARN ";
        case Level::error: return "ERROR";
    }
    return "?";
}

} // namespace

bool open_file(const std::string& path) {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_file.open(path, std::ios::out | std::ios::trunc);
    if (!g_file) return false;
    g_file << "PHOSPHOR host log\n";
    g_file.flush();
    return true;
}

void close() {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_file.is_open()) g_file.close();
}

bool active() {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_file.is_open();
}

void set_frame(long frame) { g_frame = frame; }

std::string joined_argv(int argc, char** argv) {
    std::string out;
    for (int i = 0; i < argc; ++i) {
        if (i) out += ' ';
        const std::string arg = argv[i] ? argv[i] : "";
        if (arg.find(' ') == std::string::npos) {
            out += arg;
        } else {
            out += '"';
            out += arg;
            out += '"';
        }
    }
    return out;
}

void write(Level level, const std::string& message) {
    // stderr 只在 warn/error 时出声：info 是给事后复盘用的，不该刷屏
    if (level == Level::warn)
        std::fprintf(stderr, "WARN: %s\n", message.c_str());
    else if (level == Level::error)
        std::fprintf(stderr, "ERROR: %s\n", message.c_str());

    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_file.is_open()) return;

    char frame_tag[32];
    std::snprintf(frame_tag, sizeof(frame_tag), "f%-7ld", g_frame);
    g_file << timestamp() << " [" << frame_tag << "] " << level_name(level) << " " << message
           << "\n";
    g_file.flush();  // 崩溃 / 强杀时也要留下证据
}

} // namespace log
} // namespace phos
