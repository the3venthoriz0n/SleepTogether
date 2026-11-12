#pragma once

#include <optional>
#include <string>
#include <string_view>

namespace SleepTogether::Protocol
{
    inline constexpr const char* kChannel = "sleeptogether.v1";

    // Client to server: "STv2|HOURS|<n>" (n in [1, 24]), "STv2|UNTIL|<h>" (h in [0, 23]), "STv2|WAIT|<n>"
    // (n in [1, 24], a shared Wait) or "STv2|WAKE" (cancel the running session; no value, value is 0).
    enum class RequestKind { kHours, kUntil, kWait, kWake };

    struct Request
    {
        RequestKind kind;
        int         value;
    };

    std::string FormatRequest(const Request& request);

    // Strict: exact prefix, then decimal digits only (no sign, no whitespace, no trailing junk, leading zeros
    // accepted), total length <= 32. Returns nothing for any other input or an out-of-range value.
    std::optional<Request> ParseRequest(std::string_view text);

    // Server to client: "STv2|STEP|<milliHours>" (1..24000), "STv2|DONE|<milliHours>" (0..24000) or
    // "STv2|STOP|<milliHours>" (0..24000, ended early or was a wait: no stat restore).
    enum class ServerKind { kStep, kDone, kStop };

    struct ServerMessage
    {
        ServerKind kind;
        int        milliHours;
    };

    // Same strictness as ParseRequest.
    std::optional<ServerMessage> ParseServerMessage(std::string_view text);
}
