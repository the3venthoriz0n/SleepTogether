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

    Protocol::Request DecideRequest(std::optional<float> initialSlider, std::optional<float> pressSlider,
        bool useDefaultWake, int wakeHour)
    {
        const Protocol::Request until{ Protocol::RequestKind::kUntil, std::clamp(wakeHour, 0, 23) };
        if (!pressSlider || !std::isfinite(*pressSlider)) {
            return until;
        }

        const float press = std::clamp(*pressSlider, 0.0f, 24.0f);
        const Protocol::Request hours{ Protocol::RequestKind::kHours,
            std::clamp(static_cast<int>(std::floor(press + 0.5f)), 1, 24) };
        if (!useDefaultWake) {
            return hours;
        }
        if (!initialSlider || !std::isfinite(*initialSlider)) {
            return until;
        }
        const bool explicitChoice = std::fabs(static_cast<double>(*pressSlider) - static_cast<double>(*initialSlider)) > 0.001;
        return explicitChoice ? hours : until;
    }

    float StatRestoreAmount(float maximum, float current) noexcept
    {
        if (!std::isfinite(maximum) || !std::isfinite(current)) {
            return 0.0f;
        }
        return std::max(0.0f, maximum - current);
    }

    std::string AdvanceMessage(std::string_view name, float hours)
    {
        const int n = std::isfinite(hours) ? std::max(1, static_cast<int>(std::lround(std::clamp(hours, 0.0f, 24000.0f)))) : 1;
        std::string msg = "[Sleep Together] ";
        msg += name;
        msg += " slept for ";
        msg += std::to_string(n);
        msg += n == 1 ? " hour." : " hours.";
        return msg;
    }

    int HoursUntilWake(float currentHour, int wakeHour)
    {
        if (!std::isfinite(currentHour)) {
            return 8;
        }
        double span = static_cast<double>(std::clamp(wakeHour, 0, 23)) - static_cast<double>(currentHour);
        if (span <= 0.0) {
            span += 24.0;
        }
        return std::clamp(static_cast<int>(std::lround(span)), 1, 24);
    }

    std::optional<int> WaitHours(std::optional<float> slider)
    {
        if (!slider || !std::isfinite(*slider)) {
            return std::nullopt;
        }
        const float v = std::clamp(*slider, 0.0f, 24.0f);
        return std::clamp(static_cast<int>(std::floor(v + 0.5f)), 1, 24);
    }

    std::string WaitMessage(std::string_view name, float hours)
    {
        const int n = std::isfinite(hours) ? std::max(1, static_cast<int>(std::lround(std::clamp(hours, 0.0f, 24000.0f)))) : 1;
        std::string msg = "[Sleep Together] ";
        msg += name;
        msg += " waited for ";
        msg += std::to_string(n);
        msg += n == 1 ? " hour." : " hours.";
        return msg;
    }

    std::string WakeMessage(std::string_view name)
    {
        std::string msg = "[Sleep Together] ";
        msg += name;
        msg += " woke up early.";
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
        constexpr std::size_t kMaxLength  = 4000;

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
