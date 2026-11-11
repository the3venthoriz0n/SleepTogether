#include "Core.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>

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

    std::string FormatProbeSnapshot(float timer, bool isSleeping, bool isActive, float gameHour,
        const std::vector<std::pair<std::string, std::string>>& members)
    {
        constexpr std::size_t kMaxMembers = 60;
        constexpr std::size_t kMaxLength  = 2000;

        char head[160];
        std::snprintf(head, sizeof(head), "Sleep menu probe: timer=%.2f isSleeping=%d isActive=%d gameHour=%.2f members={",
            static_cast<double>(timer), isSleeping ? 1 : 0, isActive ? 1 : 0, static_cast<double>(gameHour));
        std::string out = head;

        const std::size_t shown = std::min(members.size(), kMaxMembers);
        for (std::size_t i = 0; i < shown; ++i) {
            if (i > 0) {
                out += ", ";
            }
            out += members[i].first;
            out += '=';
            out += members[i].second;
        }
        if (members.size() > shown) {
            out += ", ...+" + std::to_string(members.size() - shown) + " more";
        }
        out += '}';

        if (out.size() > kMaxLength) {
            out.resize(kMaxLength);
        }
        return out;
    }
}
