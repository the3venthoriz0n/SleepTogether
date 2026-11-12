#pragma once

// Settings live in MCM Helper's files, so they can be edited in the SkyUI Mod Configuration Menu:
//   defaults  Data\MCM\Config\SleepTogether\settings.ini   (shipped with the mod)
//   user      Data\MCM\Settings\SleepTogether.ini          (written by the MCM; overrides the defaults)
// Without MCM Helper the same files can be edited by hand. Changes are picked up within a second.
namespace SleepTogether::Config
{
    struct Settings
    {
        bool          enabled{ true };
        std::uint32_t wakeHour{ 8 };  // game hour (0 to 23) the party wakes at
        bool          debug{ false };
        bool          useDefaultWake{ true };  // untouched slider means "sleep until wakeHour"
        bool          restoreStats{ true };    // refill health, magicka and stamina after a shared sleep
    };

    void Load();

    // Re-reads the files if either changed on disk. Cheap enough to call about once a second.
    void ReloadIfChanged();

    // A copy of the current settings (thread-safe).
    [[nodiscard]] Settings Get();
}
