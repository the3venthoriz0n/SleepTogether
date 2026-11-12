#pragma once

// Minimal stand-in for Catch2 v2 single header. Supports only TEST_CASE,
// REQUIRE(expr) and Approx(x).margin(y), enough for the server test files verified here.
#include <cmath>
#include <cstdio>
#include <functional>
#include <limits>
#include <vector>

namespace StubCatch
{
struct TestCase
{
    const char* Name;
    void (*Func)();
};

inline std::vector<TestCase>& Registry()
{
    static std::vector<TestCase> registry;
    return registry;
}

struct Registrar
{
    Registrar(const char* aName, void (*aFunc)()) { Registry().push_back({aName, aFunc}); }
};

inline int& Failures()
{
    static int failures = 0;
    return failures;
}

inline void Check(bool aOk, const char* aExpr, const char* aFile, int aLine)
{
    if (!aOk)
    {
        std::printf("%s(%d): FAILED: REQUIRE( %s )\n", aFile, aLine, aExpr);
        ++Failures();
    }
}
} // namespace StubCatch

namespace Catch
{
namespace Detail
{
class Approx
{
public:
    explicit Approx(double aValue)
        : m_value(aValue)
    {}

    Approx& margin(double aMargin)
    {
        m_margin = aMargin;
        return *this;
    }

    Approx& epsilon(double aEpsilon)
    {
        m_epsilon = aEpsilon;
        return *this;
    }

    template <typename T> friend bool operator==(const T& aLhs, const Approx& aRhs) { return aRhs.Matches(static_cast<double>(aLhs)); }
    template <typename T> friend bool operator==(const Approx& aLhs, const T& aRhs) { return aLhs.Matches(static_cast<double>(aRhs)); }
    template <typename T> friend bool operator!=(const T& aLhs, const Approx& aRhs) { return !aRhs.Matches(static_cast<double>(aLhs)); }
    template <typename T> friend bool operator!=(const Approx& aLhs, const T& aRhs) { return !aLhs.Matches(static_cast<double>(aRhs)); }

private:
    bool Matches(double aOther) const
    {
        return std::fabs(aOther - m_value) <= m_margin || std::fabs(aOther - m_value) <= m_epsilon * (1.0 + std::fabs(m_value));
    }

    double m_value;
    double m_margin = 0.0;
    // Catch2 v2 default: float epsilon * 100
    double m_epsilon = static_cast<double>(std::numeric_limits<float>::epsilon()) * 100.0;
};
} // namespace Detail
} // namespace Catch

using Catch::Detail::Approx;

#define STUB_CONCAT2(a, b) a##b
#define STUB_CONCAT(a, b) STUB_CONCAT2(a, b)
#define TEST_CASE(name, ...) \
    static void STUB_CONCAT(StubTest_, __LINE__)(); \
    static StubCatch::Registrar STUB_CONCAT(StubReg_, __LINE__)(name, &STUB_CONCAT(StubTest_, __LINE__)); \
    static void STUB_CONCAT(StubTest_, __LINE__)()
#define REQUIRE(...) StubCatch::Check(static_cast<bool>(__VA_ARGS__), #__VA_ARGS__, __FILE__, __LINE__)

#ifdef CATCH_CONFIG_MAIN
int main()
{
    for (const auto& test : StubCatch::Registry())
    {
        const int before = StubCatch::Failures();
        test.Func();
        std::printf("[%s] %s\n", StubCatch::Failures() == before ? "PASS" : "FAIL", test.Name);
    }
    std::printf("%d failure(s) in %zu test case(s)\n", StubCatch::Failures(), StubCatch::Registry().size());
    return StubCatch::Failures() == 0 ? 0 : 1;
}
#endif
