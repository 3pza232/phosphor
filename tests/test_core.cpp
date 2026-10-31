// 纯逻辑单元测试：只覆盖不依赖 GL / GLFW / Lua 的核心（颜色、文本、配置、色板、主题…）。
// 这些是"最该有测试、也最容易崩"的纯函数；有窗口/渲染参与的部分由 tools/ 下的
// 集成脚本（window_smoke / draw_smoke 等）覆盖。

#include "harness.hpp"

#include "core/color.hpp"
#include "core/config.hpp"
#include "core/crt.hpp"
#include "core/format.hpp"
#include "core/json_lite.hpp"
#include "core/layered_screen.hpp"
#include "core/palette.hpp"
#include "core/screen_draw.hpp"
#include "core/screen_text.hpp"
#include "core/skin.hpp"
#include "core/surface.hpp"
#include "core/text.hpp"
#include "core/text_input.hpp"
#include "core/ui.hpp"
#include "ui/frame.hpp"
#include "cart/cart_files.hpp"
#include "cart/cart_info.hpp"
#include "cart/save_store.hpp"
#include "pack/builtin.hpp"
#include "pack/content_library.hpp"
#include "shell/shelf_search.hpp"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <limits>
#include <string>

using namespace phos;

namespace {

/// 单元测试的落盘目录：项目内（运行时目录下的 tests-out/unit），不依赖 OS 临时目录。
/// 受限环境/只读 %TEMP% 下测试照样能跑，且崩溃残留可直接查看。
std::filesystem::path unit_scratch(const char* name = nullptr) {
    const std::filesystem::path dir = std::filesystem::path("tests-out") / "unit";
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    return name ? dir / name : dir;
}

} // namespace
using namespace phos::text;

namespace {

// ---------------------------------------------------------------- color

TEST(color_channel_clamp) {
    CHECK_EQ(int(clamp_channel(-1)), 0);
    CHECK_EQ(int(clamp_channel(0)), 0);
    CHECK_EQ(int(clamp_channel(255)), 255);
    CHECK_EQ(int(clamp_channel(256)), 255);
}

TEST(color_rgb_clamped) {
    const Color c = rgb_clamped(-10, 128, 999);
    CHECK_EQ(int(c.r), 0);
    CHECK_EQ(int(c.g), 128);
    CHECK_EQ(int(c.b), 255);
}

TEST(color_scale_does_not_wrap) {
    const Color up = scale_color(Color{200, 100, 0}, 2.0f);
    CHECK_EQ(int(up.r), 255);  // 400 不会回绕
    CHECK_EQ(int(up.g), 200);
    const Color down = scale_color(Color{200, 100, 0}, 0.5f);
    CHECK_EQ(int(down.r), 100);
}

TEST(color_keep_flag) {
    CHECK(kKeepBg.keep);
    CHECK(!Color{}.keep);
    CHECK_EQ(int(Color::black.r), 0);
    CHECK_EQ(int(Color::white.r), 230);
}

// ---------------------------------------------------------------- text

TEST(text_char_width) {
    CHECK_EQ(char_width(U'\n'), 0);
    CHECK_EQ(char_width(U'A'), 1);
    CHECK_EQ(char_width(U'中'), 2);
}

TEST(text_display_width) {
    CHECK_EQ(display_width("hello"), 5);
    CHECK_EQ(display_width("中文 abc"), 8);
}

TEST(text_truncate_never_splits_wide) {
    CHECK_EQ(truncate("abc", 2), std::string("ab"));
    CHECK_EQ(truncate("中中中", 3), std::string("中"));  // 切不到第 2 个整字就停
}

TEST(text_utf8_roundtrip) {
    CHECK_EQ(decode("中").size(), size_t(1));
    CHECK_EQ(int(decode("中")[0]), 0x4E2D);
    std::string s;
    append_utf8(s, U'中');
    CHECK_EQ(s, std::string("中"));
    pop_back_utf8(s);
    CHECK(s.empty());
}

// ---------------------------------------------------------------- text_input

TEST(text_input_filters) {
    CHECK(TextInput::accept_hex(U'0'));
    CHECK(TextInput::accept_hex(U'f'));
    CHECK(TextInput::accept_hex(U'A'));
    CHECK(!TextInput::accept_hex(U'g'));
    CHECK(!TextInput::accept_hex(U'中'));
    CHECK(TextInput::accept_digits(U'5'));
    CHECK(!TextInput::accept_digits(U'a'));
}

TEST(text_input_limit_and_backspace) {
    TextInput in(TextInput::accept_any, 3);
    in.apply("abc");
    CHECK_EQ(in.value(), std::string("abc"));
    CHECK_EQ(in.count(), size_t(3));
    in.apply("d");  // 超限：丢弃
    CHECK_EQ(in.value(), std::string("abc"));
    in.apply(std::string(1, kBackspace) + "d");  // 退格后补 d
    CHECK_EQ(in.value(), std::string("abd"));
    in.clear();
    CHECK(in.empty());
    CHECK_EQ(in.count(), size_t(0));
}

TEST(text_input_backspace_removes_whole_codepoint) {
    TextInput in;
    in.apply("中");
    CHECK_EQ(in.count(), size_t(1));
    in.apply(std::string(1, kBackspace));
    CHECK(in.empty());  // 删掉整个码点，不是删一个字节
}

// ---------------------------------------------------------------- json

TEST(json_escape_and_quote) {
    CHECK_EQ(json::escape("a\nb"), std::string("a\\nb"));
    CHECK_EQ(json::quote("a\"b"), std::string("\"a\\\"b\""));
}

TEST(json_parse_object) {
    json::Object obj;
    std::string err;
    CHECK(obj.parse("{\"a\":1,\"b\":\"x\",\"c\":true,\"n\":{\"k\":2}}", err));
    CHECK_EQ(obj.integer("a"), 1);
    CHECK_EQ(obj.str("b"), std::string("x"));
    CHECK(obj.flag("c"));
    CHECK_EQ(obj.integer("missing", 7), 7);
    const json::Object* nested = obj.object("n");
    CHECK(nested != nullptr);
    CHECK_EQ(nested->integer("k"), 2);
}

TEST(json_parse_rejects_garbage) {
    json::Object obj;
    std::string err;
    CHECK(!obj.parse("not json at all", err));
    CHECK(!err.empty());
}

TEST(json_rejects_deep_nesting) {
    // 200 层嵌套：必须判错（而不是递归爆栈）。控制通道 / 网络包是不可信输入
    std::string deep;
    for (int i = 0; i < 200; ++i) deep += "{\"a\":";
    for (int i = 0; i < 200; ++i) deep += "}";
    json::Object obj;
    std::string err;
    CHECK(!obj.parse(deep, err));
    CHECK(!err.empty());

    json::Object ok_obj;  // 正常深度仍可解析
    std::string ok_err;
    CHECK(ok_obj.parse("{\"a\":{\"b\":{\"c\":1}}}", ok_err));
}

TEST(json_string_array) {
    json::Object obj;
    std::string err;
    CHECK(obj.parse("{\"a\":[\"x\",\"y\"],\"n\":[1,2],\"e\":[],\"o\":{\"k\":1},\"s\":\"z\"}",
                    err));
    const std::vector<std::string> a = obj.string_array("a");
    CHECK_EQ(a.size(), size_t(2));
    CHECK_EQ(a[0], std::string("x"));
    CHECK_EQ(a[1], std::string("y"));
    CHECK_EQ(obj.string_array("n").size(), size_t(2));  // 数字按原样文本收
    CHECK(obj.string_array("e").empty());               // 空数组
    CHECK(obj.string_array("o").empty());               // 非数组 → 空
    CHECK(obj.string_array("s").empty());               // 字符串不是数组
    CHECK(obj.string_array("missing").empty());
    CHECK_EQ(obj.integer("x", 5), 5);  // 数组不干扰其它取值
}

// ---------------------------------------------------------------- json unicode / 数值 / 转义

TEST(json_unicode_escape_decodes_to_utf8) {
    json::Object obj;
    std::string err;
    // 基本平面：\u4E2D\u6587 = 中文
    CHECK(obj.parse(R"({"t":"\u4E2D\u6587"})", err));
    CHECK_EQ(obj.str("t"), std::string("中文"));
    // 十六进制大小写都合法：\u00e9 = é
    CHECK(obj.parse(R"({"t":"\u00e9"})", err));
    CHECK_EQ(obj.str("t"), std::string("é"));
    // \u0000 是合法的 NUL：按字节进 std::string，长度不因转义而变
    CHECK(obj.parse(R"({"t":"a\u0000b"})", err));
    CHECK_EQ(obj.str("t").size(), size_t(3));
    CHECK_EQ(int(obj.str("t")[1]), 0);
}

TEST(json_unicode_surrogate_pair) {
    json::Object obj;
    std::string err;
    // U+1F600 = F0 9F 98 80：代理对合并成一个 4 字节 UTF-8 码点，而不是两个坏字符
    CHECK(obj.parse(R"({"e":"\uD83D\uDE00"})", err));
    CHECK_EQ(obj.str("e"), std::string("\xF0\x9F\x98\x80"));
    // 裸 UTF-8 与转义混写（标准 JSON 客户端可能逐段转义）
    CHECK(obj.parse(R"({"e":"A\uD83D\uDE00中"})", err));
    CHECK_EQ(obj.str("e"), std::string("A\xF0\x9F\x98\x80中"));
}

TEST(json_unicode_invalid_rejected) {
    json::Object obj;
    std::string err;
    CHECK(!obj.parse(R"({"t":"\u12"})", err));     // 位数不够
    CHECK(!obj.parse(R"({"t":"\uZZZZ"})", err));   // 非十六进制
    CHECK(!obj.parse(R"({"t":"\uD800"})", err));   // 孤立高代理
    CHECK(!obj.parse(R"({"t":"\uDE00"})", err));   // 孤立低代理
    CHECK(!obj.parse(R"({"t":"\uD83Dx"})", err));  // 高代理后不是低代理
    CHECK(!obj.parse(R"({"t":"\q"})", err));       // 未知转义
    CHECK(!err.empty());
}

TEST(json_escape_table_roundtrip) {
    // 八个标准转义各来一个：解析结果必须与对应的控制字符逐字节一致
    json::Object obj;
    std::string err;
    CHECK(obj.parse(R"({"t":"\" \\ \/ \b \f \n \r \t"})", err));
    CHECK_EQ(obj.str("t"), std::string("\" \\ / \b \f \n \r \t"));
}

TEST(json_number_grammar_is_strict) {
    json::Object obj;
    std::string err;
    // 合法：负号 / 负零 / 小数 / 指数
    CHECK(obj.parse(R"({"a":-5,"b":-0,"c":-1.5,"d":1e3,"e":0.25,"f":-2E-2})", err));
    CHECK_EQ(obj.integer("a"), -5);
    CHECK_EQ(obj.integer("b"), 0);
    CHECK_EQ(obj.number("c"), -1.5);
    CHECK_EQ(obj.integer("c"), -1);  // 向零截断
    CHECK_EQ(obj.integer("d"), 1000);
    CHECK_EQ(obj.number("e"), 0.25);
    CHECK_EQ(obj.number("f"), -0.02);

    // 非法字面量：NaN/Infinity 不是 JSON；strtod 会"宽容接受"的写法同样必须拒绝
    const char* bad[] = {
        R"({"a":NaN})",       R"({"a":nan})",  R"({"a":Infinity})", R"({"a":-Infinity})",
        R"({"a":+1})",        R"({"a":01})",   R"({"a":.5})",       R"({"a":1.})",
        R"({"a":1e})",        R"({"a":0x10})", R"({"a":})",         R"({"a":1e999})",
        R"({"a":-1e999})",    R"({"a":[NaN]})", R"({"a":[1e999]})",
    };
    for (const char* text : bad) {
        json::Object strict;
        std::string bad_err;
        CHECK(!strict.parse(text, bad_err));
        CHECK(!bad_err.empty());
    }
}

TEST(json_number_narrowing_is_clamped_not_ub) {
    json::Object obj;
    std::string err;
    // 合法但超出 int 的数值：读取必须钳到端点（double → int 越界是 UB）
    CHECK(obj.parse(R"({"big":1e30,"small":-1e30,"wide":123456789012345678901234567890})",
                    err));
    CHECK_EQ(obj.integer("big"), std::numeric_limits<int>::max());
    CHECK_EQ(obj.integer("small"), std::numeric_limits<int>::min());
    CHECK_EQ(obj.integer("wide"), std::numeric_limits<int>::max());
    // 字符串形式的数值按 strtod 解析，但非有限文本不得传播成 inf/nan
    CHECK(obj.parse(R"({"s":"inf","n":"12"})", err));
    CHECK_EQ(obj.number("s", 7.0), 7.0);
    CHECK_EQ(obj.integer("n", 9), 12);
}

TEST(json_escape_controls_and_invalid_utf8) {
    // 全部控制字符都必须转义：输出里不能再出现裸控制字节
    for (int code = 0; code < 0x20; ++code) {
        const std::string raw(1, static_cast<char>(code));
        CHECK(json::quote(raw).find(static_cast<char>(code)) == std::string::npos);
    }
    CHECK_EQ(json::escape(std::string("a\x01", 2)), std::string("a\\u0001"));
    CHECK_EQ(json::escape("\b\f\n\r\t"), std::string("\\b\\f\\n\\r\\t"));
    CHECK_EQ(json::escape("\x7F"), std::string("\\u007F"));      // DEL
    CHECK_EQ(json::escape("\xC2\x85"), std::string("\\u0085"));  // C1 控制字符 U+0085

    // 孤立代理（CESU-8 的 U+D800）与非法字节不能原样进 JSON
    CHECK_EQ(json::quote("\xED\xA0\x80"), std::string("\"\\uFFFD\""));
    CHECK_EQ(json::quote("\xFF"), std::string("\"\\uFFFD\""));
    // 合法 UTF-8 原样保留：中文不转义成 \uXXXX
    CHECK_EQ(json::escape("中文"), std::string("中文"));
    CHECK_EQ(json::escape("A中\xF0\x9F\x98\x80"), std::string("A中\xF0\x9F\x98\x80"));
}

TEST(json_quote_roundtrips_arbitrary_text) {
    const std::string samples[] = {
        "plain",
        "with \"quotes\" and \\backslash",
        "中文与 emoji \xF0\x9F\x98\x80",
        std::string("nul\0inside", 10),
        "tab\tnewline\ncr\r",
        "\x01\x1F\x7F",
    };
    for (const std::string& sample : samples) {
        json::Object obj;
        std::string err;
        CHECK(obj.parse("{\"t\":" + json::quote(sample) + "}", err));
        CHECK_EQ(obj.str("t"), sample);  // 转义 → 解析必须逐字节还原
    }
    // 孤立代理被替换成 U+FFFD，产出仍是合法 JSON
    json::Object obj;
    std::string err;
    CHECK(obj.parse("{\"t\":" + json::quote("\xED\xA0\x80") + "}", err));
    CHECK_EQ(obj.str("t"), std::string("\xEF\xBF\xBD"));
}

TEST(json_depth_limit_boundary) {
    const auto nested = [](int levels) {
        std::string text;
        for (int i = 0; i < levels; ++i) text += "{\"a\":";
        text += "1";
        for (int i = 0; i < levels; ++i) text += "}";
        return text;
    };
    json::Object obj;
    std::string err;
    CHECK(obj.parse(nested(json::Object::kMaxDepth), err));       // 上限内：能解析
    CHECK(!obj.parse(nested(json::Object::kMaxDepth + 1), err));  // 超一层即拒绝
    CHECK(!err.empty());
}

TEST(json_value_roundtrip_nested) {
    json::Value value;
    std::string err;
    CHECK(value.parse(R"({"name":"ADA","stats":{"hp":100,"mp":30.5},)"
                      R"("history":[1,2,3],"tags":["a","b"],"seen":true,"ratio":0.25})",
                      err));
    CHECK(value.kind == json::Value::Kind::object);
    CHECK_EQ(value.members.size(), size_t(6));
    CHECK_EQ(value.members.at("name").text, std::string("ADA"));
    const json::Value& stats = value.members.at("stats");
    CHECK(stats.kind == json::Value::Kind::object);
    CHECK_EQ(stats.members.at("hp").number, 100.0);
    CHECK_EQ(stats.members.at("mp").number, 30.5);
    const json::Value& history = value.members.at("history");
    CHECK(history.kind == json::Value::Kind::array);
    CHECK_EQ(history.items.size(), size_t(3));
    CHECK_EQ(history.items[2].number, 3.0);

    // 序列化稳定：dump → parse → dump 完全一致；嵌套容器保持 JSON 形状
    const std::string dumped = value.dump();
    json::Value again;
    CHECK(again.parse(dumped, err));
    CHECK_EQ(again.dump(), dumped);
    CHECK(dumped.find("\"history\":[1,2,3]") != std::string::npos);
    CHECK(dumped.find("\"stats\":{") != std::string::npos);
    // 17 位有效数字：小数可无损回读
    json::Value number;
    CHECK(number.parse("0.1", err));
    CHECK_EQ(number.number, 0.1);
    // 文本转义与 Object 共用同一份实现
    json::Value text;
    CHECK(text.parse("\"a\\\"b\\n\u4e2d\"", err));
    CHECK_EQ(text.text, std::string("a\"b\n中"));
    CHECK_EQ(text.dump(), std::string("\"a\\\"b\\n中\""));
}

TEST(json_value_strict_and_depth_limit) {
    json::Value value;
    std::string err;
    CHECK(!value.parse("", err));
    CHECK(!value.parse("[1,2", err));
    CHECK(!value.parse("{\"a\":1} junk", err));  // 必须整串消费
    CHECK(!value.parse("NaN", err));
    CHECK(!value.parse("Infinity", err));
    CHECK(!value.parse("1e999", err));
    CHECK(!value.parse("1abc", err));  // 数字后必须是分隔符
    CHECK(!value.parse("null junk", err));
    CHECK(value.parse("null", err));
    CHECK(value.kind == json::Value::Kind::null);

    const auto nested = [](int levels) {
        std::string text;
        for (int i = 0; i < levels; ++i) text += '[';
        text += '1';
        for (int i = 0; i < levels; ++i) text += ']';
        return text;
    };
    CHECK(value.parse(nested(json::Value::kMaxDepth), err));       // 上限内
    CHECK(!value.parse(nested(json::Value::kMaxDepth + 1), err));  // 超一层即拒绝
}

TEST(json_value_reports_duplicate_keys_per_object) {
    json::Value value;
    std::string err;
    CHECK(value.parse(R"({"a":1,"a":2,"outer":{"b":1,"b":2}})", err));
    CHECK_EQ(value.duplicate_keys.size(), size_t(1));
    CHECK_EQ(value.duplicate_keys[0], std::string("a"));
    CHECK_EQ(value.members.at("a").number, 2.0);  // 后者生效
    const json::Value& outer = value.members.at("outer");
    CHECK_EQ(outer.duplicate_keys.size(), size_t(1));
    CHECK_EQ(outer.duplicate_keys[0], std::string("b"));

    // Object 视图继续把各层重复键暴露给配置读取
    json::Object object;
    CHECK(object.parse(R"({"theme":{"skin":"a","skin":"b"}})", err));
    const json::Object* theme = object.object("theme");
    CHECK(theme != nullptr);
    CHECK_EQ(theme->duplicate_keys().size(), size_t(1));
    CHECK_EQ(theme->str("skin"), std::string("b"));
}
// S10：json_lite 严格性补测（转义 / 数字 / 结构 / 序列化稳定性）

TEST(json_value_escapes_and_unterminated) {
    json::Value value;
    std::string err;
    // 八个标准转义：解析结果必须与对应字符逐字节一致
    CHECK(value.parse(R"JSON("\" \\ \/ \b \f \n \r \t")JSON", err));
    CHECK_EQ(value.text, std::string("\" \\ / \b \f \n \r \t"));

    // \uXXXX 与代理对：合并成一个 4 字节 UTF-8 码点
    CHECK(value.parse(R"JSON("\uD83D\uDE00")JSON", err));
    CHECK_EQ(value.text, std::string("\xF0\x9F\x98\x80"));

    // 未闭合字符串（顶层与对象内）与非法转义/非法代理都必须拒绝
    CHECK(!value.parse("\"abc", err));
    CHECK(!value.parse("\"abc\\", err));
    CHECK(!value.parse("{\"a\":\"x}", err));
    CHECK(!value.parse("\"\\q\"", err));
    CHECK(!value.parse("\"\\u12\"", err));
    CHECK(!value.parse("\"\\uD800\"", err));
    CHECK(!value.parse("\"\\uDE00\"", err));
    CHECK(!err.empty());
}

TEST(json_value_number_grammar_and_17g_roundtrip) {
    json::Value value;
    std::string err;
    CHECK(value.parse("-5", err));
    CHECK_EQ(value.number, -5.0);
    CHECK(value.parse("1e3", err));
    CHECK_EQ(value.number, 1000.0);
    CHECK(value.parse("-0", err));
    CHECK_EQ(value.number, 0.0);
    CHECK(value.parse("2.5E-3", err));
    CHECK_EQ(value.number, 0.0025);

    // JSON 数字文法：前导零/正号/裸小数点/缺指数/NaN/Infinity/溢出成 inf 全部拒绝
    const char* bad[] = {"01",   "+1",       ".5",      "1.",     "1e",     "NaN",
                         "Infinity", "-Infinity", "1e999", "-1e999", "1abc"};
    for (const char* text : bad) {
        json::Value strict;
        std::string bad_err;
        CHECK(!strict.parse(text, bad_err));
        CHECK(!bad_err.empty());
    }

    // %.17g 序列化必须能无损回读（含 DBL_MAX / denormal / 非常规小数）；
    // 同一份值重复 dump 逐字节一致
    const double numbers[] = {0.0,
                              -0.0,
                              1.5,
                              0.1,
                              1.0 / 3.0,
                              0.1 + 0.2,
                              std::numeric_limits<double>::max(),
                              std::numeric_limits<double>::denorm_min(),
                              1e300,
                              1e-300};
    for (double number : numbers) {
        const json::Value original = json::Value::of_number(number);
        const std::string dumped = original.dump();
        json::Value back;
        std::string back_err;
        CHECK(back.parse(dumped, back_err));
        CHECK_EQ(back.number, number);
        CHECK_EQ(back.dump(), dumped);
    }
    CHECK_EQ(json::Value::of_number(1.5).dump(), std::string("1.5"));
    CHECK_EQ(json::Value::of_number(-0.0).dump(), std::string("-0"));
}

TEST(json_value_empty_and_mixed_nesting) {
    json::Value value;
    std::string err;
    CHECK(value.parse("{}", err));
    CHECK_EQ(value.dump(), std::string("{}"));
    CHECK(value.parse("[]", err));
    CHECK_EQ(value.dump(), std::string("[]"));
    CHECK(value.parse(" {\"a\":[],\"b\":{}} ", err));
    CHECK_EQ(value.dump(), std::string("{\"a\":[],\"b\":{}}"));

    // 对象/数组混合嵌套：64 层恰好接受，65 层拒绝（与同构嵌套同一上限）
    const auto mixed = [](int levels) {
        std::string text;
        for (int i = 0; i < levels; ++i) text += (i % 2 == 0) ? "{\"a\":" : "[";
        text += "1";
        for (int i = levels - 1; i >= 0; --i) text += (i % 2 == 0) ? "}" : "]";
        return text;
    };
    CHECK(value.parse(mixed(json::Value::kMaxDepth), err));
    CHECK(!value.parse(mixed(json::Value::kMaxDepth + 1), err));

    // 整串消费：前导/尾随空白允许，任何尾随字符都拒绝；Object 还要求根是对象
    json::Object object;
    CHECK(!object.parse("[]", err));
    CHECK(object.parse("  {\"a\":1}  ", err));
    CHECK(!object.parse("{\"a\":1} trailing", err));
    CHECK(!object.parse("{\"a\":1}[]", err));
}

TEST(json_value_dump_stability_and_key_order) {
    json::Value value;
    std::string err;
    CHECK(value.parse(R"JSON({"b":1,"a":2,"c":{"z":1,"y":[3,2,1]}})JSON", err));
    const std::string first = value.dump();
    CHECK_EQ(first, std::string("{\"a\":2,\"b\":1,\"c\":{\"y\":[3,2,1],\"z\":1}}"));
    CHECK_EQ(value.dump(), first);  // 同值重复 dump 逐字节一致
    json::Value again;
    CHECK(again.parse(first, err));
    CHECK_EQ(again.dump(), first);  // dump → parse → dump 稳定

    // 程序化构造：键插入顺序不影响 dump（std::map 升序），输出可回读
    json::Value manual = json::Value::of_object();
    manual.members["b"] = json::Value::of_number(1);
    manual.members["a"] = json::Value::of_text("x");
    CHECK_EQ(manual.dump(), std::string("{\"a\":\"x\",\"b\":1}"));

    // 文本经 dump 后仍是合法 JSON，并能解析回同一份文本
    const json::Value text = json::Value::of_text(std::string("a\"b\n中"));
    const std::string text_dump = text.dump();
    CHECK_EQ(text_dump, std::string("\"a\\\"b\\n中\""));
    json::Value text_back;
    CHECK(text_back.parse(text_dump, err));
    CHECK_EQ(text_back.text, text.text);

    // 重复键诊断：第 2、3 次出现各记一次；Object 视图同样给出升序顶层键
    CHECK(value.parse(R"JSON({"k":1,"k":2,"k":3})JSON", err));
    CHECK_EQ(value.duplicate_keys.size(), size_t(2));
    CHECK_EQ(value.members.at("k").number, 3.0);

    json::Object object;
    CHECK(object.parse(R"JSON({"b":1,"a":2,"k":1,"k":2})JSON", err));
    const std::vector<std::string> keys = object.keys();
    CHECK_EQ(keys.size(), size_t(3));
    CHECK_EQ(keys[0], std::string("a"));
    CHECK_EQ(keys[1], std::string("b"));
    CHECK_EQ(keys[2], std::string("k"));
    CHECK_EQ(object.duplicate_keys().size(), size_t(1));
}

TEST(json_object_integer_boundary_narrowing) {
    // double → int 的越界是 UB：读取必须钳到端点，而不是回绕
    json::Object object;
    std::string err;
    CHECK(object.parse(
        R"JSON({"max":2147483647,"over":2147483648,"min":-2147483648,)JSON"
        R"JSON("under":-2147483649,"frac":2147483646.9,)JSON"
        R"JSON("smax":"2147483648","sneg":"-2147483649"})JSON",
        err));

    CHECK_EQ(object.integer("max"), std::numeric_limits<int>::max());
    CHECK_EQ(object.integer("over"), std::numeric_limits<int>::max());
    CHECK_EQ(object.integer("min"), std::numeric_limits<int>::min());
    CHECK_EQ(object.integer("under"), std::numeric_limits<int>::min());
    CHECK_EQ(object.integer("frac"), 2147483646);  // 小数向零截断，且不越界
    CHECK_EQ(object.integer("smax"), std::numeric_limits<int>::max());
    CHECK_EQ(object.integer("sneg"), std::numeric_limits<int>::min());
    CHECK_EQ(object.integer("missing", 5), 5);
}


// ---------------------------------------------------------------- palette / builtin

TEST(palette_slot_names) {
    CHECK_EQ(kPaletteSlots, size_t(12));
    CHECK_EQ(std::string(palette_slot_name(PaletteSlot::purple)), std::string("purple"));
    CHECK_EQ(std::string(palette_slot_name(PaletteSlot::dark_gray)), std::string("dark_gray"));
}

TEST(builtin_and_raw_palette) {
    const Palette p = builtin_palette();
    CHECK_EQ(p.slots[static_cast<size_t>(PaletteSlot::red)].r, Color::red.r);
    CHECK_EQ(p.slots[static_cast<size_t>(PaletteSlot::white)].g, Color::white.g);

    const Palette raw = raw_palette();  // 回退链最后一环：不做色调
    CHECK_EQ(raw.id, std::string("none"));
    CHECK_EQ(raw.scan_strength, 0.0f);
}

// ---------------------------------------------------------------- crt

TEST(crt_params_by_level) {
    const Palette raw = raw_palette();  // scan_strength = 0：扫描线强度由档位决定
    CHECK_EQ(std::string(crt_level_name(0)), std::string("OFF"));
    CHECK_EQ(std::string(crt_level_name(-5)), std::string("OFF"));      // 越界钳到两端
    CHECK_EQ(std::string(crt_level_name(99)), std::string("STRONG"));
    CHECK(!crt_params_for_level(0, raw).compensate);  // OFF 不做亮度补偿
    CHECK(crt_params_for_level(3, raw).compensate);
    CHECK(crt_params_for_level(3, raw).scanline > crt_params_for_level(1, raw).scanline);
}

TEST(crt_palette_overrides_scanline) {
    Palette pal;
    pal.scan_strength = 0.5f;  // 色板声明了扫描线强度：非 OFF 档位以它为准
    CHECK_EQ(crt_params_for_level(2, pal).scanline, 0.5f);
    CHECK_EQ(crt_params_for_level(0, pal).scanline, 0.0f);  // OFF 档位不受色板影响
    CHECK_EQ(int(crt_params_for_level(2, pal).tint.r), int(pal.tint.r));
}

TEST(crt_scanline_phase_hits_dark_window) {
    // 像素中心约定：底行 0.5、顶行 H-0.5。整数坐标（旧 bug：少了半个像素）永远够不到
    // 暗线区间 kScanlineDarkStart，扫描线在 CPU 这条路上会整条消失
    float max_center = 0.0f;
    float max_integer = 0.0f;
    for (int row = 0; row < 12; ++row) {
        max_center = std::max(max_center, crt_scanline_phase(static_cast<float>(row) + 0.5f));
        max_integer = std::max(max_integer, crt_scanline_phase(static_cast<float>(row)));
    }
    CHECK(max_center > kScanlineDarkStart);   // 有行落进暗线 → 扫描线可见
    CHECK(max_integer < kScanlineDarkStart);  // 整数相位够不到 → 这正是旧 bug
}

// ---------------------------------------------------------------- skin

TEST(skin_builtin_geometry) {
    const Skin s = builtin_skin();
    CHECK_EQ(s.grid_w(), s.screen_x * 2 + s.screen_w);
    CHECK_EQ(s.grid_h(), int(s.top.size()) + s.screen_h + int(s.bottom.size()));
    CHECK_EQ(s.screen_w, kContentW);
    const ui::Rect r = content_rect(s);
    CHECK_EQ(r.x, s.screen_x);
    CHECK_EQ(r.y, s.screen_y);
    CHECK_EQ(r.w, s.screen_w);
    CHECK_EQ(r.h, s.screen_h);
    CHECK(!s.lamps.empty());
}

// ---------------------------------------------------------------- format

TEST(format_score_thousands) {
    CHECK_EQ(format::score(0), std::string("0"));
    CHECK_EQ(format::score(999), std::string("999"));
    CHECK_EQ(format::score(1000), std::string("1,000"));
    CHECK_EQ(format::score(31200), std::string("31,200"));
    CHECK_EQ(format::score(1234567), std::string("1,234,567"));
    CHECK_EQ(format::score(-1234), std::string("-1,234"));
}

TEST(format_clock) {
    CHECK_EQ(format::clock(0), std::string("00:00"));
    CHECK_EQ(format::clock(59), std::string("00:59"));
    CHECK_EQ(format::clock(754), std::string("12:34"));
    CHECK_EQ(format::clock(3661), std::string("1:01:01"));
    CHECK_EQ(format::clock(-5), std::string("00:00"));
}

TEST(format_percent) {
    CHECK_EQ(format::percent(0.4567), std::string("45.7%"));
    CHECK_EQ(format::percent(1.0), std::string("100.0%"));
    CHECK_EQ(format::percent(0.5, 0), std::string("50%"));
    CHECK_EQ(format::percent(0.12345, 2), std::string("12.35%"));
    CHECK_EQ(format::percent(0.5, 9), std::string("50.00%"));  // digits 钳到 2
}

// ---------------------------------------------------------------- config

TEST(config_defaults_when_missing) {
    const Config c = load_config("phosphor-unit-file-that-does-not-exist.json");
    CHECK_EQ(c.skin, std::string("default"));
    CHECK_EQ(c.fps, kDefaultFps);
    CHECK_EQ(c.crt_level, kDefaultCrtLevel);
    CHECK_EQ(c.music_volume, kDefaultMusicVolume);
    CHECK_EQ(c.sfx_volume, kDefaultSfxVolume);
}

TEST(config_roundtrip) {
    const std::filesystem::path path =
        unit_scratch("config.json");

    Config c;
    c.skin = "neon-husk";
    c.boot = "spectrum";
    c.language = "en";
    c.font_size = 20;
    c.crt_level = 3;
    c.fps = 120;
    c.music_volume = 42;
    c.sfx_volume = 13;
    c.mods_disabled = {"default", "snake"};
    save_config(path.string(), c);

    const Config r = load_config(path.string());
    CHECK_EQ(r.skin, std::string("neon-husk"));
    CHECK_EQ(r.boot, std::string("spectrum"));
    CHECK_EQ(r.language, std::string("en"));
    CHECK_EQ(r.font_size, 20);
    CHECK_EQ(r.crt_level, 3);
    CHECK_EQ(r.fps, 120);
    CHECK_EQ(r.music_volume, 42);
    CHECK_EQ(r.sfx_volume, 13);
    CHECK_EQ(r.mods_disabled.size(), size_t(2));
    CHECK_EQ(r.mods_disabled[0], std::string("default"));
    CHECK_EQ(r.mods_disabled[1], std::string("snake"));

    std::error_code ec;
    std::filesystem::remove(path, ec);  // 清理临时文件；删不掉也无所谓
}

// ---------------------------------------------------------------- screen / surface

TEST(screen_quadrant_bit_order) {
    CHECK_EQ(Screen::quadrant_glyph(0), U' ');
    CHECK_EQ(Screen::quadrant_glyph(1), char32_t(0x2598));   // 左上
    CHECK_EQ(Screen::quadrant_glyph(2), char32_t(0x259D));   // 右上
    CHECK_EQ(Screen::quadrant_glyph(4), char32_t(0x2596));   // 左下
    CHECK_EQ(Screen::quadrant_glyph(8), char32_t(0x2597));   // 右下
    CHECK_EQ(Screen::quadrant_glyph(15), char32_t(0x2588));  // 整格
}

TEST(screen_cell_of) {
    const Screen::SubCell tl = Screen::cell_of(0, 0);
    CHECK_EQ(tl.x, 0);
    CHECK_EQ(tl.y, 0);
    CHECK_EQ(int(tl.bit), 1);
    CHECK_EQ(int(Screen::cell_of(1, 1).bit), 8);  // 右下
    CHECK_EQ(Screen::cell_of(2, 0).x, 1);         // 第三列 = 第 1 格
}

TEST(screen_blend_rejects_cells_without_glyph_slot) {
    Screen s(6, 2);
    s.put(0, 0, U'中');                      // 宽字：0 是头格、1 是续格（无字形槽）
    CHECK_EQ(int(s.at(1, 0).cols), 0);
    CHECK(!s.blend(1, 0, U'#', Color::white));  // 续格收不下笔迹
    CHECK(s.blend(0, 0, U'#', Color::white));   // 头格可以叠

    s.put(0, 1, U'A', Color::white, kKeepBg, 2);  // 缩放块：覆盖格无字形槽
    CHECK_EQ(int(s.at(1, 1).scale), 0);
    CHECK(!s.blend(1, 1, U'#', Color::white));
  }

TEST(screen_put_clips_and_keeps_bg) {
    Screen s(4, 2);
    s.put(-1, 0, U'X');  // 越界一律静默丢弃
    s.put(4, 0, U'X');
    s.put(0, 9, U'X');
    CHECK_EQ(s.at(0, 0).ch, U' ');

    s.put(0, 0, U'A', Color::white, rgb_clamped(10, 20, 30));
    CHECK_EQ(int(s.at(0, 0).bg.r), 10);
    s.put(0, 0, U'B');  // 默认底色 = keep：保留原有底色
    CHECK_EQ(int(s.at(0, 0).bg.r), 10);
    CHECK_EQ(s.at(0, 0).ch, U'B');
}

TEST(screen_wide_char_head_and_tail) {
    Screen s(4, 1);
    s.put(0, 0, U'中');
    CHECK_EQ(int(s.at(0, 0).cols), 2);  // 头格
    CHECK_EQ(int(s.at(1, 0).cols), 0);  // 续格没有字形
    CHECK_EQ(s.glyph_at(1, 0), U'中');  // 续格报头格字符
}

TEST(screen_back_with_keep_is_noop) {
    Screen s(2, 1);
    s.put(0, 0, U'A', Color::white, Color::black);
    s.back(0, 0, kKeepBg);  // keep = 不动背景
    CHECK_EQ(int(s.at(0, 0).bg.r), 0);
    s.back(0, 0, rgb_clamped(50, 60, 70));  // 真底色：写入
    CHECK_EQ(int(s.at(0, 0).bg.g), 60);
}

TEST(screen_scaled_cell_reserves_block) {
    // 2x2 大字：头格 scale=2，块内其余格被覆盖（scale=0）
    Screen s(10, 6);
    s.put(2, 1, U'A', Color::white, Color::black, 2);
    CHECK_EQ(int(s.at(2, 1).scale), 2);   // 头格
    CHECK_EQ(int(s.at(2, 1).cols), 1);
    CHECK_EQ(int(s.at(2, 1).ch), int(U'A'));
    CHECK_EQ(int(s.at(3, 1).scale), 0);   // 被覆盖
    CHECK_EQ(int(s.at(2, 2).scale), 0);
    CHECK_EQ(int(s.at(3, 2).scale), 0);
    CHECK_EQ(int(s.glyph_at(2, 1)), int(U'A'));
    CHECK_EQ(int(s.glyph_at(3, 1)), 0);   // 覆盖格自身没有字形

    // 写到块内任意一格都先清整块，否则会留下残缺的块
    s.put(3, 2, U'B', Color::white, Color::black);
    CHECK_EQ(int(s.at(2, 1).scale), 1);   // 头格回到常规
    CHECK_EQ(int(s.at(2, 1).ch), int(U' '));
    CHECK_EQ(int(s.at(3, 2).ch), int(U'B'));

    // 全角缩放块：占 4 列 x 2 行（宽字 2 列 x 2 行）
    Screen w(12, 6);
    w.put(2, 1, U'\u4E2D', Color::white, Color::black, 2);  // 中
    CHECK_EQ(int(w.at(2, 1).cols), 2);
    CHECK_EQ(int(w.at(2, 1).scale), 2);
    CHECK_EQ(int(w.at(3, 1).cols), 0);   // 宽字续格
    CHECK_EQ(int(w.at(4, 1).scale), 0);  // 块内其余格被覆盖
    CHECK_EQ(int(w.at(5, 1).scale), 0);
    CHECK_EQ(int(w.at(2, 2).scale), 0);

    // 宽字左邻紧挨大字头：续格落到块内，必须连带清掉整块（不留孤儿覆盖格）
    w.put(1, 1, U'\u4E2D', Color::white, Color::black);
    bool orphan = false;
    for (int yy = 0; yy < 6; ++yy)
        for (int xx = 0; xx < 12; ++xx)
            if (w.at(xx, yy).scale == 0) orphan = true;
    CHECK(!orphan);
}

TEST(screen_text_forwarding_matches_export) {
    // 转发断言：Screen::to_text 只是 screen_text::to_text 的一行转发，
    // 全角续格与缩放块覆盖格的导出规则必须两边逐字节相同
    Screen wide(4, 2);
    wide.put(0, 0, U'A');
    wide.put(1, 0, U'中');  // 全角：头格 + 续格
    wide.put(0, 1, U'B');
    CHECK_EQ(wide.to_text(), screen_text::to_text(wide));
    CHECK_EQ(screen_text::to_text(wide), std::string("A中 \nB   \n"));

    Screen scaled(4, 2);
    scaled.put(1, 0, U'X', Color::white, Color::black, 2);  // 2x2 块：覆盖格导出空格
    CHECK_EQ(scaled.to_text(), screen_text::to_text(scaled));
    CHECK_EQ(screen_text::to_text(scaled), std::string(" X  \n    \n"));
}

TEST(screen_draw_forwarding_matches_writer) {
    // 转发断言：Screen 的写入方法只是 screen_draw::Writer 的一行转发。
    // 同一组操作分别走方法与 Writer，完整状态（字形/底色/宽字/缩放/笔迹/子位/裁剪）必须一致
    const Color fg = rgb_clamped(10, 20, 30);
    const Color bg = rgb_clamped(40, 50, 60);
    auto snapshot = [](const Screen& s) {
        std::string out = s.to_text();
        for (int y = 0; y < s.height(); ++y)
            for (int x = 0; x < s.width(); ++x) {
                const Cell& c = s.at(x, y);
                out += std::to_string(int(c.ch)) + ":" + std::to_string(int(c.fg.r)) + "," +
                       std::to_string(int(c.fg.g)) + "," + std::to_string(int(c.fg.b)) + ":" +
                       std::to_string(int(c.bg.r)) + "," + std::to_string(int(c.bg.g)) + "," +
                       std::to_string(int(c.bg.b)) + ":" + std::to_string(int(c.cols)) + ":" +
                       std::to_string(int(c.scale)) + ":" + std::to_string(int(c.alpha)) + ":" +
                       std::to_string(int(s.covered_by_scaled_block(x, y))) + "[";
                for (const auto& ink : s.inks(x, y))
                    out += std::to_string(int(ink.ch)) + "," + std::to_string(int(ink.fg.r)) + ".";
                out += "]";
            }
        return out;
    };
    auto by_method = [&](Screen& s) {
        s.put(0, 0, U'A');
        s.put(2, 0, U'中');
        s.put(5, 0, U'Z', fg, bg, 2);
        s.print(0, 1, "hi", fg, bg);
        s.fill(0, 2, 3, 2, U'#', fg, bg);
        s.blend(0, 0, U'x', fg);
        s.back(1, 1, bg);
        s.plot(0, 0, fg);
        s.plot(1, 0, fg);
        s.plot(1, 1, fg);
        s.set(3, 2, s.at(0, 0));
        s.prepend_ink(0, 1, U'p', fg);
        s.forget_plot_bits(1, 1);
        s.clear_transparent();
        s.put(1, 1, U'q', fg, bg);
    };
    auto by_writer = [&](Screen& s) {
        screen_draw::Writer::put(s, 0, 0, U'A', Color::white, kKeepBg, 1);
        screen_draw::Writer::put(s, 2, 0, U'中', Color::white, kKeepBg, 1);
        screen_draw::Writer::put(s, 5, 0, U'Z', fg, bg, 2);
        screen_draw::Writer::print(s, 0, 1, "hi", fg, bg, 1);
        screen_draw::Writer::fill(s, 0, 2, 3, 2, U'#', fg, bg);
        screen_draw::Writer::blend(s, 0, 0, U'x', fg);
        screen_draw::Writer::back(s, 1, 1, bg);
        screen_draw::Writer::plot(s, 0, 0, fg);
        screen_draw::Writer::plot(s, 1, 0, fg);
        screen_draw::Writer::plot(s, 1, 1, fg);
        screen_draw::Writer::set(s, 3, 2, s.at(0, 0));
        screen_draw::Writer::prepend_ink(s, 0, 1, U'p', fg);
        screen_draw::Writer::forget_plot_bits(s, 1, 1);
        screen_draw::Writer::clear_transparent(s);
        screen_draw::Writer::put(s, 1, 1, U'q', fg, bg, 1);
    };
    Screen via_method(8, 5), via_writer(8, 5);
    by_method(via_method);
    by_writer(via_writer);
    CHECK_EQ(snapshot(via_method), snapshot(via_writer));
}

TEST(layered_merge_normalizes_scaled_block) {
    // 上层压掉大字块里的一格 → 整块归一消失（要么完整、要么不出现），只留下上层的字
    LayeredScreen layers;
    layers.reset(8, 8);
    layers.create("lo", 0)->cells.put(2, 2, U'A', Color::white, Color::black, 2);
    layers.create("hi", 1)->cells.put(3, 2, U'@', Color::white, Color::black, 1);

    Screen merged(8, 8);
    CHECK(layers.merge_over(merged, 0, 0));
    CHECK_EQ(int(merged.at(2, 2).scale), 1);  // 头格被清
    CHECK_EQ(int(merged.at(2, 2).ch), int(U' '));
    CHECK_EQ(int(merged.at(3, 2).ch), int(U'@'));  // 上层那个字还在

    bool orphan = false;
    for (int y = 0; y < 8; ++y)
        for (int x = 0; x < 8; ++x)
            if (merged.at(x, y).scale == 0) orphan = true;
    CHECK(!orphan);  // 没有残留的被覆盖格
}

TEST(surface_clips_to_bounds) {
    Screen screen(6, 3);
    Surface surface(screen, 0, 0, 3, 2);  // 面只有左上 3x2
    surface.put(0, 0, U'#', Color::white, Color::black);
    surface.put(3, 0, U'#', Color::white, Color::black);  // 面外：丢弃
    CHECK_EQ(screen.at(0, 0).ch, U'#');
    CHECK_EQ(screen.at(3, 0).ch, U' ');

    surface.fill(0, 0, 1000000, 1000000, U'.', Color::white, kKeepBg);  // 超大尺寸：与面求交
    CHECK_EQ(screen.at(2, 1).ch, U'.');
    CHECK_EQ(screen.at(3, 1).ch, U' ');  // 面外未被填
}

// ---------------------------------------------------------------- layered

TEST(layered_find_create_and_limit) {
    LayeredScreen ls;
    ls.reset(8, 2);
    CHECK(!ls.active());
    Layer* a = ls.create("a", 0);
    CHECK(a != nullptr);
    CHECK(ls.active());
    CHECK(ls.create("a", 5) == a);  // 重名幂等：返回同一个，不改 z
    CHECK_EQ(a->z, 0);
    for (int i = 1; i < LayeredScreen::kMaxLayers; ++i)
        CHECK(ls.create("L" + std::to_string(i), i) != nullptr);
    CHECK(ls.create("overflow", 0) == nullptr);  // 达上限返回 nullptr
    CHECK(ls.remove("a"));
    CHECK(!ls.remove("a"));
}

TEST(layered_merge_transparent_and_overlay) {
    LayeredScreen ls;
    ls.reset(4, 1);
    Screen base(4, 1);
    base.put(0, 0, U'B', Color::white, rgb_clamped(1, 2, 3));

    Layer* top = ls.create("top", 0);
    top->cells.put(1, 0, U'T', Color::white);  // 底色 keep → alpha 保持 0（透明底）

    CHECK(ls.merge_over(base, 0, 0));
    CHECK_EQ(base.at(0, 0).ch, U'B');      // 未写到的格透传
    CHECK_EQ(base.at(1, 0).ch, U'T');      // 上层字形压上
    CHECK_EQ(int(base.at(0, 0).bg.r), 1);  // 底层底色保留
    CHECK_EQ(base.at(2, 0).ch, U' ');

    LayeredScreen none;
    none.reset(4, 1);
    Screen target(4, 1);
    CHECK(!none.merge_over(target, 0, 0));  // 无层：什么都不做
}

// ---------------------------------------------------------------- json 重复键

TEST(json_duplicate_keys_last_wins) {
    json::Object obj;
    std::string err;
    CHECK(obj.parse("{\"a\":1,\"a\":2}", err));
    CHECK_EQ(obj.integer("a"), 2);  // 后者生效
    CHECK_EQ(obj.duplicate_keys().size(), size_t(1));
    CHECK_EQ(obj.duplicate_keys()[0], std::string("a"));
}

// ---------------------------------------------------------------- shelf search

TEST(shelf_search_states) {
    ShelfSearch s;
    CHECK(!s.visible());
    CHECK(!s.editing());
    s.begin_edit();
    CHECK(s.visible());
    CHECK(s.editing());
    s.apply_text("wo");
    CHECK_EQ(s.query(), std::string("wo"));
    s.commit();  // Enter：保留查询、退出输入
    CHECK(s.visible());
    CHECK(!s.editing());
    CHECK_EQ(s.query(), std::string("wo"));
    s.cancel();  // Esc：清空并收起
    CHECK(!s.visible());
    CHECK(s.query().empty());
}

TEST(shelf_search_match_case_insensitive_subsequence) {
    std::vector<CartInfo> carts(3);
    carts[0].id = "snake";  carts[0].name.zh = "贪吃蛇";     carts[0].name.en = "SNAKE";
    carts[1].id = "worms";  carts[1].name.zh = "炮兵对战";   carts[1].name.en = "WORMS";
    carts[2].id = "tetris"; carts[2].name.zh = "俄罗斯方块"; carts[2].name.en = "TETRIS";

    ShelfSearch s;
    s.begin_edit();
    CHECK_EQ(s.match(carts).size(), size_t(3));  // 空查询 = 全部

    s.apply_text("WOR");  // 大小写不敏感
    std::vector<int> hits = s.match(carts);
    CHECK_EQ(hits.size(), size_t(1));
    CHECK_EQ(hits[0], 1);  // worms

    s.cancel();
    s.begin_edit();
    s.apply_text("wr");  // 子序列（不连续）也命中 worms
    hits = s.match(carts);
    CHECK_EQ(hits.size(), size_t(1));
    CHECK_EQ(hits[0], 1);

    s.cancel();
    s.begin_edit();
    s.apply_text("方块");  // 名字本地化后中文名同样可搜
    hits = s.match(carts);
    CHECK_EQ(hits.size(), size_t(1));
    CHECK_EQ(hits[0], 2);  // tetris（俄罗斯方块）

    s.cancel();
    s.begin_edit();
    s.apply_text("zzz");  // 拼不出子序列：空结果
    CHECK(s.match(carts).empty());
}

// ---------------------------------------------------------------- text 折行 / 补齐 / 居中

TEST(text_wrap_by_display_width) {
    const std::vector<std::string> latin = wrap("abcdef", 3);
    CHECK_EQ(latin.size(), size_t(2));
    CHECK_EQ(latin[0], std::string("abc"));
    CHECK_EQ(latin[1], std::string("def"));

    const std::vector<std::string> zh = wrap("中中中中", 4);  // 每行两个全角 = 4 列
    CHECK_EQ(zh.size(), size_t(2));
    CHECK_EQ(zh[0], std::string("中中"));

    const std::vector<std::string> one = wrap("abcdef", 3, 1);  // 只留一行：截断补 "..."
    CHECK_EQ(one.size(), size_t(1));
    CHECK_EQ(one[0], std::string("..."));

    CHECK(wrap("", 3).empty());
}

TEST(text_pad_right) {
    CHECK_EQ(pad_right("ab", 4), std::string("ab  "));
    CHECK_EQ(pad_right("abcdef", 3), std::string("abc"));  // 超宽先截断
    CHECK_EQ(display_width(pad_right("中文", 5)), 5);
}

TEST(text_centered_x) {
    CHECK_EQ(centered_x("ab", 0, 10), 4);
    CHECK_EQ(centered_x("ab", 5, 6), 7);
    CHECK_EQ(centered_x("aaaa", 0, 2), 0);  // 比可用宽还宽：夹到 base
}

// ---------------------------------------------------------------- json flag

TEST(json_flag_variants) {
    json::Object obj;
    std::string err;
    CHECK(obj.parse("{\"a\":true,\"b\":false,\"c\":\"yes\",\"d\":\"on\",\"e\":\"nope\"}", err));
    CHECK(obj.flag("a"));
    CHECK(!obj.flag("b"));
    CHECK(obj.flag("c"));              // 字符串 "yes"
    CHECK(obj.flag("d"));              // 字符串 "on"
    CHECK(!obj.flag("e"));
    CHECK(obj.flag("missing", true));  // 缺项取 fallback
}

// ---------------------------------------------------------------- config 校验

TEST(config_clamps_and_validates) {
    const std::filesystem::path path =
        unit_scratch("config_clamp.json");
    {
        std::ofstream out(path.string());
        out << R"({"crt_level":99,"music_volume":999,"sfx_volume":-5,"fps":90,)"
               R"("shelf_style":"bogus","volume":55})";
    }
    const Config c = load_config(path.string());
    CHECK_EQ(c.crt_level, kCrtLevelCount - 1);        // 越界钳到最高档
    CHECK_EQ(c.music_volume, 100);                    // 越界钳到 0..100
    CHECK_EQ(c.sfx_volume, 0);
    CHECK_EQ(c.fps, 60);                              // 90 落到最近档（|60-90| 与 |120-90| 并列，取更小）
    // 卡带架样式名原样保留：它可以是 list / window，也可以是某个 shelf 包 id。
    // "有没有对应包"由内容库在扫描后裁决（找不到回退 window），配置层不替它判断
    CHECK_EQ(c.shelf_style, std::string("bogus"));
    std::error_code ec;
    std::filesystem::remove(path, ec);
}

TEST(config_font_size_scope_and_clamp) {
    const std::filesystem::path path =
        unit_scratch("config_font_size.json");
    const auto load_json = [&path](const char* text) {
        std::ofstream out(path.string());
        out << text;
        out.close();
        return load_config(path.string());
    };

    // 字号住在 theme 作用域里（与 font 同级）。加载时只做**宽松**钳制（[min, 硬上限]）——
    // 真正的可调范围由当前字体方案声明（Mod 可抬高 max），加载时还不知道方案
    CHECK_EQ(load_json(R"({"theme":{"font_size":99}})").font_size, kMaxFontPxCeiling);
    CHECK_EQ(load_json(R"({"theme":{"font_size":28}})").font_size, 28);  // 落在硬上限内 → 原样保留
    CHECK_EQ(load_json(R"({"theme":{"font_size":3}})").font_size, kMinFontPx);   // 越界钳到下限
    CHECK_EQ(load_json(R"({"theme":{"font_size":-1}})").font_size, 0);           // 负数 = 跟随方案
    CHECK_EQ(load_json(R"({"theme":{"font":"x"}})").font_size, 0);               // 缺省 = 跟随方案
    // 写错作用域（顶层）不生效：字号是主题的一部分，不该被顶层同名键抢走
    CHECK_EQ(load_json(R"({"font_size":20})").font_size, 0);

    std::error_code ec;
    std::filesystem::remove(path, ec);
}

TEST(config_escapes_special_names) {
    namespace fs = std::filesystem;
    const fs::path path = unit_scratch("config-escape.json");

    Config c;
    c.skin = "中\"\\\n\t";  // 中文 / 引号 / 反斜杠 / 换行 / 制表符
    c.boot = "back\\slash";
    c.sound = "夜间";
    c.font = "f\"ont";
    c.language = "en";
    c.shelf_style = "window\"x";
    c.mods_disabled = {"mod\"1", "back\\slash"};
    save_config(path.string(), c);

    // 落盘内容必须是合法 JSON：引号/反斜杠/换行都不能把配置写坏
    std::ifstream in(path.string());
    CHECK(in.good());
    std::string text, line;
    while (std::getline(in, line)) text += line + "\n";
    in.close();
    json::Object disk;
    std::string err;
    CHECK(disk.parse(text, err));
    CHECK(disk.object("theme") != nullptr);
    CHECK_EQ(disk.object("theme")->str("skin"), c.skin);

    const Config r = load_config(path.string());
    CHECK_EQ(r.skin, c.skin);
    CHECK_EQ(r.boot, c.boot);
    CHECK_EQ(r.sound, c.sound);
    CHECK_EQ(r.font, c.font);
    CHECK_EQ(r.language, c.language);
    CHECK_EQ(r.shelf_style, c.shelf_style);
    CHECK_EQ(r.mods_disabled.size(), size_t(2));
    CHECK_EQ(r.mods_disabled[0], c.mods_disabled[0]);
    CHECK_EQ(r.mods_disabled[1], c.mods_disabled[1]);

    std::error_code ec;
    fs::remove(path, ec);
}

TEST(config_atomic_write_keeps_old_on_failure) {
    namespace fs = std::filesystem;
    const fs::path path = unit_scratch("config-atomic.json");
    const fs::path tmp = fs::path(path.string() + ".tmp");
    std::error_code ec;
    fs::remove_all(path, ec);
    fs::remove_all(tmp, ec);

    Config old_cfg;
    old_cfg.skin = "old";
    save_config(path.string(), old_cfg);
    CHECK_EQ(load_config(path.string()).skin, std::string("old"));

    // 掉电模拟：临时文件位置被目录占住 → 写不进去，旧配置必须原样保留
    CHECK(fs::create_directory(tmp, ec));
    Config new_cfg;
    new_cfg.skin = "new";
    save_config(path.string(), new_cfg);
    CHECK_EQ(load_config(path.string()).skin, std::string("old"));

    // 故障排除后写回：新值生效，旧文件被整份替换
    fs::remove_all(tmp, ec);
    save_config(path.string(), new_cfg);
    CHECK_EQ(load_config(path.string()).skin, std::string("new"));

    fs::remove_all(path, ec);
}

TEST(config_bad_json_falls_back_and_ignores_unknown) {
    namespace fs = std::filesystem;
    const fs::path path = unit_scratch("config-bad.json");
    const auto load_text = [&path](const char* text) {
        std::ofstream out(path.string());
        out << text;
        out.close();
        return load_config(path.string());
    };

    // 截断的 JSON：解析失败 → 整体默认值（主机必须开得起来，绝不卡死在启动）
    Config c = load_text(R"({"theme":{"skin":"broken")");
    CHECK_EQ(c.skin, std::string("default"));
    CHECK_EQ(c.language, std::string("zh"));

    // 未知字段忽略，已知字段照读（手写配置常带超前字段）
    c = load_text(R"({"theme":{"skin":"neon","future":true},)"
                  R"("unknown":{"x":[1,2]},"fps":120})");
    CHECK_EQ(c.skin, std::string("neon"));
    CHECK_EQ(c.fps, 120);

    // 旧配置的单个 volume 字段仍是两层音量的初值（兼容路径不变）
    c = load_text(R"({"volume":55})");
    CHECK_EQ(c.music_volume, 55);
    CHECK_EQ(c.sfx_volume, 55);

    std::error_code ec;
    fs::remove(path, ec);
}

// ---------------------------------------------------------------- ui 组件

TEST(ui_rect_centered) {
    const ui::Rect area{0, 0, 100, 40};
    const ui::Rect r = ui::Rect::centered(area, 20, 10);
    CHECK_EQ(r.w, 20);
    CHECK_EQ(r.h, 10);
    CHECK_EQ(r.x, 40);  // (100-20)/2
    CHECK_EQ(r.y, 15);  // (40-10)/2
}

TEST(ui_navigate_wrap_and_actions) {
    Input input;
    ui::NavAction action = ui::NavAction::none;

    CHECK_EQ(ui::navigate(input, 3, 1, action), 1);  // 无输入：原样返回
    CHECK(action == ui::NavAction::none);

    input.set_key(Key::up, true);  // 上：循环到末尾
    CHECK_EQ(ui::navigate(input, 3, 0, action), 2);
    input.next_frame();

    input.set_key(Key::down, true);  // 下：循环到开头
    CHECK_EQ(ui::navigate(input, 3, 2, action), 0);
    input.next_frame();

    input.set_key(Key::a, true);  // 确认
    ui::navigate(input, 3, 0, action);
    CHECK(action == ui::NavAction::confirm);
    input.next_frame();

    input.set_key(Key::b, true);  // 取消
    ui::navigate(input, 3, 0, action);
    CHECK(action == ui::NavAction::cancel);

    CHECK_EQ(ui::navigate(input, 0, 5, action), 0);  // 空列表
}

TEST(ui_bar_nonfinite_ratio_is_zero_and_clamped) {
    Screen screen(12, 1);
    const ui::Style style;
    const auto render = [&screen, &style](float ratio) {
        ui::bar(screen, 0, 0, 12, ratio, style);
    };

    // 非有限值不得进入 int 转换（NaN/inf -> int 是 UB），一律按 0：内部全是未填充格
    render(std::numeric_limits<float>::quiet_NaN());
    CHECK_EQ(screen.at(1, 0).ch, U'-');
    CHECK_EQ(screen.at(10, 0).ch, U'-');
    render(std::numeric_limits<float>::infinity());
    CHECK_EQ(screen.at(1, 0).ch, U'-');
    render(-std::numeric_limits<float>::infinity());
    CHECK_EQ(screen.at(1, 0).ch, U'-');

    // 有限值钳到 0..1
    render(-1.0f);
    CHECK_EQ(screen.at(1, 0).ch, U'-');
    render(2.0f);
    CHECK_EQ(screen.at(1, 0).ch, U'#');
    CHECK_EQ(screen.at(10, 0).ch, U'#');
    CHECK_EQ(screen.at(0, 0).ch, U'[');
    CHECK_EQ(screen.at(11, 0).ch, U']');

    // 0.5：内部 10 格填 5 格
    render(0.5f);
    CHECK_EQ(screen.at(5, 0).ch, U'#');
    CHECK_EQ(screen.at(6, 0).ch, U'-');
}

TEST(ui_frame_bar_nonfinite_ratio_is_zero) {
    // 声明式组件的 bar 是第二条绘制路径：同一套"非有限按 0、其余钳 0..1"的规则
    const auto filled_cells = [](float ratio) {
        Screen screen(12, 1);
        ui::State state;
        const ui::Theme theme;
        ui::Frame frame("unit.bar", state, theme, ui::Rect{0, 0, 12, 1}, nullptr);
        ui::Node& bar = frame.root().add_bar("hp", ratio);
        bar.props.width = 12;  // 固定宽度：bar 的自然宽是 20，超出测试屏
        frame.run();
        frame.paint(screen);
        int filled = 0;
        for (int x = 0; x < 12; ++x)
            if (screen.at(x, 0).ch == U'#') ++filled;
        return filled;
    };

    CHECK_EQ(filled_cells(std::numeric_limits<float>::quiet_NaN()), 0);
    CHECK_EQ(filled_cells(std::numeric_limits<float>::infinity()), 0);
    CHECK_EQ(filled_cells(0.5f), 5);   // 12 格 - 两侧括号 = 10 格，一半
    CHECK_EQ(filled_cells(2.0f), 10);  // 钳到 1 = 满
}

TEST(ui_icon_width_uses_display_width) {
    // 多字节字符画的宽度必须按显示宽度（"中" = 2 列），不是字节数（3）：
    // 卡带 sprite 的宽/居中与 icon 共用这一条度量
    Screen screen(14, 3);
    const std::vector<std::string> art{"中"};
    const std::map<char, Color> colors;
    ui::icon(screen, art, colors, 6, 1, 1, 1.0f, Color::white);
    CHECK_EQ(screen.at(5, 1).ch, U'中');  // draw_w = 2 -> x0 = 6 - 1
    CHECK_EQ(int(screen.at(5, 1).cols), 2);
    CHECK_EQ(int(screen.at(6, 1).cols), 0);  // 宽字续格
}

TEST(ui_icon_step_downsamples) {
    const std::map<char, Color> colors;
    // step = 2：源图 4x2 每 2 列/行取一个 -> 成品 2x1；中心 (5,5) -> 左上 (4,5)
    Screen s(12, 8);
    const std::vector<std::string> art{"abcd", "efgh"};
    ui::icon(s, art, colors, 5, 5, 2, 1.0f, Color::white);
    CHECK_EQ(s.at(4, 5).ch, U'a');
    CHECK_EQ(s.at(5, 5).ch, U'c');
    CHECK_EQ(s.at(3, 5).ch, U' ');
    CHECK_EQ(s.at(4, 6).ch, U' ');  // 第 2 行被降采样掉
    CHECK_EQ(s.at(5, 6).ch, U' ');

    // step < 1 钳到 1（旧实现会整只不画），即逐字符
    Screen one(12, 8);
    ui::icon(one, std::vector<std::string>{"ab"}, colors, 5, 5, 0, 1.0f, Color::white);
    CHECK_EQ(one.at(4, 5).ch, U'a');
    CHECK_EQ(one.at(5, 5).ch, U'b');

    // 超大 step 不溢出：向上取整退化为 1 个采样格
    Screen huge(12, 8);
    ui::icon(huge, std::vector<std::string>{"ab"}, colors, 5, 5,
             std::numeric_limits<int>::max(), 1.0f, Color::white);
    CHECK_EQ(huge.at(5, 5).ch, U'a');
    CHECK_EQ(huge.at(4, 5).ch, U' ');
}

TEST(ui_icon_brightness_clamped) {
    const std::vector<std::string> art{"#"};
    const std::map<char, Color> colors;
    const Color base{200, 100, 50};

    // brightness = 0：字形仍占格，前景全黑（视觉上等于"画空"）
    Screen zero(12, 8);
    ui::icon(zero, art, colors, 5, 5, 1, 0.0f, base);
    CHECK_EQ(zero.at(5, 5).ch, U'#');
    CHECK_EQ(int(zero.at(5, 5).fg.r), 0);
    CHECK_EQ(int(zero.at(5, 5).fg.g), 0);
    CHECK_EQ(int(zero.at(5, 5).fg.b), 0);

    // 非有限按 1，> 1 钳到 1：都等于原色
    Screen nan(12, 8);
    ui::icon(nan, art, colors, 5, 5, 1, std::numeric_limits<float>::quiet_NaN(), base);
    CHECK_EQ(int(nan.at(5, 5).fg.r), 200);
    CHECK_EQ(int(nan.at(5, 5).fg.g), 100);
    CHECK_EQ(int(nan.at(5, 5).fg.b), 50);

    Screen over(12, 8);
    ui::icon(over, art, colors, 5, 5, 1, 5.0f, base);
    CHECK_EQ(int(over.at(5, 5).fg.r), 200);
    CHECK_EQ(int(over.at(5, 5).fg.g), 100);

    // 负数钳到 0 = 全黑
    Screen negative(12, 8);
    ui::icon(negative, art, colors, 5, 5, 1, -2.0f, base);
    CHECK_EQ(int(negative.at(5, 5).fg.r), 0);
}

// ---------------------------------------------------------------- ui 几何原语

namespace {

int count_cells(const Screen& screen, char32_t ch) {
    int n = 0;
    for (int y = 0; y < screen.height(); ++y)
        for (int x = 0; x < screen.width(); ++x)
            if (screen.at(x, y).ch == ch) ++n;
    return n;
}

} // namespace

TEST(ui_line_flat_steep_diagonal_and_reverse) {
    // 平线 / 竖线：整段长度、端点外不画
    Screen flat(12, 8);
    ui::line(flat, 1, 2, 6, 2, U'#', Color::white, Color::black);
    CHECK_EQ(count_cells(flat, U'#'), 6);
    for (int x = 1; x <= 6; ++x) CHECK_EQ(flat.at(x, 2).ch, U'#');
    CHECK_EQ(flat.at(0, 2).ch, U' ');
    CHECK_EQ(flat.at(7, 2).ch, U' ');

    Screen vertical(12, 8);
    ui::line(vertical, 3, 0, 3, 4, U'|', Color::white, Color::black);
    CHECK_EQ(count_cells(vertical, U'|'), 5);
    for (int y = 0; y <= 4; ++y) CHECK_EQ(vertical.at(3, y).ch, U'|');

    // 对角线：每格只写一次（5 格），反向线落在同一组格
    Screen diag(12, 8);
    ui::line(diag, 0, 0, 4, 4, U'/', Color::white, Color::black);
    CHECK_EQ(count_cells(diag, U'/'), 5);
    for (int i = 0; i <= 4; ++i) CHECK_EQ(diag.at(i, i).ch, U'/');

    Screen reverse(12, 8);
    ui::line(reverse, 4, 4, 0, 0, U'/', Color::white, Color::black);
    CHECK_EQ(count_cells(reverse, U'/'), 5);
    for (int i = 0; i <= 4; ++i) CHECK_EQ(reverse.at(i, i).ch, U'/');

    // 陡线：每个扫描行恰好一格，单格不重复写
    Screen steep(12, 8);
    ui::line(steep, 0, 0, 2, 5, U'*', Color::white, Color::black);
    CHECK_EQ(count_cells(steep, U'*'), 6);
    CHECK_EQ(steep.at(0, 0).ch, U'*');
    CHECK_EQ(steep.at(2, 5).ch, U'*');
    for (int y = 0; y <= 5; ++y) {
        int row = 0;
        for (int x = 0; x < 12; ++x)
            if (steep.at(x, y).ch == U'*') ++row;
        CHECK_EQ(row, 1);
    }
}

TEST(ui_line_clips_offscreen) {
    // 屏幕外的超大端点：先裁到视口再光栅化，只画可见段且循环有界
    Screen s(10, 6);
    ui::line(s, -1000, 3, 1000, 3, U'#', Color::white, Color::black);
    CHECK_EQ(count_cells(s, U'#'), 10);
    CHECK_EQ(s.at(0, 3).ch, U'#');
    CHECK_EQ(s.at(9, 3).ch, U'#');

    Screen outside(10, 6);
    ui::line(outside, -5, 0, -5, 5, U'#', Color::white, Color::black);
    CHECK_EQ(count_cells(outside, U'#'), 0);
}

TEST(ui_outline_ring_and_degenerate) {
    Screen ring(14, 10);
    ui::outline(ring, 2, 2, 6, 4, U'#', Color::white, Color::black);
    CHECK_EQ(count_cells(ring, U'#'), 16);  // 2*6 + 2*4 - 4 个角
    for (int x = 2; x <= 7; ++x) {
        CHECK_EQ(ring.at(x, 2).ch, U'#');
        CHECK_EQ(ring.at(x, 5).ch, U'#');
    }
    for (int y = 3; y <= 4; ++y) {
        CHECK_EQ(ring.at(2, y).ch, U'#');
        CHECK_EQ(ring.at(7, y).ch, U'#');
    }
    CHECK_EQ(ring.at(3, 3).ch, U' ');  // 内部不画
    CHECK_EQ(ring.at(6, 4).ch, U' ');

    // w < 2 / h < 2：退化为单列 / 单行 / 单格
    Screen column(10, 6);
    ui::outline(column, 1, 0, 1, 6, U'|', Color::white, Color::black);
    CHECK_EQ(count_cells(column, U'|'), 6);
    Screen row(10, 6);
    ui::outline(row, 0, 1, 6, 1, U'-', Color::white, Color::black);
    CHECK_EQ(count_cells(row, U'-'), 6);
    Screen dot(10, 6);
    ui::outline(dot, 4, 4, 1, 1, U'+', Color::white, Color::black);
    CHECK_EQ(count_cells(dot, U'+'), 1);

    Screen none(10, 6);
    ui::outline(none, 1, 1, 0, 4, U'#', Color::white, Color::black);
    CHECK_EQ(count_cells(none, U'#'), 0);

    // 屏幕只落在矩形内部（四条边都在屏外）：不画任何东西
    Screen huge(10, 6);
    ui::outline(huge, -2, -2, 20, 20, U'#', Color::white, Color::black);
    CHECK_EQ(count_cells(huge, U'#'), 0);
}

TEST(ui_circle_symmetry_and_radius) {
    Screen s(24, 24);
    ui::circle(s, 10, 10, 3, U'o', Color::white, Color::black);
    CHECK_EQ(count_cells(s, U'o'), 16);  // 3 个八分弧步：4 + 8 + 4
    // 四向 + 八向对称
    CHECK_EQ(s.at(13, 10).ch, U'o');
    CHECK_EQ(s.at(7, 10).ch, U'o');
    CHECK_EQ(s.at(10, 13).ch, U'o');
    CHECK_EQ(s.at(10, 7).ch, U'o');
    CHECK_EQ(s.at(11, 13).ch, U'o');
    CHECK_EQ(s.at(9, 13).ch, U'o');
    CHECK_EQ(s.at(11, 7).ch, U'o');
    CHECK_EQ(s.at(9, 7).ch, U'o');
    CHECK_EQ(s.at(13, 11).ch, U'o');
    CHECK_EQ(s.at(7, 11).ch, U'o');
    CHECK_EQ(s.at(12, 12).ch, U'o');
    CHECK_EQ(s.at(8, 8).ch, U'o');
    // 空心 + 半径边界
    CHECK_EQ(s.at(10, 10).ch, U' ');
    CHECK_EQ(s.at(14, 10).ch, U' ');

    // r <= 0 画一格
    Screen zero(8, 8);
    ui::circle(zero, 5, 5, 0, U'.', Color::white, Color::black);
    CHECK_EQ(count_cells(zero, U'.'), 1);
    CHECK_EQ(zero.at(5, 5).ch, U'.');
    ui::circle(zero, 2, 2, -3, U',', Color::white, Color::black);
    CHECK_EQ(zero.at(2, 2).ch, U',');

    // 半径远大于屏幕：有界且不画（圆心在屏内，整圆都在屏外）
    Screen huge(12, 12);
    ui::circle(huge, 5, 5, 1000000, U'x', Color::white, Color::black);
    CHECK_EQ(count_cells(huge, U'x'), 0);

    // 圆心在屏外、半径很大但弧穿过屏幕：仍能画到可见点（且循环有界）
    Screen edge(12, 12);
    ui::circle(edge, -1000, 5, 1000, U'x', Color::white, Color::black);
    CHECK_EQ(edge.at(0, 5).ch, U'x');
}

TEST(ui_geometry_clip_rect) {
    // 第三个裁剪矩形是 Region 的机制：原语只画 clip ∩ 屏幕。x 5..8、y 2..4
    const ui::Rect clip{5, 2, 4, 3};

    Screen line_screen(20, 10);
    ui::line(line_screen, 0, 3, 19, 3, U'#', Color::white, Color::black, &clip);
    CHECK_EQ(count_cells(line_screen, U'#'), 4);
    CHECK_EQ(line_screen.at(5, 3).ch, U'#');
    CHECK_EQ(line_screen.at(8, 3).ch, U'#');
    CHECK_EQ(line_screen.at(4, 3).ch, U' ');
    CHECK_EQ(line_screen.at(9, 3).ch, U' ');

    // 矩形边都在 clip 外（clip 在矩形内部）：一条边也不画
    Screen inside(20, 10);
    ui::outline(inside, 0, 0, 20, 10, U'#', Color::white, Color::black, &clip);
    CHECK_EQ(count_cells(inside, U'#'), 0);

    // 部分相交：只画落在 clip 内的上边与左边段
    Screen partial(20, 10);
    ui::outline(partial, 5, 2, 8, 6, U'#', Color::white, Color::black, &clip);
    CHECK_EQ(count_cells(partial, U'#'), 6);  // 上边 4 + 左边 2
    CHECK_EQ(partial.at(5, 2).ch, U'#');
    CHECK_EQ(partial.at(8, 2).ch, U'#');
    CHECK_EQ(partial.at(5, 4).ch, U'#');
    CHECK_EQ(partial.at(8, 3).ch, U' ');  // 右边 x=12 在 clip 外
    CHECK_EQ(partial.at(5, 5).ch, U' ');

    // 圆：r=1 的四个正方向点都落在 clip 内（对角线不在半径 1 上）
    Screen circle_screen(20, 10);
    ui::circle(circle_screen, 6, 3, 1, U'o', Color::white, Color::black, &clip);
    CHECK_EQ(count_cells(circle_screen, U'o'), 4);
    CHECK_EQ(circle_screen.at(5, 3).ch, U'o');
    CHECK_EQ(circle_screen.at(7, 3).ch, U'o');
    CHECK_EQ(circle_screen.at(6, 2).ch, U'o');
    CHECK_EQ(circle_screen.at(6, 4).ch, U'o');
    CHECK_EQ(circle_screen.at(5, 2).ch, U' ');
}

// ---------------------------------------------------------------- save store

TEST(save_store_roundtrip_and_limits) {
    const std::filesystem::path dir =
        unit_scratch("saves");
    std::error_code ec;
    std::filesystem::remove_all(dir, ec);

    SaveStore store;
    CHECK(store.open(dir.string(), "snake"));
    CHECK_EQ(store.size(), size_t(0));
    CHECK(store.set("high", "9000"));
    CHECK(store.get("high").has_value());
    CHECK_EQ(*store.get("high"), std::string("9000"));

    // 越界一律拒绝：空键 / 超长键 / 键含 '=' / 超长值
    CHECK(!store.set("", "x"));
    CHECK(!store.set(std::string(SaveStore::kMaxKeyLength + 1, 'k'), "x"));
    CHECK(!store.set("a=b", "x"));
    CHECK(!store.set("k", std::string(SaveStore::kMaxValueLength + 1, 'v')));

    // 落盘：另一个实例读到同样的数据
    SaveStore reopened;
    CHECK(reopened.open(dir.string(), "snake"));
    CHECK_EQ(*reopened.get("high"), std::string("9000"));

    // 条目上限：写满 kMaxEntries 后，新键被拒
    CHECK(store.erase("high"));
    for (int i = 0; i < static_cast<int>(SaveStore::kMaxEntries); ++i)
        CHECK(store.set("k" + std::to_string(i), "v"));
    CHECK(!store.set("overflow", "v"));

    std::filesystem::remove_all(dir, ec);
}

TEST(save_store_slots_are_independent) {
    const std::filesystem::path dir = unit_scratch("saves-slots");
    std::error_code ec;
    std::filesystem::remove_all(dir, ec);

    SaveStore slot0;
    CHECK(slot0.open(dir.string(), "game", 0));
    CHECK(slot0.set("progress", "10"));

    SaveStore slot3;
    CHECK(slot3.open(dir.string(), "game", 3));
    CHECK(slot3.set("progress", "30"));
    CHECK_EQ(*slot3.get("progress"), std::string("30"));

    // 两个槽位落成两个文件，互不覆盖
    CHECK(std::filesystem::exists(dir / "game.sav"));
    CHECK(std::filesystem::exists(dir / "game.s3.sav"));
    SaveStore reopen0;
    CHECK(reopen0.open(dir.string(), "game", 0));
    CHECK_EQ(*reopen0.get("progress"), std::string("10"));
    // 越界槽位钳到上限而不是报错崩溃
    SaveStore clamp;
    CHECK(clamp.open(dir.string(), "game", 99));

    std::filesystem::remove_all(dir, ec);
}

TEST(save_store_typed_values_roundtrip) {
    const std::filesystem::path dir = unit_scratch("saves-typed");
    std::error_code ec;
    std::filesystem::remove_all(dir, ec);

    SaveStore store;
    CHECK(store.open(dir.string(), "typed"));
    CHECK(store.set("name", SaveStore::Value::of_text("ADA")));
    CHECK(store.set("level", SaveStore::Value::of_number(12.5)));
    CHECK(store.set("seen", SaveStore::Value::of_boolean(true)));
    // 非有限数不是合法 JSON：拒绝入库
    CHECK(!store.set("bad", SaveStore::Value::of_number(
                                 std::numeric_limits<double>::infinity())));

    SaveStore reopened;
    CHECK(reopened.open(dir.string(), "typed"));
    const auto level = reopened.get_value("level");
    CHECK(level.has_value() && level->kind == SaveStore::Value::Kind::number);
    CHECK(std::abs(level->number - 12.5) < 1e-12);
    const auto seen = reopened.get_value("seen");
    CHECK(seen.has_value() && seen->kind == SaveStore::Value::Kind::boolean && seen->boolean);
    CHECK_EQ(*reopened.get("name"), std::string("ADA"));
    CHECK_EQ(*reopened.get("level"), std::string("12.5"));  // 文本视图

    std::filesystem::remove_all(dir, ec);
}

TEST(save_store_structured_values_roundtrip) {
    namespace fs = std::filesystem;
    const fs::path dir = unit_scratch("saves-structured");
    std::error_code ec;
    fs::remove_all(dir, ec);

    json::Value stats = json::Value::of_object();
    stats.members["hp"] = json::Value::of_number(100);
    stats.members["mp"] = json::Value::of_number(30.5);

    json::Value history = json::Value::of_array();
    for (int i = 1; i <= 3; ++i) history.items.push_back(json::Value::of_number(i));

    json::Value tags = json::Value::of_array();
    tags.items.push_back(json::Value::of_text("a"));
    tags.items.push_back(json::Value::of_text("b"));

    json::Value profile = json::Value::of_object();
    profile.members["name"] = json::Value::of_text("ADA");
    profile.members["seen"] = json::Value::of_boolean(true);
    profile.members["stats"] = stats;
    profile.members["history"] = history;
    profile.members["tags"] = tags;

    SaveStore store;
    CHECK(store.open(dir.string(), "struct"));
    CHECK(store.set("profile", profile));
    CHECK(store.get_value("profile").has_value());

    // 落盘正文就是 JSON：数组与嵌套对象原样，不是被拍平成字符串
    {
        std::ifstream in(dir / "struct.sav", std::ios::binary);
        std::string text, line;
        while (std::getline(in, line)) text += line + '\n';
        in.close();
        CHECK(text.find("\"history\":[1,2,3]") != std::string::npos);
        CHECK(text.find("\"stats\":{") != std::string::npos);
        CHECK(text.find("\"tags\":[\"a\",\"b\"]") != std::string::npos);
    }

    // 另一个实例读回同构值；文本视图是它的 JSON 文本
    SaveStore reopened;
    CHECK(reopened.open(dir.string(), "struct"));
    const auto loaded = reopened.get_value("profile");
    CHECK(loaded.has_value() && loaded->kind == json::Value::Kind::object);
    CHECK_EQ(loaded->dump(), profile.dump());
    CHECK_EQ(*reopened.get("profile"), profile.dump());

    // 标量值仍按原类型取回
    CHECK(store.set("level", "9"));
    CHECK(store.set("hp", SaveStore::Value::of_number(7)));
    SaveStore again;
    CHECK(again.open(dir.string(), "struct"));
    CHECK_EQ(*again.get("level"), std::string("9"));
    CHECK_EQ(again.get_value("hp")->number, 7.0);

    fs::remove_all(dir, ec);
}

TEST(save_store_rejects_invalid_structured_values) {
    namespace fs = std::filesystem;
    const fs::path dir = unit_scratch("saves-structured-bad");
    std::error_code ec;
    fs::remove_all(dir, ec);

    SaveStore store;
    CHECK(store.open(dir.string(), "bad"));

    // null 不是存档值（Lua 里 null 与"键不存在"无法区分）
    CHECK(!store.set("null", json::Value{}));
    // 嵌套 NaN / Infinity 会让 JSON 变成非法文本：整份拒绝
    json::Value nan = json::Value::of_object();
    nan.members["x"] = json::Value::of_number(std::numeric_limits<double>::quiet_NaN());
    CHECK(!store.set("nan", nan));
    json::Value inf = json::Value::of_array();
    inf.items.push_back(json::Value::of_number(std::numeric_limits<double>::infinity()));
    CHECK(!store.set("inf", inf));
    json::Value with_null = json::Value::of_object();
    with_null.members["x"] = json::Value{};
    CHECK(!store.set("with_null", with_null));

    // 结构化值按其 JSON 文本计入 4096 上限
    json::Value huge = json::Value::of_object();
    huge.members["blob"] = json::Value::of_text(std::string(5000, 'x'));
    CHECK(!store.set("huge", huge));
    json::Value fits = json::Value::of_object();
    fits.members["blob"] = json::Value::of_text(std::string(4000, 'x'));
    CHECK(store.set("fits", fits));

    // 被拒绝的写入不改变内存；已写入的合法值落盘可读
    CHECK(!store.get("nan").has_value());
    CHECK(!store.get("null").has_value());
    SaveStore reopened;
    CHECK(reopened.open(dir.string(), "bad"));
    const auto loaded = reopened.get_value("fits");
    CHECK(loaded.has_value() && loaded->kind == json::Value::Kind::object);

    fs::remove_all(dir, ec);
}

TEST(save_store_tape_code_flattens_structured_values) {
    namespace fs = std::filesystem;
    const fs::path dir = unit_scratch("saves-structured-tape");
    std::error_code ec;
    fs::remove_all(dir, ec);

    json::Value profile = json::Value::of_object();
    profile.members["name"] = json::Value::of_text("ADA");
    json::Value history = json::Value::of_array();
    history.items.push_back(json::Value::of_number(1));
    history.items.push_back(json::Value::of_number(2));
    profile.members["history"] = history;

    SaveStore source;
    CHECK(source.open(dir.string(), "tape"));
    CHECK(source.set("profile", profile));
    const std::string code = source.export_code();
    CHECK(!code.empty());

    // 磁带码只有旧版 key=value 文本语义：结构化值导出为 JSON 文本，导入后成为文本值
    SaveStore target;
    CHECK(target.open(dir.string(), "tape2"));
    CHECK(target.import_code(code));
    const auto imported = target.get_value("profile");
    CHECK(imported.has_value() && imported->kind == json::Value::Kind::text);
    CHECK_EQ(imported->text, profile.dump());
    CHECK_EQ(*target.get("profile"), profile.dump());

    fs::remove_all(dir, ec);
}

TEST(save_store_export_import_roundtrip) {
    const std::filesystem::path dir =
        unit_scratch("saves2");
    std::error_code ec;
    std::filesystem::remove_all(dir, ec);

    SaveStore a;
    CHECK(a.open(dir.string(), "life"));
    CHECK(a.set("gen", "42"));
    CHECK(a.set("best", "1337"));
    const std::string code = a.export_code();
    CHECK(!code.empty());

    SaveStore b;  // 另一台"机器"
    CHECK(b.open(dir.string(), "life2"));
    CHECK(b.import_code(code));
    CHECK_EQ(*b.get("best"), std::string("1337"));

    // 非法码：整份拒绝，原数据不动
    CHECK(!b.import_code("XY"));   // 偶数长度但非十六进制
    CHECK(!b.import_code("ABC"));  // 奇数长度
    CHECK_EQ(*b.get("best"), std::string("1337"));

    std::filesystem::remove_all(dir, ec);
}

TEST(save_store_failed_write_keeps_old_value) {
    namespace fs = std::filesystem;
    const fs::path dir = unit_scratch("saves-rollback");
    std::error_code ec;
    fs::remove_all(dir, ec);

    SaveStore store;
    CHECK(store.open(dir.string(), "power"));
    CHECK(store.set("high", "9000"));

    // 掉电模拟：目标位置被一个目录占住，rename 无法覆盖 → 写盘必须报告失败
    const fs::path target = dir / "power.sav";
    CHECK(fs::remove(target, ec));
    CHECK(fs::create_directory(target, ec));

    CHECK(!store.set("high", "100"));
    CHECK_EQ(*store.get("high"), std::string("9000"));  // 失败后内存仍是磁盘上的旧值
    CHECK(!store.erase("high"));
    CHECK_EQ(*store.get("high"), std::string("9000"));
    CHECK(!fs::exists(fs::path(target.string() + ".tmp"), ec));  // 半份临时文件已清掉

    // 故障排除后同一个实例继续可用：失败不粘住
    fs::remove_all(target, ec);
    CHECK(store.set("high", "100"));
    SaveStore reopened;
    CHECK(reopened.open(dir.string(), "power"));
    CHECK_EQ(*reopened.get("high"), std::string("100"));

    fs::remove_all(dir, ec);
}

TEST(save_store_open_clears_previous_data) {
    namespace fs = std::filesystem;
    const fs::path dir = unit_scratch("saves-reopen");
    std::error_code ec;
    fs::remove_all(dir, ec);

    SaveStore store;
    CHECK(store.open(dir.string(), "alpha"));
    CHECK(store.set("k", "1"));
    // 复用同一个对象：再 open 必须从磁盘重新装载，不能叠加旧内容
    CHECK(store.open(dir.string(), "alpha"));
    CHECK_EQ(store.size(), size_t(1));
    CHECK_EQ(*store.get("k"), std::string("1"));
    // 换一张卡带：上一次的内容必须清空
    CHECK(store.open(dir.string(), "beta"));
    CHECK_EQ(store.size(), size_t(0));
    CHECK(!store.get("k").has_value());
    CHECK(store.set("k", "2"));
    CHECK_EQ(*store.get("k"), std::string("2"));
    // 旧卡带的档没有被污染
    SaveStore alpha;
    CHECK(alpha.open(dir.string(), "alpha"));
    CHECK_EQ(*alpha.get("k"), std::string("1"));

    fs::remove_all(dir, ec);
}

TEST(save_store_reads_legacy_text_format) {
    namespace fs = std::filesystem;
    const fs::path dir = unit_scratch("saves-legacy");
    std::error_code ec;
    fs::remove_all(dir, ec);
    fs::create_directories(dir, ec);
    {
        // 既有 .sav 格式：key=value 换行文本，Windows 行尾，可能夹坏行
        std::ofstream out(dir / "old.sav", std::ios::binary);
        out << "high=42\r\nbest=7\r\nbroken-line\r\na=b=c\r\n";
    }

    SaveStore store;
    CHECK(store.open(dir.string(), "old"));
    CHECK_EQ(store.size(), size_t(3));  // broken-line 没有 '='：忽略
    CHECK_EQ(*store.get("high"), std::string("42"));
    CHECK_EQ(*store.get("best"), std::string("7"));
    CHECK_EQ(*store.get("a"), std::string("b=c"));  // 值里可以带 '='

    // 首次打开即升级为 v2 容器：头部带版本/卡带 id/校验和，正文是 JSON；
    // 旧文件保留为 .v1 备份，升级失败也不会丢原档
    CHECK(store.set("best", "8"));
    std::ifstream in(dir / "old.sav", std::ios::binary);
    std::string text, line;
    std::getline(in, line);
    CHECK(line.rfind("PHOSPHOR-SAVE 2 old ", 0) == 0);
    while (std::getline(in, line)) text += line + "\n";
    in.close();
    CHECK(text.find("\"best\":\"8\"") != std::string::npos);
    CHECK(text.find("\"high\":\"42\"") != std::string::npos);

    std::ifstream backup(dir / "old.sav.v1", std::ios::binary);
    std::string legacy((std::istreambuf_iterator<char>(backup)),
                       std::istreambuf_iterator<char>());
    CHECK(legacy.find("best=7") != std::string::npos);
    CHECK(legacy.find("high=42") != std::string::npos);

    fs::remove_all(dir, ec);
}

TEST(save_store_rejects_corrupted_v2) {
    namespace fs = std::filesystem;
    const fs::path dir = unit_scratch("saves-corrupt");
    std::error_code ec;
    fs::remove_all(dir, ec);
    {
        SaveStore store;
        CHECK(store.open(dir.string(), "corrupt"));
        CHECK(store.set("best", "7"));
    }

    // 改掉正文里的一个字节：校验和不再匹配
    {
        std::ifstream in(dir / "corrupt.sav", std::ios::binary);
        std::string text((std::istreambuf_iterator<char>(in)),
                         std::istreambuf_iterator<char>());
        in.close();
        const size_t payload = text.find('\n');
        if (payload != std::string::npos && payload + 2 < text.size())
            text[payload + 2] = text[payload + 2] == 'a' ? 'b' : 'a';
        std::ofstream out(dir / "corrupt.sav", std::ios::binary | std::ios::trunc);
        out << text;
    }

    SaveStore store;
    CHECK(!store.open(dir.string(), "corrupt"));  // 校验失败：按不可读处理
    CHECK(!store.set("best", "9"));                // 只读：绝不覆盖未知内容
    fs::remove_all(dir, ec);
}

TEST(save_store_exact_limits_and_readonly) {
    namespace fs = std::filesystem;
    const fs::path dir = unit_scratch("saves-limits");
    std::error_code ec;
    fs::remove_all(dir, ec);

    SaveStore store;
    CHECK(store.open(dir.string(), "limits"));
    // 上限是"含"：恰好等于上限必须接受
    CHECK(store.set(std::string(SaveStore::kMaxKeyLength, 'k'),
                    std::string(SaveStore::kMaxValueLength, 'v')));
    CHECK(store.erase(std::string(SaveStore::kMaxKeyLength, 'k')));
    // 换行会破坏 key=value 行格式：键与值都拒绝
    CHECK(!store.set("a\nb", "x"));
    CHECK(!store.set("a", "x\ny"));

    // 存档目录位置被普通文件占住：open 只能只读，写入如实失败（不假装存下了）
    const fs::path not_a_dir = unit_scratch("saves-not-a-dir");
    fs::remove_all(not_a_dir, ec);
    {
        std::ofstream out(not_a_dir);
        out << "not a directory";
    }
    SaveStore blocked;
    CHECK(!blocked.open(not_a_dir.string(), "cart"));
    CHECK_EQ(blocked.size(), size_t(0));
    CHECK(!blocked.set("k", "v"));
    CHECK(!blocked.erase("k"));
    CHECK(!blocked.import_code("00"));
    CHECK(blocked.export_code().empty());

    // 已打开的存档：临时文件位置被目录占住 → 写失败，读到的仍是旧值
    CHECK(store.set("k", "v"));
    const fs::path tmp = dir / "limits.sav.tmp";
    CHECK(fs::create_directory(tmp, ec));
    CHECK(!store.set("k", "w"));
    CHECK_EQ(*store.get("k"), std::string("v"));
    fs::remove_all(tmp, ec);

    fs::remove_all(dir, ec);
    fs::remove_all(not_a_dir, ec);
}

TEST(save_store_readonly_target_rejects_write) {
#ifdef _WIN32
    // 只读文件属性在 Windows 上会让 rename 覆盖失败（POSIX 只检查目录权限，语义不同）
    namespace fs = std::filesystem;
    const fs::path dir = unit_scratch("saves-readonly-target");
    std::error_code ec;
    fs::remove_all(dir, ec);

    SaveStore store;
    CHECK(store.open(dir.string(), "ro"));
    CHECK(store.set("high", "1"));
    const fs::path target = dir / "ro.sav";
    fs::permissions(target, fs::perms::owner_read, ec);
    CHECK(!ec);

    CHECK(!store.set("high", "2"));                    // 旧档只读：写不进去
    CHECK_EQ(*store.get("high"), std::string("1"));    // 内存回滚到磁盘上的值

    fs::permissions(target, fs::perms::owner_all, ec);
    fs::remove_all(dir, ec);
#endif
}

// ---------------------------------------------------------------- 内容库

TEST(content_library_resolve_palette) {
    ContentLibrary lib;
    lib.palettes.push_back(builtin_palette());  // [0] id="default"
    lib.palettes.push_back(raw_palette());      // [1] id="none"

    Skin skin = builtin_skin();
    skin.palette = "none";  // 主题声明使用 raw 色板
    lib.skins.push_back(skin);
    lib.skin_index = 0;

    lib.resolve_palette();
    CHECK_EQ(lib.palette_index, 1);  // 命中 raw（id="none"）

    skin.palette = "does-not-exist";
    lib.skins[0] = skin;
    lib.resolve_palette();
    CHECK_EQ(lib.palette_index, 0);  // 找不到 -> 回落 [0]（兜底）
}

TEST(order_by_recent_puts_recent_first) {
    std::vector<CartInfo> carts(3);
    carts[0].id = "snake";
    carts[1].id = "worms";
    carts[2].id = "tetris";

    order_by_recent(carts, {"tetris", "snake"});  // 最近打开：tetris 最前
    CHECK_EQ(carts[0].id, std::string("tetris"));
    CHECK_EQ(carts[1].id, std::string("snake"));
    CHECK_EQ(carts[2].id, std::string("worms"));  // 不在记录里：排后面，保持原相对顺序

    std::vector<CartInfo> plain(2);
    plain[0].id = "a";
    plain[1].id = "b";
    order_by_recent(plain, {});  // 空记录：原样
    CHECK_EQ(plain[0].id, std::string("a"));
}

TEST(cart_id_validation) {
    CHECK(is_valid_cart_id("snake"));
    CHECK(is_valid_cart_id("net-demo"));
    CHECK(is_valid_cart_id("a1-b2"));
    CHECK(!is_valid_cart_id(""));                     // 空
    CHECK(!is_valid_cart_id("Snake"));                // 大写
    CHECK(!is_valid_cart_id(".."));                   // 越界
    CHECK(!is_valid_cart_id("a/b"));                  // 路径分隔
    CHECK(!is_valid_cart_id("c:x"));                  // 盘符 / 冒号
    CHECK(!is_valid_cart_id(std::string(65, 'a')));   // 超长
}

TEST(cart_files_read_cap_and_path_safety) {
    namespace fs = std::filesystem;
    const fs::path dir = unit_scratch("cart");
    std::error_code ec;
    fs::remove_all(dir, ec);
    fs::create_directories(dir, ec);
    {
        std::ofstream out(dir / "hi.txt", std::ios::binary);
        out << "hello";
    }
    {
        std::ofstream out(dir / "big.txt", std::ios::binary);
        out << std::string(9u * 1024 * 1024, 'x');  // 超过 8 MiB 上限
    }

    const CartFiles files = CartFiles::open(dir.string());
    CHECK(files.valid());
    CHECK_EQ(files.read("hi.txt").value_or(""), std::string("hello"));
    CHECK(!files.read("big.txt").has_value());  // 超限：拒读
    CHECK(files.exists("big.txt"));             // 但存在性如实
    CHECK_EQ(files.size("big.txt").value_or(0), size_t(9u * 1024 * 1024));
    CHECK(!files.read("../escape.txt").has_value());  // 越界：拒读
    CHECK(!files.read("/abs.txt").has_value());       // 绝对路径：拒读
    CHECK(!files.exists("../escape.txt"));

    std::filesystem::remove_all(dir, ec);
}

TEST(json_value_dump_nonfinite_is_null) {
    // 防御性兜底：非有限数不应产出 inf/nan 这种非法 JSON（正常写入路径已在 Host 侧拒绝）
    CHECK_EQ(json::Value::of_number(std::nan("")).dump(), std::string("null"));
    CHECK_EQ(json::Value::of_number(std::numeric_limits<double>::infinity()).dump(), std::string("null"));
    CHECK_EQ(json::Value::of_number(-std::numeric_limits<double>::infinity()).dump(), std::string("null"));
}

} // namespace