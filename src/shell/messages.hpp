#pragma once

#include <string>

namespace phos {

/// 界面语言。**主机界面**的文案从这里取；**卡带文案属于卡带内容**，
/// 卡带用 `phos.sys.language()` 读当前语言、自行选择自己的文案。
enum class Lang { zh, en };

/// 配置里存的名字 ↔ 枚举（"zh" / "en"，未知一律按中文）
Lang lang_from_name(const std::string& name);
const char* lang_name(Lang lang);

/// 主机界面文案的标识。顺序即表格下标，新增只能追加在 count 之前。
enum class Msg {
    // 卡带架
    shelf_title,
    shelf_insert_hint,
    shelf_info,
    shelf_empty,
    shelf_empty_hint,
    shelf_broken,
    shelf_search_title,
    shelf_search_hint,
    shelf_search_empty,

    // 设置界面
    settings_title,
    settings_footer,
    section_machine,
    section_audio,
    section_system,
    row_theme,
    row_filter,
    row_font,
    row_scanlines,
    row_sound,
    row_music,
    row_sfx,
    row_boot,
    row_shelf_view,
    row_language,
    row_back,
    value_default,
    value_none,
    value_silent,
    value_builtin,
    value_window,
    value_list,
    value_crt_off,
    value_crt_low,
    value_crt_mid,
    value_crt_high,
    language_zh,
    language_en,

    // 暂停菜单
    pause_title,
    pause_resume,
    pause_tape,
    pause_eject,
    pause_footer,

    // 磁带码
    tape_title,
    tape_view,
    tape_edit,
    tape_cart,
    tape_code_label,
    tape_input_label,
    tape_scroll,
    tape_typed,
    tape_ok,
    tape_invalid,
    tape_no_save,
    tape_hint_no_save,
    tape_footer,
    tape_back_hint,

    // 错误屏
    error_title,
    error_body,
    error_footer,

    // 开机自检（内置兜底屏）
    boot_memory,
    boot_display,
    boot_shell,
    boot_tube,
    boot_waiting,

    count
};

/// 取文案：未填的条目回落中文，绝不返回空串
const char* tr(Lang lang, Msg id);

} // namespace phos
