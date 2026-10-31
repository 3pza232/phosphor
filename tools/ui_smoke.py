#!/usr/bin/env python3
"""声明式界面契约：`phos.ui.render` 的组件、焦点、事件与主题。

跑的是 devkit 的界面样板卡带（devkit/examples/ui/）。它把每个组件都摆一遍，
并按事件改状态；因此这里断言的是"卡带能看到的契约"，不是像素：

* 组件渲染：标题/列表/取值行/勾选/文本域/进度条/键位提示都在文本画面里；
* 焦点：初始在列表；Tab 换到勾选与文本域；同一帧只让 input=true 的界面消费按键
  （侧栏那次 input=false 不会抢走 Tab/确认）；
* 事件：列表确认带 index、勾选带 checked、文本域提交带 text，且都能改变卡带状态。

跑法（在含 phosphor.exe 的构建目录）：python ../tools/ui_smoke.py
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from phos import Host  # noqa: E402


class Checks:
    def __init__(self) -> None:
        self.failures = 0

    def check(self, condition: object, what: str) -> None:
        if condition:
            print(f"  ok   {what}")
        else:
            self.failures += 1
            print(f"  FAIL {what}")

    def finish(self) -> int:
        print()
        if self.failures:
            print(f"ui smoke: {self.failures} check(s) failed")
        else:
            print("ui smoke: all checks passed")
        return 1 if self.failures else 0




def _probe_contract(checks: "Checks") -> None:
    """用临时测试卡带核对 parser 层契约：根 id、disabled 1 基、reset 快照。"""
    cart = Path("tests-out") / "ui-contract-probe"
    cart.mkdir(parents=True, exist_ok=True)
    (cart / "manifest.lua").write_text(
        'return { id = "ui-contract-probe", name = "PROBE", desc = "contract probe", '
        'version = "1.0.0", entry = "main.lua", phos_api = 7 }\n',
        encoding="utf-8")
    (cart / "main.lua").write_text(
        '''local st = { focus = "", last = "", skip = false }
function update()
  if phos.input.pressed("b") then
    phos.ui.reset()
    st.skip = true
    st.last = "reset"
  end
end
function draw()
  if st.skip then
    st.skip = false
    phos.screen.clear()
    st.focus = phos.ui.focus()
    return
  end
  phos.screen.clear()
  local events = phos.ui.render{
    screen = "probe", surface = "content", input = true,
    kind = "list", items = { "A", "B", "C" }, disabled = { 2 },
    children = {
      { kind = "list", id = "probe/2", items = { "X", "Y" }, disabled = { 1 } },
    },
  }
  for _, e in ipairs(events) do st.last = e.kind .. ":" .. tostring(e.index or "") end
  st.focus = phos.ui.focus()
end
function debug_state() return { focus = st.focus, last = st.last } end
''',
        encoding="utf-8")
    print("  -- parser 契约（临时 probe 卡带）--")
    with Host(cart=str(cart.resolve()), extra=("--seed", "1")) as host:
        host.step(5)
        snapshot = host.send("ui.list").get("ui") or {}
        checks.check(snapshot.get("screen") == "probe", "根 screen 命名空间")
        checks.check(snapshot.get("focus") == "probe",
                     f"顶层 kind 省略 id 时根 id = screen（{snapshot.get('focus')}）")
        host.key("down")
        host.step(2)
        snapshot = host.send("ui.list").get("ui") or {}
        widget = (snapshot.get("widgets") or [{}])[0]
        selected = (widget.get("state") or {}).get("selected")
        checks.check(selected == 3,
                     f"disabled 下标 1 基（禁用第 2 行，实际 selected={selected}）")
        # ui.activate 在 disabled 行上必须与玩家按 A 一致：不产生 activated
        host.send("ui.activate", id="probe/2")
        host.step(2)
        debug = host.state().get("debug") or {}
        checks.check(str(debug.get("last")) != "activated:1",
                     f"ui.activate 不触发 disabled 列表行（{debug.get('last')}）")
        host.inject_key("b")
        host.step(1)
        checks.check(host.send("ui.list").get("ui") is None,
                     "ui.reset 清除 ui.list/state.query.ui 快照")
    checks.check(host.exited_cleanly, "probe 宿主干净退出")


def main() -> int:
    checks = Checks()
    with Host(cart="devkit/examples/ui", extra=("--seed", "1")) as host:
        host.step(12)
        text = host.screen_text()
        debug = host.state().get("debug") or {}

        print("  -- 组件渲染 --")
        checks.check("界面样板" in text, "title 渲染（box 标题）")
        checks.check("选一个" in text, "text 段渲染")
        checks.check("ALPHA" in text and "GAMMA" in text, "list 渲染全部行")
        checks.check("得分" in text and "10" not in str(debug.get("score")), "stat 渲染标签与取值")
        checks.check("[ ]" in text or "[x]" in text, "checkbox 渲染勾选框")
        checks.check("#" in text and "-" in text and "[" in text, "bar 渲染进度")
        checks.check("move" in text and "next" in text, "hint 渲染键位提示")
        checks.check("STATUS" in text, "侧栏（surface=panel）独立渲染")

        print("  -- 网格 / 滚动 / option --")
        checks.check("CARD 1" in text and "CARD 6" in text, "卡片墙（2×3，等宽列）渲染")
        card_row = next((line for line in text.splitlines() if "CARD 1" in line), "")
        checks.check("CARD 2" in card_row and "CARD 3" in card_row,
                     "grid 按 cols 逐行排（CARD 1/2/3 同一行）")
        checks.check("LOG 05" in text and "LOG 08" in text and "LOG 04" not in text,
                     "scroll 视口按初始偏移裁出 4 行（视口外的行不画）")
        checks.check("COL001" not in text and "beta gamma" in text,
                     "scroll_x 横向裁剪（初始偏移 10 列）")
        checks.check("画质: MID" in text, "option 渲染卡带格式化的当前取值")

        print("  -- 表格 --")
        checks.check("RANK" in text and "SCORE" in text, "表头渲染")
        checks.check("ALPHA" in text and "1200" in text and "GAMMA" in text, "数据行渲染")
        checks.check("─" in text, "表头分隔线")

        print("  -- 焦点与事件 --")
        checks.check(debug.get("focus") == "demo_list", f"初始焦点在列表（{debug.get('focus')}）")
        host.key("down")
        host.key("a")
        host.step(2)
        debug = host.state().get("debug") or {}
        checks.check(debug.get("score") == 10, f"列表确认第 2 项 → 事件 index=2、得分 10（{debug.get('score')}）")
        checks.check(str(debug.get("last")) == "list:2", f"卡带收到 activated(index)（{debug.get('last')}）")

        host.key("tab")
        host.step(1)
        debug = host.state().get("debug") or {}
        checks.check(debug.get("focus") == "demo_sfx", f"Tab 离开列表 → 勾选框（{debug.get('focus')}）")
        host.key("a")
        host.step(2)
        debug = host.state().get("debug") or {}
        checks.check(debug.get("checked") is True, "勾选事件把 checked 置真")
        checks.check("[x]" in host.screen_text(), "勾选框画面同步为 [x]")
        checks.check(str(debug.get("last")) == "sound:true", f"卡带收到 changed(checked)（{debug.get('last')}）")

        host.key("tab")
        host.step(1)
        debug = host.state().get("debug") or {}
        checks.check(debug.get("focus") == "demo_name", f"Tab 再到文本域（{debug.get('focus')}）")
        host.send("input.text", text="neo")
        host.step(2)
        debug = host.state().get("debug") or {}
        checks.check(str(debug.get("name")) == "neo", f"文本域收字（{debug.get('name')}）")
        host.key("a")
        host.step(2)
        debug = host.state().get("debug") or {}
        checks.check(str(debug.get("last")) == "name:neo", f"提交事件带文本（{debug.get('last')}）")

        print("  -- agent 语义接口 --")
        snapshot = host.send("ui.list").get("ui") or {}
        widgets = snapshot.get("widgets") or []
        ids = {w.get("id") for w in widgets}
        checks.check("demo_list" in ids and "demo_sfx" in ids and "demo_name" in ids,
                     f"ui.list 暴露可交互控件（{sorted(ids)}）")
        checks.check(snapshot.get("focus") == "demo_name", "ui.list 报出当前焦点")
        host.send("ui.activate", id="demo_sfx")
        host.step(2)
        debug = host.state().get("debug") or {}
        checks.check(debug.get("checked") is False, "ui.activate 按玩家确认的语义激活控件")
        checks.check(str(debug.get("last")) == "sound:false", "激活产生的事件回到卡带")

        print("  -- toast --")
        # 上一步列表激活时卡带调用了 phos.ui.toast：先在场，随后按时长消失
        checks.check("PICK" in host.screen_text(), "toast 出现")
        host.step(160)  # 1.6s 显示时长 + 余量
        checks.check("PICK" not in host.screen_text(), "toast 到时消失")

        print("  -- 退出 --")
    checks.check(host.exited_cleanly, "宿主干净退出")
    _probe_contract(checks)
    return checks.finish()


if __name__ == "__main__":
    sys.exit(main())