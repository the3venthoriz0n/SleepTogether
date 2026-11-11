#pragma once

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
}
