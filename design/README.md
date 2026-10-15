# PHOSPHOR 引擎文档（开发期）

> **本目录不随发行包发布。** 它记录引擎**内部**的实现与设计——只有要读 / 改 `src/`
> 的 C++ 源码时才需要。用户与卡带作者请读 [`../docs/`](../docs/README.md)：
> 那一份会随 `phosphor.exe` 一起分发。

## 读什么

| 想知道什么 | 看哪里 |
|---|---|
| 分层、目录职责、依赖方向 | [architecture.md](architecture.md) |
| 代码风格与命名约定 | [code-style.md](code-style.md) |
| 绘制 API 的底层（格 / 子格 / 笔） | [draw-api.md](draw-api.md) |
| 图层与 API 的分层设计 | [layers-and-api.md](layers-and-api.md) |
| 联机（拓扑、协议、线程、确定性注意） | [networking.md](networking.md) |
| 路线图与待办 | [roadmap.md](roadmap.md) |
| 产品设想 | [vision.md](vision.md) |

## 两份文档的关系

PHOSPHOR 的文档分**两层**，界限是"谁来读"：

| 目录 | 面向谁 | 内容 | 进发行包吗 |
|---|---|---|---|
| [`docs/`](../docs/README.md) | 玩家 / 卡带作者 / 内容包作者 / agent | 怎么玩、怎么写卡带、`phos.*` API、内容包、agent 接口 | **是**（构建同步到发行目录的 `docs/`） |
| `design/`（本目录） | 引擎开发者 | 引擎怎么实现、为什么这么分层、下一步做什么 | **否**（只在开发仓库里） |

> 构建只把 `docs/` 同步进发行包（见 `tools/sync_package.cmake`），`design/` 永远不会
> 出现在发行产物里。所以一份"由字符构成的游戏机"发行包是自洽的：只有"怎么用、怎么写"。
