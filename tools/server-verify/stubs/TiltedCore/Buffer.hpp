#pragma once

// Stand-in for TiltedCore/Buffer.hpp: only what encoding/Structs/TimeModel.h needs to compile
namespace TiltedPhoques
{
struct Buffer
{
    struct Writer;
    struct Reader;
};
} // namespace TiltedPhoques
