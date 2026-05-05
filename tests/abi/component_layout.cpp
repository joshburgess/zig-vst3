#include "pluginterfaces/vst/ivstcomponent.h"

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
	std::printf ("MediaTypes.kAudio %d\n", Steinberg::Vst::kAudio);
	std::printf ("MediaTypes.kEvent %d\n", Steinberg::Vst::kEvent);
	std::printf ("BusDirections.kInput %d\n", Steinberg::Vst::kInput);
	std::printf ("BusDirections.kOutput %d\n", Steinberg::Vst::kOutput);
	std::printf ("BusTypes.kMain %d\n", Steinberg::Vst::kMain);
	std::printf ("BusTypes.kAux %d\n", Steinberg::Vst::kAux);
	std::printf ("IoModes.kSimple %d\n", Steinberg::Vst::kSimple);
	std::printf ("IoModes.kAdvanced %d\n", Steinberg::Vst::kAdvanced);
	std::printf ("IoModes.kOfflineProcessing %d\n", Steinberg::Vst::kOfflineProcessing);
	std::printf ("BusInfo.kDefaultActive %u\n", Steinberg::Vst::BusInfo::kDefaultActive);
	std::printf ("BusInfo.kIsControlVoltage %u\n", Steinberg::Vst::BusInfo::kIsControlVoltage);

	PRINT_TYPE (BusInfo);
	PRINT_OFFSET (BusInfo, mediaType);
	PRINT_OFFSET (BusInfo, direction);
	PRINT_OFFSET (BusInfo, channelCount);
	PRINT_OFFSET (BusInfo, name);
	PRINT_OFFSET (BusInfo, busType);
	PRINT_OFFSET (BusInfo, flags);

	PRINT_TYPE (RoutingInfo);
	PRINT_OFFSET (RoutingInfo, mediaType);
	PRINT_OFFSET (RoutingInfo, busIndex);
	PRINT_OFFSET (RoutingInfo, channel);

	print_iid ("IComponent", Steinberg::Vst::IComponent_iid);
	return 0;
}
