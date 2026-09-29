#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <vector>

extern "C" {

struct HoaReferenceSpeaker {
    double azimuth_degrees;
    double elevation_degrees;
    std::uint8_t is_lfe;
};

static_assert(sizeof(HoaReferenceSpeaker) == 24);
static_assert(offsetof(HoaReferenceSpeaker, elevation_degrees) == 8);
static_assert(offsetof(HoaReferenceSpeaker, is_lfe) == 16);

int hoa_reference_basis(
    std::uint32_t normalization,
    std::uint32_t order,
    std::int32_t degree,
    double azimuth_degrees,
    double elevation_degrees,
    double* output);

int hoa_reference_matrix(
    const std::uint32_t* orders,
    const std::int32_t* degrees,
    std::size_t input_count,
    std::uint32_t normalization,
    const HoaReferenceSpeaker* speakers,
    std::size_t output_count,
    std::uint8_t max_re,
    double* output,
    std::size_t coefficient_count);

}

namespace {

constexpr double pi = 3.141592653589793238462643383279502884;
constexpr std::uint32_t maximum_order = 3;

double factorial(std::uint32_t value) {
    double result = 1.0;
    for (std::uint32_t factor = 2; factor <= value; ++factor) {
        result *= static_cast<double>(factor);
    }
    return result;
}

double integerPower(double base, std::uint32_t exponent) {
    double result = 1.0;
    for (std::uint32_t power = 0; power < exponent; ++power) {
        result *= base;
    }
    return result;
}

bool associatedLegendre(
    std::uint32_t order,
    std::uint32_t degree,
    double x,
    double& output)
{
    if (degree > order || !std::isfinite(x) || x < -1.0 || x > 1.0) {
        return false;
    }
    double derivative = 0.0;
    const double divisor = integerPower(2.0, order);
    for (std::uint32_t term = 0; term <= order / 2; ++term) {
        const std::uint32_t power = order - 2 * term;
        if (power < degree) continue;
        const double sign = term % 2 == 0 ? 1.0 : -1.0;
        const double coefficient =
            sign * factorial(2 * order - 2 * term) /
            (divisor * factorial(term) * factorial(order - term) *
             factorial(power));
        derivative +=
            coefficient * factorial(power) /
            factorial(power - degree) *
            integerPower(x, power - degree);
    }
    output = integerPower(
                 std::sqrt(std::max(0.0, 1.0 - x * x)),
                 degree) *
        derivative;
    return std::isfinite(output);
}

bool normalizationFactor(
    std::uint32_t normalization,
    std::uint32_t order,
    std::uint32_t degree,
    double& output)
{
    const double repeated_degree = degree == 0 ? 1.0 : 2.0;
    const double sn3d = std::sqrt(
        repeated_degree * factorial(order - degree) /
        factorial(order + degree));
    double scale = 0.0;
    switch (normalization) {
        case 0:
            scale = 1.0;
            break;
        case 1:
            scale = std::sqrt(static_cast<double>(2 * order + 1));
            break;
        case 2:
            if (order == 0) {
                scale = 1.0 / std::sqrt(2.0);
            } else if (order == 1) {
                scale = 1.0;
            } else if (order == 2) {
                scale = degree == 0 ? 1.0 : 2.0 / std::sqrt(3.0);
            } else if (order == 3) {
                if (degree == 0) {
                    scale = 1.0;
                } else if (degree == 1) {
                    scale = std::sqrt(45.0 / 32.0);
                } else if (degree == 2) {
                    scale = 3.0 / std::sqrt(5.0);
                } else if (degree == 3) {
                    scale = std::sqrt(8.0 / 5.0);
                } else {
                    return false;
                }
            } else {
                return false;
            }
            break;
        default:
            return false;
    }
    output = sn3d * scale;
    return std::isfinite(output);
}

bool evaluateBasis(
    std::uint32_t normalization,
    std::uint32_t order,
    std::int32_t degree,
    double azimuth_degrees,
    double elevation_degrees,
    double& output)
{
    if (order > maximum_order ||
        degree < -static_cast<std::int32_t>(order) ||
        degree > static_cast<std::int32_t>(order) ||
        !std::isfinite(azimuth_degrees) ||
        azimuth_degrees < -180.0 || azimuth_degrees > 180.0 ||
        !std::isfinite(elevation_degrees) ||
        elevation_degrees < -90.0 || elevation_degrees > 90.0)
    {
        return false;
    }
    const std::uint32_t absolute_degree = static_cast<std::uint32_t>(
        degree < 0 ? -static_cast<std::int64_t>(degree) : degree);
    const double elevation = elevation_degrees * pi / 180.0;
    const double azimuth = azimuth_degrees * pi / 180.0;
    double legendre = 0.0;
    double factor = 0.0;
    if (!associatedLegendre(
            order,
            absolute_degree,
            std::sin(elevation),
            legendre) ||
        !normalizationFactor(
            normalization,
            order,
            absolute_degree,
            factor))
    {
        return false;
    }
    const double angular = degree < 0
        ? std::sin(static_cast<double>(absolute_degree) * azimuth)
        : degree > 0
            ? std::cos(static_cast<double>(absolute_degree) * azimuth)
            : 1.0;
    output = factor * legendre * angular;
    return std::isfinite(output);
}

bool invertMatrix(
    const std::vector<double>& input,
    std::size_t size,
    std::vector<double>& inverse)
{
    if (size == 0 ||
        size > std::numeric_limits<std::size_t>::max() / size)
    {
        return false;
    }
    const std::size_t square = size * size;
    if (input.size() != square ||
        square > std::numeric_limits<std::size_t>::max() / 2)
    {
        return false;
    }
    std::vector<double> augmented(square * 2, 0.0);
    const std::size_t width = size * 2;
    for (std::size_t row = 0; row < size; ++row) {
        for (std::size_t column = 0; column < size; ++column) {
            augmented[row * width + column] = input[row * size + column];
        }
        augmented[row * width + size + row] = 1.0;
    }

    for (std::size_t pivot_column = 0;
         pivot_column < size;
         ++pivot_column)
    {
        std::size_t pivot_row = pivot_column;
        double pivot_magnitude = std::abs(
            augmented[pivot_row * width + pivot_column]);
        for (std::size_t row = pivot_column + 1; row < size; ++row) {
            const double candidate = std::abs(
                augmented[row * width + pivot_column]);
            if (candidate > pivot_magnitude) {
                pivot_magnitude = candidate;
                pivot_row = row;
            }
        }
        if (!std::isfinite(pivot_magnitude) || pivot_magnitude <= 1.0e-14) {
            return false;
        }
        if (pivot_row != pivot_column) {
            for (std::size_t column = 0; column < width; ++column) {
                std::swap(
                    augmented[pivot_column * width + column],
                    augmented[pivot_row * width + column]);
            }
        }
        const double pivot = augmented[
            pivot_column * width + pivot_column];
        for (std::size_t column = 0; column < width; ++column) {
            augmented[pivot_column * width + column] /= pivot;
        }
        for (std::size_t row = 0; row < size; ++row) {
            if (row == pivot_column) continue;
            const double factor = augmented[row * width + pivot_column];
            for (std::size_t column = 0; column < width; ++column) {
                augmented[row * width + column] -=
                    factor * augmented[pivot_column * width + column];
            }
        }
    }

    inverse.resize(square);
    for (std::size_t row = 0; row < size; ++row) {
        for (std::size_t column = 0; column < size; ++column) {
            const double value = augmented[row * width + size + column];
            if (!std::isfinite(value)) return false;
            inverse[row * size + column] = value;
        }
    }
    return true;
}

double legendrePolynomial(std::uint32_t order, double x) {
    if (order == 0) return 1.0;
    if (order == 1) return x;
    double previous_previous = 1.0;
    double previous = x;
    for (std::uint32_t current_order = 2;
         current_order <= order;
         ++current_order)
    {
        const double current =
            (static_cast<double>(2 * current_order - 1) * x * previous -
             static_cast<double>(current_order - 1) * previous_previous) /
            static_cast<double>(current_order);
        previous_previous = previous;
        previous = current;
    }
    return previous;
}

double orderWeight(
    bool max_re,
    std::uint32_t maximum_component_order,
    std::uint32_t order)
{
    if (!max_re || maximum_component_order == 0) return 1.0;
    const double angle =
        137.9 / (static_cast<double>(maximum_component_order) + 1.51) *
        pi / 180.0;
    return legendrePolynomial(order, std::cos(angle));
}

}

extern "C" int hoa_reference_basis(
    std::uint32_t normalization,
    std::uint32_t order,
    std::int32_t degree,
    double azimuth_degrees,
    double elevation_degrees,
    double* output)
{
    if (output == nullptr) return 2;
    double value = 0.0;
    if (!evaluateBasis(
            normalization,
            order,
            degree,
            azimuth_degrees,
            elevation_degrees,
            value))
    {
        return 3;
    }
    *output = value;
    return 0;
}

extern "C" int hoa_reference_matrix(
    const std::uint32_t* orders,
    const std::int32_t* degrees,
    std::size_t input_count,
    std::uint32_t normalization,
    const HoaReferenceSpeaker* speakers,
    std::size_t output_count,
    std::uint8_t max_re,
    double* output,
    std::size_t coefficient_count)
{
    if (orders == nullptr || degrees == nullptr || input_count == 0 ||
        speakers == nullptr || output_count == 0 || output == nullptr ||
        max_re > 1)
    {
        return 2;
    }
    if (input_count >
            std::numeric_limits<std::size_t>::max() / output_count ||
        coefficient_count != input_count * output_count)
    {
        return 3;
    }
    try {
        std::uint32_t maximum_component_order = 0;
        std::vector<double> basis(coefficient_count, 0.0);
        for (std::size_t input = 0; input < input_count; ++input) {
            maximum_component_order = std::max(
                maximum_component_order,
                orders[input]);
            for (std::size_t speaker = 0; speaker < output_count; ++speaker) {
                if (speakers[speaker].is_lfe > 1) return 4;
                if (speakers[speaker].is_lfe != 0) continue;
                if (!evaluateBasis(
                        normalization,
                        orders[input],
                        degrees[input],
                        speakers[speaker].azimuth_degrees,
                        speakers[speaker].elevation_degrees,
                        basis[input * output_count + speaker]))
                {
                    return 4;
                }
            }
        }

        if (input_count >
            std::numeric_limits<std::size_t>::max() / input_count)
        {
            return 5;
        }
        std::vector<double> gram(input_count * input_count, 0.0);
        for (std::size_t row = 0; row < input_count; ++row) {
            for (std::size_t column = 0; column < input_count; ++column) {
                double value = 0.0;
                for (std::size_t speaker = 0;
                     speaker < output_count;
                     ++speaker)
                {
                    value += basis[row * output_count + speaker] *
                        basis[column * output_count + speaker];
                }
                gram[row * input_count + column] = value;
            }
        }
        std::vector<double> gram_inverse;
        if (!invertMatrix(gram, input_count, gram_inverse)) return 6;

        std::vector<double> staged(coefficient_count, 0.0);
        for (std::size_t speaker = 0; speaker < output_count; ++speaker) {
            for (std::size_t input = 0; input < input_count; ++input) {
                double value = 0.0;
                for (std::size_t basis_row = 0;
                     basis_row < input_count;
                     ++basis_row)
                {
                    value += basis[basis_row * output_count + speaker] *
                        gram_inverse[basis_row * input_count + input];
                }
                value *= orderWeight(
                    max_re != 0,
                    maximum_component_order,
                    orders[input]);
                if (!std::isfinite(value)) return 7;
                staged[speaker * input_count + input] = value;
            }
        }
        std::copy(staged.begin(), staged.end(), output);
        return 0;
    } catch (const std::bad_alloc&) {
        return 8;
    } catch (...) {
        return 9;
    }
}
