#pragma once

#include <optional>

namespace SleepTogether::SleepWatch
{
    // Starts a lightweight poller (once) that notices the local player starting to sleep.
    void Install();

    // Sends the sleep request (throttled) when the mod is enabled. chosenEndHour is the hour the
    // player picked, if known; otherwise the configured wake hour is used.
    void OnSleepStarted(std::optional<float> chosenEndHour);
}
