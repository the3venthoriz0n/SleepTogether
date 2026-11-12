#include "Protocol.h"

namespace SleepTogether::Protocol
{
    namespace
    {
        constexpr std::string_view kHoursPrefix = "STv2|HOURS|";
        constexpr std::string_view kUntilPrefix = "STv2|UNTIL|";
        constexpr std::string_view kStepPrefix  = "STv2|STEP|";
        constexpr std::string_view kDonePrefix  = "STv2|DONE|";
        constexpr std::size_t      kMaxLength   = 32;

        // Decimal digits only, non-empty; nothing if any other character or if the value exceeds maxValue.
        std::optional<int> ParseNumber(std::string_view digits, int maxValue)
        {
            if (digits.empty()) {
                return std::nullopt;
            }
            int value = 0;
            for (const char c : digits) {
                if (c < '0' || c > '9') {
                    return std::nullopt;
                }
                value = value * 10 + (c - '0');
                if (value > maxValue) {
                    return std::nullopt;
                }
            }
            return value;
        }
    }

    std::string FormatRequest(const Request& request)
    {
        const std::string_view prefix = request.kind == RequestKind::kHours ? kHoursPrefix : kUntilPrefix;
        return std::string(prefix) + std::to_string(request.value);
    }

    std::optional<Request> ParseRequest(std::string_view text)
    {
        if (text.size() > kMaxLength) {
            return std::nullopt;
        }
        if (text.starts_with(kHoursPrefix)) {
            const auto n = ParseNumber(text.substr(kHoursPrefix.size()), 24);
            if (n && *n >= 1) {
                return Request{ RequestKind::kHours, *n };
            }
        } else if (text.starts_with(kUntilPrefix)) {
            if (const auto h = ParseNumber(text.substr(kUntilPrefix.size()), 23)) {
                return Request{ RequestKind::kUntil, *h };
            }
        }
        return std::nullopt;
    }

    std::optional<ServerMessage> ParseServerMessage(std::string_view text)
    {
        if (text.size() > kMaxLength) {
            return std::nullopt;
        }
        if (text.starts_with(kStepPrefix)) {
            const auto n = ParseNumber(text.substr(kStepPrefix.size()), 24000);
            if (n && *n >= 1) {
                return ServerMessage{ ServerKind::kStep, *n };
            }
        } else if (text.starts_with(kDonePrefix)) {
            if (const auto n = ParseNumber(text.substr(kDonePrefix.size()), 24000)) {
                return ServerMessage{ ServerKind::kDone, *n };
            }
        }
        return std::nullopt;
    }
}
