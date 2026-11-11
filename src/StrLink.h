#pragma once

namespace SleepTogether::StrLink
{
    // Loads STRPluginMessagingAPI.dll and registers the Sleep Together channel.
    // Returns false (and logs an error) when the API is not installed or registration fails.
    bool Start();

    // Sends "STv1|SLEEP|<hour>" to the server. Returns false when not started or not connected.
    // Safe to call from any thread.
    bool SendSleepRequest(int hour);
}
