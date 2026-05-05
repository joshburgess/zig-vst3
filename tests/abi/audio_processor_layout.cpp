#include "pluginterfaces/vst/ivstaudioprocessor.h"

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

	print_iid ("IAudioProcessor", Steinberg::Vst::IAudioProcessor_iid);
	print_iid ("IAudioPresentationLatency", Steinberg::Vst::IAudioPresentationLatency_iid);
	print_iid ("IProcessContextRequirements", Steinberg::Vst::IProcessContextRequirements_iid);
	return 0;
}
