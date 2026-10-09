#pragma once

namespace sol { class state; }

namespace phos {
class HostContext;

/// 注册 phos.assets.* API（包内资源读取：文本 / 按行 / 存在性 / 大小 / 列表）。
/// 只能读当前卡带包内的文件，路径越界一律拒绝；覆盖层 Mod 生效时读到的是替换后的内容。
void register_assets_api(sol::state& lua, HostContext& host);

} // namespace phos
