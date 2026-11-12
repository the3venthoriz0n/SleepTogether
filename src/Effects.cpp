#include "PCH.h"
#include "Effects.h"

#include "Config.h"
#include "Core.h"

namespace SleepTogether::Effects
{
    void OnStep(int milliHours)
    {
        static bool warned = false;

        auto* calendar = RE::Calendar::GetSingleton();
        auto* global   = calendar ? calendar->gameDaysPassed : nullptr;
        if (!global) {
            if (!warned) {
                warned = true;
                spdlog::warn("Sleep step ignored: calendar or days-passed global not available");
            }
            return;
        }

        global->value += static_cast<float>(milliHours) / 1000.0f / 24.0f;
        spdlog::info("Sleep step +{} milli-hours (days passed now {})", milliHours, global->value);
    }

    void OnDone(int milliHours)
    {
        if (!Config::Get().restoreStats) {
            spdlog::info("Sleep done ({} milli-hours), stat restore disabled", milliHours);
            return;
        }

        auto* player = RE::PlayerCharacter::GetSingleton();
        auto* owner  = player ? player->AsActorValueOwner() : nullptr;
        if (!owner) {
            spdlog::warn("Sleep done ({} milli-hours), player not available, nothing restored", milliHours);
            return;
        }

        std::string restored;
        const std::pair<RE::ActorValue, const char*> stats[] = {
            { RE::ActorValue::kHealth, "health" },
            { RE::ActorValue::kMagicka, "magicka" },
            { RE::ActorValue::kStamina, "stamina" },
        };
        for (const auto& [av, name] : stats) {
            const float amount = Core::StatRestoreAmount(player->GetActorValueMax(av), owner->GetActorValue(av));
            if (amount > 0.0f) {
                owner->RestoreActorValue(av, amount);
                restored += restored.empty() ? "" : ", ";
                restored += std::format("{} +{:.1f}", name, amount);
            }
        }
        spdlog::info("Sleep done ({} milli-hours), restored {}", milliHours,
            restored.empty() ? "nothing (all stats already full)" : restored);
    }
}
