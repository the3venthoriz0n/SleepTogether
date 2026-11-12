#include "PCH.h"
#include "StrLink.h"

#include "Effects.h"
#include "SleepWatch.h"
#include "Protocol.h"
#include "STRPluginMessagingAPI/STRPluginMessagingAPI.h"

namespace SleepTogether::StrLink
{
    namespace
    {
        // Written once in Start() before g_running is set; read only after g_running is observed true.
        const STRPM::Interface* g_api{ nullptr };
        std::atomic<bool>       g_running{ false };

        constexpr std::size_t kMaxPayload = 64;

        // Runs on the bridge's dispatcher thread: copy, parse and queue only. The payload buffer is destroyed
        // when this returns, so nothing from `message` may be kept.
        void STRPM_CALL OnMessage(const STRPM::Message* message, void*)
        {
            if (!message || !message->data || message->size == 0 || message->size > kMaxPayload ||
                !message->channel || std::string_view(message->channel) != Protocol::kChannel) {
                return;
            }

            const std::string payload(static_cast<const char*>(message->data), message->size);
            const auto        parsed = Protocol::ParseServerMessage(payload);
            if (!parsed) {
                spdlog::debug("Ignored message");
                return;
            }

            auto* tasks = SKSE::GetTaskInterface();
            if (!tasks) {
                return;
            }
            const auto kind       = parsed->kind;
            const auto milliHours = parsed->milliHours;
            tasks->AddTask([kind, milliHours]() {
                if (kind == Protocol::ServerKind::kStep) {
                    Effects::OnStep(milliHours);
                } else if (kind == Protocol::ServerKind::kStop) {
                    SleepWatch::OnSessionEnded();
                    Effects::OnStop(milliHours);
                } else {
                    SleepWatch::OnSessionEnded();
                    Effects::OnDone(milliHours);
                }
            });
        }
    }

    bool Start()
    {
        if (g_running.load()) {
            return true;
        }

        const auto* api = STRPM::LoadFromModule();
        if (!api || !api->registerChannel || !api->send) {
            spdlog::error("STRPluginMessagingAPI.dll not found or incompatible; Sleep Together cannot reach the server");
            return false;
        }

        STRPM::ListenerHandle listener{};
        if (const auto result = api->registerChannel(Protocol::kChannel, &OnMessage, nullptr, &listener);
            result != STRPM::Result::kOk) {
            spdlog::error("STRPM registerChannel failed: {}", STRPM::ResultToString(result));
            return false;
        }

        g_api = api;
        g_running.store(true);
        spdlog::info("STRPM link started: channel={}", Protocol::kChannel);
        return true;
    }

    bool SendRequest(const Protocol::Request& request)
    {
        if (!g_running.load()) {
            return false;
        }

        const std::string   payload = Protocol::FormatRequest(request);
        const STRPM::Target server{ STRPM::TargetKind::kServer, 0, nullptr };

        constexpr auto flags = STRPM::kMessageReliable | STRPM::kMessageOrdered;
        const auto     result = g_api->send(Protocol::kChannel, server, payload.data(), payload.size(), flags);
        if (result != STRPM::Result::kOk) {
            // Not connected is normal outside a session.
            spdlog::debug("STRPM send '{}' failed: {}", payload, STRPM::ResultToString(result));
            return false;
        }

        spdlog::info("Request sent {}", payload);
        return true;
    }
}
