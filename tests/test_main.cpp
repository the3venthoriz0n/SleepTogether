#include "Core.h"
#include "Protocol.h"

#include <cmath>
#include <cstdio>
#include <optional>
#include <string>
#include <string_view>
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
    CHECK(Core::DenyMessage() == "[Sleep Together] Only the party leader can advance time.");
    CHECK(Core::AdvanceMessage("Alice", 8.0f) == "[Sleep Together] Alice slept for 8 hours.");
    CHECK(Core::AdvanceMessage("Bob", 1.0f) == "[Sleep Together] Bob slept for 1 hour.");
    CHECK(Core::AdvanceMessage("Bob", 0.2f) == "[Sleep Together] Bob slept for 1 hour.");
    CHECK(Core::AdvanceMessage("Cy", 18.36f) == "[Sleep Together] Cy slept for 18 hours.");
    using Protocol::Request;
    using Protocol::RequestKind;
    CHECK(Protocol::FormatRequest({ RequestKind::kHours, 7 }) == "STv2|HOURS|7");
    CHECK(Protocol::FormatRequest({ RequestKind::kUntil, 8 }) == "STv2|UNTIL|8");
    {
        const auto expectReq = [](std::string_view text, RequestKind kind, int value) {
            const auto r = Protocol::ParseRequest(text);
            return r && r->kind == kind && r->value == value;
        };
        CHECK(expectReq("STv2|HOURS|1", RequestKind::kHours, 1));
        CHECK(expectReq("STv2|HOURS|24", RequestKind::kHours, 24));
        CHECK(expectReq("STv2|HOURS|07", RequestKind::kHours, 7));
        CHECK(expectReq("STv2|UNTIL|0", RequestKind::kUntil, 0));
        CHECK(expectReq("STv2|UNTIL|23", RequestKind::kUntil, 23));
        for (auto bad : { "STv2|HOURS|0", "STv2|HOURS|25", "STv2|UNTIL|24", "STv2|UNTIL|-1", "STv2|HOURS|",
                          "STv2|HOURS|8x", "STv2|HOURS|+8", "STv2|HOURS|8 ", "STv1|SLEEP|8", "STv2|SLEEP|8",
                          "STv2|hours|8", "" })
            CHECK(!Protocol::ParseRequest(bad));
        CHECK(!Protocol::ParseRequest(std::string(5000, '8')));
        CHECK(!Protocol::ParseRequest("STv2|HOURS|" + std::string(22, '0') + "8"));  // 33 characters
        CHECK(expectReq("STv2|HOURS|" + std::string(20, '0') + "8", RequestKind::kHours, 8));  // 32 characters
        CHECK(!Protocol::ParseRequest(std::string("STv2|HOURS|8\0", 13)));
        CHECK(!Protocol::ParseRequest(std::string("STv2|HOURS|\0" "8", 13)));
    }
    {
        using Protocol::ServerKind;
        const auto expectMsg = [](std::string_view text, ServerKind kind, int milli) {
            const auto m = Protocol::ParseServerMessage(text);
            return m && m->kind == kind && m->milliHours == milli;
        };
        CHECK(expectMsg("STv2|STEP|1000", ServerKind::kStep, 1000));
        CHECK(expectMsg("STv2|STEP|24000", ServerKind::kStep, 24000));
        CHECK(expectMsg("STv2|DONE|0", ServerKind::kDone, 0));
        CHECK(expectMsg("STv2|DONE|18360", ServerKind::kDone, 18360));
        CHECK(expectMsg("STv2|DONE|24000", ServerKind::kDone, 24000));
        CHECK(expectMsg("STv2|STEP|0001000", ServerKind::kStep, 1000));
        for (auto bad : { "STv2|STEP|0", "STv2|STEP|24001", "STv2|DONE|24001", "STv2|STEP|", "STv2|DONE|",
                          "STv2|STEP|1e3", "STv2|STEP|-5", "STv2|STEP|+5", "STv2|STEP|5 ", "STv2|HOURS|3", "" })
            CHECK(!Protocol::ParseServerMessage(bad));
        CHECK(!Protocol::ParseServerMessage(std::string(5000, '1')));
        CHECK(!Protocol::ParseServerMessage("STv2|STEP|" + std::string(23, '0') + "1"));  // 34 characters
        CHECK(!Protocol::ParseServerMessage("STv2|DONE|" + std::string(23, '0')));
        CHECK(!Protocol::ParseServerMessage(std::string("STv2|STEP|1\0", 12)));
    }
    {
        const float nan = std::nanf("");
        const auto  same = [](Request r, RequestKind kind, int value) { return r.kind == kind && r.value == value; };
        CHECK(same(Core::DecideRequest(18.f, 18.f, true, 8), RequestKind::kUntil, 8));
        CHECK(same(Core::DecideRequest(1.f, 7.345f, true, 8), RequestKind::kHours, 7));
        CHECK(same(Core::DecideRequest(1.f, 1.f, false, 8), RequestKind::kHours, 1));
        CHECK(same(Core::DecideRequest(1.f, 7.5f, true, 8), RequestKind::kHours, 8));
        CHECK(same(Core::DecideRequest(1.f, 30.f, true, 8), RequestKind::kHours, 24));
        CHECK(same(Core::DecideRequest(1.f, 0.2f, true, 8), RequestKind::kHours, 1));
        CHECK(same(Core::DecideRequest(1.f, nan, false, 8), RequestKind::kUntil, 8));
        CHECK(same(Core::DecideRequest(1.f, std::nullopt, false, 8), RequestKind::kUntil, 8));
        CHECK(same(Core::DecideRequest(1.f, nan, true, 8), RequestKind::kUntil, 8));
        CHECK(same(Core::DecideRequest(std::nullopt, 7.f, true, 8), RequestKind::kUntil, 8));
        CHECK(same(Core::DecideRequest(std::nullopt, 7.f, false, 8), RequestKind::kHours, 7));
        CHECK(same(Core::DecideRequest(18.f, 18.f, true, 99), RequestKind::kUntil, 23));
        CHECK(same(Core::DecideRequest(18.f, 18.f, true, -3), RequestKind::kUntil, 0));
    }
    CHECK(Core::StatRestoreAmount(100.f, 40.f) == 60.f);
    CHECK(Core::StatRestoreAmount(100.f, 100.f) == 0.f);
    CHECK(Core::StatRestoreAmount(100.f, 120.f) == 0.f);
    CHECK(Core::StatRestoreAmount(std::nanf(""), 40.f) == 0.f);
    CHECK(Core::StatRestoreAmount(100.f, std::nanf("")) == 0.f);
    CHECK(Core::StatRestoreAmount(-5.f, 0.f) == 0.f);
    CHECK(std::string(Protocol::kChannel) == "sleeptogether.v1");
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
    CHECK(Core::PickPressValue(5.f, 4.2f) == std::optional<float>(5.f));
    CHECK(Core::PickPressValue(std::nullopt, 4.2f) == std::optional<float>(4.2f));
    CHECK(!Core::PickPressValue(std::nullopt, std::nullopt).has_value());
    CHECK(Core::PickPressValue(5.f, std::nullopt) == std::optional<float>(5.f));
    // 0.3.0: preselect, cancel, shared wait
    CHECK(Core::HoursUntilWake(22.0f, 8) == 10);
    CHECK(Core::HoursUntilWake(8.0f, 8) == 24);
    CHECK(Core::HoursUntilWake(7.6f, 8) == 1);
    CHECK(Core::HoursUntilWake(0.0f, 8) == 8);
    CHECK(Core::HoursUntilWake(7.0f, 8) == 1);
    CHECK(Core::HoursUntilWake(8.4f, 8) == 24);
    CHECK(Core::HoursUntilWake(std::nanf(""), 8) == 8);
    CHECK(Core::HoursUntilWake(INFINITY, 8) == 8);
    CHECK(Core::HoursUntilWake(22.0f, 99) == 1);  // wake clamped to 23
    CHECK(Core::HoursUntilWake(23.5f, 0) == 1);   // 0.5 hours away rounds to 1 (or 0 -> clamp 1)
    CHECK(!Core::WasCancelled(std::nullopt));
    CHECK(!Core::WasCancelled(std::nanf("")));
    CHECK(!Core::WasCancelled(0.0f));
    CHECK(!Core::WasCancelled(1.49f));
    CHECK(Core::WasCancelled(1.5f));
    CHECK(Core::WasCancelled(7.3f));
    CHECK(!Core::WasCancelled(INFINITY));
    CHECK(Core::WaitMessage("Alice", 3.0f) == "[Sleep Together] Alice waited for 3 hours.");
    CHECK(Core::WaitMessage("Bob", 1.0f) == "[Sleep Together] Bob waited for 1 hour.");
    CHECK(Core::WaitMessage("Bob", 0.2f) == "[Sleep Together] Bob waited for 1 hour.");
    CHECK(Core::WakeMessage("Cy") == "[Sleep Together] Cy woke up early.");
    for (int bits = 0; bits < 8; ++bits) {
        const bool open = (bits & 4) != 0, sleeping = (bits & 2) != 0, active = (bits & 1) != 0;
        CHECK(Core::IsWaitPressed(open, sleeping, active) == (open && !sleeping && active));
    }
    CHECK(Core::WaitHours(3.4f) == std::optional<int>(3));
    CHECK(Core::WaitHours(3.5f) == std::optional<int>(4));
    CHECK(Core::WaitHours(0.2f) == std::optional<int>(1));
    CHECK(Core::WaitHours(30.f) == std::optional<int>(24));
    CHECK(!Core::WaitHours(std::nullopt).has_value());
    CHECK(!Core::WaitHours(std::nanf("")).has_value());
    {
        // fresh open: slider shows 1, wanted 10
        Core::SliderPreselect p(10);
        CHECK(!p.Update(std::nullopt, 0).has_value());
        CHECK(p.Update(1.f, 100) == std::optional<int>(10));   // first attempt
        CHECK(p.Update(1.f, 200) == std::optional<int>(10));   // menu reinitialised, unmoved: re-apply
        CHECK(!p.Confirmed());
        CHECK(!p.Update(10.f, 300).has_value());               // took effect
        CHECK(p.Confirmed());
        CHECK(!p.Update(1.f, 400).has_value());                // confirmed: never again
    }
    {
        Core::SliderPreselect p(10);
        CHECK(p.Update(1.f, 0) == std::optional<int>(10));
        CHECK(!p.Update(5.f, 100).has_value());                // player moved it
        CHECK(!p.Update(1.f, 200).has_value());                // even back at the original: stopped
        CHECK(!p.Confirmed());
    }
    {
        Core::SliderPreselect p(10);
        CHECK(p.Update(1.f, 0).has_value());
        int again = 0;
        for (int i = 1; i <= 20; ++i) {
            if (p.Update(1.f, i * 50)) ++again;
        }
        CHECK(again == 5);                                      // at most 5 re-applies
    }
    {
        Core::SliderPreselect p(10);
        CHECK(p.Update(1.f, 0).has_value());
        CHECK(p.Update(1.f, 2000).has_value());
        CHECK(!p.Update(1.f, 2001).has_value());                // beyond 2000 ms
    }
    {
        Core::SliderPreselect p(1);                             // slider already shows the wanted value
        CHECK(!p.Update(1.f, 0).has_value());
        CHECK(p.Confirmed());
    }
    {
        Core::SliderPreselect p(10);
        CHECK(!p.Update(std::nanf(""), 0).has_value());
        CHECK(p.Update(1.f, 100) == std::optional<int>(10));
    }
    {
        using Protocol::ServerKind;
        CHECK(Protocol::FormatRequest({ RequestKind::kWait, 5 }) == "STv2|WAIT|5");
        CHECK(Protocol::FormatRequest({ RequestKind::kWake, 0 }) == "STv2|WAKE");
        const auto expectReq = [](std::string_view text, RequestKind kind, int value) {
            const auto r = Protocol::ParseRequest(text);
            return r && r->kind == kind && r->value == value;
        };
        CHECK(expectReq("STv2|WAIT|1", RequestKind::kWait, 1));
        CHECK(expectReq("STv2|WAIT|24", RequestKind::kWait, 24));
        CHECK(expectReq("STv2|WAIT|07", RequestKind::kWait, 7));
        CHECK(expectReq("STv2|WAKE", RequestKind::kWake, 0));
        for (auto bad : { "STv2|WAIT|0", "STv2|WAIT|25", "STv2|WAIT|", "STv2|WAIT|-1", "STv2|WAIT|5 ", "STv2|WAKE|",
                          "STv2|WAKE|1", "STv2|WAKE ", "STv2|wake", "STv2|WAKEX", " STv2|WAKE", "STv2|WAIT" })
            CHECK(!Protocol::ParseRequest(bad));
        CHECK(!Protocol::ParseRequest(std::string("STv2|WAKE\0", 10)));
        CHECK(!Protocol::ParseRequest("STv2|WAIT|" + std::string(23, '0') + "8"));
        const auto expectMsg = [](std::string_view text, ServerKind kind, int milli) {
            const auto m = Protocol::ParseServerMessage(text);
            return m && m->kind == kind && m->milliHours == milli;
        };
        CHECK(expectMsg("STv2|STOP|0", ServerKind::kStop, 0));
        CHECK(expectMsg("STv2|STOP|3000", ServerKind::kStop, 3000));
        CHECK(expectMsg("STv2|STOP|24000", ServerKind::kStop, 24000));
        for (auto bad : { "STv2|STOP|24001", "STv2|STOP|", "STv2|STOP|-1", "STv2|STOP|5 ", "STv2|STOP|1e3", "STv2|STOP" })
            CHECK(!Protocol::ParseServerMessage(bad));
        CHECK(!Protocol::ParseServerMessage("STv2|STOP|" + std::string(23, '0')));
    }
    std::puts("All tests passed");
    return 0;
}
