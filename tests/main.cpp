#include "harness.hpp"

#include <cstdlib>
#include <string>

int main() {
    // 不缓冲：崩溃/断言时已跑过的用例与失败行必须留在输出里（否则管道下全丢）
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::setvbuf(stderr, nullptr, _IONBF, 0);
    ::photest::Registry& registry = ::photest::Registry::get();
    // PHOTEST_FILTER=子串 只跑匹配的用例：排查"哪个用例把堆搞坏"时按名字二分
    const char* filter = std::getenv("PHOTEST_FILTER");
    int failed_tests = 0;
    for (const auto& [name, fn] : registry.tests) {
        if (filter && name.find(filter) == std::string::npos) continue;
        const int before = registry.failures;
        fn();
        if (registry.failures > before) {
            ++failed_tests;
            std::printf("FAILED  %s\n", name.c_str());
        }
    }
    std::printf("unit: %zu test(s), %d check(s), %d failure(s)\n", registry.tests.size(),
                registry.checks, registry.failures);
    return registry.failures == 0 ? 0 : 1;
}