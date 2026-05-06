#include "pluginterfaces/vst/ivstmidilearn.h"
#include "pluginterfaces/vst/ivstmidimapping2.h"

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
	PRINT_TYPE (Midi2Controller);
	PRINT_TYPE (Midi2ControllerParamIDAssignment);
	PRINT_OFFSET (Midi2ControllerParamIDAssignment, pId);
	PRINT_OFFSET (Midi2ControllerParamIDAssignment, busIndex);
	PRINT_OFFSET (Midi2ControllerParamIDAssignment, channel);
	PRINT_OFFSET (Midi2ControllerParamIDAssignment, controller);
	PRINT_TYPE (Midi2ControllerParamIDAssignmentList);
	PRINT_OFFSET (Midi2ControllerParamIDAssignmentList, count);
	PRINT_OFFSET (Midi2ControllerParamIDAssignmentList, map);

	PRINT_TYPE (Midi1ControllerParamIDAssignment);
	PRINT_OFFSET (Midi1ControllerParamIDAssignment, pId);
	PRINT_OFFSET (Midi1ControllerParamIDAssignment, busIndex);
	PRINT_OFFSET (Midi1ControllerParamIDAssignment, channel);
	PRINT_OFFSET (Midi1ControllerParamIDAssignment, controller);
	PRINT_TYPE (Midi1ControllerParamIDAssignmentList);
	PRINT_OFFSET (Midi1ControllerParamIDAssignmentList, count);
	PRINT_OFFSET (Midi1ControllerParamIDAssignmentList, map);

	PRINT_TYPE (IMidiLearn);
	PRINT_TYPE (IMidiMapping2);
	PRINT_TYPE (IMidiLearn2);

	print_iid ("IMidiLearn", Steinberg::Vst::IMidiLearn_iid);
	print_iid ("IMidiMapping2", Steinberg::Vst::IMidiMapping2_iid);
	print_iid ("IMidiLearn2", Steinberg::Vst::IMidiLearn2_iid);
	return 0;
}
