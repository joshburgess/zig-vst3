#include "pluginterfaces/base/funknown.h"
#include "pluginterfaces/vst/ivstautomationstate.h"
#include "pluginterfaces/vst/ivstpluginterfacesupport.h"
#include "pluginterfaces/vst/ivstprefetchablesupport.h"

#include <cstddef>
#include <cstdio>

#define PRINT_TYPE(Type) std::printf (#Type " size %zu align %zu\n", sizeof (Steinberg::Vst::Type), alignof (Steinberg::Vst::Type))

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
	std::printf ("ePrefetchableSupport.kIsNeverPrefetchable %d\n", Steinberg::Vst::kIsNeverPrefetchable);
	std::printf ("ePrefetchableSupport.kIsYetPrefetchable %d\n", Steinberg::Vst::kIsYetPrefetchable);
	std::printf ("ePrefetchableSupport.kIsNotYetPrefetchable %d\n", Steinberg::Vst::kIsNotYetPrefetchable);
	std::printf ("ePrefetchableSupport.kNumPrefetchableSupport %d\n", Steinberg::Vst::kNumPrefetchableSupport);
	std::printf ("IAutomationState.kNoAutomation %d\n", Steinberg::Vst::IAutomationState::kNoAutomation);
	std::printf ("IAutomationState.kReadState %d\n", Steinberg::Vst::IAutomationState::kReadState);
	std::printf ("IAutomationState.kWriteState %d\n", Steinberg::Vst::IAutomationState::kWriteState);
	std::printf ("IAutomationState.kReadWriteState %d\n", Steinberg::Vst::IAutomationState::kReadWriteState);

	PRINT_TYPE (IPlugInterfaceSupport);
	PRINT_TYPE (IPrefetchableSupport);
	PRINT_TYPE (IAutomationState);

	print_iid ("IPlugInterfaceSupport", Steinberg::Vst::IPlugInterfaceSupport_iid);
	print_iid ("IPrefetchableSupport", Steinberg::Vst::IPrefetchableSupport_iid);
	print_iid ("IAutomationState", Steinberg::Vst::IAutomationState_iid);
	return 0;
}
