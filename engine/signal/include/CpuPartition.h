#ifndef SIGNAL_CPU_PARTITION_H
#define SIGNAL_CPU_PARTITION_H

#include <cassert>
#include <cstddef>
#include <cstdint>

namespace SignalCpuPartition
{
    struct Range { std::size_t begin, end; };

    inline Range range(std::size_t count, std::uint32_t worker, std::uint32_t workers)
    {
        assert(workers > 0 && worker < workers);
        const std::size_t quotient = count / workers;
        const std::uint64_t remainder = count % workers;
        // floor(count * index / workers), without multiplying count by index.
        // quotient * index <= count; the uint32 team bounds remainder * index
        // below UINT64_MAX, and the final sum is at most count.
        const auto boundary = [quotient, remainder, workers](std::uint32_t index)
        {
            return quotient * index + static_cast<std::size_t>(remainder * index / workers);
        };
        return {boundary(worker), boundary(worker + 1)};
    }
}

#endif
