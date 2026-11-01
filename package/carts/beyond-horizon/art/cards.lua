-- art/cards.lua —— 8 张章节卡（80x45 全屏）。章号/章名文字由程序叠加：
-- 画面给"章号大字 + 章节母题 + 预留标题带"，不写不可本地化的标题。
-- 稳定 id：chapter_card.1 .. chapter_card.8
local U = require("art.util")

local function merge(...)
  local out = {}
  for _, src in ipairs({ ... }) do
    if src then for k, v in pairs(src) do out[k] = v end end
  end
  return out
end

local DIGIT = {
  ["0"] = { ".#.", "#.#", "#.#", "#.#", ".#." },
  ["1"] = { ".#.", "##.", ".#.", ".#.", "###" },
  ["2"] = { "##.", "..#", ".#.", "#..", "###" },
  ["3"] = { "##.", "..#", ".#.", "..#", "##." },
  ["4"] = { "#.#", "#.#", "###", "..#", "..#" },
  ["5"] = { "###", "#..", "##.", "..#", "##." },
  ["6"] = { ".##", "#..", "###", "#.#", ".#." },
  ["7"] = { "###", "..#", ".#.", ".#.", ".#." },
  ["8"] = { "###", "#.#", "###", "#.#", "###" },
}

-- 5x3 像素字放大 scale 倍画在 (x,y)
local function digit(c, x, y, ch, scale)
  local g = DIGIT[ch]
  for gy = 1, 5 do
    for gx = 1, 3 do
      if g[gy]:sub(gx, gx) == "#" then
        for sy = 0, scale - 1 do
          for sx = 0, scale - 1 do
            U.cput(c, x + (gx - 1) * scale + sx, y + (gy - 1) * scale + sy, "#")
          end
        end
      end
    end
  end
end

-- 章节母题（9x5 小图）
local MOTIF = {
  [1] = [==[
,---,
| ~ |
'---'
]==],
  [2] = [==[
  /
 /
 \
]==],
  [3] = [==[
 ,-.
( o )
 '-'
]==],
  [4] = [==[
~~~~~
 ,-,
]==],
  [5] = [==[
,---,
| | |
'---'
]==],
  [6] = [==[
  +
 +++
  +
]==],
  [7] = [==[
 /\
/==\
\  /
]==],
  [8] = [==[
 ,----,
(  ##  )
 '----'
]==],
}

local function card(n)
  local c = U.canvas(80, 45)
  U.stars(c, U.rng(3300 + n), 90)
  -- 外框 + 四角刻线
  U.chline(c, 0, 0, 80, "-")
  U.chline(c, 0, 44, 80, "-")
  U.cvline(c, 0, 1, 43, "|")
  U.cvline(c, 79, 1, 43, "|")
  U.cput(c, 0, 0, "+") U.cput(c, 79, 0, "+")
  U.cput(c, 0, 44, "+") U.cput(c, 79, 44, "+")
  U.chline(c, 3, 2, 12, "-")
  U.chline(c, 65, 2, 12, "-")
  U.cput(c, 3, 2, "+") U.cput(c, 14, 2, "+")
  U.cput(c, 65, 2, "+") U.cput(c, 76, 2, "+")
  -- 章号：两位数字（01..08），scale=3 居中
  local label = string.format("%02d", n)
  local dw = (3 * 3) * 2 + 3
  local x = (80 - dw) // 2
  digit(c, x, 14, label:sub(1, 1), 3)
  digit(c, x + 12, 14, label:sub(2, 2), 3)
  -- 母题
  U.cstamp(c, 35, 31, MOTIF[n])
  -- 标题带：上一条细线，正文由程序写在这一带之下
  U.chline(c, 8, 36, 64, "-")
  U.chline(c, 8, 43, 64, "-")
  U.cput(c, 8, 36, "+") U.cput(c, 71, 36, "+")
  U.cput(c, 8, 43, "+") U.cput(c, 71, 43, "+")
  return U.canvas_block("chapter_card." .. n, c,
    merge(U.ascii_ink(), {
      ["*"] = "body", ["'"] = "panel", [","] = "panel",
      ["#"] = "white", ["o"] = "ice", ["~"] = "deep",
      ["+"] = "line", ["-"] = "line", ["|"] = "line",
      ["/"] = "line", ["\\"] = "line", ["("] = "line", [")"] = "line",
    }), { note = "80x45 章节卡 " .. label .. "（章名由程序叠加在标题带）" })
end

local K = { order = {}, blocks = {} }
for n = 1, 8 do
  K.order[n] = n
  K[n] = card(n)
  K.blocks["chapter_card." .. n] = K[n]
end
return K
