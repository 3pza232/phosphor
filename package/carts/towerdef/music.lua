-- music.lua —— 循环 BGM：4 个乐段 + 曲序，三角波低音打底、方波旋律保持复古感。
-- 纯数据；换这份文件就换曲（mod 可覆盖）。耐听向，不过分刺激。

return {
	bpm = 116,
	wave = "square",
	loop = true,
	patterns = {
		A = {
			lead = { wave = "square", volume = 0.42, release = 0.16,
				steps = "A3 - - - C4 - - E4 - - - - D4 - - -" },
			bass = { wave = "triangle", volume = 0.7, release = 0.28,
				steps = "A1 - - - A1 - - - A1 - - - A1 - - -" },
			perc = { volume = 0.5, steps = "K - H - S - H - K - H - S - H -" },
		},
		B = {
			lead = { wave = "square", volume = 0.42, release = 0.16,
				steps = "E4 - - G4 - - A4 - - - - G4 - E4 -" },
			bass = { wave = "triangle", volume = 0.7, release = 0.28,
				steps = "F1 - - - F1 - - - G1 - - - G1 - - -" },
			perc = { volume = 0.5, steps = "K - H - S - H - K - H - S - H -" },
		},
		C = {
			lead = { wave = "square", volume = 0.4, release = 0.18,
				steps = "C4 - - - E4 - - G4 - - - - - - - -" },
			bass = { wave = "triangle", volume = 0.72, release = 0.30,
				steps = "C2 - - - C2 - - - E1 - - - E1 - - -" },
			perc = { volume = 0.45, steps = "K - - H - - S - K - - H - - S -" },
		},
		D = {
			lead = { wave = "square", volume = 0.44, release = 0.14,
				steps = "D4 - F4 - A4 - - - G4 - E4 - D4 - - -" },
			bass = { wave = "triangle", volume = 0.72, release = 0.28,
				steps = "D1 - - - A1 - - - D1 - - - A1 - - -" },
			perc = { volume = 0.55, steps = "K - H - S - H - K - H - S - H S" },
		},
	},
	order = { "A", "A", "B", "A", "C", "A", "B", "D" },
}
