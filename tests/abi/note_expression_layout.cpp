#include "pluginterfaces/vst/ivstnoteexpression.h"

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
	std::printf ("NoteExpressionTypeIDs.kVolumeTypeID %u\n", Steinberg::Vst::kVolumeTypeID);
	std::printf ("NoteExpressionTypeIDs.kPanTypeID %u\n", Steinberg::Vst::kPanTypeID);
	std::printf ("NoteExpressionTypeIDs.kTuningTypeID %u\n", Steinberg::Vst::kTuningTypeID);
	std::printf ("NoteExpressionTypeIDs.kVibratoTypeID %u\n", Steinberg::Vst::kVibratoTypeID);
	std::printf ("NoteExpressionTypeIDs.kExpressionTypeID %u\n", Steinberg::Vst::kExpressionTypeID);
	std::printf ("NoteExpressionTypeIDs.kBrightnessTypeID %u\n", Steinberg::Vst::kBrightnessTypeID);
	std::printf ("NoteExpressionTypeIDs.kTextTypeID %u\n", Steinberg::Vst::kTextTypeID);
	std::printf ("NoteExpressionTypeIDs.kPhonemeTypeID %u\n", Steinberg::Vst::kPhonemeTypeID);
	std::printf ("NoteExpressionTypeIDs.kCustomStart %u\n", Steinberg::Vst::kCustomStart);
	std::printf ("NoteExpressionTypeIDs.kCustomEnd %u\n", Steinberg::Vst::kCustomEnd);
	std::printf ("NoteExpressionTypeIDs.kInvalidTypeID %u\n", Steinberg::Vst::kInvalidTypeID);
	std::printf ("NoteExpressionTypeInfo.kIsBipolar %d\n", Steinberg::Vst::NoteExpressionTypeInfo::kIsBipolar);
	std::printf ("NoteExpressionTypeInfo.kIsOneShot %d\n", Steinberg::Vst::NoteExpressionTypeInfo::kIsOneShot);
	std::printf ("NoteExpressionTypeInfo.kIsAbsolute %d\n", Steinberg::Vst::NoteExpressionTypeInfo::kIsAbsolute);
	std::printf ("NoteExpressionTypeInfo.kAssociatedParameterIDValid %d\n", Steinberg::Vst::NoteExpressionTypeInfo::kAssociatedParameterIDValid);
	std::printf ("KeyswitchTypeIDs.kNoteOnKeyswitchTypeID %u\n", Steinberg::Vst::kNoteOnKeyswitchTypeID);
	std::printf ("KeyswitchTypeIDs.kOnTheFlyKeyswitchTypeID %u\n", Steinberg::Vst::kOnTheFlyKeyswitchTypeID);
	std::printf ("KeyswitchTypeIDs.kOnReleaseKeyswitchTypeID %u\n", Steinberg::Vst::kOnReleaseKeyswitchTypeID);
	std::printf ("KeyswitchTypeIDs.kKeyRangeTypeID %u\n", Steinberg::Vst::kKeyRangeTypeID);

	PRINT_TYPE (NoteExpressionValueEvent);
	PRINT_OFFSET (NoteExpressionValueEvent, typeId);
	PRINT_OFFSET (NoteExpressionValueEvent, noteId);
	PRINT_OFFSET (NoteExpressionValueEvent, value);

	PRINT_TYPE (NoteExpressionIntValueEvent);
	PRINT_OFFSET (NoteExpressionIntValueEvent, typeId);
	PRINT_OFFSET (NoteExpressionIntValueEvent, noteId);
	PRINT_OFFSET (NoteExpressionIntValueEvent, value);

	PRINT_TYPE (NoteExpressionTextEvent);
	PRINT_OFFSET (NoteExpressionTextEvent, typeId);
	PRINT_OFFSET (NoteExpressionTextEvent, noteId);
	PRINT_OFFSET (NoteExpressionTextEvent, textLen);
	PRINT_OFFSET (NoteExpressionTextEvent, text);

	PRINT_TYPE (NoteExpressionValueDescription);
	PRINT_OFFSET (NoteExpressionValueDescription, defaultValue);
	PRINT_OFFSET (NoteExpressionValueDescription, minimum);
	PRINT_OFFSET (NoteExpressionValueDescription, maximum);
	PRINT_OFFSET (NoteExpressionValueDescription, stepCount);

	PRINT_TYPE (NoteExpressionTypeInfo);
	PRINT_OFFSET (NoteExpressionTypeInfo, typeId);
	PRINT_OFFSET (NoteExpressionTypeInfo, title);
	PRINT_OFFSET (NoteExpressionTypeInfo, shortTitle);
	PRINT_OFFSET (NoteExpressionTypeInfo, units);
	PRINT_OFFSET (NoteExpressionTypeInfo, unitId);
	PRINT_OFFSET (NoteExpressionTypeInfo, valueDesc);
	PRINT_OFFSET (NoteExpressionTypeInfo, associatedParameterId);
	PRINT_OFFSET (NoteExpressionTypeInfo, flags);

	PRINT_TYPE (KeyswitchInfo);
	PRINT_OFFSET (KeyswitchInfo, typeId);
	PRINT_OFFSET (KeyswitchInfo, title);
	PRINT_OFFSET (KeyswitchInfo, shortTitle);
	PRINT_OFFSET (KeyswitchInfo, keyswitchMin);
	PRINT_OFFSET (KeyswitchInfo, keyswitchMax);
	PRINT_OFFSET (KeyswitchInfo, keyRemapped);
	PRINT_OFFSET (KeyswitchInfo, unitId);
	PRINT_OFFSET (KeyswitchInfo, flags);

	print_iid ("INoteExpressionController", Steinberg::Vst::INoteExpressionController_iid);
	print_iid ("IKeyswitchController", Steinberg::Vst::IKeyswitchController_iid);
	return 0;
}
