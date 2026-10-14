[ theme/sound - 主机音效包 ]
============================

每个子文件夹 = 一套主机音效。文件夹名就是设置里显示的名字。

现有：
  default   ARCADE BLIPS：方波电子音，街机厅的短促提示声（出厂默认）
  relay     RELAY CLACK：噪声与低频咔哒，机械继电器质感
  soft      SOFT TONES：正弦波为主，起振与释放都更慢
  chip      CHIP BEEP：8 位芯片音（方波、短促、跳脱）
  deep      DEEP HULL：低频厚重（三角/锯齿，机箱共振的沉响）
  glass     GLASS BELL：清脆玻璃钟（正弦、高频、余音长）
  muted     MUTED：轻柔极简（正弦、极短、低音量，深夜不吵）

设置里还有一项是主机内置的，不是文件夹：
  SILENT    不放任何主机音效（卡带自己的音乐与音效不受影响）

一套音效包定义 6 个主机事件：
  boot     开机（启动动画开始时）
  insert   插入卡带
  eject    弹出卡带
  key      界面按键
  confirm  确认/切换
  error    卡带故障

每个事件可写合成参数（wave/freq/sweep/dur/volume/attack/release/perc），
也可指向包内的音频文件（file = "assets/hit.wav"）。

怎么做：复制 default 文件夹，改名，编辑 sounds.lua（必需的唯一文件）。
      参数规范见 docs/content-packs.md。

音量：主机的音乐/音效音量在设置界面里分开调整；
      音效包里的 volume 是该声音自身的相对音量。
