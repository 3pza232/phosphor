#include "render/shader.hpp"

#include <glad/glad.h>

namespace phos {

Shader::~Shader() { destroy(); }

Shader::Shader(Shader&& other) noexcept : id_(other.id_) { other.id_ = 0; }

Shader& Shader::operator=(Shader&& other) noexcept {
    if (this != &other) {
        destroy();
        id_ = other.id_;
        other.id_ = 0;
    }
    return *this;
}

void Shader::destroy() {
    if (id_) {
        glDeleteProgram(id_);
        id_ = 0;
    }
}

bool Shader::build(std::string_view vert_src, std::string_view frag_src, std::string& err) {
    auto compile = [&](unsigned stage, std::string_view src) -> unsigned {
        std::string code(src);
        const char* ptr = code.c_str();
        unsigned shader = glCreateShader(stage);
        glShaderSource(shader, 1, &ptr, nullptr);
        glCompileShader(shader);
        int ok = 0;
        glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
        if (!ok) {
            char log[2048];
            glGetShaderInfoLog(shader, sizeof(log), nullptr, log);
            err = log;
            glDeleteShader(shader);
            return 0;
        }
        return shader;
    };

    unsigned vs = compile(GL_VERTEX_SHADER, vert_src);
    if (!vs) return false;
    unsigned fs = compile(GL_FRAGMENT_SHADER, frag_src);
    if (!fs) {
        glDeleteShader(vs);
        return false;
    }

    unsigned prog = glCreateProgram();
    glAttachShader(prog, vs);
    glAttachShader(prog, fs);
    glLinkProgram(prog);
    glDeleteShader(vs);
    glDeleteShader(fs);

    int ok = 0;
    glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[2048];
        glGetProgramInfoLog(prog, sizeof(log), nullptr, log);
        err = log;
        glDeleteProgram(prog);
        return false;
    }

    destroy();
    id_ = prog;
    return true;
}

void Shader::use() const {
    glUseProgram(id_);
}

void Shader::set_vec2(std::string_view name, float x, float y) const {
    glUniform2f(glGetUniformLocation(id_, std::string(name).c_str()), x, y);
}

void Shader::set_int(std::string_view name, int v) const {
    glUniform1i(glGetUniformLocation(id_, std::string(name).c_str()), v);
}

} // namespace phos
