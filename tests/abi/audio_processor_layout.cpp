#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include <cstring>
#include "public.sdk/source/vst/vstaudioprocessoralgo.h"

#include <cstddef>
#include <cstdio>

#define PRINT_TYPE(Type) std::printf (#Type " size %zu align %zu\n", sizeof (Steinberg::Vst::Type), alignof (Steinberg::Vst::Type))
#define PRINT_OFFSET(Type, Field) std::printf (#Type "." #Field " offset %zu\n", offsetof (Steinberg::Vst::Type, Field))

template <typename T>
static void print_iid (const char* name, const T& tuid)
{
	std::printf ("%s iid", name);
	for (int index = 0; index < 16; ++index)
		std::printf (" %02X", static_cast<unsigned char> (tuid[index]));
	std::printf ("\n");
}

int main ()
{
	std::printf ("ComponentFlags.kDistributable %u\n", Steinberg::Vst::kDistributable);
	std::printf ("ComponentFlags.kSimpleModeSupported %u\n", Steinberg::Vst::kSimpleModeSupported);
	std::printf ("SymbolicSampleSizes.kSample32 %d\n", Steinberg::Vst::kSample32);
	std::printf ("SymbolicSampleSizes.kSample64 %d\n", Steinberg::Vst::kSample64);
	std::printf ("ProcessModes.kRealtime %d\n", Steinberg::Vst::kRealtime);
	std::printf ("ProcessModes.kPrefetch %d\n", Steinberg::Vst::kPrefetch);
	std::printf ("ProcessModes.kOffline %d\n", Steinberg::Vst::kOffline);
	std::printf ("kNoTail %u\n", Steinberg::Vst::kNoTail);
	std::printf ("kInfiniteTail %u\n", Steinberg::Vst::kInfiniteTail);
	std::printf ("IProcessContextRequirements.kNeedSystemTime %u\n", Steinberg::Vst::IProcessContextRequirements::kNeedSystemTime);
	std::printf ("IProcessContextRequirements.kNeedContinousTimeSamples %u\n", Steinberg::Vst::IProcessContextRequirements::kNeedContinousTimeSamples);
	std::printf ("IProcessContextRequirements.kNeedProjectTimeMusic %u\n", Steinberg::Vst::IProcessContextRequirements::kNeedProjectTimeMusic);
	std::printf ("IProcessContextRequirements.kNeedBarPositionMusic %u\n", Steinberg::Vst::IProcessContextRequirements::kNeedBarPositionMusic);
	std::printf ("IProcessContextRequirements.kNeedCycleMusic %u\n", Steinberg::Vst::IProcessContextRequirements::kNeedCycleMusic);
	std::printf ("IProcessContextRequirements.kNeedSamplesToNextClock %u\n", Steinberg::Vst::IProcessContextRequirements::kNeedSamplesToNextClock);
	std::printf ("IProcessContextRequirements.kNeedTempo %u\n", Steinberg::Vst::IProcessContextRequirements::kNeedTempo);
	std::printf ("IProcessContextRequirements.kNeedTimeSignature %u\n", Steinberg::Vst::IProcessContextRequirements::kNeedTimeSignature);
	std::printf ("IProcessContextRequirements.kNeedChord %u\n", Steinberg::Vst::IProcessContextRequirements::kNeedChord);
	std::printf ("IProcessContextRequirements.kNeedFrameRate %u\n", Steinberg::Vst::IProcessContextRequirements::kNeedFrameRate);
	std::printf ("IProcessContextRequirements.kNeedTransportState %u\n", Steinberg::Vst::IProcessContextRequirements::kNeedTransportState);

	PRINT_TYPE (ProcessSetup);
	PRINT_OFFSET (ProcessSetup, processMode);
	PRINT_OFFSET (ProcessSetup, symbolicSampleSize);
	PRINT_OFFSET (ProcessSetup, maxSamplesPerBlock);
	PRINT_OFFSET (ProcessSetup, sampleRate);

	PRINT_TYPE (AudioBusBuffers);
	PRINT_OFFSET (AudioBusBuffers, numChannels);
	PRINT_OFFSET (AudioBusBuffers, silenceFlags);
	PRINT_OFFSET (AudioBusBuffers, channelBuffers64);

	PRINT_TYPE (ProcessData);
	PRINT_OFFSET (ProcessData, processMode);
	PRINT_OFFSET (ProcessData, symbolicSampleSize);
	PRINT_OFFSET (ProcessData, numSamples);
	PRINT_OFFSET (ProcessData, numInputs);
	PRINT_OFFSET (ProcessData, numOutputs);
	PRINT_OFFSET (ProcessData, inputs);
	PRINT_OFFSET (ProcessData, outputs);
	PRINT_OFFSET (ProcessData, inputParameterChanges);
	PRINT_OFFSET (ProcessData, outputParameterChanges);
	PRINT_OFFSET (ProcessData, inputEvents);
	PRINT_OFFSET (ProcessData, outputEvents);
	PRINT_OFFSET (ProcessData, processContext);

	Steinberg::Vst::ProcessSetup setup32 {};
	setup32.symbolicSampleSize = Steinberg::Vst::kSample32;
	Steinberg::Vst::ProcessSetup setup64 {};
	setup64.symbolicSampleSize = Steinberg::Vst::kSample64;
	float channel32[4] {};
	double channel64[4] {};
	float* channels32[1] {channel32};
	double* channels64[1] {channel64};
	Steinberg::Vst::AudioBusBuffers buffers32 {};
	buffers32.channelBuffers32 = channels32;
	Steinberg::Vst::AudioBusBuffers buffers64 {};
	buffers64.channelBuffers64 = channels64;
	std::printf ("AudioProcessorAlgo.getChannelBuffersPointer.32 %d\n", Steinberg::Vst::getChannelBuffersPointer (setup32, buffers32) == reinterpret_cast<void**> (channels32));
	std::printf ("AudioProcessorAlgo.getChannelBuffersPointer.64 %d\n", Steinberg::Vst::getChannelBuffersPointer (setup64, buffers64) == reinterpret_cast<void**> (channels64));
	std::printf ("AudioProcessorAlgo.getSampleFramesSizeInBytes.32 %u\n", Steinberg::Vst::getSampleFramesSizeInBytes (setup32, 8));
	std::printf ("AudioProcessorAlgo.getSampleFramesSizeInBytes.64 %u\n", Steinberg::Vst::getSampleFramesSizeInBytes (setup64, 8));
	std::printf ("AudioProcessorAlgo.getChannelMask.0 %llu\n", static_cast<unsigned long long> (Steinberg::Vst::getChannelMask (0)));
	std::printf ("AudioProcessorAlgo.getChannelMask.6 %llu\n", static_cast<unsigned long long> (Steinberg::Vst::getChannelMask (6)));
	std::printf ("AudioProcessorAlgo.getChannelMask.64 %llu\n", static_cast<unsigned long long> (Steinberg::Vst::getChannelMask (64)));
	float src32Ch0[4] {1.f, 2.f, 3.f, 4.f};
	float src32Ch1[4] {5.f, 6.f, 7.f, 8.f};
	float dest32Ch0[6] {};
	float dest32Ch1[6] {};
	float* src32Channels[2] {src32Ch0, src32Ch1};
	float* dest32Channels[2] {dest32Ch0, dest32Ch1};
	Steinberg::Vst::AudioBusBuffers src32 {};
	src32.numChannels = 2;
	src32.channelBuffers32 = src32Channels;
	Steinberg::Vst::AudioBusBuffers dest32 {};
	dest32.numChannels = 2;
	dest32.channelBuffers32 = dest32Channels;
	Steinberg::Vst::Algo::copy32 (&src32, &dest32, 3, 2);
	std::printf ("AudioProcessorAlgo.copy32.dest0.2 %.1f\n", dest32Ch0[2]);
	std::printf ("AudioProcessorAlgo.copy32.dest1.4 %.1f\n", dest32Ch1[4]);
	Steinberg::Vst::Algo::mix32 (src32, dest32, 3);
	std::printf ("AudioProcessorAlgo.mix32.dest0.0 %.1f\n", dest32Ch0[0]);
	std::printf ("AudioProcessorAlgo.mix32.dest1.2 %.1f\n", dest32Ch1[2]);
	Steinberg::Vst::Algo::multiply32 (src32, dest32, 3, 2.f);
	std::printf ("AudioProcessorAlgo.multiply32.dest0.1 %.1f\n", dest32Ch0[1]);
	std::printf ("AudioProcessorAlgo.isSilent32.before %d\n", Steinberg::Vst::Algo::isSilent32 (dest32, 3));
	Steinberg::Vst::Algo::clear32 (&dest32, 3);
	std::printf ("AudioProcessorAlgo.clear32.dest0.1 %.1f\n", dest32Ch0[1]);
	std::printf ("AudioProcessorAlgo.isSilent32.after %d\n", Steinberg::Vst::Algo::isSilent32 (dest32, 3));
	double src64Ch0[3] {1.5, 2.5, 3.5};
	double dest64Ch0[5] {};
	double* src64Channels[1] {src64Ch0};
	double* dest64Channels[1] {dest64Ch0};
	Steinberg::Vst::AudioBusBuffers src64 {};
	src64.numChannels = 1;
	src64.channelBuffers64 = src64Channels;
	Steinberg::Vst::AudioBusBuffers dest64 {};
	dest64.numChannels = 1;
	dest64.channelBuffers64 = dest64Channels;
	Steinberg::Vst::Algo::copy64 (&src64, &dest64, 2, 1);
	std::printf ("AudioProcessorAlgo.copy64.dest0.2 %.1f\n", dest64Ch0[2]);
	Steinberg::Vst::Algo::multiply64 (src64, dest64, 2, 3.0);
	std::printf ("AudioProcessorAlgo.multiply64.dest0.1 %.1f\n", dest64Ch0[1]);
	std::printf ("AudioProcessorAlgo.isSilent64.before %d\n", Steinberg::Vst::Algo::isSilent64 (dest64, 2));
	Steinberg::Vst::Algo::clear64 (&dest64, 2);
	std::printf ("AudioProcessorAlgo.isSilent64.after %d\n", Steinberg::Vst::Algo::isSilent64 (dest64, 2));

	print_iid ("IAudioProcessor", Steinberg::Vst::IAudioProcessor_iid);
	print_iid ("IAudioPresentationLatency", Steinberg::Vst::IAudioPresentationLatency_iid);
	print_iid ("IProcessContextRequirements", Steinberg::Vst::IProcessContextRequirements_iid);
	return 0;
}
