#include <AmbisonicDecoder.h>
#include <BFormat.h>
#include <mysofa.h>

#include <cmath>
#include <cstddef>
#include <vector>

extern "C" int established_hrtf_filter(
    const char* path,
    float sample_rate,
    float x,
    float y,
    float z,
    int interpolate,
    float* interleaved_output,
    std::size_t output_count,
    std::size_t* frame_count_output,
    float* left_delay_output,
    float* right_delay_output) {
    if (path == nullptr || interleaved_output == nullptr ||
        frame_count_output == nullptr || left_delay_output == nullptr ||
        right_delay_output == nullptr || !std::isfinite(sample_rate) ||
        sample_rate <= 0.0f || !std::isfinite(x) || !std::isfinite(y) ||
        !std::isfinite(z)) {
        return 1;
    }

    int frame_count = 0;
    int error = 0;
    MYSOFA_EASY* easy = mysofa_open_no_norm(
        path,
        sample_rate,
        &frame_count,
        &error);
    if (easy == nullptr || error != MYSOFA_OK || frame_count <= 0) {
        if (easy != nullptr) mysofa_close(easy);
        return 2;
    }
    const std::size_t required = static_cast<std::size_t>(frame_count) * 2;
    if (output_count != required) {
        mysofa_close(easy);
        return 3;
    }

    std::vector<float> left(static_cast<std::size_t>(frame_count));
    std::vector<float> right(static_cast<std::size_t>(frame_count));
    float left_delay = 0.0f;
    float right_delay = 0.0f;
    if (interpolate != 0) {
        mysofa_getfilter_float(
            easy, x, y, z, left.data(), right.data(),
            &left_delay, &right_delay);
    } else {
        mysofa_getfilter_float_nointerp(
            easy, x, y, z, left.data(), right.data(),
            &left_delay, &right_delay);
    }
    mysofa_close(easy);

    for (std::size_t frame = 0; frame < static_cast<std::size_t>(frame_count);
         ++frame) {
        if (!std::isfinite(left[frame]) || !std::isfinite(right[frame]))
            return 4;
    }
    if (!std::isfinite(left_delay) || !std::isfinite(right_delay)) return 4;
    for (std::size_t frame = 0; frame < static_cast<std::size_t>(frame_count);
         ++frame) {
        interleaved_output[frame * 2] = left[frame];
        interleaved_output[frame * 2 + 1] = right[frame];
    }
    *frame_count_output = static_cast<std::size_t>(frame_count);
    *left_delay_output = left_delay;
    *right_delay_output = right_delay;
    return 0;
}

extern "C" int established_hoa_render(
    unsigned order,
    unsigned layout,
    unsigned sample_rate,
    const float* channel_major_inputs,
    std::size_t input_count,
    std::size_t sample_count,
    float* output_major_coefficients,
    std::size_t coefficient_count,
    float* channel_major_outputs,
    std::size_t output_count) {
    if (order == 0 || order > 3 || sample_rate < 8000 ||
        channel_major_inputs == nullptr || output_major_coefficients == nullptr ||
        channel_major_outputs == nullptr || sample_count == 0) {
        return 1;
    }
    const std::size_t required_inputs =
        static_cast<std::size_t>((order + 1) * (order + 1));
    if (input_count != required_inputs) return 2;

    spaudio::Amblib_SpeakerSetUps speaker_layout;
    switch (layout) {
        case 0:
            speaker_layout = spaudio::Amblib_SpeakerSetUps::kAmblib_Stereo;
            break;
        case 1:
            speaker_layout = spaudio::Amblib_SpeakerSetUps::kAmblib_51;
            break;
        case 2:
            speaker_layout = spaudio::Amblib_SpeakerSetUps::kAmblib_71;
            break;
        default:
            return 3;
    }

    spaudio::AmbisonicDecoder decoder;
    if (!decoder.Configure(
            order, true, static_cast<unsigned>(sample_count), sample_rate,
            speaker_layout) || !decoder.GetPresetLoaded()) {
        return 4;
    }
    const std::size_t speaker_count = decoder.GetSpeakerCount();
    if (coefficient_count != speaker_count * input_count ||
        output_count != speaker_count * sample_count) {
        return 5;
    }

    spaudio::BFormat b_format;
    if (!b_format.Configure(order, true, static_cast<unsigned>(sample_count)))
        return 6;
    for (std::size_t channel = 0; channel < input_count; ++channel) {
        b_format.InsertStream(
            const_cast<float*>(channel_major_inputs + channel * sample_count),
            static_cast<unsigned>(channel),
            static_cast<unsigned>(sample_count));
    }

    std::vector<float*> outputs(speaker_count);
    for (std::size_t speaker = 0; speaker < speaker_count; ++speaker)
        outputs[speaker] = channel_major_outputs + speaker * sample_count;
    decoder.Process(&b_format, static_cast<unsigned>(sample_count), outputs.data());

    for (std::size_t speaker = 0; speaker < speaker_count; ++speaker) {
        for (std::size_t channel = 0; channel < input_count; ++channel) {
            const float coefficient = decoder.GetCoefficient(
                static_cast<unsigned>(speaker),
                static_cast<unsigned>(channel));
            if (!std::isfinite(coefficient)) return 7;
            output_major_coefficients[speaker * input_count + channel] =
                coefficient;
        }
    }
    for (std::size_t index = 0; index < output_count; ++index) {
        if (!std::isfinite(channel_major_outputs[index])) return 7;
    }
    return 0;
}
