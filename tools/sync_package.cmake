# 把 package/ 与 docs/ 同步到构建目录（由 assemble_package 目标在每次构建时调用）
#
#   cmake -DSRC=<package> -DDOCS=<docs> -DDEST=<构建目录> -P tools/sync_package.cmake
#
# build/ 就是**可以直接整包发出去的发行目录**，所以这里一律用"合并式复制"：
#   * 每个目录都是真实文件。用目录联接（junction）是不行的——把 build/ 拷到别人
#     机器上，联接会变成指向你机器上路径的死链，游戏直接不能用
#   * file(COPY) 只补不删：构建目录里多出来的东西（例如 `--new` 就地建在 carts/
#     里的新卡带）不会被构建抹掉
# 代价：改了 package/ 里的内容要跑一次构建（很快）；而卡带本来就在构建目录里
# 就地编辑，改完直接跑。

if(NOT DEFINED SRC OR NOT DEFINED DEST)
    message(FATAL_ERROR "sync_package.cmake 需要 -DSRC=<package> -DDEST=<构建目录>")
endif()

file(MAKE_DIRECTORY "${DEST}")

# package/ 下的内容目录
set(CONTENT_DIRS carts devkit theme mods)
foreach(name IN LISTS CONTENT_DIRS)
    if(EXISTS "${SRC}/${name}")
        file(COPY "${SRC}/${name}" DESTINATION "${DEST}")
    endif()
endforeach()

# 空目录也要保证存在：发行包里 saves/ 是存档落点、mods/ 是覆盖层入口，
# 少了它们玩家第一次存档就可能失败。空目录不能用 file(COPY) 指望，直接建
file(MAKE_DIRECTORY "${DEST}/saves" "${DEST}/mods")

# docs/ 在开发仓库根目录，不在 package/ 里
if(DEFINED DOCS AND EXISTS "${DOCS}")
    file(COPY "${DOCS}" DESTINATION "${DEST}")
endif()

# 其余零散文件（package 下的 .txt / .md）
file(GLOB stray "${SRC}/*.txt" "${SRC}/*.md")
foreach(file IN LISTS stray)
    file(COPY "${file}" DESTINATION "${DEST}")
endforeach()
