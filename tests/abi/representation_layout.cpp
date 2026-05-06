#include "pluginterfaces/vst/ivstrepresentation.h"

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
	std::printf ("RepresentationInfo.kNameSize %d\n", Steinberg::Vst::RepresentationInfo::kNameSize);
	PRINT_TYPE (RepresentationInfo);
	PRINT_OFFSET (RepresentationInfo, vendor);
	PRINT_OFFSET (RepresentationInfo, name);
	PRINT_OFFSET (RepresentationInfo, version);
	PRINT_OFFSET (RepresentationInfo, host);

	std::printf ("LayerType.kKnob %d\n", Steinberg::Vst::LayerType::kKnob);
	std::printf ("LayerType.kFader %d\n", Steinberg::Vst::LayerType::kFader);
	std::printf ("LayerType.kEndOfLayerType %d\n", Steinberg::Vst::LayerType::kEndOfLayerType);
	std::printf ("LayerType.layerTypeFIDString.0 %s\n", Steinberg::Vst::LayerType::layerTypeFIDString[0]);
	std::printf ("LayerType.layerTypeFIDString.7 %s\n", Steinberg::Vst::LayerType::layerTypeFIDString[7]);

	print_iid ("IXmlRepresentationController", Steinberg::Vst::IXmlRepresentationController_iid);
	return 0;
}
