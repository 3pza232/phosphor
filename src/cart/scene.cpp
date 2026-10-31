#include "cart/scene.hpp"

#include "api/lua_guard.hpp"

namespace phos {

namespace {

bool call_void(const sol::protected_function& fn, std::string& err) {
    if (!fn.valid()) return true;
    lua_guard::BudgetScope budget;
    const sol::protected_function_result result = fn();
    if (!result.valid()) {
        sol::error error = result;
        err = error.what();
        return false;
    }
    return true;
}

} // namespace

bool SceneStack::push(SceneEntry entry, std::string& err) {
    if (busy_ > 0) {
        Pending op;
        op.push = true;
        op.entry = std::move(entry);
        pending_.push_back(std::move(op));
        return true;
    }
    if (scenes_.size() >= kMaxDepth) {
        err = "scene stack is full (max " + std::to_string(kMaxDepth) + ")";
        return false;
    }
    if (!call_void(entry.on_enter, err)) return false;
    entry.skip_update = true;
    scenes_.push_back(std::move(entry));
    return true;
}

namespace {

/// 执行一次出栈（调用方保证 busy_/栈状态正确）
bool pop_now(std::vector<SceneEntry>& scenes, sol::object result, std::string& err) {
    if (scenes.empty()) {
        err = "scene stack is empty";
        return false;
    }
    SceneEntry entry = std::move(scenes.back());
    scenes.pop_back();
    if (!entry.on_exit.valid()) return true;
    lua_guard::BudgetScope budget;
    const sol::protected_function_result called =
        result.valid() ? entry.on_exit(result) : entry.on_exit();
    if (!called.valid()) {
        sol::error error = called;
        err = error.what();
        return false;
    }
    return true;
}

} // namespace

bool SceneStack::pop(sol::object result, std::string& err) {
    if (busy_ > 0) {
        Pending op;
        op.push = false;
        op.result = result;
        op.has_result = result.valid();
        pending_.push_back(std::move(op));
        return true;
    }
    return pop_now(scenes_, result, err);
}

void SceneStack::drain(std::string& err) {
    // 队列里的操作可能继续产生新操作（例如 on_exit 又压栈）：循环到空
    while (!pending_.empty()) {
        Pending op = std::move(pending_.front());
        pending_.erase(pending_.begin());
        ++busy_;
        bool ok = true;
        if (op.push) {
            if (scenes_.size() >= kMaxDepth) {
                err = "scene stack is full (max " + std::to_string(kMaxDepth) + ")";
                ok = false;
            } else if (!call_void(op.entry.on_enter, err)) {
                ok = false;
            } else {
                op.entry.skip_update = true;
                scenes_.push_back(std::move(op.entry));
            }
        } else {
            ok = pop_now(scenes_, op.has_result ? op.result : sol::object(), err);
        }
        --busy_;
        if (!ok) return;
    }
}

SceneEntry* SceneStack::top() { return scenes_.empty() ? nullptr : &scenes_.back(); }
const SceneEntry* SceneStack::top() const { return scenes_.empty() ? nullptr : &scenes_.back(); }

bool SceneStack::pause_world() const {
    for (const SceneEntry& scene : scenes_)
        if (scene.pause_world) return true;
    return false;
}

bool SceneStack::wants_audio_pause() const {
    for (const SceneEntry& scene : scenes_)
        if (scene.audio_pause) return true;
    return false;
}

bool SceneStack::update(float dt, std::string& err) {
    SceneEntry* scene = top();
    if (!scene || !scene->update.valid()) return true;
    if (scene->skip_update) {
        // 压栈那一帧按键还停在"按下"状态：此刻调 update 会立刻把同一个键当成关闭
        scene->skip_update = false;
        return true;
    }
    sol::protected_function callback = scene->update;  // 拷贝一份：回调里可能出栈
    ++busy_;
    lua_guard::BudgetScope budget;
    const sol::protected_function_result result = callback(dt);
    --busy_;
    if (!result.valid()) {
        sol::error error = result;
        err = error.what();
        return false;
    }
    drain(err);
    return true;
}

bool SceneStack::draw(std::string& err) {
    ++busy_;
    // 逐层取快照：回调里的 push/pop 先排队，本趟绘制用稳定副本
    std::vector<sol::protected_function> layers;
    layers.reserve(scenes_.size());
    for (const SceneEntry& scene : scenes_)
        if (scene.draw.valid()) layers.push_back(scene.draw);
    bool ok = true;
    for (sol::protected_function& draw : layers) {
        lua_guard::BudgetScope budget;
        const sol::protected_function_result result = draw();
        if (!result.valid()) {
            sol::error error = result;
            err = error.what();
            ok = false;
            break;
        }
    }
    --busy_;
    if (ok) drain(err);
    return ok;
}

} // namespace phos