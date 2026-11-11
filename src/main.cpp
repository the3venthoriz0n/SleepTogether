#include "PCH.h"

#include "Config.h"
#include "SleepWatch.h"
#include "StrLink.h"

namespace
{
    void SetupLog()
    {
        auto logDirectory = SKSE::log::log_directory();
        if (!logDirectory) {
            return;
        }

        auto logPath = *logDirectory / "SleepTogether.log";
        auto sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(logPath.string(), true);
        auto logger = std::make_shared<spdlog::logger>("SleepTogether", std::move(sink));

        logger->set_level(spdlog::level::info);
        logger->flush_on(spdlog::level::info);
        logger->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [SleepTogether] [%l] %v");
        spdlog::set_default_logger(std::move(logger));
    }

    void OnSKSEMessage(SKSE::MessagingInterface::Message* a_message)
    {
        if (a_message && a_message->type == SKSE::MessagingInterface::kDataLoaded) {
            spdlog::info("Data loaded");
            if (SleepTogether::StrLink::Start()) {
                spdlog::info("STRPM link ready");
            } else {
                spdlog::error("STRPM link unavailable: install STRPluginMessagingAPI and Bridge");
            }
            SleepTogether::SleepWatch::Install();
        }
    }
}

SKSEPluginLoad(const SKSE::LoadInterface* a_skse)
{
    SKSE::Init(a_skse);
    SetupLog();
    spdlog::info("SleepTogether 0.1.0 loading");

    SleepTogether::Config::Load();
    if (SleepTogether::Config::Get().debug) {
        // The logger itself was created at info level; raise its verbosity as well as the global one.
        spdlog::set_level(spdlog::level::debug);
        spdlog::default_logger()->set_level(spdlog::level::debug);
    }

    auto* messaging = SKSE::GetMessagingInterface();
    if (!messaging || !messaging->RegisterListener(OnSKSEMessage)) {
        spdlog::critical("Could not register SKSE messaging listener");
        return false;
    }

    return true;
}
