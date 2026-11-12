#pragma once

#include <cmath>
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

    // The slider value to treat as "at press": the last reading taken while the menu was idle (not yet sleeping),
    // because the slider counts down once sleeping starts; the current reading only when there was no idle one.
    inline std::optional<float> PickPressValue(std::optional<float> lastIdle, std::optional<float> current) noexcept
    {
        return lastIdle.has_value() ? lastIdle : current;
    }

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

    // Hours the sleep slider should show to reach wakeHour (clamped to [0, 23]) from currentHour: the span to the
    // next occurrence of wakeHour (a full 24 when it is now), rounded to the nearest whole hour and clamped to
    // [1, 24]. A non-finite currentHour gives the 8-hour fallback.
    int HoursUntilWake(float currentHour, int wakeHour);

    // The player left the menu while a sleep or wait was still counting down: the last slider reading taken while
    // active is present, finite and at least 0.5 (a natural finish leaves it near zero).
    inline bool WasCancelled(std::optional<float> lastActiveSlider) noexcept
    {
        return lastActiveSlider.has_value() && std::isfinite(*lastActiveSlider) && *lastActiveSlider >= 0.5f;
    }

    // Hours to ask the server to wait: the slider reading rounded half up, clamped to [1, 24]; nothing when the
    // reading is missing or not finite.
    std::optional<int> WaitHours(std::optional<float> slider);

    // "[Sleep Together] <name> waited for <n> hour(s)." n = nearest whole hour, at least 1.
    std::string WaitMessage(std::string_view name, float hours);

    // "[Sleep Together] <name> woke up early."
    std::string WakeMessage(std::string_view name);

    // The player pressed Wait: the menu is open, was not opened from a bed and the button has been pressed.
    inline bool IsWaitPressed(bool menuOpen, bool menuIsSleeping, bool menuIsActive) noexcept
    {
        return menuOpen && !menuIsSleeping && menuIsActive;
    }

    // Decides, one poll at a time, when to write the wanted hours into the sleep slider. The first reading is taken
    // as the original; the wanted value is applied once, and re-applied (at most 5 times, one per call, only within
    // the first 2000 ms of the open menu) while the reading still equals the original, because the menu may
    // reinitialise the slider just after opening. Once the reading shows the wanted value it is confirmed and
    // nothing more happens; once the reading differs from both the original and the wanted value (the player moved
    // it) nothing more happens either.
    class SliderPreselect
    {
    public:
        explicit SliderPreselect(int wanted) noexcept : wanted_(wanted) {}

        // Returns the value to write now, if any.
        std::optional<int> Update(std::optional<float> reading, std::int64_t msSinceOpen) noexcept
        {
            if (!reading || !std::isfinite(*reading) || confirmed_ || stopped_) {
                return std::nullopt;
            }
            if (Near(*reading, static_cast<float>(wanted_))) {
                confirmed_ = true;
                return std::nullopt;
            }
            if (!original_) {
                original_ = *reading;
                return wanted_;
            }
            if (!Near(*reading, *original_)) {
                stopped_ = true;
                return std::nullopt;
            }
            if (reapplied_ >= 5 || msSinceOpen > 2000) {
                return std::nullopt;
            }
            ++reapplied_;
            return wanted_;
        }

        [[nodiscard]] bool Confirmed() const noexcept { return confirmed_; }
        [[nodiscard]] int  Wanted() const noexcept { return wanted_; }

    private:
        static bool Near(float a, float b) noexcept { return std::fabs(a - b) <= 0.001f; }

        int                  wanted_;
        std::optional<float> original_;
        int                  reapplied_{ 0 };
        bool                 confirmed_{ false };
        bool                 stopped_{ false };
    };

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
