#pragma once

namespace SleepTogether::Effects
{
    // Both functions touch game state and must be called on the game thread only (queue them with
    // SKSE::GetTaskInterface()->AddTask).

    // One server step: advances the calendar's days passed by milliHours / 1000 hours.
    void OnStep(int milliHours);

    // End of the shared sleep: refills health, magicka and stamina when the restoreStats setting is on.
    void OnDone(int milliHours);
}
