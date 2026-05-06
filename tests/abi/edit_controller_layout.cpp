#include "pluginterfaces/vst/ivsteditcontroller.h"

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
	std::printf ("kVstComponentControllerClass %s\n", kVstComponentControllerClass);
	std::printf ("ViewType.kEditor %s\n", Steinberg::Vst::ViewType::kEditor);
	std::printf ("ParameterInfo.kNoFlags %d\n", Steinberg::Vst::ParameterInfo::kNoFlags);
	std::printf ("ParameterInfo.kCanAutomate %d\n", Steinberg::Vst::ParameterInfo::kCanAutomate);
	std::printf ("ParameterInfo.kIsReadOnly %d\n", Steinberg::Vst::ParameterInfo::kIsReadOnly);
	std::printf ("ParameterInfo.kIsWrapAround %d\n", Steinberg::Vst::ParameterInfo::kIsWrapAround);
	std::printf ("ParameterInfo.kIsList %d\n", Steinberg::Vst::ParameterInfo::kIsList);
	std::printf ("ParameterInfo.kIsHidden %d\n", Steinberg::Vst::ParameterInfo::kIsHidden);
	std::printf ("ParameterInfo.kIsProgramChange %d\n", Steinberg::Vst::ParameterInfo::kIsProgramChange);
	std::printf ("ParameterInfo.kIsBypass %d\n", Steinberg::Vst::ParameterInfo::kIsBypass);
	std::printf ("RestartFlags.kReloadComponent %d\n", Steinberg::Vst::kReloadComponent);
	std::printf ("RestartFlags.kIoChanged %d\n", Steinberg::Vst::kIoChanged);
	std::printf ("RestartFlags.kParamValuesChanged %d\n", Steinberg::Vst::kParamValuesChanged);
	std::printf ("RestartFlags.kLatencyChanged %d\n", Steinberg::Vst::kLatencyChanged);
	std::printf ("RestartFlags.kParamTitlesChanged %d\n", Steinberg::Vst::kParamTitlesChanged);
	std::printf ("RestartFlags.kMidiCCAssignmentChanged %d\n", Steinberg::Vst::kMidiCCAssignmentChanged);
	std::printf ("RestartFlags.kNoteExpressionChanged %d\n", Steinberg::Vst::kNoteExpressionChanged);
	std::printf ("RestartFlags.kIoTitlesChanged %d\n", Steinberg::Vst::kIoTitlesChanged);
	std::printf ("RestartFlags.kPrefetchableSupportChanged %d\n", Steinberg::Vst::kPrefetchableSupportChanged);
	std::printf ("RestartFlags.kRoutingInfoChanged %d\n", Steinberg::Vst::kRoutingInfoChanged);
	std::printf ("RestartFlags.kKeyswitchChanged %d\n", Steinberg::Vst::kKeyswitchChanged);
	std::printf ("RestartFlags.kParamIDMappingChanged %d\n", Steinberg::Vst::kParamIDMappingChanged);
	std::printf ("ProgressType.AsyncStateRestoration %u\n", Steinberg::Vst::IProgress::AsyncStateRestoration);
	std::printf ("ProgressType.UIBackgroundTask %u\n", Steinberg::Vst::IProgress::UIBackgroundTask);
	std::printf ("KnobModes.kCircularMode %d\n", Steinberg::Vst::kCircularMode);
	std::printf ("KnobModes.kRelativCircularMode %d\n", Steinberg::Vst::kRelativCircularMode);
	std::printf ("KnobModes.kLinearMode %d\n", Steinberg::Vst::kLinearMode);

	PRINT_TYPE (ParameterInfo);
	PRINT_OFFSET (ParameterInfo, id);
	PRINT_OFFSET (ParameterInfo, title);
	PRINT_OFFSET (ParameterInfo, shortTitle);
	PRINT_OFFSET (ParameterInfo, units);
	PRINT_OFFSET (ParameterInfo, stepCount);
	PRINT_OFFSET (ParameterInfo, defaultNormalizedValue);
	PRINT_OFFSET (ParameterInfo, unitId);
	PRINT_OFFSET (ParameterInfo, flags);

	PRINT_TYPE (IComponentHandler);
	PRINT_TYPE (IComponentHandler2);
	PRINT_TYPE (IComponentHandlerBusActivation);
	PRINT_TYPE (IProgress);
	PRINT_TYPE (IEditController);
	PRINT_TYPE (IEditController2);
	PRINT_TYPE (IMidiMapping);
	PRINT_TYPE (IEditControllerHostEditing);
	PRINT_TYPE (IComponentHandlerSystemTime);
	print_iid ("IComponentHandler", Steinberg::Vst::IComponentHandler_iid);
	print_iid ("IComponentHandler2", Steinberg::Vst::IComponentHandler2_iid);
	print_iid ("IComponentHandlerBusActivation", Steinberg::Vst::IComponentHandlerBusActivation_iid);
	print_iid ("IProgress", Steinberg::Vst::IProgress_iid);
	print_iid ("IEditController", Steinberg::Vst::IEditController_iid);
	print_iid ("IEditController2", Steinberg::Vst::IEditController2_iid);
	print_iid ("IMidiMapping", Steinberg::Vst::IMidiMapping_iid);
	print_iid ("IEditControllerHostEditing", Steinberg::Vst::IEditControllerHostEditing_iid);
	print_iid ("IComponentHandlerSystemTime", Steinberg::Vst::IComponentHandlerSystemTime_iid);
	return 0;
}
