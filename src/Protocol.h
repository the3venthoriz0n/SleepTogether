#pragma once

#include <optional>
#include <string>
#include <string_view>

namespace SleepTogether::Protocol
{
    inline constexpr const char* kChannel = "sleeptogether.v1";

    // "STv1|SLEEP|<hour>"
    std::string FormatSleepRequest(int hour);

    // Strict: exact prefix, then decimal digits only (no sign, no whitespace, no trailing junk),
    // total length <= 32. Returns the hour in [0, 23], or nothing for any other input.
    std::optional<int> ParseSleepRequest(std::string_view text);
}
