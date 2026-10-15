"""定位运行根（含 phosphor.exe 的目录），让 dev 脚本住哪都能跑。

脚本住的两种位置都要支持：
  * 引擎开发仓库：package/carts/<id>/dev/ —— 运行根是同仓库的 build/
  * 发行目录：build/carts/<id>/dev/ —— 运行根就是上溯三层的 build/

做法：从脚本位置向上找"同时含 package/ 与 build/ 的仓库根"，取它的 build/；
找不到（老布局/被拷到别处）再回退到上溯三层。
"""
import os


def run_root():
    here = os.path.dirname(os.path.abspath(__file__))
    d = here
    while True:
        if os.path.isdir(os.path.join(d, "package")) and os.path.isdir(os.path.join(d, "build")):
            return os.path.join(d, "build")
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    # 兜底：脚本在 build/carts/<id>/dev 时，上溯三层就是运行根
    return os.path.abspath(os.path.join(here, "..", "..", ".."))
