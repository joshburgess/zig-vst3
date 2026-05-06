#include "pluginterfaces/vst/ivstprocesscontext.h"

#include <cstddef>
#include <cstdio>

#define PRINT_TYPE(Type) std::printf (#Type " size %zu align %zu\n", sizeof (Steinberg::Vst::Type), alignof (Steinberg::Vst::Type))
#define PRINT_OFFSET(Type, Field) std::printf (#Type "." #Field " offset %zu\n", offsetof (Steinberg::Vst::Type, Field))

int main ()
{
	std::printf ("FrameRate.kPullDownRate %u\n", Steinberg::Vst::FrameRate::kPullDownRate);
	std::printf ("FrameRate.kDropRate %u\n", Steinberg::Vst::FrameRate::kDropRate);
	std::printf ("Chord.kChordMask %d\n", Steinberg::Vst::Chord::kChordMask);
	std::printf ("Chord.kReservedMask %d\n", Steinberg::Vst::Chord::kReservedMask);
	std::printf ("ProcessContext.kPlaying %u\n", Steinberg::Vst::ProcessContext::kPlaying);
	std::printf ("ProcessContext.kCycleActive %u\n", Steinberg::Vst::ProcessContext::kCycleActive);
	std::printf ("ProcessContext.kRecording %u\n", Steinberg::Vst::ProcessContext::kRecording);
	std::printf ("ProcessContext.kSystemTimeValid %u\n", Steinberg::Vst::ProcessContext::kSystemTimeValid);
	std::printf ("ProcessContext.kContTimeValid %u\n", Steinberg::Vst::ProcessContext::kContTimeValid);
	std::printf ("ProcessContext.kProjectTimeMusicValid %u\n", Steinberg::Vst::ProcessContext::kProjectTimeMusicValid);
	std::printf ("ProcessContext.kBarPositionValid %u\n", Steinberg::Vst::ProcessContext::kBarPositionValid);
	std::printf ("ProcessContext.kCycleValid %u\n", Steinberg::Vst::ProcessContext::kCycleValid);
	std::printf ("ProcessContext.kTempoValid %u\n", Steinberg::Vst::ProcessContext::kTempoValid);
	std::printf ("ProcessContext.kTimeSigValid %u\n", Steinberg::Vst::ProcessContext::kTimeSigValid);
	std::printf ("ProcessContext.kChordValid %u\n", Steinberg::Vst::ProcessContext::kChordValid);
	std::printf ("ProcessContext.kSmpteValid %u\n", Steinberg::Vst::ProcessContext::kSmpteValid);
	std::printf ("ProcessContext.kClockValid %u\n", Steinberg::Vst::ProcessContext::kClockValid);

	PRINT_TYPE (FrameRate);
	PRINT_OFFSET (FrameRate, framesPerSecond);
	PRINT_OFFSET (FrameRate, flags);

	PRINT_TYPE (Chord);
	PRINT_OFFSET (Chord, keyNote);
	PRINT_OFFSET (Chord, rootNote);
	PRINT_OFFSET (Chord, chordMask);

	PRINT_TYPE (ProcessContext);
	PRINT_OFFSET (ProcessContext, state);
	PRINT_OFFSET (ProcessContext, sampleRate);
	PRINT_OFFSET (ProcessContext, projectTimeSamples);
	PRINT_OFFSET (ProcessContext, systemTime);
	PRINT_OFFSET (ProcessContext, continousTimeSamples);
	PRINT_OFFSET (ProcessContext, projectTimeMusic);
	PRINT_OFFSET (ProcessContext, barPositionMusic);
	PRINT_OFFSET (ProcessContext, cycleStartMusic);
	PRINT_OFFSET (ProcessContext, cycleEndMusic);
	PRINT_OFFSET (ProcessContext, tempo);
	PRINT_OFFSET (ProcessContext, timeSigNumerator);
	PRINT_OFFSET (ProcessContext, timeSigDenominator);
	PRINT_OFFSET (ProcessContext, chord);
	PRINT_OFFSET (ProcessContext, smpteOffsetSubframes);
	PRINT_OFFSET (ProcessContext, frameRate);
	PRINT_OFFSET (ProcessContext, samplesToNextClock);
	return 0;
}
