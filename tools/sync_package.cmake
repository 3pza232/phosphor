# 把 package/ 同步到构建目录（由 assemble_package 目标在每次构建时调用）
#
#   cmake -DSRC=<package> -DDEST=<构建目录> -P tools/sync_package.cmake
#
# 内容目录（卡带 / devkit / 皮肤 / mod）优先建立**目录联接**：源码目录就是运行时的目录，
# 于是"改卡带立刻生效、不必重新构建"——卡带的承诺本来就是即放即玩。
# 建不成联接（文件系统或权限不允许）才退回逐目录复制：那条路要重新构建才生效。
#
# 拆旧联接用 rmdir（只删链接本身，不会穿透删掉源目录里的文件）；
# 只有确认是普通目录（旧版复制留下的）才用 REMOVE_RECURSE。

if(NOT DEFINED SRC OR NOT DEFINED DEST)
    message(FATAL_ERROR "sync_package.cmake 需要 -DSRC=<package> -DDEST=<构建目录>")
endif()

file(MAKE_DIRECTORY "${DEST}")

set(LINKED carts devkit theme mods)

foreach(name IN LISTS LINKED)
    if(NOT EXISTS "${SRC}/${name}")
        continue()
    endif()
    set(link "${DEST}/${name}")

    if(CMAKE_HOST_WIN32)
        if(EXISTS "${link}")
            execute_process(COMMAND cmd /c rmdir "${link}"
                            RESULT_VARIABLE rm_rc OUTPUT_QUIET ERROR_QUIET)
            if(NOT rm_rc EQUAL 0 AND EXISTS "${link}")
                file(REMOVE_RECURSE "${link}")   # 普通目录：旧版留下的副本，删掉重建
            endif()
        endif()
        # mklink 是 cmd 内建命令，只认反斜杠路径：这里必须转成原生路径，
        # 否则 CMake 传进来的 "c:/a/b" 会让它直接失败并悄悄退回复制
        file(TO_NATIVE_PATH "${link}" link_native)
        file(TO_NATIVE_PATH "${SRC}/${name}" target_native)
        execute_process(COMMAND cmd /c mklink /J "${link_native}" "${target_native}"
                        RESULT_VARIABLE link_rc OUTPUT_QUIET ERROR_QUIET)
        if(link_rc EQUAL 0)
            message(STATUS "sync: ${name} → 联接（改动即时生效，无需重新构建）")
            continue()
        endif()
        message(STATUS "sync: ${name} 建联接失败（rc=${link_rc}），改为复制")
    endif()

    file(COPY "${SRC}/${name}" DESTINATION "${DEST}")
endforeach()

# docs/ 在开发仓库根目录（不在 package/ 里），单独同步一次：
# 发行包里必须带文档——用户拿到的是构建目录，让他去仓库里找文档等于没有文档
if(DEFINED DOCS AND EXISTS "${DOCS}")
    set(doc_link "${DEST}/docs")
    if(CMAKE_HOST_WIN32)
        if(EXISTS "${doc_link}")
            execute_process(COMMAND cmd /c rmdir "${doc_link}"
                            RESULT_VARIABLE rm_rc OUTPUT_QUIET ERROR_QUIET)
            if(NOT rm_rc EQUAL 0 AND EXISTS "${doc_link}")
                file(REMOVE_RECURSE "${doc_link}")
            endif()
        endif()
        file(TO_NATIVE_PATH "${doc_link}" doc_link_native)
        file(TO_NATIVE_PATH "${DOCS}" docs_native)
        execute_process(COMMAND cmd /c mklink /J "${doc_link_native}" "${docs_native}"
                        RESULT_VARIABLE doc_rc OUTPUT_QUIET ERROR_QUIET)
        if(doc_rc EQUAL 0)
            message(STATUS "sync: docs → 联接（改动即时生效，无需重新构建）")
        else()
            message(STATUS "sync: docs 建联接失败（rc=${doc_rc}），改为复制")
            file(COPY "${DOCS}" DESTINATION "${DEST}")
        endif()
    else()
        file(COPY "${DOCS}" DESTINATION "${DEST}")
    endif()
endif()

# 其余零散文件（package 下的 .txt/.md）照旧复制
file(GLOB stray "${SRC}/*.txt" "${SRC}/*.md")
foreach(file IN LISTS stray)
    file(COPY "${file}" DESTINATION "${DEST}")
endforeach()
