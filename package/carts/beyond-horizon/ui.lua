-- ui.lua —— 表现层：HUD / 房间美术 / 探索面板 / 对话框（含选项）/ 状态 / 地图 /
-- 暂停 / 存读档 / 设置 / 章卡 / 小游戏 / 结局 / 失败。
--
-- 只读 game/story，返回界面事件数组；不改状态。全部输入界面走 phos.ui.render
-- （同一帧只允许一个 input=true，由 main.lua 的屏幕状态机保证）。
local Map = require("map")
local Systems = require("systems")
local Art = require("art")
local Story = require("story_engine")

local UI = {}

UI.HUD_H = 2
UI.ROOM_Y = 2
UI.ROOM_H = 25
UI.PANEL_Y = 27
UI.PANEL_H = 17   -- y=27..43
UI.KEY_Y = 44

local function pick(fields)
  if type(fields) == "string" then return fields end
  if type(fields) ~= "table" then return "" end
  return phos.lang.pick(fields)
end

local function centered_x(width, text)
  return math.max(0, (width - phos.text.width(text)) // 2)
end

local function clock(minutes_left) return Systems.clock(minutes_left) end

-- 美术槽 → 块：先按剧情给的 slot，再按房间 id；找不到返回 nil（程序回退文字底图）
-- 房间/场景美术槽：优先剧情声明的 art（room.<id> / scene.<key>），其次当前房间；
-- 有变体时先试 room.<id>.<variant>（美术按变体整块替换，不做叠加）。
local function block_for(slot, variant, room_id)
  if not slot and not room_id then return nil end
  local candidates = {}
  local function add(id) if id then candidates[#candidates + 1] = id end end
  if slot and variant then add("room." .. slot .. "." .. variant); add("scene." .. slot .. "." .. variant) end
  if room_id and variant then add("room." .. room_id .. "." .. variant) end
  if slot then add("room." .. slot); add("scene." .. slot); add(slot) end
  if room_id then add("room." .. room_id) end
  for _, id in ipairs(candidates) do
    local block = Art.get(id)
    if block then return block end
  end
  return nil
end

local function draw_art_block(block, x, y, region)
  if not block then return false end
  if region then
    region:sprite(0, 0, block.rows, Art.colors(block), 1, 1)
  else
    Art.draw(x or 0, y or 0, block)
  end
  return true
end


-- 菜单兜底：list 在部分主题下排版异常，暂停/存读档用逐行 option（键位与 agent 控件仍在）。
function UI.menu(screen_id, rect, title, entries, hint)
  local children = {}
  for _, e in ipairs(entries) do
    children[#children + 1] = { kind = "option", id = e.id, text = e.label,
                                enabled = e.enabled ~= false }
  end
  children[#children + 1] = { kind = "hint", items = hint or {
    phos.input.key_name("up") .. "/" .. phos.input.key_name("down"), phos.lang.pick({ zh = "选择", en = "SELECT" }),
    phos.input.key_name("a"), phos.lang.pick({ zh = "确认", en = "OK" }),
    phos.input.key_name("b"), phos.lang.pick({ zh = "返回", en = "BACK" }),
  } }
  return phos.ui.render{
    screen = screen_id, surface = "playfield", input = true,
    rect = rect, kind = "box", title = title,
    border = "single", opaque = true, bg = "black", gap = 0,
    children = children,
  }
end

-- ── HUD（GDD §8.1：站名 / 房间 / T-剩余 / 信号窗口；四条资源条）────────
function UI.hud(game, story)
  local S, C = phos.screen, phos.color
  local px, py, pw = S.playfield()
  local st = game.state
  local room = Map.ROOMS[st.room] or Map.ROOMS[game.map.current]
  local left = string.format("%s   %s",
    phos.lang.pick({ zh = "长望站 LONGVIEW", en = "LONGVIEW" }),
    room and pick(room.name) or "")
  S.print(px, py, phos.text.fit(left, pw - 26), C.yellow)
  local time_left = math.max(0, Systems.TIME_TOTAL - (st.time or 0))
  local tcol = time_left < 360 and C.red or C.white
  local right = string.format("T-%s   %s %d/7", clock(time_left),
    phos.lang.pick({ zh = "信号", en = "SIG" }), st.counters.signal_windows or 0)
  S.print(px + pw - phos.text.width(right) - 1, py, right, tcol)

  local x = px
  for _, id in ipairs(Systems.RES_ORDER) do
    local def = Systems.RES_BY_ID[id]
    local ratio = Systems.res_ratio(st, id)
    local bar_w = 10
    local fill = math.floor(ratio * bar_w + 0.5)
    local bar = string.rep("#", fill) .. string.rep("-", bar_w - fill)
    local label = string.format("%s[%s]%3d", pick(def.name), bar,
                                math.floor((st.res[id] or 0) + 0.5))
    local col = C.white
    if ratio * 100 <= def.crit then col = C.red
    elseif ratio * 100 <= def.warn then col = C.yellow end
    S.print(x, py + 1, label, col)
    x = x + phos.text.width(label) + 2
  end
end

-- ── 房间美术区（y=2..26，80x25，裁剪；无美术时画星野底）────────────────
function UI.room_art(game, story)
  local S, C = phos.screen, phos.color
  local px, py, pw = S.playfield()
  local area = phos.ui.region(px, UI.ROOM_Y, pw, UI.ROOM_H)
  local st = game.state
  local block = block_for(st.art, st.art_variant, st.room)
  area:clear(C.gray, C.rgb(3, 4, 8))
  if not draw_art_block(block, 0, 0, area) then
    -- 回退：确定性星野（美术未覆盖的房间也不留空）
    for y = 0, area.h - 1, 2 do
      for x = 0, area.w - 1, 2 do
        if (x * 31 + y * 17) % 19 == 0 then area:put(x, y, ".", C.dark_gray) end
      end
    end
    area:print(2, 2, phos.lang.pick({ zh = "（该房间的美术槽尚未提供）", en = "(room art pending)" }),
               C.dark_gray)
  end
end

-- ── 探索面板（y=27..43）：[继续主线] + 房间动作 + 出口 ─────────────────
-- view = { items = { {label, kind, enabled, reason} ... }, objective, room_name, sel }
function UI.explore(game, view)
  local S = phos.screen
  local px, py, pw = S.playfield()
  local items = {}
  for _, item in ipairs(view.items or {}) do
    items[#items + 1] = item.label .. ((not item.enabled and item.reason ~= "") and ("  — " .. item.reason) or "")
  end
  local disabled = {}
  for i, item in ipairs(view.items or {}) do if not item.enabled then disabled[#disabled + 1] = i end end
  local children = {
    { kind = "text", text = view.room_name or "", accent = true },
    { kind = "list", id = "explore/actions", items = items, indent = 2, text_gap = 2,
      disabled = (#disabled > 0) and disabled or nil },
    { kind = "text", text = phos.lang.pick({ zh = "目标：", en = "GOAL: " }) ..
        phos.text.fit(view.objective or "", 60), dim = true },
    { kind = "hint", items = {
      phos.input.key_name("up") .. "/" .. phos.input.key_name("down"), phos.lang.pick({ zh = "选择", en = "SELECT" }),
      phos.input.key_name("a"), phos.lang.pick({ zh = "执行", en = "ACT" }),
      phos.input.key_name("m"), phos.lang.pick({ zh = "地图", en = "MAP" }),
      phos.input.key_name("tab"), phos.lang.pick({ zh = "状态", en = "STATUS" }),
      phos.input.key_name("start"), phos.lang.pick({ zh = "暂停", en = "PAUSE" }),
    } },
  }
  return phos.ui.render{
    screen = "explore", surface = "playfield", input = true,
    rect = { x = px, y = UI.PANEL_Y, w = pw, h = UI.PANEL_H },
    kind = "box", title = phos.lang.pick({ zh = "舱室操作", en = "COMPARTMENT" }),
    border = "single", opaque = true, bg = "black",
    children = children,
  }
end

-- ── 对话框（y=27..43；正文 3 行/页；选项嵌在框内）────────────────────
function UI.dialogue(game, story)
  local S = phos.screen
  local px, py, pw, ph = S.playfield()
  local speaker = story:speaker_id()
  local name = speaker and story:_speaker_name(speaker) or ""
  local color = story:speaker_color()
  local visible = story:visible_page()
  local children = {}
  -- 说话人名字不占正文行：画在 ui.textbox 顶边的 [ ] 牌位（slot speaker x=5,y=0,w=10）
  local speaker_slot = 10
  local speaker_x = 5   -- 文本框顶边 [ ] 的内侧起点（frame x=1 + 内缩 4）
  for _, line in ipairs(visible) do
    children[#children + 1] = { kind = "text", text = line, overflow = "clip" }
  end
  for _ = #visible + 1, 3 do children[#children + 1] = { kind = "text", text = " " } end
  if story:has_choices() then
    local items = {}
    local disabled = {}
    for i, ch in ipairs(story.choices) do
      items[i] = ch.text .. ((not ch.disabled and ch.disabled == false) and "" or "")
      if ch.disabled then
        items[i] = ch.text .. "  — " .. ch.reason
        disabled[#disabled + 1] = i
      end
    end
    children[#children + 1] = { kind = "list", id = "dialogue/choices", items = items,
                                indent = 2, text_gap = 2,
                                disabled = (#disabled > 0) and disabled or nil }
  else
    children[#children + 1] = { kind = "spacer", grow = 1 }
  end
  local status = {}
  if story.auto then status[#status + 1] = phos.lang.pick({ zh = "自动", en = "AUTO" }) end
  if story.ff then status[#status + 1] = phos.lang.pick({ zh = "快进", en = "FF" }) end
  local frame = Art.get and Art.get("ui.textbox") or nil
  if frame then Art.draw(1, UI.PANEL_Y, frame) end
  if name ~= "" then
    local label = phos.text.fit(name, speaker_slot)
    local shown = math.min(phos.text.width(label), speaker_slot)
    local sxp = speaker_x + math.max(0, (speaker_slot - shown) // 2)
    phos.screen.print(sxp, UI.PANEL_Y, label, color or phos.color.white, phos.color.black)
  end
  -- 键位提示固定在文本框底栏（ui.textbox slot hint y=14），不参与正文/选项流式布局；
  -- 否则选项出现时整行提示会被推到选项下面，看起来像“跑进选项框里”
  local hints = string.format("[%s] %s  [%s] %s  [%s] %s  [%s] %s  [%s] %s  [%s] %s",
    phos.input.key_name("a"), phos.lang.pick({ zh = "继续", en = "NEXT" }),
    phos.input.key_name("b"), phos.lang.pick({ zh = "历史", en = "LOG" }),
    phos.input.key_name("x"), phos.lang.pick({ zh = "自动", en = "AUTO" }),
    phos.input.key_name("y"), phos.lang.pick({ zh = "快进", en = "FF" }),
    phos.input.key_name("tab"), phos.lang.pick({ zh = "状态", en = "STATUS" }),
    phos.input.key_name("start"), phos.lang.pick({ zh = "暂停", en = "PAUSE" }))
  local events = phos.ui.render{
    screen = "dialogue", surface = "playfield", input = true,
    rect = { x = px + 3, y = UI.PANEL_Y + 2, w = pw - 6, h = UI.PANEL_H - 3 },
    kind = "column", border = "none", opaque = false, gap = 0,
    children = children,
  }
  -- 最后画：固定在文本框底栏，不被正文/选项的 render 覆盖
  phos.screen.print(px + 2, UI.PANEL_Y + 14, phos.text.fit(hints, pw - 4),
                    phos.color.dark_gray, phos.color.black)
  return events
end

-- ── 状态页（Tab；浮窗，世界冻结）─────────────────────────────────────
function UI.status(game, story)
  local S = phos.screen
  local px, py, pw, ph = S.playfield()
  local st = game.state
  local children = {
    { kind = "text", text = phos.lang.pick({ zh = "资源", en = "RESOURCES" }), accent = true },
  }
  for _, id in ipairs(Systems.RES_ORDER) do
    local def = Systems.RES_BY_ID[id]
    children[#children + 1] = { kind = "stat", text = pick(def.name),
                                value = string.format("%d / %d", math.floor(st.res[id] or 0), def.max) }
  end
  children[#children + 1] = { kind = "divider", fg = "dark_gray" }
  children[#children + 1] = { kind = "text", text = phos.lang.pick({ zh = "计数器", en = "COUNTERS" }), accent = true }
  for _, name in ipairs({ "trust", "communion", "understand", "mercy", "signal_windows" }) do
    children[#children + 1] = { kind = "stat", text = name,
                                value = tostring(st.counters[name] or 0) }
  end
  children[#children + 1] = { kind = "divider", fg = "dark_gray" }
  children[#children + 1] = { kind = "text", text = phos.lang.pick({ zh = "目标", en = "OBJECTIVE" }), dim = true }
  children[#children + 1] = { kind = "text", text = phos.text.fit(
    st.objective and pick(st.objective) or "-", 60) }
  children[#children + 1] = { kind = "hint", items = { phos.input.key_name("tab"), phos.lang.pick({ zh = "关闭", en = "CLOSE" }),
                                                       phos.input.key_name("b"), phos.lang.pick({ zh = "关闭", en = "CLOSE" }) } }
  return phos.ui.render{
    screen = "status", surface = "playfield", input = true,
    -- 全内容区不透明面板：状态页内容比旧浮窗高，半屏浮窗会把最后一行压到框外，
    -- 看起来和底下的对白/场景叠在一起
    rect = { x = px, y = py, w = pw, h = ph },
    padding = { x = 2, y = 1 },
    kind = "box", title = phos.lang.pick({ zh = "观测记录", en = "STATUS" }),
    border = "single", opaque = true, bg = "black",
    children = children,
  }
end

-- ── 地图（M；浮窗）──────────────────────────────────────────────────
function UI.map(game)
  local S = phos.screen
  local px, py, pw, ph = S.playfield()
  local children = {}
  for _, id in ipairs(Map.ORDER) do
    local room = Map.ROOMS[id]
    local unlocked = game.map:is_unlocked(id)
    local here = game.map.current == id
    children[#children + 1] = { kind = "text",
      text = string.format("%s %s", here and ">" or " ", unlocked and pick(room.name) or "???"),
      accent = here, dim = not unlocked }
  end
  children[#children + 1] = { kind = "hint", items = { phos.input.key_name("m") .. "/" .. phos.input.key_name("b"),
                                                       phos.lang.pick({ zh = "关闭", en = "CLOSE" }) } }
  local w, h = 40, 18
  return phos.ui.render{
    screen = "map", surface = "playfield", input = true,
    rect = { x = px + (pw - w) // 2, y = py + (ph - h) // 2, w = w, h = h },
    kind = "box", title = phos.lang.pick({ zh = "长望站 · 舱室图", en = "LONGVIEW · MAP" }),
    border = "single", opaque = true, bg = "black", children = children,
  }
end

-- ── 暂停（场景栈；pause_world + audio_pause）────────────────────────
function UI.pause(has_save)
  local S = phos.screen
  local px, py, pw, ph = S.playfield()
  local w, h = 40, 10
  return UI.menu("pause", { x = px + (pw - w) // 2, y = py + (ph - h) // 2, w = w, h = h },
    phos.lang.pick({ zh = "暂停", en = "PAUSED" }), {
      { id = "pause/resume", label = phos.lang.pick({ zh = "继续", en = "RESUME" }) },
      { id = "pause/save", label = phos.lang.pick({ zh = "保存进度", en = "SAVE" }) },
      { id = "pause/load", label = phos.lang.pick({ zh = "读取进度", en = "LOAD" }) },
      { id = "pause/settings", label = phos.lang.pick({ zh = "设置", en = "SETTINGS" }) },
      { id = "pause/title", label = phos.lang.pick({ zh = "返回标题", en = "TITLE" }) },
    })
end

-- ── 存 / 读档（4 行：自动 + 槽 1-3）───────────────────────────────────
function UI.slots(game, for_load)
  local S = phos.screen
  local px, py, pw, ph = S.playfield()
  local entries = {}
  local first = for_load and 0 or 1
  for slot = first, 3 do
    local summary = game:save_summary(slot)
    local label
    if summary then
      label = string.format("%s  %s  T-%s  %s",
        slot == 0 and phos.lang.pick({ zh = "自动", en = "AUTO" }) or ("槽 " .. slot),
        summary.chapter_title and pick(summary.chapter_title) or ("CH." .. tostring(summary.chapter)),
        clock(math.max(0, Systems.TIME_TOTAL - (summary.time or 0))),
        summary.room or "")
    else
      label = (slot == 0 and phos.lang.pick({ zh = "自动", en = "AUTO" }) or ("槽 " .. slot)) ..
        "  " .. phos.lang.pick({ zh = "（空）", en = "(empty)" })
    end
    entries[#entries + 1] = {
      id = (for_load and "load/" or "save/") .. slot,
      label = label, enabled = summary ~= nil or slot == 0 or not for_load,
    }
  end
  local w, h = 68, 10
  return UI.menu(for_load and "load" or "save",
    { x = px + (pw - w) // 2, y = py + (ph - h) // 2, w = w, h = h },
    for_load and phos.lang.pick({ zh = "读取进度", en = "LOAD" }) or phos.lang.pick({ zh = "保存进度", en = "SAVE" }),
    entries)
end

-- ── 设置（阅读设置；GDD §8.4）────────────────────────────────────────
function UI.settings(game)
  local S = phos.screen
  local px, py, pw, ph = S.playfield()
  local speeds = { "slow", "normal", "fast", "instant" }
  local labels = { slow = "慢", normal = "标准", fast = "快", instant = "瞬显" }
  local entries = {}
  for _, id in ipairs(speeds) do
    entries[#entries + 1] = {
      id = "settings/" .. id,
      label = ((game.settings.speed == id) and "> " or "  ") ..
        phos.lang.pick({ zh = "文字速度：" .. labels[id], en = "Text speed: " .. id }),
    }
  end
  entries[#entries + 1] = { id = "settings/clear", label = phos.lang.pick({ zh = "清除已读记录", en = "Clear read marks" }) }
  local w, h = 46, 11
  return UI.menu("settings", { x = px + (pw - w) // 2, y = py + (ph - h) // 2, w = w, h = h },
    phos.lang.pick({ zh = "设置", en = "SETTINGS" }), entries)
end

-- ── 历史记录（场景栈；B 打开）───────────────────────────────────────
local function history_lines(story, inner_w)
  local lines = {}
  for _, entry in ipairs(story.history) do
    if entry.chapter ~= nil and entry.who ~= nil then
      local prefix = entry.who ~= "" and (entry.who .. "：") or ""
      for _, line in ipairs(Story.wrap(prefix .. entry.text, inner_w)) do lines[#lines + 1] = line end
      lines[#lines + 1] = ""
    end
  end
  return lines
end

-- 返回 (行, 最大回退行数, 内宽, 内高)。offset 是“从最新一行往回退多少行”，
-- 0 = 当前对白在最后一行；不依赖引擎 scroll（不同主题下滚动容器表现不一致）。
function UI.history_metrics(story)
  local S = phos.screen
  local _, _, pw, ph = S.playfield()
  local inner_w = pw - 4
  local text_rows = ph - 5   -- 顶/底边框 + 底部键位行
  local lines = history_lines(story, inner_w)
  return lines, math.max(0, #lines - text_rows), inner_w, text_rows
end

function UI.history(story, offset)
  local S = phos.screen
  local px, py, pw, ph = S.playfield()
  local lines, max_offset, inner_w, text_rows = UI.history_metrics(story)
  offset = math.max(0, math.min(max_offset or 0, offset or 0))
  local last = math.max(0, #lines - offset)
  local first = math.max(1, last - text_rows + 1)
  local count = math.max(0, last - first + 1)
  -- 面板本身用声明式 box（只画框/标题/不透明底），文字用 region 画：
  -- region 是真正的裁剪组件，任何一行都不会越过边框画到机身外壳上。
  local events = phos.ui.render{
    screen = "history", surface = "playfield", input = true,
    rect = { x = px, y = py, w = pw, h = ph },
    kind = "box", title = phos.lang.pick({ zh = "历史记录", en = "HISTORY" }),
    border = "single", opaque = true, bg = "black",
  }
  local area = phos.ui.region(px + 1, py + 1, pw - 2, ph - 2)
  local base = math.max(0, text_rows - count)  -- 少量行时压到底部
  for i = first, last do
    local y = base + (i - first)
    if y >= 0 and y < text_rows then
      area:print(1, y, phos.text.fit(lines[i] or "", inner_w), phos.color.white)
    end
  end
  local at_bottom = offset == 0 and phos.lang.pick({ zh = "最新", en = "LATEST" })
    or string.format(phos.lang.pick({ zh = "回退 %d 行", en = "%d lines back" }), offset)
  local hint = string.format("%s   [%s/%s] %s   [%s/%s] %s",
    at_bottom,
    phos.input.key_name("up"), phos.input.key_name("down"), phos.lang.pick({ zh = "滚动", en = "SCROLL" }),
    phos.input.key_name("b"), phos.input.key_name("start"), phos.lang.pick({ zh = "关闭", en = "CLOSE" }))
  area:print(1, text_rows, phos.text.fit(hint, inner_w), phos.color.dark_gray)
  return events
end

-- ── 章卡（场景栈；pause_world）──────────────────────────────────────
function UI.chapter_card(chapter, title)
  local S, C = phos.screen, phos.color
  local px, py, pw, ph = S.playfield()
  local n = math.max(1, math.min(8, chapter or 1))
  local block = Art.get and Art.get("chapter_card." .. n) or nil
  if block then Art.draw(0, 0, block) else S.fill(px, py, pw, ph, " ", C.white, C.rgb(1, 2, 6)) end
  local t = pick(title)
  S.print(px + math.max(0, (pw - phos.text.width(t) * 2) // 2), py + 24, t, C.white, nil, 2)
  local hint = "[" .. phos.input.key_name("a") .. "] " .. phos.lang.pick({ zh = "继续", en = "CONTINUE" })
  S.print(px + centered_x(pw, hint), py + ph - 3, hint, C.dark_gray)
end

-- ── 小游戏：电力配给（GDD §7.3 上）──────────────────────────────────
function UI.power_mg(mg)
  local S = phos.screen
  local px, py, pw, ph = S.playfield()
  local children = {
    { kind = "text", text = string.format("%s  %s %d/%d   T %s",
        phos.lang.pick({ zh = "电力配给", en = "POWER ROUTING" }),
        phos.lang.pick({ zh = "相位", en = "PHASE" }), mg.phase, mg.phases,
        clock(mg.result and 0 or math.max(0, mg.phase_time - mg.t))) },
    { kind = "bar", ratio = mg:total() / math.max(1, mg.cap) },
    { kind = "text", text = string.format("%s %d / %d",
        phos.lang.pick({ zh = "总容量 已分配", en = "CAP / ALLOC" }), mg:total(), mg.cap) },
    { kind = "divider", fg = "dark_gray" },
  }
  for i, bus in ipairs(mg.buses) do
    local band = mg.bands[i]
    children[#children + 1] = { kind = "text",
      text = string.format("%s %-6s %2d   [%2d..%2d]", (mg.sel == i) and ">" or " ",
                           bus.id, bus.value, band.lo, band.hi),
      accent = (mg.sel == i) }
  end
  children[#children + 1] = { kind = "divider", fg = "dark_gray" }
  children[#children + 1] = { kind = "text",
    text = phos.lang.pick({ zh = "约束：", en = "CONSTRAINT: " }) ..
      (mg.phase % 2 == 1 and phos.lang.pick({ zh = "耀斑抵达，绿区偏移", en = "Solar flare: bands shifted" })
                          or phos.lang.pick({ zh = "通信窗口，带宽收窄", en = "Comm window: tighter bands" })) }
  children[#children + 1] = { kind = "hint", items = {
    phos.input.key_name("up") .. "/" .. phos.input.key_name("down"), phos.lang.pick({ zh = "选母线", en = "BUS" }),
    phos.input.key_name("left") .. "/" .. phos.input.key_name("right"), phos.lang.pick({ zh = "调 1", en = "ADJUST" }),
    phos.input.key_name("b"), phos.lang.pick({ zh = "放弃", en = "GIVE UP" }) } }
  local result = mg.result and ((mg.result == "success") and phos.lang.pick({ zh = "配给成功", en = "SUCCESS" })
    or phos.lang.pick({ zh = "配给失败", en = "FAILED" })) or ""
  if result ~= "" then children[#children + 1] = { kind = "text", text = result, accent = true } end
  local w, h = 72, 16
  return phos.ui.render{
    screen = "mg_power", surface = "playfield", input = false,
    rect = { x = px + (pw - w) // 2, y = py + (ph - h) // 2, w = w, h = h },
    kind = "box", title = phos.lang.pick({ zh = "反应堆配电", en = "REACTOR ROUTING" }),
    border = "double", opaque = true, bg = "black", children = children,
  }
end

-- ── 小游戏：信号解调（GDD §7.3 下）──────────────────────────────────
function UI.signal_mg(mg)
  local S = phos.screen
  local px, py, pw, ph = S.playfield()
  local coh = mg:coherence()
  local wave = {}
  for i = 1, 46 do
    local n = math.sin(i * (1 + (100 - coh) / 12) + phos.sys.time() * (4 + (100 - coh) / 6))
    wave[#wave + 1] = (math.abs(n) > 0.7) and "-" or "."
  end
  local children = {
    { kind = "text", text = string.format("%s   %s %d/%d",
        phos.lang.pick({ zh = "信号解调", en = "SIGNAL DEMOD" }),
        phos.lang.pick({ zh = "窗口", en = "WINDOW" }), mg.windows, mg.total_windows) },
    { kind = "bar", ratio = coh / 100 },
    { kind = "text", text = string.format("%s %d", phos.lang.pick({ zh = "相干度", en = "COHERENCE" }), coh) },
    { kind = "text", text = table.concat(wave), fg = "green" },
    { kind = "divider", fg = "dark_gray" },
    { kind = "text", text = string.format("%s %2d   %s", (mg.sel == 1) and ">" or " ",
        mg.freq, phos.lang.pick({ zh = "（线索：氢线偏红）", en = "(clue: hydrogen line reddened)" })) },
    { kind = "text", text = string.format("%s %2d   %s", (mg.sel == 2) and ">" or " ",
        mg.phase, phos.lang.pick({ zh = "（线索：第三次日食后 +4）", en = "(clue: +4 after the third eclipse)" })) },
  }
  if mg.message == "closer" then children[#children + 1] = { kind = "text", text = phos.lang.pick({ zh = "提示：更近了", en = "Hint: closer" }), dim = true }
  elseif mg.message == "freq_off" then children[#children + 1] = { kind = "text", text = phos.lang.pick({ zh = "提示：频率偏了", en = "Hint: frequency off" }), dim = true }
  elseif mg.message == "phase_off" then children[#children + 1] = { kind = "text", text = phos.lang.pick({ zh = "提示：相位不对", en = "Hint: phase off" }), dim = true }
  elseif mg.message == "locking" then children[#children + 1] = { kind = "text", text = phos.lang.pick({ zh = "正在锁定……", en = "LOCKING..." }), accent = true } end
  if mg.inverted and mg.understand >= 2 then
    children[#children + 1] = { kind = "text", text = phos.lang.pick({ zh = "读数反了（←→ 是反的）", en = "READOUT INVERTED (left/right reversed)" }), danger = true }
  end
  children[#children + 1] = { kind = "hint", items = {
    phos.input.key_name("up") .. "/" .. phos.input.key_name("down"), phos.lang.pick({ zh = "选参数", en = "PARAM" }),
    phos.input.key_name("left") .. "/" .. phos.input.key_name("right"), phos.lang.pick({ zh = "调 1", en = "ADJUST" }),
    phos.input.key_name("a"), phos.lang.pick({ zh = "试解调", en = "TRY" }),
    phos.input.key_name("b"), phos.lang.pick({ zh = "放弃", en = "GIVE UP" }) } }
  local w, h = 72, 18
  return phos.ui.render{
    screen = "mg_signal", surface = "playfield", input = false,
    rect = { x = px + (pw - w) // 2, y = py + (ph - h) // 2, w = w, h = h },
    kind = "box", title = phos.lang.pick({ zh = "长望环 · 解调", en = "LONGVIEW RING" }),
    border = "double", opaque = true, bg = "black", children = children,
  }
end

-- ── 结局 / 失败（场景栈之外的整屏）──────────────────────────────────
function UI.ending(game, ending_id, title, blurb)
  local S, C = phos.screen, phos.color
  local px, py, pw, ph = S.playfield()
  local block = (Art.get and Art.get("ending." .. tostring(ending_id or "")))
    or (Art.get and Art.get("scene.inside")) or nil
  if block then
    Art.draw(0, 0, block)
  else
    S.fill(px, py, pw, 45, " ", C.white, C.rgb(0, 0, 0))
  end
  local t = pick(title)
  S.print(px + math.max(0, (pw - phos.text.width(t) * 2) // 2), py + 12, t, C.white, nil, 2)
  local body = {}
  for _, line in ipairs(Story.wrap(pick(blurb), 60)) do body[#body + 1] = line end
  for i, line in ipairs(body) do
    S.print(px + centered_x(pw, line), py + 18 + i, line, C.gray)
  end
  local hint = "[" .. phos.input.key_name("a") .. "] " .. phos.lang.pick({ zh = "返回标题", en = "BACK TO TITLE" })
  S.print(px + centered_x(pw, hint), py + ph - 5, hint, C.dark_gray)
end

function UI.failure(game, failure_id)
  local S, C = phos.screen, phos.color
  local px, py, pw, ph = S.playfield()
  S.clear(C.white, C.rgb(6, 0, 0))
  local title = failure_id == "F1" and phos.lang.pick({ zh = "缺氧", en = "ASPHYXIA" })
    or phos.lang.pick({ zh = "结构解体", en = "HULL LOSS" })
  S.print(px + math.max(0, (pw - phos.text.width(title) * 2) // 2), py + 14, title, C.red, nil, 2)
  local hint = "[" .. phos.input.key_name("a") .. "] " .. phos.lang.pick({ zh = "读取最近存档", en = "LOAD LAST SAVE" })
    .. "   [" .. phos.input.key_name("b") .. "] " .. phos.lang.pick({ zh = "重开本章", en = "RESTART CHAPTER" })
  S.print(px + centered_x(pw, hint), py + ph - 6, hint, C.gray)
end

-- ── 标题画面（art.title）────────────────────────────────────────────
function UI.title(cart, has_save)
  local S, C = phos.screen, phos.color
  local px, py, pw, ph = S.playfield()
  S.clear(C.white, C.rgb(1, 2, 6))
  local screen = Art.get and Art.get("title.screen") or nil
  if screen then Art.draw(0, 0, screen) end
  local word = Art.get and Art.get("title.wordmark") or nil
  if word then Art.draw(14, 13, word) end
  local name = pick(cart.name)
  S.print(px + math.max(0, (pw - phos.text.width(name) * 3) // 2), py + 5, name, C.white, nil, 3)
  local sub = pick({ zh = "在视界之外，听见里面", en = "LISTENING FROM OUTSIDE THE HORIZON" })
  S.print(px + centered_x(pw, sub), py + 9, sub, C.cyan)
  local w, h = 34, 10
  return UI.menu("title", { x = px + (pw - w) // 2, y = py + 29, w = w, h = h },
    phos.lang.pick({ zh = "长望站", en = "LONGVIEW" }), {
      { id = "title/new", label = phos.lang.pick({ zh = "开始新游戏", en = "NEW GAME" }) },
      { id = "title/load", label = phos.lang.pick({ zh = "读取进度", en = "LOAD" }) },
      { id = "title/settings", label = phos.lang.pick({ zh = "设置", en = "SETTINGS" }) },
      { id = "title/about", label = phos.lang.pick({ zh = "关于", en = "ABOUT" }) },
    }, {
      phos.input.key_name("up") .. "/" .. phos.input.key_name("down"),
      phos.lang.pick({ zh = "选择", en = "SELECT" }),
      phos.input.key_name("a"), phos.lang.pick({ zh = "确认", en = "OK" }),
    })
end

return UI
