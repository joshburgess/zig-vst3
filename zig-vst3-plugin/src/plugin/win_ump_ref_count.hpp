#pragma once

#include <atomic>
#include <cstdint>
#include <limits>

namespace zv3 {

class pinned_ref_count final {
public:
    explicit pinned_ref_count(uint32_t initial = 1) noexcept
        : value_(initial)
    {
    }

    uint32_t add_ref() noexcept
    {
        uint32_t current = value_.load(std::memory_order_relaxed);
        const uint32_t maximum = std::numeric_limits<uint32_t>::max();
        while (current != maximum) {
            if (value_.compare_exchange_weak(
                    current,
                    current + 1,
                    std::memory_order_relaxed,
                    std::memory_order_relaxed
                )) {
                return current + 1;
            }
        }
        return maximum;
    }

    bool release(uint32_t &remaining) noexcept
    {
        uint32_t current = value_.load(std::memory_order_relaxed);
        const uint32_t maximum = std::numeric_limits<uint32_t>::max();
        while (current != 0 && current != maximum) {
            if (value_.compare_exchange_weak(
                    current,
                    current - 1,
                    std::memory_order_acq_rel,
                    std::memory_order_relaxed
                )) {
                remaining = current - 1;
                return remaining == 0;
            }
        }
        remaining = current;
        return false;
    }

private:
    std::atomic<uint32_t> value_;
};

}
