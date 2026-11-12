#include "PCH.h"
#include "StrLink.h"

#include "Protocol.h"
#include "STRPluginMessagingAPI/STRPluginMessagingAPI.h"

namespace SleepTogether::StrLink
{
    namespace
    {
        // Written once in Start() before g_running is set; read only after g_running is observed true.
        const STRPM::Interface* g_api{ nullptr };
        std::atomic<bool>       g_running{ false };

        // This mod only sends; the server answers through ordinary chat messages.
        void STRPM_CALL OnMessage(const STRPM::Message*, void*) {}
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

    bool SendSleepRequest(int hour)
    {
        if (!g_running.load()) {
            return false;
        }

        const std::string   payload = Protocol::FormatRequest({ Protocol::RequestKind::kUntil, hour });  // temporary until Task 7
        const STRPM::Target server{ STRPM::TargetKind::kServer, 0, nullptr };

        constexpr auto flags = STRPM::kMessageReliable | STRPM::kMessageOrdered;
        const auto     result = g_api->send(Protocol::kChannel, server, payload.data(), payload.size(), flags);
        if (result != STRPM::Result::kOk) {
            // Not connected is normal outside a session.
            spdlog::debug("STRPM send '{}' failed: {}", payload, STRPM::ResultToString(result));
            return false;
        }

        spdlog::info("Sleep request sent hour={}", hour);
        return true;
    }
}
