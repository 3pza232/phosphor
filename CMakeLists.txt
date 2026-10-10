# PHOSPHOR 构建定义
# 编译器无关：主力 GCC(MinGW-w64)，亦可用 Clang/MSVC 构建
cmake_minimum_required(VERSION 3.28)
project(phosphor LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

set(EXTERN ${CMAKE_SOURCE_DIR}/extern)

# --- glad：OpenGL 3.3 Core 函数加载 ---
add_library(glad STATIC ${EXTERN}/glad/src/glad.c)
target_include_directories(glad PUBLIC ${EXTERN}/glad/include)

# --- GLFW：预编译 MinGW 静态库 ---
add_library(glfw STATIC IMPORTED GLOBAL)
set_target_properties(glfw PROPERTIES
    IMPORTED_LOCATION ${EXTERN}/glfw-3.5.1.bin.WIN64/lib-mingw-w64/libglfw3.a
    INTERFACE_INCLUDE_DIRECTORIES ${EXTERN}/glfw-3.5.1.bin.WIN64/include)

# --- Lua 5.4：静态库（排除解释器与编译器入口） ---
file(GLOB LUA_SOURCES ${EXTERN}/lua-5.4.2/src/*.c)
list(REMOVE_ITEM LUA_SOURCES
    ${EXTERN}/lua-5.4.2/src/lua.c
    ${EXTERN}/lua-5.4.2/src/luac.c)
add_library(lua STATIC ${LUA_SOURCES})
target_include_directories(lua PUBLIC ${EXTERN}/lua-5.4.2/src)

# --- miniz：zip 读取（.phos 卡带容器），3.x 拆分版需全部核心源文件 ---
add_library(miniz STATIC
    ${EXTERN}/miniz/miniz.c
    ${EXTERN}/miniz/miniz_zip.c
    ${EXTERN}/miniz/miniz_tdef.c
    ${EXTERN}/miniz/miniz_tinfl.c)
target_include_directories(miniz PUBLIC ${EXTERN}/miniz)

# --- ImGui：调试台（核心 + GLFW/OpenGL3 后端） ---
set(IMGUI_DIR ${EXTERN}/imgui)
add_library(imgui STATIC
    ${IMGUI_DIR}/imgui.cpp
    ${IMGUI_DIR}/imgui_draw.cpp
    ${IMGUI_DIR}/imgui_tables.cpp
    ${IMGUI_DIR}/imgui_widgets.cpp
    ${IMGUI_DIR}/backends/imgui_impl_glfw.cpp
    ${IMGUI_DIR}/backends/imgui_impl_opengl3.cpp)
target_include_directories(imgui PUBLIC ${IMGUI_DIR} ${IMGUI_DIR}/backends)
target_link_libraries(imgui PUBLIC glfw)

# --- phosphor 主机 ---
# WIN32：GUI 子系统（双击无控制台黑框）；CLI 输出由 main 中 AttachConsole 保留
file(GLOB_RECURSE PHOS_SOURCES CONFIGURE_DEPENDS ${CMAKE_SOURCE_DIR}/src/*.cpp)

# sol2 的安全检查是**全工程编译期策略**：必须在每个翻译单元里于包含 sol 之前定义，
# 所以集中在这里定义一次。散在各文件里容易漏——漏一处就少一份运行时检查，
# 而编译器不会提醒你漏了。
add_compile_definitions(SOL_ALL_SAFETIES_ON=1)
add_executable(phosphor WIN32 ${PHOS_SOURCES})
target_include_directories(phosphor PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${EXTERN}/stb
    ${EXTERN}/sol2
    ${EXTERN}/miniaudio)
target_link_libraries(phosphor PRIVATE glad glfw lua miniz imgui opengl32 gdi32 user32 shell32)
# 控制通道使用 Winsock（仅 Windows）
if(WIN32)
    target_link_libraries(phosphor PRIVATE ws2_32)
endif()

# MinGW：静态链接运行时，产出免依赖 exe
if(MINGW)
    target_link_options(phosphor PRIVATE -static-libgcc -static-libstdc++)
endif()

# --- 程序包组装：exe + package/ 骨架 ---
# 每次构建都执行：内容目录（卡带 / devkit / 皮肤 / mod）由源码**同步**（合并式复制）过来：
# 复制出来的那份是快照，改卡带后不重新构建就仍在玩旧副本——卡带的承诺是即放即玩。
# 详见 tools/sync_package.cmake。改了源码后重新构建一次即可（也可直接改运行目录里的副本）。
add_custom_target(assemble_package ALL
    COMMAND ${CMAKE_COMMAND}
        -DSRC=${CMAKE_SOURCE_DIR}/package
        -DDOCS=${CMAKE_SOURCE_DIR}/docs
        -DDEST=$<TARGET_FILE_DIR:phosphor>
        -P ${CMAKE_SOURCE_DIR}/tools/sync_package.cmake
    COMMENT "Assembling PHOSPHOR package (real files: ready to ship as-is)")
add_dependencies(assemble_package phosphor)
