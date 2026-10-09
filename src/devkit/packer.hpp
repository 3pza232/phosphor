#pragma once

#include <string>

namespace phos::devkit {

/// 打包结果
struct PackResult {
    std::string output_path;
    int file_count = 0;
    std::string cart_id;
    std::string error;
};

/// 将卡带目录打包为 .phos（zip 容器）。
/// 打包前校验 manifest.lua 与入口脚本：校验不通过则不产出文件。
bool pack_cart(const std::string& source_dir, const std::string& output_path, PackResult& result);

/// 建卡时可以一次填好的身份字段（"创建时就命名"）。
/// 留空即走默认值：id ← 目标目录名，name ← id，author ← "you"
/// 放结构体而不是三个相邻字符串参数：id 与 name 相邻，按位置传参极易写反
struct ScaffoldInfo {
    std::string id;
    std::string name;
    std::string author;
};

/// 从 devkit 模板生成新卡带骨架：复制模板目录，替换
/// `__ID__` / `__NAME__` / `__AUTHOR__`（留空的字段走上面的默认值）。
/// 其余身份字段（简介 / 图标 / 侧栏 / 存档声明）由作者在生成的 manifest.lua 里改。
/// 替换值会按 Lua 字符串转义，所以带引号的名字也写不出坏 manifest。
/// template_dir 通常为 "devkit/template"。file_count 返回实际写出的文件数。
bool scaffold_cart(const std::string& template_dir, const std::string& target_dir,
                   const ScaffoldInfo& info, int& file_count, std::string& error);

} // namespace phos::devkit
