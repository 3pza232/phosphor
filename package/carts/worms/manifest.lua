-- manifest.lua —— 卡带身份证。字段规范见 docs/cart-format.md
--
-- 建卡时由 CLI 填好 id / name / author：
--   phosphor --new carts/mygame --id mygame --name "我的游戏" --author "你"
-- 之后改身份（标题 / 简介 / 图标 / 侧栏 / 存档）就改本文件，改完立刻生效，
-- 不必重新生成——卡带架与侧栏读的就是这里。

return {
	-- ─── 必填 ───────────────────────────────────────────────
	id = "worms", -- 唯一标识：小写字母/数字/下划线；打包出的 <id>.phos 用它
	name = "WORMS", -- 卡带架与侧栏显示的标题（ASCII，短）
	entry = "main.lua", -- 入口脚本；改了文件名就改这里

	-- ─── 建议填写 ───────────────────────────────────────────
	author = "PZA",
	version = "0.3.0", -- 你自己的版本号（与主机版本无关）
	-- 简介：写表 = 各语言一份（缺 en 回落 zh）；写字符串 = 中英同文
	desc = {
		zh = "炮兵对战：轮流开炮，把对面的虫子轰进海里；人机、同机或局域网都能打。",
		en = "Artillery duel: take turns firing to knock the other team into the sea - vs CPU, hot-seat, or LAN.",
	},

	-- ─── 按需打开 ───────────────────────────────────────────
	-- 右侧栏：声明后把它当第二个屏幕用（phos.panel.*）。0 或删掉这行 = 无侧栏。
	-- 宽度也能在运行时改：phos.panel.resize(w)
	sidebar = { w = 22 },

	-- 存档：改 true 才有 saves/<id>.sav 与 phos.save.*（磁带码也随之可用）
	save = false,

	-- 卡带架里的像素图标（'.' 与空格为透明）：一枚炸开的炮弹
	icon = {
		"   ##   ",
		"  ####  ",
		" ###### ",
		"##.##.##",
		"########",
		" ###### ",
		"  ####  ",
		"   ##   ",
	},
	icon_colors = { ["#"] = { 255, 150, 60 } },

	-- 本卡带用了 phos.layer（第二代）、phos.screen.blend / quadrant / cell_of（第三代）
	-- 与 phos.net（第四代局域网联机）：声明 4，旧主机在卡带架上就明确拒绝，而不是运行到
	-- 那一行才撞上缺失接口（见 docs/cart-format.md 的「版本兼容」）
	phos_api = 4,
}
