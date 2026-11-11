#include "Core.h"

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace SleepTogether::Core
{
    int ResolveWakeHour(std::optional<float> chosenEndHour, int fallbackHour)
    {
        if (chosenEndHour && std::isfinite(*chosenEndHour) && *chosenEndHour >= 0.0f && *chosenEndHour < 24.0f) {
            return static_cast<int>(std::lround(*chosenEndHour)) % 24;
        }
        return std::clamp(fallbackHour, 0, 23);
    }

    std::string FormatHour(int hour)
    {
        char buf[16];
        std::snprintf(buf, sizeof(buf), "%02d:00", std::clamp(hour, 0, 23));
        return buf;
    }

    std::string AdvanceMessage(std::string_view leaderName, int hour)
    {
        std::string msg = "[Sleep Together] ";
        msg += leaderName;
        msg += " slept. It is now ";
        msg += FormatHour(hour);
        msg += ".";
        return msg;
    }

    std::string DenyMessage()
    {
        return "[Sleep Together] Only the party leader can advance time.";
    }
}
