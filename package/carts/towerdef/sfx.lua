-- sfx.lua —— 事件 → 音效映射。只做"听到什么"，不含任何规则。
-- main.lua 把 game:update 返回的事件表递进来即可（玩法层不知道有音效）。

local Sfx = {}

local function beep(...) phos.audio.beep(...) end

function Sfx.play(ev)
	if ev.built then beep(620, 0.06, { wave = "square", volume = 0.16 }) end
	if ev.sold then beep(300, 0.08, { wave = "square", volume = 0.14 }) end
	if ev.upgraded then beep(760, 0.10, { wave = "square", sweep = 1200, volume = 0.18 }) end
	if ev.denied then beep(120, 0.05, { wave = "square", volume = 0.16 }) end
	if ev.kill then beep(720, 0.03, { volume = 0.06 }) end
	if ev.boss_kill then beep(200, 0.30, { wave = "saw", volume = 0.22 }) end
	if ev.leak then beep(180, 0.18, { wave = "saw", volume = 0.20 }) end
	if ev.tower_down then beep(150, 0.24, { wave = "saw", sweep = 70, volume = 0.22 }) end
	if ev.boom then beep(90, 0.40, { wave = "noise", volume = 0.30, release = 0.3 }) end
	if ev.airstrike then beep(420, 0.10, { wave = "square", sweep = 760, volume = 0.20 }) end
	if ev.wave_start then beep(520, 0.12, { wave = "square", volume = 0.20 }) end
	if ev.wave_clear then beep(660, 0.10, { wave = "triangle", volume = 0.20 }) end
	if ev.early_bonus then beep(1000, 0.08, { wave = "square", volume = 0.16 }) end
	if ev.won then beep(880, 0.50, { wave = "triangle", sweep = 1300, volume = 0.24 }) end
	if ev.over then beep(140, 0.60, { wave = "saw", sweep = 60, volume = 0.24 }) end
end

return Sfx
