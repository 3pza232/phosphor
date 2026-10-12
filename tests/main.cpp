#include "harness.hpp"

int main() {
    ::photest::Registry& registry = ::photest::Registry::get();
    int failed_tests = 0;
    for (const auto& [name, fn] : registry.tests) {
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
