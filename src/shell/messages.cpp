#include "shell/messages.hpp"

#include <array>

namespace phos {

namespace {

/// 一条文案：中英两列各自独立维护，都当正式文案写。
/// 含 `%d` 的条目由调用方用 snprintf 格式化（只出现在磁带码的次数显示上）。
struct Entry {
    const char* zh;
    const char* en;
};

constexpr std::array<Entry, static_cast<size_t>(Msg::count)> kTable{{
    // 卡带架
    {"卡带架", "CARTRIDGE SHELF"},
    {"[Enter] 插入   [F] 搜索   [F2] 设置   [Esc] 关机",
     "[Enter] INSERT   [F] SEARCH   [F2] SETTINGS   [Esc] POWER OFF"},
    {"信息", "INFO"},
    {"（无卡带）", "(no cartridges)"},
    {"把 .phos 卡带放进 carts/ 后重启", "drop .phos carts into carts/ and restart"},
    {"  [损坏]", "  [BROKEN]"},
    {"搜索卡带", "SEARCH CARTS"},
    {"输入即筛选   [Enter] 确认   [Esc] 清空并退出", "type to filter   [Enter] ok   [Esc] clear"},
    {"无匹配", "no match"},

    // 设置界面
    {"设置", "SETTINGS"},
    {"[方向键] 选择/改值   [Enter] 确认   [Esc] 返回",
     "[Arrows] ADJUST   [Enter] SELECT   [Esc] BACK"},
    {"机身", "MACHINE"},
    {"声音", "AUDIO"},
    {"系统", "SYSTEM"},
    {"游戏机主题", "CONSOLE THEME"},
    {"显像管滤镜", "TUBE FILTER"},
    {"字体方案", "FONT SCHEME"},
    {"扫描线", "SCANLINES"},
    {"音效包", "SOUND PACK"},
    {"音乐音量", "MUSIC VOLUME"},
    {"音效音量", "SFX VOLUME"},
    {"开机动画", "BOOT ANIMATION"},
    {"卡带架样式", "SHELF VIEW"},
    {"界面语言", "LANGUAGE"},
    {"返回", "BACK"},
    {"默认", "DEFAULT"},
    {"无", "NONE"},
    {"静音", "SILENT"},
    {"内置", "BUILT-IN"},
    {"橱窗", "WINDOW"},
    {"列表", "LIST"},
    {"关", "OFF"},
    {"弱", "LOW"},
    {"中", "MID"},
    {"强", "HIGH"},
    {"中文", "中文 / Chinese"},
    {"English", "English"},

    // 暂停菜单
    {"已暂停", "PAUSED"},
    {"继续游戏", "RESUME"},
    {"磁带码", "TAPE CODE"},
    {"拔出卡带", "EJECT CART"},
    {"[↑ / ↓] 选择   [Enter] 确认   [Esc] 继续", "[Up / Down] CHOOSE   [Enter] CONFIRM   [Esc] RESUME"},

    // 磁带码
    {"磁带码", "TAPE CODE"},
    {"查看", "VIEW"},
    {"输入", "EDIT"},
    {"卡带: ", "CART: "},
    {"本机存档的磁带码（十六进制）：", "This cart's save as a tape code (hex):"},
    {"把磁带码敲进来（只接受 0-9 与 A-F）：", "Type a tape code (0-9 and A-F only):"},
    {"第 %d 行起 / 共 %d 行（↑ / ↓ 滚动）", "from line %d of %d (up / down scrolls)"},
    {"已输入 %d 位", "%d characters typed"},
    {"导入成功（重新插卡后生效）", "imported (re-insert the cart to apply)"},
    {"磁带码无效，未做任何改动", "invalid code, nothing changed"},
    {"此卡带没有存档", "this cart has no save"},
    {"此卡带没有存档，磁带码无处可写。",
     "This cart has no save, so there is no tape code to show or write."},
    {"[← / →] 查看 / 输入   [Enter] 导入   [Esc] 返回",
     "[Left / Right] VIEW / EDIT   [Enter] IMPORT   [Esc] BACK"},
    {"[Esc] 返回", "[Esc] BACK"},

    // 错误屏
    {"卡带故障", "CARTRIDGE FAULT"},
    {"已安全停机 —— 主机无恙", "halted safely - the console is fine"},
    {"[Enter] 返回卡带架", "[Enter] BACK TO SHELF"},

    // 开机自检（内置兜底屏）
    {"内存自检 ............ 通过", "MEMORY CHECK ............ OK"},
    {"显示层 ............. 通过", "DISPLAY LAYER ........... OK"},
    {"外壳层 ............. 通过", "SHELL LAYER ............. OK"},
    {"显像管预热 .......... 通过", "TUBE WARMUP ............. OK"},
    {"等待插入卡带 _", "AWAITING CARTRIDGE _"},
}};

static_assert(kTable.size() == static_cast<size_t>(Msg::count),
              "Msg 新增了条目但没填文案表——表格顺序必须与枚举一致");

} // namespace

Lang lang_from_name(const std::string& name) {
    return name == "en" ? Lang::en : Lang::zh;
}

const char* lang_name(Lang lang) {
    return lang == Lang::en ? "en" : "zh";
}

const char* tr(Lang lang, Msg id) {
    const size_t index = static_cast<size_t>(id);
    if (index >= kTable.size()) return "";
    const Entry& entry = kTable[index];
    const char* text = lang == Lang::en ? entry.en : entry.zh;
    return text != nullptr ? text : entry.zh;
}

} // namespace phos
