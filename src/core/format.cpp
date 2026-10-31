#include "core/format.hpp"

#include <cmath>
#include <cstdio>

namespace phos::format {

namespace {

std::string group_thousands(long long value) {
    const bool negative = value < 0;
    unsigned long long magnitude =
        negative ? static_cast<unsigned long long>(-(value + 1)) + 1ULL
                 : static_cast<unsigned long long>(value);
    std::string digits = std::to_string(magnitude);
    std::string out;
    out.reserve(digits.size() + digits.size() / 3 + (negative ? 1 : 0));
    if (negative) out += '-';
    for (size_t i = 0; i < digits.size(); ++i) {
        if (i > 0 && (digits.size() - i) % 3 == 0) out += ',';
        out += digits[i];
    }
    return out;
}

} // namespace

std::string score(long long value) { return group_thousands(value); }

std::string clock(long long seconds) {
    if (seconds < 0) seconds = 0;
    const long long hours = seconds / 3600;
    const long long minutes = (seconds % 3600) / 60;
    const long long secs = seconds % 60;
    char buffer[32];
    if (hours > 0)
        std::snprintf(buffer, sizeof(buffer), "%lld:%02lld:%02lld", hours, minutes, secs);
    else
        std::snprintf(buffer, sizeof(buffer), "%02lld:%02lld", minutes, secs);
    return std::string(buffer);
}

std::string percent(double ratio, int digits) {
    if (digits < 0) digits = 0;
    if (digits > 2) digits = 2;
    if (!std::isfinite(ratio)) ratio = 0.0;
    char buffer[32];
    std::snprintf(buffer, sizeof(buffer), "%.*f%%", digits, ratio * 100.0);
    return std::string(buffer);
}

} // namespace phos::format
