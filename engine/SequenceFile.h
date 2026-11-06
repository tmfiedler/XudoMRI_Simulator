#ifndef NUTATE_SEQUENCE_FILE_H
#define NUTATE_SEQUENCE_FILE_H

#include <cmath>
#include <complex>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

// The versioned float32 layout described in docs/FILE_FORMATS.md, shared by the
// signal and noise readers. Noise validates every section but retains only
// timing/events. No expanded scientific storage is allocated before validation.
namespace SequenceFile
{
    struct Data
    {
        unsigned int count = 0;
        unsigned short tx = 0, rx = 0;
        std::vector<float> time, sampleOffset, dwell, gx, gy, gz;
        std::vector<int> acq;
        std::vector<std::vector<std::complex<float>>> rf;
        std::vector<std::vector<float>> frequency;
    };

    namespace Detail
    {
        inline void require(bool valid, const char* message)
        {
            if (!valid) throw std::runtime_error(message);
        }
        inline std::uint32_t magnitudeBits(float value)
        {
            // Floating-point comparisons may flush subnormals to zero. Format
            // zero constraints must inspect the encoded value, allowing -0.
            std::uint32_t bits;
            std::memcpy(&bits, &value, sizeof(bits));
            return bits & 0x7fffffffu;
        }
        inline bool nonnegative(float value)
        {
            std::uint32_t bits;
            std::memcpy(&bits, &value, sizeof(bits));
            return (bits & 0x80000000u) == 0 || (bits & 0x7fffffffu) == 0;
        }
        inline unsigned int count(float value, unsigned int maximum,
            bool allowZero, const char* message)
        {
            const double v = value;
            require(std::isfinite(v) && std::floor(v) == v &&
                v >= (allowZero ? 0.0 : 1.0) && v <= maximum, message);
            return static_cast<unsigned int>(value);
        }
        struct Loop { std::size_t offset; unsigned int lines, repeats; };
        using Section = std::vector<Loop>;

        class Cursor
        {
            const Section& section;
            const std::vector<float>& raw;
            std::size_t block = 0;
            unsigned int row = 0, repetition = 0;
        public:
            Cursor(const Section& s, const std::vector<float>& r) : section(s), raw(r) {}
            float next()
            {
                const Loop& loop = section[block];
                const float value = raw[loop.offset + row];
                if (++row == loop.lines)
                {
                    row = 0;
                    if (++repetition == loop.repeats) { repetition = 0; ++block; }
                }
                return value;
            }
        };

        template<class Emit>
        inline void expand(const Section& section, const std::vector<float>& raw,
            unsigned int width, Emit emit)
        {
            for (const Loop& loop : section)
                for (unsigned int repeat = 0; repeat < loop.repeats; ++repeat)
                    for (unsigned int row = 0; row < loop.lines; ++row)
                        emit(&raw[loop.offset + static_cast<std::size_t>(row) * width]);
        }
    }

    inline bool read(const std::string& filename, bool retainFields,
        Data& data, std::string& error)
    {
        using namespace Detail;
        try
        {
            std::ifstream file(filename.c_str(), std::ios::binary | std::ios::ate);
            require(file.is_open(), "could not open sequence file");
            const std::streamoff bytes = file.tellg();
            require(bytes >= 20 && bytes % sizeof(float) == 0,
                "truncated header or partial float32 payload");
            require(static_cast<std::uint64_t>(bytes) <=
                static_cast<std::uint64_t>(std::numeric_limits<std::streamsize>::max()),
                "file exceeds stream read bounds");
            const std::uint64_t words = static_cast<std::uint64_t>(bytes) / sizeof(float);
            require(words <= std::vector<float>().max_size(), "encoded file exceeds allocation bounds");
            std::vector<float> raw(static_cast<std::size_t>(words));
            file.seekg(0);
            require(static_cast<bool>(file.read(reinterpret_cast<char*>(raw.data()),
                static_cast<std::streamsize>(bytes))), "truncated sequence read");

            require(raw[0] == -1.0f && raw[1] == 1.0f,
                "unsupported sequence format; V1 required (regenerate with current Setup)");
            const std::size_t header = 5, rfSection = 4;
            data.count = count(raw[2], std::numeric_limits<unsigned int>::max(), false,
                "total steps must be a positive finite integral unsigned count");
            data.tx = static_cast<unsigned short>(count(raw[3],
                std::numeric_limits<unsigned short>::max(), true,
                "transmit channels must be a finite integral count in range"));
            data.rx = static_cast<unsigned short>(count(raw[4],
                std::numeric_limits<unsigned short>::max(), false,
                "receive channels must be a positive finite integral count in range"));
            // Each nonempty scalar section needs two loop counts plus a value;
            // each Tx section needs two counts plus one RF/frequency triple.
            require(raw.size() - header >= 21 + static_cast<std::size_t>(data.tx) * 5,
                "truncated sequence sections");
            std::vector<Section> sections(static_cast<std::size_t>(data.tx) + rfSection + 3);
            std::size_t position = header;
            for (std::size_t channel = 0; channel < sections.size(); ++channel)
            {
                const unsigned int width = channel >= rfSection && channel < rfSection + data.tx ? 3 : 1;
                unsigned int remaining = data.count;
                while (remaining)
                {
                    require(raw.size() - position >= 2, "truncated loop header");
                    const unsigned int lines = count(raw[position++],
                        std::numeric_limits<int>::max(), false,
                        "loop length must be a positive finite integral signed count");
                    const unsigned int repeats = count(raw[position++],
                        std::numeric_limits<int>::max(), false,
                        "loop repeats must be a positive finite integral signed count");
                    require(lines <= remaining / repeats, "loop expansion exceeds declared total steps");
                    require(lines <= (raw.size() - position) / width, "truncated loop payload");
                    const std::size_t elements = static_cast<std::size_t>(lines) * width;
                    for (std::size_t j = 0; j < elements; ++j)
                    {
                        const float value = raw[position + j];
                        require(std::isfinite(value), "nonfinite sequence value");
                        if (channel == 0)
                        {
                            require(value >= 0.0f, "negative timestep duration");
                        }
                        else if (channel == 1)
                        {
                            require(value == -2.0f || value == -1.0f || value == 0.0f || value == 1.0f,
                                "event flag must be exactly -2, -1, 0 or 1");
                        }
                    }
                    sections[channel].push_back({position, lines, repeats});
                    position += elements;
                    // Division check above proves this product and subtraction fit.
                    remaining -= lines * repeats;
                }
            }
            require(position == raw.size(), "unexpected data after sequence sections");
            {
                Cursor time(sections[0], raw), event(sections[1], raw);
                Cursor offset(sections[2], raw), dwell(sections[3], raw);
                for (unsigned int i = 0; i < data.count; ++i)
                {
                    const float durationMs = time.next();
                    const float duration = durationMs / 1000.0f;
                    const float flag = event.next();
                    require(flag != 1.0f || duration > 0.0f,
                        "ADC duration must remain positive in seconds");
                    const float beforeMs = offset.next();
                    const float windowMs = dwell.next();
                    require(flag == 1.0f ? nonnegative(beforeMs) && beforeMs <= durationMs && windowMs / 1000.0f > 0.0f :
                        magnitudeBits(beforeMs) == 0 && magnitudeBits(windowMs) == 0,
                        "invalid ADC sample offset or original dwell");
                }
            }

            const std::size_t bytesPerStep = 3 * sizeof(float) + sizeof(int) +
                (retainFields ? 3 * sizeof(float) +
                    static_cast<std::size_t>(data.tx) * (sizeof(std::complex<float>) + sizeof(float)) : 0);
            require(data.count <= std::numeric_limits<std::size_t>::max() / bytesPerStep &&
                data.count <= std::vector<float>().max_size() &&
                data.count <= std::vector<int>().max_size() &&
                (!retainFields || data.count <= std::vector<std::complex<float>>().max_size()),
                "expanded sequence exceeds allocation bounds");

            data.time.reserve(data.count);
            data.acq.reserve(data.count);
            expand(sections[0], raw, 1, [&](const float* v) { data.time.push_back(v[0] / 1000.0f); });
            expand(sections[1], raw, 1, [&](const float* v) { data.acq.push_back(static_cast<int>(v[0])); });
            data.sampleOffset.reserve(data.count);
            data.dwell.reserve(data.count);
            expand(sections[2], raw, 1, [&](const float* v) { data.sampleOffset.push_back(v[0] / 1000.0f); });
            expand(sections[3], raw, 1, [&](const float* v) { data.dwell.push_back(v[0] / 1000.0f); });
            if (retainFields)
            {
                data.rf.resize(data.tx);
                data.frequency.resize(data.tx);
                for (unsigned int coil = 0; coil < data.tx; ++coil)
                {
                    data.rf[coil].reserve(data.count);
                    data.frequency[coil].reserve(data.count);
                    expand(sections[rfSection + coil], raw, 3, [&](const float* v)
                    {
                        data.rf[coil].emplace_back(v[0], v[1]);
                        data.frequency[coil].push_back(v[2]);
                    });
                }
                std::vector<float>* gradients[] = {&data.gx, &data.gy, &data.gz};
                for (unsigned int axis = 0; axis < 3; ++axis)
                {
                    gradients[axis]->reserve(data.count);
                    expand(sections[rfSection + data.tx + axis], raw, 1, [&](const float* v)
                    { gradients[axis]->push_back(v[0] / 1000.0f); });
                }
            }
            return true;
        }
        catch (const std::bad_alloc&) { error = "sequence allocation failed"; }
        catch (const std::length_error&) { error = "sequence allocation exceeds container bounds"; }
        catch (const std::runtime_error& failure) { error = failure.what(); }
        return false;
    }
}
#endif
