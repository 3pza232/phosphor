#include "app/boot_sequence.hpp"

namespace phos {

void BootSequence::reset() {
    elapsed_ = 0.0f;
}

void BootSequence::start(float duration) {
    elapsed_ = 0.0f;
    duration_ = duration < kMinSeconds ? kMinSeconds : duration;
}

void BootSequence::tick(float dt) {
    elapsed_ += dt;
}

} // namespace phos
