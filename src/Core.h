#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "Protocol.h"

namespace SleepTogether::Core
{
    // Whole wake-up hour in [0, 23]. A chosen end hour is rounded to the nearest hour (24 wraps to 0);
    // a missing, NaN or out-of-range [0, 24) value falls back to fallbackHour clamped to [0, 23].
    int ResolveWakeHour(std::optional<float> chosenEndHour, int fallbackHour);

    // Decides what to ask the server for from the Sleep/Wait menu sliders. initialSlider is the slider value when
    // the menu opened, pressSlider the value when Sleep was pressed (nullopt or non-finite: unreadable).
    // An explicit choice (press differs from initial by more than 0.001) or a disabled default gives
    // kHours (round-half-up of the press value, clamped to [1, 24]); otherwise kUntil with wakeHour clamped to
    // [0, 23]. An unreadable press value, or an unreadable initial value while the default is enabled (it cannot
    // be told whether the player moved the slider), also gives kUntil.
    Protocol::Request DecideRequest(std::optional<float> initialSlider, std::optional<float> pressSlider,
        bool useDefaultWake, int wakeHour);

    // How much of a stat to restore to reach its maximum: max(0, maximum - current), 0 for non-finite input.
    float StatRestoreAmount(float maximum, float current) noexcept;

    // "[Sleep Together] <name> slept for <n> hour(s)." n = nearest whole hour, at least 1.
    std::string AdvanceMessage(std::string_view name, float hours);

    std::string DenyMessage();

    // Whether the Sleep/Wait menu probe should log now: always on the first line after the menu opens or when
    // the key content changed; for timer/hour-only changes at most once per minMsForTimerOnly.
    inline bool ShouldLogProbe(bool keyChanged, bool snapshotChanged, bool firstAfterOpen,
        std::int64_t msSinceLastLine, std::int64_t minMsForTimerOnly) noexcept
    {
        return firstAfterOpen || keyChanged || (snapshotChanged && msSinceLastLine >= minMsForTimerOnly);
    }

    // One diagnostic line describing the Sleep/Wait menu: "Sleep menu probe: timer=<f> isSleeping=<0|1>
    // isActive=<0|1> gameHour=<f> members={name=value, ...}". At most 60 members are listed (then
    // ", ...+<n> more"); the whole line is truncated to 4000 characters.
    std::string FormatProbeSnapshot(float timer, bool isSleeping, bool isActive, float gameHour,
        const std::vector<std::pair<std::string, std::string>>& members);

    // The player pressed Sleep: the Sleep/Wait menu is open, was opened from a bed (isSleeping) and the Sleep
    // button has been pressed (isActive). A Wait menu or a cancelled sleep menu is never "pressed".
    inline bool IsSleepPressed(bool menuOpen, bool menuIsSleeping, bool menuIsActive) noexcept
    {
        return menuOpen && menuIsSleeping && menuIsActive;
    }

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
