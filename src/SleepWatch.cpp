#include "PCH.h"

#include "SleepWatch.h"

#include "Config.h"
#include "Core.h"
#include "StrLink.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace SleepTogether::SleepWatch
{
    namespace
    {
        constexpr auto kPollInterval = std::chrono::milliseconds(100);

        std::atomic_bool g_started{ false };
        std::atomic_bool g_taskPending{ false };

        std::int64_t NowMs()
        {
            using namespace std::chrono;
            return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
        }

        // Read-only diagnostic, game thread only: logs what the open Sleep/Wait menu exposes (one line per change).
        void ProbeSleepMenu(RE::UI* ui, bool menuOpen)
        {
            static std::string lastSnapshot;
            static std::string lastKey;
            static std::int64_t lastLineMs     = 0;
            static bool         firstAfterOpen = true;
            static bool         wasOpen        = false;

            if (!menuOpen) {
                if (wasOpen) {
                    spdlog::info("Sleep menu probe: menu closed");
                    wasOpen = false;
                    lastSnapshot.clear();
                    lastKey.clear();
                    firstAfterOpen = true;
                }
                return;
            }
            wasOpen = true;

            auto menu = ui->GetMenu(RE::SleepWaitMenu::MENU_NAME);
            if (!menu) {
                return;
            }
            auto* sleepMenu = static_cast<RE::SleepWaitMenu*>(menu.get());
            auto& data      = sleepMenu->GetRuntimeData();
            auto* calendar  = RE::Calendar::GetSingleton();
            const float gameHour = calendar ? calendar->GetHour() : -1.0f;

            std::vector<std::pair<std::string, std::string>> members;
            if (data.root.IsObject()) {
                // Plain member enumeration; does not call any ActionScript function.
                data.root.VisitMembers([&members](const char* name, const RE::GFxValue& value) {
                    if (members.size() > 100 || !name) {
                        return;
                    }
                    std::string text;
                    if (value.IsNumber()) {
                        char buf[48];
                        std::snprintf(buf, sizeof(buf), "%g", value.GetNumber());
                        text = buf;
                    } else if (value.IsBool()) {
                        text = value.GetBool() ? "true" : "false";
                    } else if (value.IsString()) {
                        const char* s = value.GetString();
                        text          = s ? s : "";
                    } else if (value.IsObject()) {
                        text = "<object>";
                    } else {
                        text = "<other>";
                    }
                    members.emplace_back(name, std::move(text));
                });
            }

            auto snapshot = Core::FormatProbeSnapshot(
                data.timer, data.isSleeping, data.isActive, gameHour, members);
            // The key ignores timer and game hour, which can change on every poll.
            auto key = Core::FormatProbeSnapshot(0.0f, data.isSleeping, data.isActive, 0.0f, members);

            const auto now = NowMs();
            if (Core::ShouldLogProbe(key != lastKey, snapshot != lastSnapshot, firstAfterOpen,
                    now - lastLineMs, 1000)) {
                spdlog::info("{}", snapshot);
                lastSnapshot   = std::move(snapshot);
                lastKey        = std::move(key);
                lastLineMs     = now;
                firstAfterOpen = false;
            }
        }

        // Runs on the game thread.
        void PollOnGameThread()
        {
            static Core::SleepEdge edge;
            static int             ticks = 0;

            // About once a second, pick up MCM changes.
            if (++ticks % 10 == 0) {
                Config::ReloadIfChanged();
            }

            static int          lastState    = -1;
            static int          lastMenuOpen = -1;
            static std::int64_t lastChangeMs = 0;

            bool pressed = false;
            if (auto* player = RE::PlayerCharacter::GetSingleton()) {
                // The raw sit/sleep state is not meaningful in this game build (constant 10); diagnostic only.
                const auto state = player->GetSitSleepState();
                auto* ui         = RE::UI::GetSingleton();
                const int   menuOpen = (ui && ui->IsMenuOpen(RE::SleepWaitMenu::MENU_NAME)) ? 1 : 0;
                if (static_cast<int>(state) != lastState || menuOpen != lastMenuOpen) {
                    const auto now = NowMs();
                    spdlog::info("Sleep state: sitSleepState(raw)={} sleepMenuOpen={} (+{} ms since last change)",
                        static_cast<int>(state), menuOpen, lastState < 0 ? 0 : now - lastChangeMs);
                    lastState    = static_cast<int>(state);
                    lastMenuOpen = menuOpen;
                    lastChangeMs = now;
                }
                if (ui) {
                    ProbeSleepMenu(ui, menuOpen != 0);
                    if (menuOpen != 0) {
                        if (auto menu = ui->GetMenu(RE::SleepWaitMenu::MENU_NAME)) {
                            auto& data = static_cast<RE::SleepWaitMenu*>(menu.get())->GetRuntimeData();
                            pressed    = Core::IsSleepPressed(true, data.isSleeping, data.isActive);
                        }
                    }
                }
            }

            if (edge.Update(pressed)) {
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
            spdlog::info("Sleep started but Sleep Together is disabled");
            return;
        }

        static Core::Throttle throttle(3000);
        static std::mutex     throttleMutex;
        bool                  allowed;
        {
            std::lock_guard lock(throttleMutex);
            allowed = throttle.Allow(NowMs());
        }
        if (!allowed) {
            spdlog::info("Sleep request throttled");
            return;
        }

        const int hour = Core::ResolveWakeHour(chosenEndHour, static_cast<int>(settings.wakeHour));
        StrLink::SendSleepRequest(hour);
        spdlog::info("Local sleep started (Sleep pressed in the sleep menu), requested wake hour {}", hour);
    }
}
