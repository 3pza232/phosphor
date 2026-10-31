#include "app/tape_glue.hpp"

#include "api/host_api.hpp"
#include "cart/cartridge.hpp"
#include "cart/save_store.hpp"
#include "core/log.hpp"
#include "shell/shell.hpp"

namespace phos {

SaveStore* TapeGlue::save_of(Cartridge* cart) {
    return cart ? cart->save() : nullptr;
}

void TapeGlue::open(Shell& shell, Cartridge* cart, bool english) {
    // 磁带码界面刚打开：把当前卡带的名字与码交过去（Shell 自己拿不到存档）
    SaveStore* save = save_of(cart);
    shell.set_tape(cart ? cart->info().name.get(english) : std::string(),
                   save ? save->export_code() : std::string(), save != nullptr);
}

void TapeGlue::import(Shell& shell, SaveStore* save, const std::string& code) {
    if (!save) {
        shell.set_tape_result(Shell::TapeResult::no_save);
        return;
    }
    const bool ok = save->import_code(code);
    // 卡带在 init 里读自己的存档，导入后要重新插卡才会用上新数据——如实写在状态行里
    shell.set_tape_result(ok ? Shell::TapeResult::ok : Shell::TapeResult::invalid);
    log::info(std::string("tape import: ") + (ok ? "ok" : "rejected"));
}

void TapeGlue::apply_save_dir(HostContext& host, const std::optional<std::string>& dir) {
    if (dir) host.save_dir = *dir;  // 工具脚本用它隔离真实存档
}

} // namespace phos
