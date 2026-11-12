#include "PCH.h"

#include "SleepWatch.h"

#include "Config.h"
#include "Core.h"
#include "StrLink.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <mutex>
#include <optional>
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

        std::string DescribeValue(const RE::GFxValue& value)
        {
            if (value.IsNumber()) {
                char buf[48];
                std::snprintf(buf, sizeof(buf), "%g", value.GetNumber());
                return buf;
            }
            if (value.IsBool()) {
                return value.GetBool() ? "true" : "false";
            }
            if (value.IsString()) {
                const char* s = value.GetString();
                return s ? s : "";
            }
            return value.IsObject() ? "<object>" : "<other>";
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
                std::vector<std::pair<std::string, RE::GFxValue>> nested;
                data.root.VisitMembers([&members, &nested](const char* name, const RE::GFxValue& value) {
                    if (members.size() > 100 || !name) {
                        return;
                    }
                    if (value.IsObject()) {
                        const std::string n = name;
                        if (n == "HoursSlider" || n == "HoursText" || n == "CurrentTime") {
                            nested.emplace_back(n, value);
                        }
                    }
                    members.emplace_back(name, DescribeValue(value));
                });
                // One level deeper for the three members that may hold the chosen hours: name, plus value for
                // number/string/bool members (objects by name only).
                for (const auto& [parent, obj] : nested) {
                    std::size_t count = 0;
                    obj.VisitMembers([&](const char* name, const RE::GFxValue& value) {
                        if (++count > 100 || !name) {
                            return;
                        }
                        members.emplace_back(parent + "." + name, DescribeValue(value));
                    });
                }
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

        // Game thread only: the hours the sleep menu's slider currently shows (HoursSlider._value), if readable.
        std::optional<float> ReadHoursSlider(RE::SleepWaitMenu* menu)
        {
            if (!menu) {
                return std::nullopt;
            }
            auto& root = menu->GetRuntimeData().root;
            if (!root.IsObject()) {
                return std::nullopt;
            }
            RE::GFxValue slider;
            if (!root.GetMember("HoursSlider", &slider) || !slider.IsObject()) {
                return std::nullopt;
            }
            RE::GFxValue value;
            if (!slider.GetMember("_value", &value) || !value.IsNumber()) {
                return std::nullopt;
            }
            return static_cast<float>(value.GetNumber());
        }

        // Game thread only: writes hours into the sleep menu's slider (HoursSlider.value). Unverified in game:
        // the result is always read back and logged by the caller. Never throws.
        bool WriteHoursSlider(RE::SleepWaitMenu* menu, int hours)
        {
            try {
                if (!menu) {
                    return false;
                }
                auto& root = menu->GetRuntimeData().root;
                if (!root.IsObject()) {
                    return false;
                }
                RE::GFxValue slider;
                if (!root.GetMember("HoursSlider", &slider) || !slider.IsObject()) {
                    return false;
                }
                return slider.SetMember("value", RE::GFxValue(static_cast<double>(hours)));
            } catch (...) {
                return false;
            }
        }

        std::string DescribeReading(const std::optional<float>& v)
        {
            return v ? fmt::format("{:g}", *v) : std::string("unreadable");
        }

        // True while a request this client sent may still be running on the server.
        std::atomic_bool g_outstanding{ false };

        // The 3 s throttle shared by sleep and wait requests.
        bool AllowRequest()
        {
            static Core::Throttle throttle(3000);
            static std::mutex     throttleMutex;
            std::lock_guard       lock(throttleMutex);
            return throttle.Allow(NowMs());
        }

        const char* KindName(Protocol::RequestKind kind)
        {
            switch (kind) {
            case Protocol::RequestKind::kHours: return "HOURS";
            case Protocol::RequestKind::kUntil: return "UNTIL";
            case Protocol::RequestKind::kWait:  return "WAIT";
            case Protocol::RequestKind::kWake:  return "WAKE";
            }
            return "?";
        }

        // Runs on the game thread.
        void PollOnGameThread()
        {
            static Core::SleepEdge edge;
            static Core::SleepEdge waitEdge;
            static int             ticks = 0;

            // About once a second, pick up MCM changes.
            if (++ticks % 10 == 0) {
                Config::ReloadIfChanged();
            }

            static int          lastState    = -1;
            static int          lastMenuOpen = -1;
            static std::int64_t lastChangeMs = 0;

            // Slider value captured while the sleep menu is open and not yet sleeping; forgotten when it closes.
            static std::optional<float> initialSlider;
            // Most recent slider reading while the menu was open, sleeping-ready and not yet active. HoursSlider._value
            // counts down once the sleep starts (7.345 at press, 6.345 about a second later, and the countdown may begin
            // immediately), so the value read on the first active tick can already be below what the player chose.
            static std::optional<float> lastIdleSlider;
            // Most recent slider reading while the menu was active (counting down); used to tell a cancelled
            // sleep or wait from a natural finish when the menu closes.
            static std::optional<float> lastActiveSlider;
            // Slider preselect for the current menu open (created once, on the first eligible poll).
            static std::optional<Core::SliderPreselect> preselect;
            static bool                                 preselectTried = false;
            static bool                                 prevMenuOpen   = false;
            static std::int64_t                         openMs         = 0;

            bool                 menuOpenNow = false;
            bool                 pressed     = false;
            bool                 waitPressed = false;
            std::optional<float> pressSlider;
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
                        menuOpenNow = true;
                        if (auto menu = ui->GetMenu(RE::SleepWaitMenu::MENU_NAME)) {
                            auto* sleepMenu = static_cast<RE::SleepWaitMenu*>(menu.get());
                            auto& data      = sleepMenu->GetRuntimeData();
                            const auto now  = NowMs();
                            if (!prevMenuOpen) {
                                openMs         = now;
                                preselect.reset();
                                preselectTried = false;
                                lastActiveSlider.reset();
                            }
                            if (data.isActive) {
                                if (const auto reading = ReadHoursSlider(sleepMenu)) {
                                    lastActiveSlider = reading;
                                }
                            } else {
                                const auto reading = ReadHoursSlider(sleepMenu);
                                if (data.isSleeping) {
                                    if (!initialSlider) {
                                        initialSlider = reading;
                                    }
                                    const auto settings = Config::Get();
                                    if (!preselectTried && settings.enabled && settings.useDefaultWake) {
                                        if (auto* calendar = RE::Calendar::GetSingleton()) {
                                            preselectTried = true;
                                            preselect.emplace(Core::HoursUntilWake(
                                                calendar->GetHour(), static_cast<int>(settings.wakeHour)));
                                        }
                                    }
                                    if (preselect) {
                                        if (const auto wanted = preselect->Update(reading, now - openMs)) {
                                            const bool wrote = WriteHoursSlider(sleepMenu, *wanted);
                                            spdlog::info("Sleep slider preselect: wanted {}, read back {}{}", *wanted,
                                                DescribeReading(ReadHoursSlider(sleepMenu)), wrote ? "" : " (write failed)");
                                        }
                                        if (preselect->Confirmed()) {
                                            initialSlider = static_cast<float>(preselect->Wanted());
                                        }
                                    }
                                }
                                if (reading) {
                                    lastIdleSlider = reading;
                                }
                            }
                            pressed     = Core::IsSleepPressed(true, data.isSleeping, data.isActive);
                            waitPressed = Core::IsWaitPressed(true, data.isSleeping, data.isActive);
                            if (pressed || waitPressed) {
                                pressSlider = Core::PickPressValue(lastIdleSlider, ReadHoursSlider(sleepMenu));
                            }
                        }
                    }
                }
            }

            if (!menuOpenNow) {
                initialSlider.reset();
                lastIdleSlider.reset();
                preselect.reset();
                if (prevMenuOpen) {
                    // Menu closed. A request that was running and a slider still well above zero means the
                    // player left early rather than the countdown finishing: ask the server to stop.
                    if (g_outstanding.exchange(false) && Core::WasCancelled(lastActiveSlider)) {
                        spdlog::info("Sleep menu closed early (last active slider {}), requesting wake",
                            DescribeReading(lastActiveSlider));
                        StrLink::SendRequest({ Protocol::RequestKind::kWake, 0 });
                    }
                    lastActiveSlider.reset();
                }
            }
            prevMenuOpen = menuOpenNow;

            if (edge.Update(pressed)) {
                OnSleepStarted(initialSlider, pressSlider);
            }
            if (waitEdge.Update(waitPressed)) {
                OnWaitStarted(pressSlider);
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

    void OnSessionEnded()
    {
        g_outstanding.store(false);
    }

    void OnSleepStarted(std::optional<float> initialSlider, std::optional<float> pressSlider)
    {
        const auto settings = Config::Get();
        if (!settings.enabled) {
            spdlog::info("Sleep started but Sleep Together is disabled");
            return;
        }
        if (!AllowRequest()) {
            spdlog::info("Sleep request throttled");
            return;
        }

        const auto request = Core::DecideRequest(
            initialSlider, pressSlider, settings.useDefaultWake, static_cast<int>(settings.wakeHour));
        if (StrLink::SendRequest(request)) {
            g_outstanding.store(true);
        }

        spdlog::info("Local sleep started (initial slider {}, last before press {}), requested {} {}",
            DescribeReading(initialSlider), DescribeReading(pressSlider), KindName(request.kind), request.value);
    }

    void OnWaitStarted(std::optional<float> pressSlider)
    {
        const auto settings = Config::Get();
        if (!settings.enabled || !settings.shareWait) {
            spdlog::info("Wait started, not shared (Sleep Together or Share waiting is off)");
            return;
        }
        const auto hours = Core::WaitHours(pressSlider);
        if (!hours) {
            spdlog::info("Wait started but the slider could not be read, not shared");
            return;
        }
        if (!AllowRequest()) {
            spdlog::info("Wait request throttled");
            return;
        }
        if (StrLink::SendRequest({ Protocol::RequestKind::kWait, *hours })) {
            g_outstanding.store(true);
        }
        spdlog::info("Local wait started (slider {}), requested WAIT {}", DescribeReading(pressSlider), *hours);
    }
}
