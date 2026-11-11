#include "PCH.h"

#include "SleepWatch.h"

#include "Config.h"
#include "Core.h"
#include "StrLink.h"

#include <atomic>
#include <chrono>
#include <thread>

namespace SleepTogether::SleepWatch
{
    namespace
    {
        constexpr auto kPollInterval = std::chrono::milliseconds(250);

        std::atomic_bool g_started{ false };
        std::atomic_bool g_taskPending{ false };

        std::int64_t NowMs()
        {
            using namespace std::chrono;
            return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
        }

        // Runs on the game thread.
        void PollOnGameThread()
        {
            static Core::SleepEdge edge;
            static int             ticks = 0;

            // About once a second, pick up MCM changes.
            if (++ticks % 4 == 0) {
                Config::ReloadIfChanged();
            }

            bool sleeping = false;
            if (auto* player = RE::PlayerCharacter::GetSingleton()) {
                switch (player->GetSitSleepState()) {
                case RE::SIT_SLEEP_STATE::kWantToSleep:
                case RE::SIT_SLEEP_STATE::kWaitingForSleepAnim:
                case RE::SIT_SLEEP_STATE::kIsSleeping:
                    sleeping = true;
                    break;
                default:
                    break;
                }
            }

            if (edge.Update(sleeping)) {
                OnSleepStarted(std::nullopt);
            }
        }

        // Timer thread: only schedules game-thread work, never touches game state itself.
        void PollerLoop()
        {
            for (;;) {
                std::this_thread::sleep_for(kPollInterval);
                // Skip a tick if the previous one has not run yet (e.g. game paused in a loading screen).
                if (g_taskPending.exchange(true)) {
                    continue;
                }
                auto* tasks = SKSE::GetTaskInterface();
                if (!tasks) {
                    g_taskPending = false;
                    continue;
                }
                tasks->AddTask([] {
                    PollOnGameThread();
                    g_taskPending = false;
                });
            }
        }
    }

    void Install()
    {
        if (g_started.exchange(true)) {
            return;
        }
        // Detached for the life of the process: the thread holds no resources and the process exit ends it.
        std::thread(PollerLoop).detach();
        spdlog::info("Sleep watcher started");
    }

    void OnSleepStarted(std::optional<float> chosenEndHour)
    {
        const auto settings = Config::Get();
        if (!settings.enabled) {
            spdlog::debug("Sleep started but Sleep Together is disabled");
            return;
        }

        static Core::Throttle throttle(3000);
        if (!throttle.Allow(NowMs())) {
            spdlog::debug("Sleep request throttled");
            return;
        }

        const int hour = Core::ResolveWakeHour(chosenEndHour, static_cast<int>(settings.wakeHour));
        StrLink::SendSleepRequest(hour);
        spdlog::info("Local sleep started, requested wake hour {}", hour);
    }
}
