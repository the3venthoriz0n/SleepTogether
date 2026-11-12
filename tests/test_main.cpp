#include "Core.h"
#include "Protocol.h"

#include <cmath>
#include <cstdio>
#include <optional>
#include <string>
#include <utility>
#include <vector>

using namespace SleepTogether;

#define CHECK(expr)                                                         \
    do {                                                                    \
        if (!(expr)) {                                                      \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr);     \
            return 1;                                                       \
        }                                                                   \
    } while (0)

int main()
{
    CHECK(Core::ResolveWakeHour(std::nullopt, 8) == 8);
    CHECK(Core::ResolveWakeHour(13.4f, 8) == 13);
    CHECK(Core::ResolveWakeHour(13.5f, 8) == 14);
    CHECK(Core::ResolveWakeHour(23.6f, 8) == 0);
    CHECK(Core::ResolveWakeHour(-1.f, 8) == 8);
    CHECK(Core::ResolveWakeHour(24.f, 8) == 8);
    CHECK(Core::ResolveWakeHour(std::nanf(""), 8) == 8);
    CHECK(Core::ResolveWakeHour(std::nullopt, 99) == 23);
    CHECK(Core::ResolveWakeHour(std::nullopt, -3) == 0);
    CHECK(Core::FormatHour(8) == "08:00");
    CHECK(Core::FormatHour(0) == "00:00");
    CHECK(Core::AdvanceMessage("Alice", 8) == "[Sleep Together] Alice slept. It is now 08:00.");
    CHECK(Core::DenyMessage() == "[Sleep Together] Only the party leader can advance time.");
    CHECK(std::string(Protocol::kChannel) == "sleeptogether.v1");
    CHECK(Protocol::FormatSleepRequest(8) == "STv1|SLEEP|8");
    CHECK(Protocol::ParseSleepRequest("STv1|SLEEP|8") == 8);
    CHECK(Protocol::ParseSleepRequest("STv1|SLEEP|0") == 0);
    CHECK(Protocol::ParseSleepRequest("STv1|SLEEP|23") == 23);
    CHECK(Protocol::ParseSleepRequest("STv1|SLEEP|08") == 8);
    for (int h = 0; h < 24; ++h)
        CHECK(Protocol::ParseSleepRequest(Protocol::FormatSleepRequest(h)) == h);
    for (auto bad : {"STv1|SLEEP|24", "STv1|SLEEP|-1", "STv1|SLEEP|", "STv1|SLEEP|8x",
                     "STv2|SLEEP|8", "", "STv1|SLEEP|08 ", "hello", "STv1|SLEEP|+8",
                     " STv1|SLEEP|8", "STv1|SLEEP|8\n", "STv1|SLEEP|8|", "stv1|SLEEP|8",
                     "STv1|SLEEP|99999999999999999999", "STv1|SLEEP|\xD9\xA8"})
        CHECK(!Protocol::ParseSleepRequest(bad));
    CHECK(!Protocol::ParseSleepRequest(std::string("STv1|SLEEP|8\0", 13)));
    CHECK(!Protocol::ParseSleepRequest(std::string("STv1|SLEEP|\0" "8", 13)));
    CHECK(!Protocol::ParseSleepRequest(std::string(5000, '8')));
    CHECK(!Protocol::ParseSleepRequest("STv1|SLEEP|" + std::string(21, '0') + "8"));
    CHECK(Protocol::ParseSleepRequest("STv1|SLEEP|" + std::string(20, '0') + "8") == 8);
    CHECK(!Protocol::ParseSleepRequest("STv1|SLEEP|" + std::string(22, '0')));
    for (int bits = 0; bits < 8; ++bits) {
        const bool open = (bits & 4) != 0, sleeping = (bits & 2) != 0, active = (bits & 1) != 0;
        CHECK(Core::IsSleepPressed(open, sleeping, active) == (bits == 7));
    }
    {
        Core::SleepEdge edge;
        CHECK(edge.Update(false) == false);
        CHECK(edge.Update(true) == true);
        CHECK(edge.Update(true) == false);
        CHECK(edge.Update(true) == false);
        CHECK(edge.Update(false) == false);
        CHECK(edge.Update(true) == true);
    }
    {
        Core::Throttle t(3000);
        CHECK(t.Allow(10000) == true);
        CHECK(t.Allow(10001) == false);
        CHECK(t.Allow(12999) == false);
        CHECK(t.Allow(13000) == true);
        CHECK(t.Allow(13001) == false);
        Core::Throttle fresh(3000);
        CHECK(fresh.Allow(0) == true);
    }
    {
        using Members = std::vector<std::pair<std::string, std::string>>;
        CHECK(Core::FormatProbeSnapshot(1.5f, true, false, 22.25f, {}) ==
              "Sleep menu probe: timer=1.50 isSleeping=1 isActive=0 gameHour=22.25 members={}");
        CHECK(Core::FormatProbeSnapshot(0.f, false, true, 8.f, Members{ { "a", "1" }, { "b", "x" } }) ==
              "Sleep menu probe: timer=0.00 isSleeping=0 isActive=1 gameHour=8.00 members={a=1, b=x}");
        Members many;
        for (int i = 0; i < 61; ++i) {
            many.emplace_back("m" + std::to_string(i), "v");
        }
        const auto s = Core::FormatProbeSnapshot(0.f, false, false, 0.f, many);
        CHECK(s.find("m59=v, ...+1 more}") != std::string::npos);
        CHECK(s.find("m60") == std::string::npos);
        Members longMembers{ { "k", std::string(5000, 'z') } };
        CHECK(Core::FormatProbeSnapshot(0.f, false, false, 0.f, longMembers).size() == 4000);
    }
    CHECK(Core::ShouldLogProbe(false, false, false, 5000, 1000) == false);
    CHECK(Core::ShouldLogProbe(false, true, false, 999, 1000) == false);
    CHECK(Core::ShouldLogProbe(false, true, false, 1000, 1000) == true);
    CHECK(Core::ShouldLogProbe(true, true, false, 0, 1000) == true);
    CHECK(Core::ShouldLogProbe(false, false, true, 0, 1000) == true);
    CHECK(Core::ShouldLogProbe(true, false, false, 0, 1000) == true);
    std::puts("All tests passed");
    return 0;
}
