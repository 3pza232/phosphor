// 纯逻辑单元测试：只覆盖不依赖 GL / GLFW / Lua 的核心（颜色、文本、配置、色板、主题…）。
// 这些是"最该有测试、也最容易崩"的纯函数；有窗口/渲染参与的部分由 tools/ 下的
// 集成脚本（window_smoke / draw_smoke 等）覆盖。

#include "harness.hpp"

#include "core/color.hpp"
#include "core/config.hpp"
#include "core/crt.hpp"
#include "core/json_lite.hpp"
#include "core/layered_screen.hpp"
#include "core/palette.hpp"
#include "core/skin.hpp"
#include "core/surface.hpp"
#include "core/text.hpp"
#include "core/text_input.hpp"
#include "core/ui.hpp"
#include "cart/save_store.hpp"
#include "pack/builtin.hpp"
#include "pack/content_library.hpp"
#include "shell/shelf_search.hpp"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <string>

using namespace phos;
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
        std::filesystem::temp_directory_path() / "phosphor_unit_config.json";

    Config c;
    c.skin = "neon-husk";
    c.boot = "spectrum";
    c.language = "en";
    c.crt_level = 3;
    c.fps = 120;
    c.music_volume = 42;
    c.sfx_volume = 13;
    save_config(path.string(), c);

    const Config r = load_config(path.string());
    CHECK_EQ(r.skin, std::string("neon-husk"));
    CHECK_EQ(r.boot, std::string("spectrum"));
    CHECK_EQ(r.language, std::string("en"));
    CHECK_EQ(r.crt_level, 3);
    CHECK_EQ(r.fps, 120);
    CHECK_EQ(r.music_volume, 42);
    CHECK_EQ(r.sfx_volume, 13);

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
    carts[0].id = "snake";  carts[0].name = "SNAKE";
    carts[1].id = "worms";  carts[1].name = "WORMS";
    carts[2].id = "tetris"; carts[2].name = "TETRIS";

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
        std::filesystem::temp_directory_path() / "phosphor_unit_config_clamp.json";
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
    CHECK_EQ(c.shelf_style, std::string("window"));   // 未知样式忽略、保持默认
    std::error_code ec;
    std::filesystem::remove(path, ec);
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

// ---------------------------------------------------------------- save store

TEST(save_store_roundtrip_and_limits) {
    const std::filesystem::path dir =
        std::filesystem::temp_directory_path() / "phosphor_unit_saves";
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

TEST(save_store_export_import_roundtrip) {
    const std::filesystem::path dir =
        std::filesystem::temp_directory_path() / "phosphor_unit_saves2";
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

} // namespace
