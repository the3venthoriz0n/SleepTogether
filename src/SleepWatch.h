#pragma once

#include <optional>

namespace SleepTogether::SleepWatch
{
    // Starts a lightweight poller (once) that notices the local player starting to sleep.
    void Install();

    // Sends the sleep request (throttled) when the mod is enabled. The slider values are the hours the menu
    // showed when it opened and when Sleep was pressed (nothing if unreadable); Core::DecideRequest picks
    // HOURS or UNTIL from them and the settings.
    void OnSleepStarted(std::optional<float> initialSlider, std::optional<float> pressSlider);

    // Sends a shared-Wait request (throttled, shared with sleep) when the mod and shareWait are enabled. The slider
    // value is the last reading taken while the Wait menu was idle.
    void OnWaitStarted(std::optional<float> pressSlider);

    // The server ended the session (DONE or STOP arrived): the local request is no longer outstanding.
    // Safe to call from any thread.
    void OnSessionEnded();
}
