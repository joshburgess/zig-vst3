#include "win_ump_ref_count.hpp"

#include <array>
#include <atomic>
#include <cstdint>
#include <limits>
#include <thread>

int main()
{
    zv3::pinned_ref_count ordinary;
    if (ordinary.add_ref() != 2) {
        return 1;
    }
    uint32_t remaining = 0;
    if (ordinary.release(remaining) || remaining != 1) {
        return 1;
    }
    if (!ordinary.release(remaining) || remaining != 0) {
        return 1;
    }

    const uint32_t maximum = std::numeric_limits<uint32_t>::max();
    zv3::pinned_ref_count saturated(maximum - 1);
    if (saturated.add_ref() != maximum) {
        return 1;
    }
    if (saturated.add_ref() != maximum) {
        return 1;
    }
    if (saturated.release(remaining) || remaining != maximum) {
        return 1;
    }

    zv3::pinned_ref_count concurrent;
    std::atomic<bool> failed{false};
    std::array<std::thread, 8> threads;
    for (std::thread &thread : threads) {
        thread = std::thread([&] {
            for (uint32_t iteration = 0; iteration < 20000; ++iteration) {
                const uint32_t added = concurrent.add_ref();
                uint32_t thread_remaining = 0;
                const bool destroy = concurrent.release(thread_remaining);
                if (added <= 1 || added == maximum || destroy ||
                    thread_remaining == 0 || thread_remaining == maximum) {
                    failed.store(true, std::memory_order_relaxed);
                }
            }
        });
    }
    for (std::thread &thread : threads) {
        thread.join();
    }
    if (failed.load(std::memory_order_relaxed)) {
        return 1;
    }
    if (!concurrent.release(remaining) || remaining != 0) {
        return 1;
    }
    return 0;
}
