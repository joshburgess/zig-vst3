#include "pluginterfaces/vst/ivstevents.h"
#include "public.sdk/source/vst/vsteventshelper.h"

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
	PRINT_OFFSET (NoteOnEvent, channel);
	PRINT_OFFSET (NoteOnEvent, pitch);
	PRINT_OFFSET (NoteOnEvent, tuning);
	PRINT_OFFSET (NoteOnEvent, velocity);
	PRINT_OFFSET (NoteOnEvent, length);
	PRINT_OFFSET (NoteOnEvent, noteId);
	PRINT_TYPE (NoteOffEvent);
	PRINT_OFFSET (NoteOffEvent, channel);
	PRINT_OFFSET (NoteOffEvent, pitch);
	PRINT_OFFSET (NoteOffEvent, velocity);
	PRINT_OFFSET (NoteOffEvent, noteId);
	PRINT_OFFSET (NoteOffEvent, tuning);
	PRINT_TYPE (DataEvent);
	PRINT_OFFSET (DataEvent, size);
	PRINT_OFFSET (DataEvent, type);
	PRINT_OFFSET (DataEvent, bytes);
	PRINT_TYPE (PolyPressureEvent);
	PRINT_OFFSET (PolyPressureEvent, channel);
	PRINT_OFFSET (PolyPressureEvent, pitch);
	PRINT_OFFSET (PolyPressureEvent, pressure);
	PRINT_OFFSET (PolyPressureEvent, noteId);
	PRINT_TYPE (ChordEvent);
	PRINT_OFFSET (ChordEvent, root);
	PRINT_OFFSET (ChordEvent, bassNote);
	PRINT_OFFSET (ChordEvent, mask);
	PRINT_OFFSET (ChordEvent, textLen);
	PRINT_OFFSET (ChordEvent, text);
	PRINT_TYPE (ScaleEvent);
	PRINT_OFFSET (ScaleEvent, root);
	PRINT_OFFSET (ScaleEvent, mask);
	PRINT_OFFSET (ScaleEvent, textLen);
	PRINT_OFFSET (ScaleEvent, text);
	PRINT_TYPE (LegacyMIDICCOutEvent);
	PRINT_OFFSET (LegacyMIDICCOutEvent, controlNumber);
	PRINT_OFFSET (LegacyMIDICCOutEvent, channel);
	PRINT_OFFSET (LegacyMIDICCOutEvent, value);
	PRINT_OFFSET (LegacyMIDICCOutEvent, value2);
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

	Steinberg::Vst::Event event {};
	Steinberg::Vst::Helpers::init (event, Steinberg::Vst::Event::kDataEvent, 2, 64, 12.5, Steinberg::Vst::Event::kIsLive);
	std::printf ("Helpers.init.busIndex %d\n", event.busIndex);
	std::printf ("Helpers.init.sampleOffset %d\n", event.sampleOffset);
	std::printf ("Helpers.init.ppqPosition %.6f\n", event.ppqPosition);
	std::printf ("Helpers.init.flags %u\n", event.flags);
	std::printf ("Helpers.init.type %u\n", event.type);
	std::printf ("Helpers.getMIDINormValue.64 %.12f\n", Steinberg::Vst::Helpers::getMIDINormValue (64));
	std::printf ("Helpers.getMIDICCOutValue.1 %d\n", Steinberg::Vst::Helpers::getMIDICCOutValue (1.0));
	std::printf ("Helpers.getMIDI14BitValue.1 %d\n", Steinberg::Vst::Helpers::getMIDI14BitValue (1.0));
	std::printf ("Helpers.getMIDI14BitNormValue.8192 %.12f\n", Steinberg::Vst::Helpers::getMIDI14BitNormValue (8192));
	auto& midi = Steinberg::Vst::Helpers::initLegacyMIDICCOutEvent (event, 10, 2, 64, 1);
	std::printf ("Helpers.initLegacy.type %u\n", event.type);
	std::printf ("Helpers.initLegacy.controlNumber %u\n", midi.controlNumber);
	std::printf ("Helpers.initLegacy.channel %d\n", midi.channel);
	std::printf ("Helpers.initLegacy.value %d\n", midi.value);
	std::printf ("Helpers.initLegacy.value2 %d\n", midi.value2);
	Steinberg::Vst::Helpers::setPitchBendValue (midi, 1.0);
	std::printf ("Helpers.pitchBend.value %d\n", midi.value);
	std::printf ("Helpers.pitchBend.value2 %d\n", midi.value2);
	std::printf ("Helpers.getPitchBendValue %d\n", Steinberg::Vst::Helpers::getPitchBendValue (midi));
	std::printf ("Helpers.getNormPitchBendValue %.12f\n", Steinberg::Vst::Helpers::getNormPitchBendValue (midi));

	PRINT_TYPE (IEventList);
	print_iid ("IEventList", Steinberg::Vst::IEventList_iid);
	return 0;
}
