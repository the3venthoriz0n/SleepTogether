#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace SleepTogether::Core
{
    // Whole wake-up hour in [0, 23]. A chosen end hour is rounded to the nearest hour (24 wraps to 0);
    // a missing, NaN or out-of-range [0, 24) value falls back to fallbackHour clamped to [0, 23].
    int ResolveWakeHour(std::optional<float> chosenEndHour, int fallbackHour);

    // "HH:00"
    std::string FormatHour(int hour);

    std::string AdvanceMessage(std::string_view leaderName, int hour);

    std::string DenyMessage();

    // Reports each false-to-true transition of a flag exactly once.
    class SleepEdge
    {
    public:
        bool Update(bool sleepingNow) noexcept
        {
            const bool rising = sleepingNow && !previous_;
            previous_ = sleepingNow;
            return rising;
        }

    private:
        bool previous_{ false };
    };

    // Allows the first call, then only calls at least minIntervalMs after the last allowed one.
    class Throttle
    {
    public:
        explicit Throttle(std::int64_t minIntervalMs) noexcept : minIntervalMs_(minIntervalMs) {}

        bool Allow(std::int64_t nowMs) noexcept
        {
            if (hasLast_ && nowMs - lastMs_ < minIntervalMs_) {
                return false;
            }
            hasLast_ = true;
            lastMs_  = nowMs;
            return true;
        }

    private:
        std::int64_t minIntervalMs_;
        std::int64_t lastMs_{ 0 };
        bool         hasLast_{ false };
    };
}
