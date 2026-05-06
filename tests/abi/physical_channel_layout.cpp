#include "pluginterfaces/vst/ivstchannelcontextinfo.h"
#include "pluginterfaces/vst/ivstphysicalui.h"

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
	std::printf ("PhysicalUITypeIDs.kPUIXMovement %u\n", Steinberg::Vst::kPUIXMovement);
	std::printf ("PhysicalUITypeIDs.kPUIYMovement %u\n", Steinberg::Vst::kPUIYMovement);
	std::printf ("PhysicalUITypeIDs.kPUIPressure %u\n", Steinberg::Vst::kPUIPressure);
	std::printf ("PhysicalUITypeIDs.kPUITypeCount %u\n", Steinberg::Vst::kPUITypeCount);
	std::printf ("PhysicalUITypeIDs.kInvalidPUITypeID %u\n", Steinberg::Vst::kInvalidPUITypeID);
	std::printf ("ChannelPluginLocation.kPreVolumeFader %d\n", Steinberg::Vst::ChannelContext::kPreVolumeFader);
	std::printf ("ChannelPluginLocation.kPostVolumeFader %d\n", Steinberg::Vst::ChannelContext::kPostVolumeFader);
	std::printf ("ChannelPluginLocation.kUsedAsPanner %d\n", Steinberg::Vst::ChannelContext::kUsedAsPanner);
	std::printf ("ChannelContext.GetBlue %u\n", Steinberg::Vst::ChannelContext::GetBlue (0x11223344));
	std::printf ("ChannelContext.GetGreen %u\n", Steinberg::Vst::ChannelContext::GetGreen (0x11223344));
	std::printf ("ChannelContext.GetRed %u\n", Steinberg::Vst::ChannelContext::GetRed (0x11223344));
	std::printf ("ChannelContext.GetAlpha %u\n", Steinberg::Vst::ChannelContext::GetAlpha (0x11223344));
	std::printf ("ChannelContext.kChannelUIDKey %s\n", Steinberg::Vst::ChannelContext::kChannelUIDKey);
	std::printf ("ChannelContext.kChannelUIDLengthKey %s\n", Steinberg::Vst::ChannelContext::kChannelUIDLengthKey);
	std::printf ("ChannelContext.kChannelRuntimeIDKey %s\n", Steinberg::Vst::ChannelContext::kChannelRuntimeIDKey);
	std::printf ("ChannelContext.kChannelNameKey %s\n", Steinberg::Vst::ChannelContext::kChannelNameKey);
	std::printf ("ChannelContext.kChannelNameLengthKey %s\n", Steinberg::Vst::ChannelContext::kChannelNameLengthKey);
	std::printf ("ChannelContext.kChannelColorKey %s\n", Steinberg::Vst::ChannelContext::kChannelColorKey);
	std::printf ("ChannelContext.kChannelIndexKey %s\n", Steinberg::Vst::ChannelContext::kChannelIndexKey);
	std::printf ("ChannelContext.kChannelIndexNamespaceOrderKey %s\n", Steinberg::Vst::ChannelContext::kChannelIndexNamespaceOrderKey);
	std::printf ("ChannelContext.kChannelIndexNamespaceKey %s\n", Steinberg::Vst::ChannelContext::kChannelIndexNamespaceKey);
	std::printf ("ChannelContext.kChannelIndexNamespaceLengthKey %s\n", Steinberg::Vst::ChannelContext::kChannelIndexNamespaceLengthKey);
	std::printf ("ChannelContext.kChannelImageKey %s\n", Steinberg::Vst::ChannelContext::kChannelImageKey);
	std::printf ("ChannelContext.kChannelPluginLocationKey %s\n", Steinberg::Vst::ChannelContext::kChannelPluginLocationKey);

	PRINT_TYPE (PhysicalUIMap);
	PRINT_OFFSET (PhysicalUIMap, physicalUITypeID);
	PRINT_OFFSET (PhysicalUIMap, noteExpressionTypeID);
	PRINT_TYPE (PhysicalUIMapList);
	PRINT_OFFSET (PhysicalUIMapList, count);
	PRINT_OFFSET (PhysicalUIMapList, map);

	print_iid ("INoteExpressionPhysicalUIMapping", Steinberg::Vst::INoteExpressionPhysicalUIMapping_iid);
	print_iid ("IInfoListener", Steinberg::Vst::ChannelContext::IInfoListener_iid);
	return 0;
}
