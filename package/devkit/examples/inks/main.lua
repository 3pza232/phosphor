-- main.lua —— 叠加与半格示例卡带。它把"引擎该保证什么"逐条摆出来：
-- 每一处只用**新原语**画一样东西，并把期望结果交给观察口（debug_state），
-- tools/draw_smoke.py 据此核对引擎有没有照办 —— 能力本身要有契约级的证据。
--
-- 画面全部画在 draw() 里：本机每帧清屏、卡带每帧重画，写进 init() 的那一帧会被擦掉
local C = phos.color

-- 场景表：x / y 是内容区格坐标，front 是**文本视图**该格应有的字形
-- （文本一格只有一个字形槽，取最前面那一笔；画面里两笔都在，见 docs/engine/drawing.md）
local SCENES = {
  { x = 4, y = 4, front = "|", note = "同格两笔" },
  { x = 10, y = 4, front = "@", note = "底色独立" },
  { x = 16, y = 4, front = "▘", note = "左上" },
  { x = 17, y = 4, front = "▝", note = "右上" },
  { x = 18, y = 4, front = "▖", note = "左下" },
  { x = 19, y = 4, front = "▗", note = "右下" },
  { x = 24, y = 4, front = "▚", note = "同格两次 plot 合并" },
  { x = 30, y = 4, front = "C", note = "叠满三笔" },
}

local cap_rejected = false

local function paint()
  phos.screen.clear()

  -- 1) 同格两笔：put 一个 X，再 blend 一笔 | —— 文本取前面那一笔，画面里两笔都在
  phos.screen.put(4, 4, "X", C.red)
  phos.screen.blend(4, 4, "|", C.green)

  -- 2) 底色独立：@ 不动，底色铺到左右各一格（"背景比字形宽一格"）
  phos.screen.put(10, 4, "@", C.cyan)
  phos.screen.back_rect(9, 4, 3, 1, C.purple)

  -- 3) 半格：四个子位各落一格（位序由引擎定义：左上 / 右上 / 左下 / 右下）
  phos.screen.plot(2 * 16, 2 * 4, C.white)
  phos.screen.plot(2 * 17 + 1, 2 * 4, C.white)
  phos.screen.plot(2 * 18, 2 * 4 + 1, C.white)
  phos.screen.plot(2 * 19 + 1, 2 * 4 + 1, C.white)

  -- 4) 同一格里两次 plot 合并成一个字形：左上 + 右下 = ▚
  phos.screen.plot(2 * 24, 2 * 4, C.white)
  phos.screen.plot(2 * 24 + 1, 2 * 4 + 1, C.white)

  -- 5) 叠画上限：一格最多 3 笔（含 put 那一笔），第 4 笔被拒绝
  phos.screen.put(30, 4, "A", C.yellow)
  phos.screen.blend(30, 4, "B", C.yellow)
  phos.screen.blend(30, 4, "C", C.yellow)
  cap_rejected = not phos.screen.blend(30, 4, "D", C.yellow)

  -- 场景都在第 4 行，行首画一个记号：门禁靠它定位"内容区第 0 列"在整屏里的位置，
  -- 不去假设机身外壳有多宽（皮肤一换，写死的列号就错了）
  phos.screen.print(0, 4, "<<<", C.gray)
end

function init() end

function update(dt) end

function draw() paint() end

function debug_state()
  return { scenes = SCENES, cap_rejected = cap_rejected and 1 or 0 }
end
