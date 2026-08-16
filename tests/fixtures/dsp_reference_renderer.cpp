#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <string>
#include <type_traits>
#include <vector>

static void writeU16(std::ofstream& output, std::uint16_t value) {
    output.put(static_cast<char>(value));
    output.put(static_cast<char>(value >> 8));
}

static void writeU32(std::ofstream& output, std::uint32_t value) {
    output.put(static_cast<char>(value));
    output.put(static_cast<char>(value >> 8));
    output.put(static_cast<char>(value >> 16));
    output.put(static_cast<char>(value >> 24));
}

static void writeU64(std::ofstream& output, std::uint64_t value) {
    writeU32(output, static_cast<std::uint32_t>(value));
    writeU32(output, static_cast<std::uint32_t>(value >> 32));
}

template <typename Sample>
static bool writeWav(const std::string& path, const std::vector<Sample>& samples) {
    const std::uint16_t bits = sizeof(Sample) * 8;
    const std::uint32_t data_bytes = static_cast<std::uint32_t>(samples.size() * sizeof(Sample));
    std::ofstream output(path, std::ios::binary);
    if (!output) return false;
    output.write("RIFF", 4);
    writeU32(output, 36 + data_bytes);
    output.write("WAVEfmt ", 8);
    writeU32(output, 16);
    writeU16(output, 3);
    writeU16(output, 1);
    writeU32(output, 48'000);
    writeU32(output, 48'000 * sizeof(Sample));
    writeU16(output, sizeof(Sample));
    writeU16(output, bits);
    output.write("data", 4);
    writeU32(output, data_bytes);
    for (Sample sample : samples) {
        if constexpr (std::is_same_v<Sample, float>) {
            std::uint32_t bits_value;
            std::memcpy(&bits_value, &sample, sizeof(bits_value));
            writeU32(output, bits_value);
        } else {
            std::uint64_t bits_value;
            std::memcpy(&bits_value, &sample, sizeof(bits_value));
            writeU64(output, bits_value);
        }
    }
    return output.good();
}

template <typename Sample>
static std::vector<Sample> render(const std::vector<float>& input) {
    std::vector<Sample> output(input.size());
    Sample state = 0;
    for (std::size_t index = 0; index < input.size(); ++index) {
        const Sample sample = static_cast<Sample>(input[index]);
        state = static_cast<Sample>(0.85) * state + static_cast<Sample>(0.15) * sample;
        output[index] = static_cast<Sample>(0.7) * sample + static_cast<Sample>(0.3) * state;
    }
    return output;
}

int main(int argc, char** argv) {
    if (argc != 4) return 2;
    constexpr std::size_t frame_count = 8192;
    std::vector<float> input(frame_count);
    for (std::size_t index = 0; index < input.size(); ++index) {
        const double phase = static_cast<double>(index);
        const double sweep = static_cast<double>(index % 97) / 96.0 * 2.0 - 1.0;
        input[index] = static_cast<float>(0.6 * std::sin(phase * 0.031) + 0.2 * sweep);
    }
    if (!writeWav(argv[1], input)) return 3;
    if (!writeWav(argv[2], render<float>(input))) return 4;
    if (!writeWav(argv[3], render<double>(input))) return 5;
    return 0;
}
