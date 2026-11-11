#include "Core.h"

#include <cmath>
#include <cstdio>
#include <optional>

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
    std::puts("All tests passed");
    return 0;
}
