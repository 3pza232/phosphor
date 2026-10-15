# PHOSPHOR 文档

你手上的这份目录就是全部文档（发行包里位于 `phosphor.exe` 同级的 `docs/`；
**引擎源码不在发行包中**，下面提到的引擎内部实现细节都属开发仓库，与你无关）。
按下面的路线读即可，不必从头翻。

## 我是来玩游戏的

| 想知道什么 | 看哪里 |
|---|---|
| 怎么启动、怎么操作、怎么设置、存档在哪 | [playing.md](playing.md) |
| 怎么换主题 / 皮肤 / 启动动画 / 界面语言 | [content-packs.md](content-packs.md) |
| 怎么装别人给的卡带、怎么把自己的存档带走 | [playing.md](playing.md) 的「卡带」与「磁带码」两节 |

## 我是来写卡带的

| 想知道什么 | 看哪里 |
|---|---|
| 五分钟上手：照着模板填空就能开工 | [devkit.md](devkit.md) |
| `manifest.lua` 有哪些字段、卡带的生命周期与沙箱 | [cart-format.md](cart-format.md) |
| 每个 `phos.*` 调用（权威规格，带示例） | [api-reference.md](api-reference.md) |
| 让卡带支持局域网联机 | [api-reference.md](api-reference.md) 的「phos.net」一节 |
| 让 agent / 脚本帮你写、帮你自测 | [agent-interface.md](agent-interface.md) |

## 发行包里还有什么

| 目录 | 是什么 |
|---|---|
| `phosphor.exe` | 主机本体。绿色免安装，双击即可 |
| `carts/` | 出厂卡带；也是可以直接读的范例 |
| `devkit/template/` | `phosphor --new` 复制的就是它 |
| `devkit/phos.lua` | 编辑器补全用的 API 定义（VSCode 挂上就有提示） |
| `theme/` | 皮肤、色板、启动动画、音效、字体 |
| `mods/` | 覆盖层：不改原文件就能替换卡带与主题里的内容 |
| `docs/` | 就是本目录 |

## 关于本目录之外

设计文档与开发计划（架构、代码风格、路线图、产品设想）**不随发行包发布**，
只存在于开发仓库的 `design/` 目录；这里放的全部是"怎么用、怎么写"。
