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

# --- 运行时自检（排查内存问题时用） ---
# 让越界访问在**现场**停下并报位置，而不是过一会儿表现为"堆已损坏"（分配器才发现）。
# 慢，不用于发行；默认关：
#   cmake -B build-sanity -DPHOSPHOR_SANITY=ON
# 这两个开关属于 libstdc++ 与编译器本身，只对 GCC/Clang 有意义
option(PHOSPHOR_SANITY "启用容器边界断言与栈保护（排查内存问题）" OFF)
if(PHOSPHOR_SANITY AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(-D_GLIBCXX_ASSERTIONS -fstack-protector-all)
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

# --- Windows 可执行文件资源：exe 图标 + 版本信息 ---
# 窗口图标（glfwSetWindowIcon，运行时读 theme/icon/phos_icon.jpg）与 exe 图标是**两件事**：
# Explorer / 任务栏给 exe 显示的图标是**链接期嵌入的 Win32 资源**，只能用 .rc 烘焙。
# .ico 由 `python tools/make_icon.py` 从那张 jpg 生成、随源码提交（构建不依赖 Python）。
# 版本号从 version.hpp 解析，保持单一真源；非 Windows 平台跳过（图标随平台而异）。
if(WIN32)
    enable_language(RC)
    set(PHOS_ICON_FILE "${CMAKE_SOURCE_DIR}/package/theme/icon/phos_icon.ico")
    file(STRINGS "${CMAKE_SOURCE_DIR}/src/core/version.hpp" PHOS_VERSION_LINE
         REGEX "kVersion[ \t]*=")
    string(REGEX MATCH "[0-9]+\\.[0-9]+\\.[0-9]+" PHOS_VERSION "${PHOS_VERSION_LINE}")
    if(NOT PHOS_VERSION)
        set(PHOS_VERSION "0.0.0")
    endif()
    string(REPLACE "." "," PHOS_VERSION_COMMA "${PHOS_VERSION}")
    set(PHOS_VERSION_COMMA "${PHOS_VERSION_COMMA},0")  # VERSIONINFO 的 FILEVERSION 要四段
    configure_file("${CMAKE_SOURCE_DIR}/tools/phos_icon.rc.in"
                   "${CMAKE_BINARY_DIR}/phos_icon.rc" @ONLY)
    target_sources(phosphor PRIVATE "${CMAKE_BINARY_DIR}/phos_icon.rc")
endif()

# --- 纯逻辑单元测试：不依赖 GL / GLFW / Lua，可无窗口、无显卡运行 ---
# 只编译"纯逻辑"那一批源文件（颜色/文本/配置/色板/主题/表面…），直接编进测试可执行文件；
# 与主机共享同一份源码，所以测的就是真代码。默认开启，tools/run_checks.py 会调用它
option(PHOSPHOR_BUILD_TESTS "构建纯逻辑单元测试" ON)
if(PHOSPHOR_BUILD_TESTS)
    add_executable(phosphor_tests
        tests/main.cpp
        tests/test_core.cpp
        src/core/color.cpp
        src/core/text.cpp
        src/core/text_input.cpp
        src/core/log.cpp
        src/core/json_lite.cpp
        src/core/config.cpp
        src/core/palette.cpp
        src/core/skin.cpp
        src/core/crt.cpp
        src/core/screen.cpp
        src/core/surface.cpp
        src/core/layered_screen.cpp
        src/pack/builtin.cpp
        src/shell/shelf_search.cpp)
    target_include_directories(phosphor_tests PRIVATE ${CMAKE_SOURCE_DIR}/src)
    if(MINGW)
        target_link_options(phosphor_tests PRIVATE -static-libgcc -static-libstdc++)
    endif()
    enable_testing()
    add_test(NAME phosphor_unit COMMAND phosphor_tests)
endif()

# --- 程序包组装：exe + package/ 骨架 ---
# 每次构建都把内容目录（卡带 / devkit / 主题 / mods / saves / docs）同步到构建目录；
# 合并式复制的规则与告警见 tools/sync_package.cmake
add_custom_target(assemble_package ALL
    COMMAND ${CMAKE_COMMAND}
        -DSRC=${CMAKE_SOURCE_DIR}/package
        -DDOCS=${CMAKE_SOURCE_DIR}/docs
        -DDEST=$<TARGET_FILE_DIR:phosphor>
        -P ${CMAKE_SOURCE_DIR}/tools/sync_package.cmake
    COMMENT "同步 PHOSPHOR 运行包（真实文件，可直接发包）")
add_dependencies(assemble_package phosphor)
