#include "core/screen_draw.hpp"

#include "core/log.hpp"
#include "core/text.hpp"

#include <algorithm>

namespace phos::screen_draw {

void Writer::clear_scaled_block_at(ScreenStore& store, int x, int y, Color fg, Color bg, bool keeps_bg) {
    int hx = 0, hy = 0;
    if (!store.scaled_block_of(x, y, hx, hy)) return;
    const Cell& head = store.cells_[static_cast<size_t>(store.index_of(hx, hy))];
    const int bw = head.cols * head.scale;
    const int bh = head.scale;
    for (int cy = hy; cy < hy + bh; ++cy)
        for (int cx = hx; cx < hx + bw; ++cx) {
            if (cx < 0 || cx >= store.w_ || cy < 0 || cy >= store.h_) continue;
            const int index = store.index_of(cx, cy);
            Cell& c = store.cells_[static_cast<size_t>(index)];
            c.ch = U' ';
            c.cols = 1;
            c.scale = 1;
            c.fg = fg;
            c.bg = bg;
            if (!keeps_bg) c.alpha = 255;
            if (!store.inks_.empty()) store.inks_.erase(index);
            if (!store.plot_bits_.empty()) store.plot_bits_.erase(index);
        }
}

void Writer::plot_bit(ScreenStore& store, int x, int y, uint8_t bit, Color fg) {
    if (x < 0 || y < 0 || x >= store.w_ || y >= store.h_) return;
    if ((bit & 0x0F) == 0) return;
    const int index = store.index_of(x, y);
    Cell& cell = store.cells_[static_cast<size_t>(index)];
    // 宽字（头格或续格）与被缩放块覆盖的格上不落半笔：改掉字形会留下半截邻格或残缺的块
    if (cell.cols != 1 || cell.scale != 1) return;
    store.plot_bits_[index] |= static_cast<uint8_t>(bit & 0x0F);
    const uint8_t bits = store.plot_bits_[index];
    cell.ch = ScreenStore::quadrant_glyph(bits);
    cell.fg = fg;
    // 只动字形槽：底色（alpha）与笔迹表都不碰 —— 半笔落在别人画的格子上是叠加，不是替换
}

void Writer::put(ScreenStore& store, int x, int y, char32_t ch, Color fg, Color bg, uint8_t scale) {
    if (y < 0 || y >= store.h_) return;
    // 替换语义：这一格（以及被宽字符连带清理的邻格）的**笔迹与子位累积一并清掉** ——
    // put 是"把这一格改成这个字"，不是"再画一笔"（那是 blend / plot）。
    // 两张表都为空时在这里一次哈希都不做：不叠笔、不画半格的卡带零开销
    const auto drop_inks_at = [&store](int cx, int cy) {
        if (cx < 0 || cx >= store.w_ || cy < 0 || cy >= store.h_) return;
        const int index = store.index_of(cx, cy);
        if (!store.inks_.empty()) store.inks_.erase(index);
        if (!store.plot_bits_.empty()) store.plot_bits_.erase(index);
    };
    // 背景色带"别动背景"标记时，先解析成该格当前背景（全屏唯一的解析点）。
    // 这一路同时意味着"不改变该格底色的存在性"——图层的字形覆盖靠它
    const bool keeps_bg = bg.keep;
    if (keeps_bg && x >= 0 && x < store.w_) {
        bg = store.cells_[static_cast<size_t>(store.index_of(x, y))].bg;
        bg.keep = false;
    }
    const int width = text::char_width(ch);
    // 给了底色就是"这一格的底存在"；带 keep 的写入不动它
    const uint8_t alpha = keeps_bg ? 0 : 255;
    // 缩放规范化：只有 2..ScreenStore::kMaxCellScale 才算"大字号块"，其余按常规
    const uint8_t block = (scale >= 2 && scale <= ScreenStore::kMaxCellScale) ? scale : 1;

    // 写到块内任意一格，先清掉它所在的旧缩放块（否则会留下残缺的块）。零宽字符不写东西，
    // 也就不该顺手动别人
    if (width != 0) {
        clear_scaled_block_at(store, x, y, fg, bg, keeps_bg);
        // 新写的是缩放块：把新块覆盖范围内的旧缩放块一并清掉
        if (block >= 2 && x >= 0 && x < store.w_) {
            for (int dy = 0; dy < block; ++dy)
                for (int dx = 0; dx < width * block; ++dx)
                    clear_scaled_block_at(store, x + dx, y + dy, fg, bg, keeps_bg);
        }
    }

    // 先清理被覆盖的旧内容：写到续格上要连带清掉它的头格，
    // 写到全角头格上要连带清掉它的续格——否则会留下半个宽字符
    if (x >= 0 && x < store.w_) {
        Cell& target = store.cells_[static_cast<size_t>(store.index_of(x, y))];
        if (target.cols == 0 && x > 0) {
            Cell& head = store.cells_[static_cast<size_t>(store.index_of(x - 1, y))];
            head.clear_glyph();
            head.fg = fg;
            head.bg = bg;
            if (!keeps_bg) head.alpha = alpha;
            drop_inks_at(x - 1, y);
        } else if (target.cols == 2 && x + 1 < store.w_) {
            Cell& tail = store.cells_[static_cast<size_t>(store.index_of(x + 1, y))];
            tail.clear_glyph();
            tail.fg = fg;
            tail.bg = bg;
            if (!keeps_bg) tail.alpha = alpha;
            drop_inks_at(x + 1, y);
        }
        // 宽字的续格落在 (x+1,y)：那一格上的旧缩放块也要清掉（宽字左邻紧挨大字头时会出现）
        if (width == 2 && x + 1 < store.w_) clear_scaled_block_at(store, x + 1, y, fg, bg, keeps_bg);
    }
    if (x < 0 || x >= store.w_ || width == 0) return;

    Cell& c = store.cells_[static_cast<size_t>(store.index_of(x, y))];
    c.ch = ch;
    c.fg = fg;
    c.bg = bg;
    c.cols = static_cast<uint8_t>(width);
    c.scale = block;
    if (!keeps_bg) c.alpha = alpha;
    drop_inks_at(x, y);

    // 宽字符续格顺手写上；落在最后一列时没有右邻格可写，最右侧就只剩头格——这是原始网格
    // 原有的行为，外壳自己的排版依赖它：贴边时看得见半个宽字，比整格少一个字好。
    // 卡带那一侧的 Surface 反过来——放不下就整格不写（见 core/surface.cpp）
    if (width == 2 && x + 1 < store.w_) {
        Cell& tail = store.cells_[static_cast<size_t>(store.index_of(x + 1, y))];
        // 即将被写成续格的那一格若原本是**全角头格**，它的续格在 x+2：不一起清掉就留下
        // 一个没有头的孤儿续格 —— 文本导出与两条渲染路都会跳过续格，整行因此少一列
        if (tail.cols == 2 && x + 2 < store.w_) {
            Cell& orphan = store.cells_[static_cast<size_t>(store.index_of(x + 2, y))];
            orphan.clear_glyph();
            orphan.fg = fg;
            orphan.bg = bg;
            if (!keeps_bg) orphan.alpha = alpha;
            drop_inks_at(x + 2, y);
        }
        tail.ch = U' ';
        tail.fg = fg;
        tail.bg = bg;
        tail.cols = 0;
        tail.scale = 1;
        if (!keeps_bg) tail.alpha = alpha;
        drop_inks_at(x + 1, y);
    }

    // 缩放块：块内其余格标记为"被覆盖"（scale = 0），空字形、同底色 —— 绘制时整块跳过，
    // 由头格的字形一次画满。宽字续格（上一段写的）不在此列，它仍是"宽字的右半"
    if (block >= 2) {
        for (int dy = 0; dy < block; ++dy)
            for (int dx = 0; dx < width * block; ++dx) {
                if (dx == 0 && dy == 0) continue;                // 头格
                if (width == 2 && dx == 1 && dy == 0) continue;  // 宽字续格
                const int cx = x + dx, cy = y + dy;
                if (cx < 0 || cx >= store.w_ || cy < 0 || cy >= store.h_) continue;
                Cell& cov = store.cells_[static_cast<size_t>(store.index_of(cx, cy))];
                cov.ch = U' ';
                cov.fg = fg;
                cov.bg = bg;
                cov.cols = 1;
                cov.scale = 0;
                if (!keeps_bg) cov.alpha = alpha;
                drop_inks_at(cx, cy);
            }
    }
}

void Writer::print(ScreenStore& store, int x, int y, std::string_view text, Color fg, Color bg, uint8_t scale) {
    const uint8_t block = (scale >= 2 && scale <= ScreenStore::kMaxCellScale) ? scale : 1;
    for (char32_t ch : text::decode(text)) {
        const int width = text::char_width(ch);
        if (width == 0) continue;
        if (x + width * block > store.w_) return;  // 块放不下就停（与 Surface 同一规则，不留半个块）
        put(store, x, y, ch, fg, bg, block);
        x += width * block;  // 缩放块的宽度是 width*scale，按此推进才不互相覆盖
    }
}

void Writer::fill(ScreenStore& store, int x, int y, int w, int h, char32_t ch, Color fg, Color bg) {
    const int width = text::char_width(ch);
    for (int row = y; row < y + h; ++row)
        for (int col = x; col < x + w; ++col) {
            // 用宽字符填充时按两格一组铺，最后若只剩一格则留空（不切半个字）
            if (width == 2 && (col - x) % 2 != 0) continue;
            if (width == 2 && col + 1 >= x + w) {
                put(store, col, row, U' ', fg, bg);
                continue;
            }
            put(store, col, row, ch, fg, bg);
        }
}

bool Writer::blend(ScreenStore& store, int x, int y, char32_t ch, Color fg) {
    if (x < 0 || y < 0 || x >= store.w_ || y >= store.h_) return false;
    // 叠画只收半角字形：宽字要占两格（还要维护续格），那是 put 的活。
    // 收下却只画半格，等于给调用方一个看不见的错误
    if (text::char_width(ch) != 1) {
        log::warn("blend 只支持半角字形（这一笔被忽略）");
        return false;
    }
    const int index = store.index_of(x, y);
    Cell& cell = store.cells_[static_cast<size_t>(index)];
    // 续格与缩放块的覆盖格没有自己的字形槽：笔迹只能落在头格上（那里的字形才参与合成）。
    // 收下却画不出/画出来又会被宽字覆盖，等于给调用方一个看不见的成功
    if (cell.cols == 0 || cell.scale == 0) {
        if (!store.warned_blend_slot_) {
            store.warned_blend_slot_ = true;
            log::warn("blend 落在无字形槽的格上（宽字续格/缩放块覆盖格），这一笔被忽略");
        }
        return false;
    }
    if (cell.ch == U' ') {
        // 这一格原本没有字形：新的一笔直接成为最前面那一笔（不进笔迹表）
        cell.ch = ch;
        cell.fg = fg;
        return true;
    }
    if (cell.ch == ch) {
        // 同一个字形再画一次：改的是这一笔的颜色，不值得为它多记一笔
        cell.fg = fg;
        return true;
    }
    // 新的一笔**在最前面**（后画的压在上面，与纸上作画一致），原先那一笔退进笔迹表。
    // 文本导出取最前面那一笔，所以文本与画面说的是同一件事
    const std::vector<Ink>* list = store.inks_at(x, y);
    const int used = list ? static_cast<int>(list->size()) : 0;
    if (used + 2 > ScreenStore::kMaxInks) {
        // 只报一次：这一格满了是**每分钟几十次**的常态（雨雪密处），
        // 每次都写日志会把日志冲成噪声，真正要看的那条反而被埋掉
        if (!store.warned_ink_cap_) {
            store.warned_ink_cap_ = true;
            log::warn("同一格叠画已达上限（kMaxInks），后续被拒绝的笔不再逐条报出");
        }
        return false;
    }
    const Ink below{cell.ch, cell.fg};
    cell.ch = ch;
    cell.fg = fg;
    // 字形槽换人了：这一格的子位累积随之作废，否则之后再来半笔会拿旧的位掩码去合成
    if (!store.plot_bits_.empty()) store.plot_bits_.erase(index);
    store.inks_[index].push_back(below);  // 表里越靠前越深，末尾就是"刚退下来的那一笔"
    return true;
}

void Writer::back(ScreenStore& store, int x, int y, Color bg) {
    if (x < 0 || y < 0 || x >= store.w_ || y >= store.h_) return;
    // 底色省略（kKeepBg）= 保留该格原有底色：什么都不做。
    // 浮层（ui.region）的 back / back_rect 正是靠这条默认值实现"只改字形、不动底"；
    // 若把 keep 当普通颜色写下去，会在画面上糊出一块白底（kKeepBg 的 rgb 是白）
    if (bg.keep) return;
    Cell& cell = store.cells_[static_cast<size_t>(store.index_of(x, y))];
    cell.bg = bg;
    cell.alpha = 255;  // "写了底色"就是"这一格的底存在"，与 put 给底色同义
}

void Writer::plot(ScreenStore& store, int x2, int y2, Color fg) {
    if (x2 < 0 || y2 < 0 || x2 >= store.w_ * 2 || y2 >= store.h_ * 2) return;
    const ScreenStore::SubCell at = ScreenStore::cell_of(x2, y2);
    plot_bit(store, at.x, at.y, at.bit, fg);
}

void Writer::forget_plot_bits(ScreenStore& store, int x, int y) {
    if (store.plot_bits_.empty() || x < 0 || y < 0 || x >= store.w_ || y >= store.h_) return;
    store.plot_bits_.erase(store.index_of(x, y));
}

void Writer::prepend_ink(ScreenStore& store, int x, int y, char32_t ch, Color fg) {
    if (ch == U' ' || x < 0 || y < 0 || x >= store.w_ || y >= store.h_) return;
    if (text::char_width(ch) != 1) return;  // 同 blend：叠画只收半角
    std::vector<Ink>& list = store.inks_[store.index_of(x, y)];
    list.insert(list.begin(), Ink{ch, fg});
    // 满了就丢**最深**的一笔：新的一笔是表层，丢了它等于这一格根本没画上
    while (static_cast<int>(list.size()) + 1 > ScreenStore::kMaxInks) {
        list.pop_back();
        log::warn("同一格叠画已达上限（kMaxInks），最深的一笔被丢弃");
    }
}

void Writer::set(ScreenStore& store, int x, int y, const Cell& cell) {
    if (x < 0 || y < 0 || x >= store.w_ || y >= store.h_) return;
    const int index = store.index_of(x, y);
    store.cells_[static_cast<size_t>(index)] = cell;
    // 字形槽换人了，子位累积作废
    if (!store.plot_bits_.empty()) store.plot_bits_.erase(index);
    // 搬来的是**可见字形**：笔迹保留 —— 层合成"下层的话 + 上层的话"叠加就靠它。
    // 搬来的是**空格**：这一格从此没有字形，压在它下面的笔迹也一并抹掉
    // （层用空格抹掉下层字形时正是这个语义；留着笔迹会在空位上留下两笔游墨）
    if (cell.ch == U' ' && !store.inks_.empty()) store.inks_.erase(index);
}

void Writer::clear_transparent(ScreenStore& store) {
    Cell transparent_cell;
    transparent_cell.alpha = 0;
    std::fill(store.cells_.begin(), store.cells_.end(), transparent_cell);
    store.inks_.clear();
    store.plot_bits_.clear();
}

} // namespace phos::screen_draw
