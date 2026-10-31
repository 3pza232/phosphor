#include "devkit/cart_lint.hpp"

#include "cart/cart_files.hpp"
#include "cart/cart_info.hpp"
#include "cart/cartridge.hpp"

#include <algorithm>
#include <cctype>
#include <string_view>

namespace phos::devkit {

namespace {

bool is_identifier_start(char c) {
    return std::isalpha(static_cast<unsigned char>(c)) != 0 || c == '_';
}

bool is_identifier_char(char c) {
    return std::isalnum(static_cast<unsigned char>(c)) != 0 || c == '_';
}

void add(LintReport& report, LintSeverity severity, const std::string& where, int line,
         std::string message) {
    report.issues.push_back(LintIssue{severity, where, line, std::move(message)});
}

/// 行首无缩进、标识符后接 `=`（排除 == / ~=）的赋值：这是"隐式全局"的典型写法。
std::string top_level_global(const std::string& line) {
    if (line.empty() || std::isspace(static_cast<unsigned char>(line[0])) != 0) return {};
    if (line.rfind("local ", 0) == 0) return {};
    size_t i = 0;
    if (!is_identifier_start(line[i])) return {};
    while (i < line.size() && is_identifier_char(line[i])) ++i;
    const std::string name = line.substr(0, i);
    while (i < line.size() && (line[i] == ' ' || line[i] == '\t')) ++i;
    if (i >= line.size() || line[i] != '=') return {};
    if (i + 1 < line.size() && (line[i + 1] == '=' || line[i + 1] == '~')) return {};
    static const char* kAllowed[] = {"init", "update", "draw", "debug_state", "observe"};
    for (const char* allowed : kAllowed)
        if (name == allowed) return {};
    return name;
}

bool is_comment(const std::string& line) {
    size_t i = 0;
    while (i < line.size() && std::isspace(static_cast<unsigned char>(line[i])) != 0) ++i;
    return i + 1 < line.size() && line[i] == '-' && line[i + 1] == '-';
}

/// 行内声明的 local 名（"local a, b = ..." / "local function f"）。
/// 用来消除"先 `local f` 声明、后 `f = function` 赋值"这种合法写法的误报。
std::vector<std::string> local_names(const std::string& line) {
    std::vector<std::string> names;
    if (line.rfind("local ", 0) != 0) return names;
    size_t i = 6;
    if (line.rfind("local function ", 0) == 0) {
        i = 15;
        while (i < line.size() && std::isspace(static_cast<unsigned char>(line[i])) != 0) ++i;
        const size_t begin = i;
        while (i < line.size() && is_identifier_char(line[i])) ++i;
        if (i > begin) names.push_back(line.substr(begin, i - begin));
        return names;
    }
    while (i < line.size()) {
        while (i < line.size() && (std::isspace(static_cast<unsigned char>(line[i])) != 0 ||
                                    line[i] == ','))
            ++i;
        if (i >= line.size() || !is_identifier_start(line[i])) break;
        const size_t begin = i;
        while (i < line.size() && is_identifier_char(line[i])) ++i;
        names.push_back(line.substr(begin, i - begin));
        while (i < line.size() && std::isspace(static_cast<unsigned char>(line[i])) != 0) ++i;
        if (i < line.size() && line[i] == '=') break;
        if (i >= line.size() || line[i] != ',') break;
    }
    return names;
}

std::vector<std::string> required_modules(const std::string& line) {
    std::vector<std::string> found;
    const std::string marker = "require(";
    size_t at = line.find(marker);
    while (at != std::string::npos) {
        size_t i = at + marker.size();
        while (i < line.size() && (line[i] == ' ' || line[i] == '\t')) ++i;
        const char quote = i < line.size() ? line[i] : '\0';
        if (quote == '"' || quote == '\'') {
            const size_t begin = ++i;
            while (i < line.size() && line[i] != quote) ++i;
            if (i < line.size()) found.push_back(line.substr(begin, i - begin));
        }
        at = line.find(marker, at + 1);
    }
    return found;
}

bool contains(const std::vector<std::string>& names, const std::string& wanted) {
    return std::find(names.begin(), names.end(), wanted) != names.end();
}

} // namespace

int LintReport::errors() const {
    return static_cast<int>(std::count_if(issues.begin(), issues.end(), [](const LintIssue& issue) {
        return issue.severity == LintSeverity::error;
    }));
}

int LintReport::warnings() const {
    return static_cast<int>(std::count_if(issues.begin(), issues.end(), [](const LintIssue& issue) {
        return issue.severity == LintSeverity::warning;
    }));
}

LintReport lint_cart(const std::string& cart_dir) {
    LintReport report;
    report.path = cart_dir;

    const CartFiles files = CartFiles::open(cart_dir);
    if (!files.valid()) {
        add(report, LintSeverity::error, "", 0, "not a readable cart directory or .phos file");
        return report;
    }
    const auto manifest = files.read("manifest.lua");
    if (!manifest) {
        add(report, LintSeverity::error, "manifest.lua", 0, "missing or unreadable");
        return report;
    }
    const CartInfo info = parse_manifest(*manifest, cart_dir);
    report.cart_id = info.id;
    if (!info.error.empty()) {
        add(report, LintSeverity::error, "manifest.lua", 0, info.error);
        return report;
    }
    if (!is_valid_cart_id(info.id))
        add(report, LintSeverity::error, "manifest.lua", 0,
            "id must match [a-z0-9-]{1,64}: " + info.id);
    if (info.entry.empty())
        add(report, LintSeverity::error, "manifest.lua", 0, "missing entry");
    else if (!files.exists(info.entry))
        add(report, LintSeverity::error, info.entry, 0, "entry script not found");

    bool exposes_state = false;
    for (const std::string& entry : files.entries("")) {
        if (entry.size() < 5 || entry.compare(entry.size() - 4, 4, ".lua") != 0) continue;
        const auto source = files.read(entry);
        if (!source) continue;
        std::vector<std::string> declared_locals;
        int line_number = 0;
        size_t begin = 0;
        while (begin <= source->size()) {
            const size_t end = source->find('\n', begin);
            std::string line = source->substr(
                begin, end == std::string::npos ? std::string::npos : end - begin);
            ++line_number;
            if (!line.empty() && line.back() == '\r') line.pop_back();
            for (const std::string& name : local_names(line)) declared_locals.push_back(name);
            if (!is_comment(line)) {
                const std::string global = top_level_global(line);
                if (!global.empty() && !contains(declared_locals, global))
                    add(report, LintSeverity::warning, entry, line_number,
                        "top-level implicit global '" + global +
                            "' (use local; globals leak between carts and reloads)");
                if (line.find("phos.screen.size()") != std::string::npos)
                    add(report, LintSeverity::warning, entry, line_number,
                        "phos.screen.size() includes the sidebar; use phos.screen.playfield()");
                if (line.find("phos.net.discover(") != std::string::npos)
                    add(report, LintSeverity::warning, entry, line_number,
                        "phos.net.discover() blocks up to its timeout; keep calls out of update()");
                for (const std::string& module : required_modules(line)) {
                    std::string inner = module;
                    std::replace(inner.begin(), inner.end(), '.', '/');
                    if (!files.exists(inner + ".lua") && !files.exists(inner + "/init.lua"))
                        add(report, LintSeverity::warning, entry, line_number,
                            "require('" + module + "') points to a module not in the cart");
                }
            }
            if (line.find("debug_state") != std::string::npos ||
                line.find("phos.observe") != std::string::npos)
                exposes_state = true;
            if (end == std::string::npos) break;
            begin = end + 1;
        }
    }

    if (!exposes_state)
        add(report, LintSeverity::info, "", 0,
            "no debug_state()/phos.observe: agents cannot read gameplay state");
    return report;
}

} // namespace phos::devkit
