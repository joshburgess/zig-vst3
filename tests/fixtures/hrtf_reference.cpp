#include <netcdf.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <new>
#include <vector>

extern "C" {

struct HrtfReferenceQuery {
    double azimuth_degrees;
    double elevation_degrees;
};

static_assert(sizeof(HrtfReferenceQuery) == 16);
static_assert(offsetof(HrtfReferenceQuery, elevation_degrees) == 8);

int hrtf_reference_render(
    const char* path,
    const HrtfReferenceQuery* queries,
    std::size_t query_count,
    std::size_t maximum_frames,
    float* output,
    std::size_t output_count,
    std::size_t* measurement_count_output,
    std::size_t* frame_count_output);

}

namespace {

constexpr std::size_t channel_count = 2;
constexpr std::size_t method_count = 2;
constexpr double pi = 3.141592653589793238462643383279502884;
constexpr double exact_direction_tolerance_squared = 1.0e-24;

struct Dataset {
    std::size_t measurement_count;
    std::size_t frame_count;
    std::vector<double> positions;
    std::vector<double> responses;
};

struct Neighbors {
    std::size_t count;
    std::array<std::size_t, 3> indices;
    std::array<double, 3> distances;
};

bool checkedMultiply(
    std::size_t first,
    std::size_t second,
    std::size_t& result)
{
    if (first != 0 &&
        second > std::numeric_limits<std::size_t>::max() / first)
    {
        return false;
    }
    result = first * second;
    return true;
}

bool variableShape(
    int file,
    const char* name,
    int expected_dimensions,
    std::vector<std::size_t>& shape,
    int& variable)
{
    if (nc_inq_varid(file, name, &variable) != NC_NOERR) return false;
    int dimension_count = 0;
    if (nc_inq_varndims(file, variable, &dimension_count) != NC_NOERR ||
        dimension_count != expected_dimensions)
    {
        return false;
    }
    std::vector<int> dimensions(static_cast<std::size_t>(dimension_count));
    if (nc_inq_vardimid(file, variable, dimensions.data()) != NC_NOERR) {
        return false;
    }
    shape.resize(static_cast<std::size_t>(dimension_count));
    for (int index = 0; index < dimension_count; ++index) {
        if (nc_inq_dimlen(
                file,
                dimensions[static_cast<std::size_t>(index)],
                &shape[static_cast<std::size_t>(index)]) != NC_NOERR)
        {
            return false;
        }
    }
    return true;
}

bool readDataset(const char* path, Dataset& dataset) {
    int file = 0;
    if (nc_open(path, NC_NOWRITE, &file) != NC_NOERR) return false;

    bool valid = false;
    do {
        int response_variable = 0;
        std::vector<std::size_t> response_shape;
        if (!variableShape(
                file,
                "Data.IR",
                3,
                response_shape,
                response_variable) ||
            response_shape[0] == 0 ||
            response_shape[1] != channel_count ||
            response_shape[2] == 0)
        {
            break;
        }

        int position_variable = 0;
        std::vector<std::size_t> position_shape;
        if (!variableShape(
                file,
                "SourcePosition",
                2,
                position_shape,
                position_variable) ||
            position_shape[0] != response_shape[0] ||
            position_shape[1] != 3)
        {
            break;
        }

        int delay_variable = 0;
        if (nc_inq_varid(file, "Data.Delay", &delay_variable) != NC_NOERR) {
            break;
        }
        int delay_dimensions = 0;
        if (nc_inq_varndims(file, delay_variable, &delay_dimensions) !=
            NC_NOERR)
        {
            break;
        }
        std::vector<int> delay_dimension_ids(
            static_cast<std::size_t>(delay_dimensions));
        if (nc_inq_vardimid(
                file,
                delay_variable,
                delay_dimension_ids.data()) != NC_NOERR)
        {
            break;
        }
        std::size_t delay_count = 1;
        for (int index = 0; index < delay_dimensions; ++index) {
            std::size_t length = 0;
            if (nc_inq_dimlen(
                    file,
                    delay_dimension_ids[static_cast<std::size_t>(index)],
                    &length) != NC_NOERR ||
                length == 0 ||
                length > std::numeric_limits<std::size_t>::max() /
                    delay_count)
            {
                delay_count = 0;
                break;
            }
            delay_count *= length;
        }
        if (delay_count == 0) break;
        std::vector<double> delays(delay_count);
        if (nc_get_var_double(file, delay_variable, delays.data()) !=
            NC_NOERR ||
            std::any_of(delays.begin(), delays.end(), [](double delay) {
                return !std::isfinite(delay) || delay != 0.0;
            }))
        {
            break;
        }

        const std::size_t measurement_count = response_shape[0];
        const std::size_t frame_count = response_shape[2];
        std::size_t position_count = 0;
        std::size_t response_stride = 0;
        std::size_t response_count = 0;
        if (!checkedMultiply(measurement_count, 3, position_count) ||
            !checkedMultiply(channel_count, frame_count, response_stride) ||
            !checkedMultiply(
                measurement_count,
                response_stride,
                response_count))
        {
            break;
        }
        dataset.measurement_count = measurement_count;
        dataset.frame_count = frame_count;
        dataset.positions.resize(position_count);
        dataset.responses.resize(response_count);
        if (nc_get_var_double(
                file,
                position_variable,
                dataset.positions.data()) != NC_NOERR ||
            nc_get_var_double(
                file,
                response_variable,
                dataset.responses.data()) != NC_NOERR)
        {
            break;
        }
        valid = std::all_of(
            dataset.positions.begin(),
            dataset.positions.end(),
            [](double value) { return std::isfinite(value); }) &&
            std::all_of(
                dataset.responses.begin(),
                dataset.responses.end(),
                [](double value) { return std::isfinite(value); });
    } while (false);

    if (nc_close(file) != NC_NOERR) return false;
    return valid;
}

std::array<double, 3> directionVector(
    double azimuth_degrees,
    double elevation_degrees)
{
    const double azimuth = azimuth_degrees * pi / 180.0;
    const double elevation = elevation_degrees * pi / 180.0;
    const double horizontal = std::cos(elevation);
    return {
        horizontal * std::cos(azimuth),
        horizontal * std::sin(azimuth),
        std::sin(elevation),
    };
}

double chordDistanceSquared(
    const std::array<double, 3>& first,
    const std::array<double, 3>& second)
{
    const double x = first[0] - second[0];
    const double y = first[1] - second[1];
    const double z = first[2] - second[2];
    return x * x + y * y + z * z;
}

Neighbors selectNeighbors(
    const Dataset& dataset,
    const HrtfReferenceQuery& query)
{
    const auto target = directionVector(
        query.azimuth_degrees,
        query.elevation_degrees);
    Neighbors result{
        std::min<std::size_t>(dataset.measurement_count, 3),
        {0, 0, 0},
        {
            std::numeric_limits<double>::infinity(),
            std::numeric_limits<double>::infinity(),
            std::numeric_limits<double>::infinity(),
        },
    };
    for (std::size_t candidate = 0;
         candidate < dataset.measurement_count;
         ++candidate)
    {
        const std::size_t position = candidate * 3;
        const auto candidate_vector = directionVector(
            dataset.positions[position],
            dataset.positions[position + 1]);
        const double distance = chordDistanceSquared(
            target,
            candidate_vector);
        std::size_t insertion = 0;
        while (insertion < result.count &&
               distance >= result.distances[insertion])
        {
            ++insertion;
        }
        if (insertion == result.count) continue;
        for (std::size_t shift = result.count - 1;
             shift > insertion;
             --shift)
        {
            result.indices[shift] = result.indices[shift - 1];
            result.distances[shift] = result.distances[shift - 1];
        }
        result.indices[insertion] = candidate;
        result.distances[insertion] = distance;
    }
    return result;
}

std::array<double, 3> interpolationWeights(const Neighbors& selected) {
    std::array<double, 3> weights{0.0, 0.0, 0.0};
    if (selected.distances[0] <= exact_direction_tolerance_squared) {
        weights[0] = 1.0;
        return weights;
    }
    double total = 0.0;
    for (std::size_t index = 0; index < selected.count; ++index) {
        weights[index] = 1.0 / selected.distances[index];
        total += weights[index];
    }
    for (std::size_t index = 0; index < selected.count; ++index) {
        weights[index] /= total;
    }
    return weights;
}

float responseSample(
    const Dataset& dataset,
    std::size_t measurement,
    std::size_t channel,
    std::size_t frame)
{
    return static_cast<float>(dataset.responses[
        (measurement * channel_count + channel) * dataset.frame_count +
        frame]);
}

void renderInverseDistance(
    const Dataset& dataset,
    const Neighbors& selected,
    const std::array<double, 3>& weights,
    float* output)
{
    for (std::size_t frame = 0; frame < dataset.frame_count; ++frame) {
        for (std::size_t channel = 0; channel < channel_count; ++channel) {
            double value = 0.0;
            for (std::size_t neighbor = 0;
                 neighbor < selected.count;
                 ++neighbor)
            {
                value += weights[neighbor] * responseSample(
                    dataset,
                    selected.indices[neighbor],
                    channel,
                    frame);
            }
            output[frame * channel_count + channel] =
                static_cast<float>(value);
        }
    }
}

void renderSpectral(
    const Dataset& dataset,
    const Neighbors& selected,
    const std::array<double, 3>& weights,
    float* output)
{
    const std::size_t count = dataset.frame_count;
    std::vector<double> spectrum_real(count);
    std::vector<double> spectrum_imaginary(count);
    for (std::size_t channel = 0; channel < channel_count; ++channel) {
        for (std::size_t bin = 0; bin < count; ++bin) {
            double log_magnitude = 0.0;
            double magnitude_sum = 0.0;
            double phase_x = 0.0;
            double phase_y = 0.0;
            double linear_real = 0.0;
            double linear_imaginary = 0.0;
            for (std::size_t neighbor = 0;
                 neighbor < selected.count;
                 ++neighbor)
            {
                double real = 0.0;
                double imaginary = 0.0;
                for (std::size_t sample = 0; sample < count; ++sample) {
                    const double angle =
                        -2.0 * pi * static_cast<double>(bin) *
                        static_cast<double>(sample) /
                        static_cast<double>(count);
                    const double value = responseSample(
                        dataset,
                        selected.indices[neighbor],
                        channel,
                        sample);
                    real += value * std::cos(angle);
                    imaginary += value * std::sin(angle);
                }
                const double magnitude = std::sqrt(
                    real * real + imaginary * imaginary);
                const double weight = weights[neighbor];
                magnitude_sum += weight * magnitude;
                log_magnitude += weight * std::log(
                    std::max(magnitude, 1.0e-30));
                if (magnitude > 1.0e-30) {
                    phase_x += weight * real / magnitude;
                    phase_y += weight * imaginary / magnitude;
                }
                linear_real += weight * real;
                linear_imaginary += weight * imaginary;
            }
            if (magnitude_sum <= 1.0e-30) {
                spectrum_real[bin] = 0.0;
                spectrum_imaginary[bin] = 0.0;
                continue;
            }
            const double phase_length = std::sqrt(
                phase_x * phase_x + phase_y * phase_y);
            if (phase_length <= 1.0e-15) {
                spectrum_real[bin] = linear_real;
                spectrum_imaginary[bin] = linear_imaginary;
            } else {
                const double magnitude = std::exp(log_magnitude);
                spectrum_real[bin] = magnitude * phase_x / phase_length;
                spectrum_imaginary[bin] =
                    magnitude * phase_y / phase_length;
            }
        }

        for (std::size_t sample = 0; sample < count; ++sample) {
            double value = 0.0;
            for (std::size_t bin = 0; bin < count; ++bin) {
                const double angle =
                    2.0 * pi * static_cast<double>(bin) *
                    static_cast<double>(sample) /
                    static_cast<double>(count);
                value +=
                    spectrum_real[bin] * std::cos(angle) -
                    spectrum_imaginary[bin] * std::sin(angle);
            }
            output[sample * channel_count + channel] =
                static_cast<float>(value / static_cast<double>(count));
        }
    }
}

}

extern "C" int hrtf_reference_render(
    const char* path,
    const HrtfReferenceQuery* queries,
    std::size_t query_count,
    std::size_t maximum_frames,
    float* output,
    std::size_t output_count,
    std::size_t* measurement_count_output,
    std::size_t* frame_count_output)
{
    if (path == nullptr || queries == nullptr || query_count == 0 ||
        output == nullptr || measurement_count_output == nullptr ||
        frame_count_output == nullptr)
    {
        return 2;
    }
    try {
        Dataset dataset{};
        if (!readDataset(path, dataset)) return 3;
        std::size_t response_size = 0;
        std::size_t methods_size = 0;
        std::size_t required = 0;
        if (dataset.frame_count > maximum_frames ||
            !checkedMultiply(
                dataset.frame_count,
                channel_count,
                response_size) ||
            !checkedMultiply(response_size, method_count, methods_size) ||
            !checkedMultiply(methods_size, query_count, required))
        {
            return 4;
        }
        if (output_count != required) return 5;

        for (std::size_t query = 0; query < query_count; ++query) {
            if (!std::isfinite(queries[query].azimuth_degrees) ||
                !std::isfinite(queries[query].elevation_degrees) ||
                queries[query].azimuth_degrees < -180.0 ||
                queries[query].azimuth_degrees > 180.0 ||
                queries[query].elevation_degrees < -90.0 ||
                queries[query].elevation_degrees > 90.0)
            {
                return 6;
            }
            const Neighbors selected = selectNeighbors(dataset, queries[query]);
            const auto weights = interpolationWeights(selected);
            float* inverse = output +
                (query * method_count) *
                    dataset.frame_count * channel_count;
            float* spectral = inverse + dataset.frame_count * channel_count;
            renderInverseDistance(dataset, selected, weights, inverse);
            renderSpectral(dataset, selected, weights, spectral);
        }
        *measurement_count_output = dataset.measurement_count;
        *frame_count_output = dataset.frame_count;
        return 0;
    } catch (const std::bad_alloc&) {
        return 7;
    } catch (...) {
        return 8;
    }
}
