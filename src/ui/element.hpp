#pragma once

#include "core/color.hpp"
#include "core/ui.hpp"

#include <string>
#include <vector>

namespace phos::ui {

/// 元素种类。控件的**行为**由种类决定（焦点、输入、事件、绘制），
/// 外观由 Props 覆盖 + Theme token 决定——不新增"某某样式变体"枚举。
enum class Kind {
    column,    ///< 纵向栈
    row,       ///< 横向栈
    box,       ///< 带边框/标题/内边距的容器
    text,      ///< 一段文字（可折行/省略）
    divider,   ///< 一条横线
    spacer,    ///< 占位（可 grow 撑开）
    list,      ///< 可选列表（光标 + 滚动）
    stat,      ///< "标签 …… 取值"行（取值右对齐）
    option,    ///< 可左右改值的行（外观 = 一段已格式化文本）
    checkbox,  ///< 勾选项
    field,     ///< 文本输入框
    bar,       ///< 进度条
    button,    ///< 按钮行（确认触发）
    hint,      ///< 页脚键位提示（items 为 [键, 说明] 交替）
    table,     ///< 表格：columns 表头（可空）+ rows 数据，列宽可指定
    grid       ///< 等宽网格：按 cols 列逐行摆放子项（卡片/按键/头像墙）
};

enum class Align { start, center, end, stretch };
enum class Overflow { clip, ellipsis, wrap };
enum class Border { none, single, double_line };
/// field 的输入过滤预设（与 core/text_input 的 accept_* 一一对应）
enum class FieldFilter { printable, ascii, digits, hex, letters, any };

/// 四边长（单位：字符格）。margin 在元素外侧、padding 在边框内侧。
struct Insets {
    int l = 0, t = 0, r = 0, b = 0;
};

/// 一个元素的声明式属性。**默认值 = 继承主题**，只有需要偏离主题的地方才填。
///
/// 盒模型与 CSS 同构：content = rect - border - padding；margin 影响兄弟间距与测量。
struct Props {
    // ---- 尺寸与盒模型 ----
    int width = 0;   ///< 0 = 自动
    int height = 0;  ///< 0 = 自动
    int min_w = 0, min_h = 0, max_w = 0, max_h = 0;
    int grow = 0;    ///< 父栈主轴上的伸展权重（>0 参与分配剩余空间）
    Insets margin{};
    Insets padding{};
    int gap = 1;     ///< 容器内子项间距
    int cols = 0;    ///< grid 的列数（0 = 全部排一行）
    Align align_h = Align::stretch;
    Align align_v = Align::start;

    // ---- 外观 ----
    bool opaque = false;        ///< 是否铺实底（不铺则透出下层：卡带浮窗的默认）
    bool has_bg = false;        ///< 显式底色（opaque 时用）
    Color bg{0, 0, 0};
    bool has_fg = false;        ///< 显式前景色
    Color fg{0, 0, 0};
    Border border = Border::none;
    std::string title;          ///< 边框标题（嵌在上边框）
    bool dim = false;           ///< 用 text_dim
    bool accent = false;        ///< 用 accent
    bool danger = false;        ///< 用 danger

    // ---- 文本 ----
    int scale = 1;              ///< 1 = 常规；>=2 成块放大
    Overflow overflow = Overflow::ellipsis;
    int lines = 1;              ///< wrap 时的最大行数

    // ---- 交互 ----
    bool enabled = true;
    int indent = 0;             ///< 选中标记相对内容区左缘的偏移（选项/列表/勾选）
    int text_gap = 1;           ///< 正文相对选中标记的间距
    int label_w = 0;            ///< stat 的标签列宽；0 = 主题默认
    FieldFilter filter = FieldFilter::printable;  ///< field 的输入过滤
    int max_chars = 0;          ///< field 的最大码点数；0 = 不限

    // ---- 数据 ----
    std::string text;                  ///< text/option/button/stat 的正文；field 的占位
    std::string value;                 ///< stat 的右值；option 的当前显示值（由调用方格式化）
    std::vector<std::string> items;    ///< list 的行；hint 的 [键, 说明] 交替
    std::vector<bool> disabled;        ///< list 中不可选的行（与 items 对齐）
    float ratio = 0.0f;                ///< bar 的比例 0..1

    // ---- 表格 ----
    std::vector<std::string> columns;              ///< 表头（空 = 无表头）
    std::vector<std::vector<std::string>> rows;    ///< 每行的单元格（不足补空）
    std::vector<int> widths;                       ///< 各列固定宽度；0 = 按内容自适应
    std::vector<Align> col_align;                  ///< 各列对齐（缺省 start）

    // ---- 定位 ----
    bool absolute = false;  ///< true = 用 x/y 相对父内容区定位，不参与流式布局
    int x = 0, y = 0;
};

/// 元素树的一个节点。**只描述**：不持有跨帧状态（状态按 id 存在 ui::State 里），
/// 每帧由宿主重新构造，因此不需要"清理/销毁"，也不会有状态同步问题。
struct Node {
    Kind kind = Kind::column;
    std::string id;   ///< 稳定标识：焦点、状态、事件、agent 观测都以它为键
    Props props;
    std::vector<Node> children;

    // ---- 布局结果（每帧由 layout 写入，宿主只读） ----
    Rect rect{};   ///< 相对整屏网格的矩形（含 border）
    Rect inner{};  ///< 去掉 border 与 padding 后的内容区
    int natural_w = 0, natural_h = 0;  ///< 本次测量的自然尺寸
    bool focusable = false;

    bool is_container() const {
        return kind == Kind::column || kind == Kind::row || kind == Kind::box ||
               kind == Kind::grid;
    }

    // ---- 构造辅助：id 必填，属性用返回引用就地设置 ----
    Node& add(Kind child_kind, std::string child_id);
    Node& add_text(std::string child_id, std::string text);
    Node& add_column(std::string child_id);
    Node& add_row(std::string child_id);
    Node& add_box(std::string child_id, std::string title = {});
    Node& add_divider(std::string child_id);
    Node& add_spacer(std::string child_id);
    Node& add_list(std::string child_id, std::vector<std::string> items);
    Node& add_option(std::string child_id, std::string text);
    Node& add_checkbox(std::string child_id, std::string text);
    Node& add_button(std::string child_id, std::string text);
    Node& add_field(std::string child_id, std::string text);
    Node& add_bar(std::string child_id, float ratio);
    Node& add_stat(std::string child_id, std::string label, std::string value);
    Node& add_hint(std::string child_id);
    Node& add_table(std::string child_id);
    Node& add_grid(std::string child_id, int cols);
};

/// 根节点：永远是 column（宿主只填它，不改种类）。
Node make_root(std::string id);

} // namespace phos::ui