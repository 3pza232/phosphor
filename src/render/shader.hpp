#pragma once

#include <string>
#include <string_view>

namespace phos {

/// OpenGL shader 程序封装（RAII）。
class Shader {
public:
    Shader() = default;
    ~Shader();
    Shader(const Shader&) = delete;
    Shader& operator=(const Shader&) = delete;
    Shader(Shader&& other) noexcept;
    Shader& operator=(Shader&& other) noexcept;

    /// 编译并链接。失败返回错误信息且对象保持无效。
    bool build(std::string_view vert_src, std::string_view frag_src, std::string& err);

    /// 绑定为当前程序（需要已有当前 GL 上下文）
    void use() const;
    /// 设置 vec2 uniform；名称不存在时静默忽略
    void set_vec2(std::string_view name, float x, float y) const;
    /// 设置 int uniform；名称不存在时静默忽略
    void set_int(std::string_view name, int v) const;

    /// GL 程序名（0 = 未构建）
    unsigned id() const { return id_; }

private:
    void destroy();
    unsigned id_ = 0;
};

} // namespace phos
