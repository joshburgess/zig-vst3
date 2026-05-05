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
	std::printf ("NoteExpressionTypeIDs.kCustomStart %u\n", Steinberg::Vst::kCustomStart);
	std::printf ("NoteExpressionTypeIDs.kInvalidTypeID %u\n", Steinberg::Vst::kInvalidTypeID);
	std::printf ("NoteExpressionTypeInfo.kIsBipolar %d\n", Steinberg::Vst::NoteExpressionTypeInfo::kIsBipolar);
	std::printf ("NoteExpressionTypeInfo.kAssociatedParameterIDValid %d\n", Steinberg::Vst::NoteExpressionTypeInfo::kAssociatedParameterIDValid);
	std::printf ("KeyswitchTypeIDs.kNoteOnKeyswitchTypeID %u\n", Steinberg::Vst::kNoteOnKeyswitchTypeID);
	std::printf ("KeyswitchTypeIDs.kKeyRangeTypeID %u\n", Steinberg::Vst::kKeyRangeTypeID);

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
	PRINT_OFFSET (KeyswitchInfo, flags);

	print_iid ("INoteExpressionController", Steinberg::Vst::INoteExpressionController_iid);
	print_iid ("IKeyswitchController", Steinberg::Vst::IKeyswitchController_iid);
	return 0;
}
