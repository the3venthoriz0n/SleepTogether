#pragma once

#include "Protocol.h"

namespace SleepTogether::StrLink
{
    // Loads STRPluginMessagingAPI.dll and registers the Sleep Together channel.
    // Returns false (and logs an error) when the API is not installed or registration fails.
    bool Start();

    // Sends the formatted request (HOURS, UNTIL, WAIT or WAKE) to the server. Returns false when not started or not
    // connected. Safe to call from any thread.
    bool SendRequest(const Protocol::Request& request);
}
