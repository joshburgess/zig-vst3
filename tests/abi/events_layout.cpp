#include "pluginterfaces/vst/ivstevents.h"

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
	std::printf ("NoteIDUserRange.kNoteIDUserRangeLowerBound %d\n", Steinberg::Vst::kNoteIDUserRangeLowerBound);
	std::printf ("NoteIDUserRange.kNoteIDUserRangeUpperBound %d\n", Steinberg::Vst::kNoteIDUserRangeUpperBound);
	std::printf ("DataEvent.kMidiSysEx %d\n", Steinberg::Vst::DataEvent::kMidiSysEx);
	std::printf ("Event.kIsLive %u\n", Steinberg::Vst::Event::kIsLive);
	std::printf ("Event.kUserReserved1 %u\n", Steinberg::Vst::Event::kUserReserved1);
	std::printf ("Event.kUserReserved2 %u\n", Steinberg::Vst::Event::kUserReserved2);
	std::printf ("Event.kNoteOnEvent %u\n", Steinberg::Vst::Event::kNoteOnEvent);
	std::printf ("Event.kNoteOffEvent %u\n", Steinberg::Vst::Event::kNoteOffEvent);
	std::printf ("Event.kDataEvent %u\n", Steinberg::Vst::Event::kDataEvent);
	std::printf ("Event.kPolyPressureEvent %u\n", Steinberg::Vst::Event::kPolyPressureEvent);
	std::printf ("Event.kNoteExpressionValueEvent %u\n", Steinberg::Vst::Event::kNoteExpressionValueEvent);
	std::printf ("Event.kNoteExpressionTextEvent %u\n", Steinberg::Vst::Event::kNoteExpressionTextEvent);
	std::printf ("Event.kChordEvent %u\n", Steinberg::Vst::Event::kChordEvent);
	std::printf ("Event.kScaleEvent %u\n", Steinberg::Vst::Event::kScaleEvent);
	std::printf ("Event.kNoteExpressionIntValueEvent %u\n", Steinberg::Vst::Event::kNoteExpressionIntValueEvent);
	std::printf ("Event.kLegacyMIDICCOutEvent %u\n", Steinberg::Vst::Event::kLegacyMIDICCOutEvent);

	PRINT_TYPE (NoteOnEvent);
	PRINT_TYPE (NoteOffEvent);
	PRINT_TYPE (DataEvent);
	PRINT_TYPE (PolyPressureEvent);
	PRINT_TYPE (ChordEvent);
	PRINT_TYPE (ScaleEvent);
	PRINT_TYPE (LegacyMIDICCOutEvent);
	PRINT_TYPE (NoteExpressionValueEvent);
	PRINT_TYPE (NoteExpressionIntValueEvent);
	PRINT_TYPE (NoteExpressionTextEvent);
	PRINT_TYPE (Event);
	PRINT_OFFSET (Event, busIndex);
	PRINT_OFFSET (Event, sampleOffset);
	PRINT_OFFSET (Event, ppqPosition);
	PRINT_OFFSET (Event, flags);
	PRINT_OFFSET (Event, type);
	PRINT_OFFSET (Event, noteOn);
	PRINT_OFFSET (Event, noteExpressionText);
	PRINT_OFFSET (Event, midiCCOut);

	print_iid ("IEventList", Steinberg::Vst::IEventList_iid);
	return 0;
}
