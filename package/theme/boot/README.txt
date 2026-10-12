[ theme/boot - 启动动画 ]
=========================

每个子文件夹 = 一套开机动画。文件夹名就是设置里显示的名字。
（设置里能看到几项，本目录下就有几个文件夹 —— 出厂默认也在这里。）

现有：
  default       TUBE WARMUP：显像管预热（亮线展开 → 逐行自检 → 稳定）
  persistence   PERSISTENCE：写头扫过显影，笔画先亮后暗，留下余辉
  static-rain   STATIC RAIN：雪花噪点如雨，LOGO 从干扰中浮现
  sweep         CART LOADER：进度条推进 + 校验灯逐块点亮
  waveform      WAVEFORM LOCK：抖动噪声波锁相成稳定方波
  bootlog       BOOT LOG：逐行滚出的开机自检，全 OK 后打出产品名
  spectrum      SPECTRUM：频谱条跳动后收平成一条线，再打出产品名
  pulse         PULSE：同心环从中心扩散收束，产品名在核心处亮起
  ember         EMBER：炉膛火焰跳动、火星升腾，产品名从火中浮出
  stardust      STARDUST：星辰向心汇聚成星滴，坠落水面溅起涟漪，产品名自水面浮起

动画是一段 Lua 脚本（main.lua），用 phos.screen / phos.color / phos.ui 逐帧作画，
能力与游戏卡带完全相同 —— 想做多夸张都行。

音效：动画可用 phos.audio.beep/note/perc 自己发声（音频设备在开机动画之前就已就绪，
      所以开机第一秒就有声音）。此外主机还会播放音效包的 boot 事件音
      （在 theme/sound/ 里定义，换音效包即换开机提示音）。

时长与跳过：默认播放约 3.2 秒后进入卡带架，任意键可立即跳过。

怎么做：复制 default 文件夹（或 static-rain），改名，编辑 main.lua。
      脚本接口见 docs/content-packs.md 与 docs/api-reference.md。

兜底：本目录下没有任何动画时，回退主机内置的文字自检动画。
