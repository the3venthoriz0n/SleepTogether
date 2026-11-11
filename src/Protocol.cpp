#include "Protocol.h"

namespace SleepTogether::Protocol
{
    namespace
    {
        constexpr std::string_view kSleepPrefix = "STv1|SLEEP|";
        constexpr std::size_t kMaxLength = 32;
    }

    std::string FormatSleepRequest(int hour)
    {
        return std::string(kSleepPrefix) + std::to_string(hour);
    }

    std::optional<int> ParseSleepRequest(std::string_view text)
    {
        if (text.size() > kMaxLength || !text.starts_with(kSleepPrefix)) {
            return std::nullopt;
        }

        const std::string_view digits = text.substr(kSleepPrefix.size());
        if (digits.empty()) {
            return std::nullopt;
        }

        int hour = 0;
        for (const char c : digits) {
            if (c < '0' || c > '9') {
                return std::nullopt;
            }
            hour = hour * 10 + (c - '0');
            if (hour > 23) {
                return std::nullopt;
            }
        }
        return hour;
    }
}
