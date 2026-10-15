# 把 package/ 与 docs/ 同步到构建目录（由 assemble_package 目标在每次构建时调用）
#
#   cmake -DSRC=<package> -DDOCS=<docs，可选> -DDEST=<构建目录> -P tools/sync_package.cmake
#
# 只同步**面向用户/作者的**内容与文档：package/（卡带/主题/模板/mods）与 docs/。
# **引擎开发文档（仓库根的 design/）永远不进发行包**——它只给读 src/ 的人看。
# 这里还留了一道防线：万一哪天有人把 design/ 嵌进了 docs/，也照样跳过。
#
# build/ 是可直接发出去的发行目录，所以用"合并式复制"：真实文件（不用目录联接，
# 否则拷到别人机器就是死链）、只补不删（`--new` 就地建的卡带不会被抹掉）、逐文件
# （好让"就地改过的那一份"能单独跳过）。
# 逐份文件的判据（内容在前、时间在后）：内容与源一致就什么都不做；不同且比上次同步
# 时刻新 = 就地改过，跳过并告警（覆盖掉等于静默丢工作）；不同但更旧 = 源变了，正常同步。
# 自测（干净目标目录也要能跑通，逐文件复制不会替你建目录）：
#   cmake -DSRC=$PWD/package -DDOCS=$PWD/docs -DDEST=<一个空目录> -P tools/sync_package.cmake

if(NOT DEFINED SRC OR NOT DEFINED DEST)
    message(FATAL_ERROR "sync_package.cmake 需要 -DSRC=<package> -DDEST=<构建目录>")
endif()

file(MAKE_DIRECTORY "${DEST}")

set(stamp_file "${DEST}/.phos_sync_stamp")
if(NOT EXISTS "${stamp_file}")
    # 首次运行：以"此刻"为界，构建目录里既有的副本一律按待同步处理
    file(WRITE "${stamp_file}" "bootstrap\n")
endif()

set(skipped 0)

# 逐个文件同步：整目录的复制做不到"这一份跳过"，所以这里自己走一遍。
# saves 也在内：源里的说明文件要进发行包，而运行目录里玩家自己的存档不会被删
# （本脚本只补不删，本地更新的文件另有告警跳过）
foreach(dir IN ITEMS "${SRC}/carts" "${SRC}/devkit" "${SRC}/theme" "${SRC}/mods" "${SRC}/saves"
                   "${DOCS}")
    if(NOT EXISTS "${dir}")
        continue()
    endif()
    get_filename_component(sub "${dir}" NAME)
    # 目录先建：逐文件复制不会连带建目录（整目录复制才会），干净构建时
    # 少了这一步就直接失败在"没有那个目录"；空目录也照建，保持"合并式复制"的原样
    file(GLOB_RECURSE rel_entries RELATIVE "${dir}" "${dir}/*")
    foreach(rel IN LISTS rel_entries)
        # 引擎开发文档不进发行包：即便被嵌进 docs/ 也跳过
        if(sub STREQUAL "docs" AND rel MATCHES "^design(/|$)")
            continue()
        endif()
        if(IS_DIRECTORY "${dir}/${rel}")
            file(MAKE_DIRECTORY "${DEST}/${sub}/${rel}")
            continue()
        endif()
        set(src_file "${dir}/${rel}")
        set(dest_file "${DEST}/${sub}/${rel}")
        get_filename_component(dest_dir "${dest_file}" DIRECTORY)
        file(MAKE_DIRECTORY "${dest_dir}")
        if(EXISTS "${dest_file}")
            file(SHA256 "${src_file}" src_hash)
            file(SHA256 "${dest_file}" dest_hash)
            if(src_hash STREQUAL dest_hash)
                continue()  # 已一致：不动，也不必刷它的时间戳
            endif()
            if("${dest_file}" IS_NEWER_THAN "${stamp_file}")
                message(WARNING
                    "运行目录里的 ${sub}/${rel} 在上次同步之后被改过，本次同步跳过它。\n"
                    "  就地改过的内容要保住，就把它拷回 package/ 再构建；\n"
                    "  否则运行目录与源码会一直不一致，发行包也会带着这份偏离。")
                math(EXPR skipped "${skipped} + 1")
                continue()
            endif()
        endif()
        file(COPY_FILE "${src_file}" "${dest_file}")
    endforeach()
endforeach()

# 其余零散文件（package 下的 .txt / .md）落在构建目录根
file(GLOB stray "${SRC}/*.txt" "${SRC}/*.md")
foreach(file IN LISTS stray)
    get_filename_component(sub "${file}" NAME)
    set(dest_file "${DEST}/${sub}")
    file(MAKE_DIRECTORY "${DEST}")
    if(EXISTS "${dest_file}")
        file(SHA256 "${file}" src_hash)
        file(SHA256 "${dest_file}" dest_hash)
        if(src_hash STREQUAL dest_hash)
            continue()
        endif()
        if("${dest_file}" IS_NEWER_THAN "${stamp_file}")
            message(WARNING
                "运行目录里的 ${sub} 在上次同步之后被改过，本次同步跳过它（同 carts/ 的说明）。")
            math(EXPR skipped "${skipped} + 1")
            continue()
        endif()
    endif()
    file(COPY_FILE "${file}" "${dest_file}")
endforeach()

# 空目录也要保证存在：发行包里 saves/ 是存档落点、mods/ 是覆盖层入口，
# 少了它们玩家第一次存档就可能失败。空目录不能用复制指望，直接建
file(MAKE_DIRECTORY "${DEST}/saves" "${DEST}/mods")

# 记下本次同步时刻：下次据此判断"运行目录里的改动是不是就地改的"
string(TIMESTAMP now_text "%Y-%m-%d %H:%M:%S" UTC)
file(WRITE "${stamp_file}" "${now_text}\n")

if(skipped GREATER 0)
    message(STATUS "sync_package: 跳过 ${skipped} 个被就地改过的文件（见上面的告警）")
endif()
