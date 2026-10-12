#pragma once

// 极简断言框架：不引第三方测试库（与宿主"零外部解析依赖"的取舍一致）。
// 一个测试 = 一个 TEST 函数；任一断言失败即打印 file:line，进程最终返回非零。

#include <cstdio>
#include <string>
#include <utility>
#include <vector>

namespace photest {

struct Registry {
    std::vector<std::pair<std::string, void (*)()>> tests;
    int checks = 0;
    int failures = 0;

    static Registry& get() {
        static Registry instance;
        return instance;
    }
};

inline void report_failure(const char* file, int line, const std::string& what) {
    ++Registry::get().failures;
    std::fprintf(stderr, "  FAIL %s:%d  %s\n", file, line, what.c_str());
}

struct Registrar {
    Registrar(const char* name, void (*fn)()) { Registry::get().tests.emplace_back(name, fn); }
};

} // namespace photest

#define TEST(name)                                               \
    static void name();                                          \
    static ::photest::Registrar registrar_##name(#name, &name);  \
    static void name()

#define CHECK(cond)                                                                    \
    do {                                                                               \
        ++::photest::Registry::get().checks;                                           \
        if (!(cond)) ::photest::report_failure(__FILE__, __LINE__, "CHECK(" #cond ")"); \
    } while (0)

#define CHECK_EQ(a, b)                                                              \
    do {                                                                            \
        ++::photest::Registry::get().checks;                                        \
        if (!((a) == (b)))                                                          \
            ::photest::report_failure(__FILE__, __LINE__, "CHECK_EQ(" #a ", " #b ")"); \
    } while (0)
