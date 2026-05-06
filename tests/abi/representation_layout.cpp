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
	std::printf ("LayerType.layerTypeFIDString.8 %s\n", Steinberg::Vst::LayerType::layerTypeFIDString[8] ? Steinberg::Vst::LayerType::layerTypeFIDString[8] : "<null>");

	std::printf ("Tag.rootXml %s\n", ROOTXML_TAG);
	std::printf ("Tag.titleDisplay %s\n", TITLEDISPLAY_TAG);
	std::printf ("Attr.parameterID %s\n", ATTR_PARAMID);
	std::printf ("Attr.turnsPerFullRange %s\n", Steinberg::Vst::Attributes::kKnobTurnsPerFullRange);
	std::printf ("Remote.generic8Cells %s\n", GENERIC_8_CELLS);
	std::printf ("Remote.quickControl8Cells %s\n", QUICK_CONTROL_8_CELLS);
	std::printf ("Curve.segment %s\n", Steinberg::Vst::CurveType::kSegment);
	std::printf ("Curve.valueList %s\n", Steinberg::Vst::CurveType::kValueList);
	std::printf ("Function.panLaw %s\n", Steinberg::Vst::AttributesFunction::kPanLawFunc);
	std::printf ("Function.volume %s\n", Steinberg::Vst::AttributesFunction::kVolumeFunc);
	std::printf ("Style.inverse %s\n", Steinberg::Vst::AttributesStyle::kInverseStyle);
	std::printf ("Style.ledBoostCut %s\n", Steinberg::Vst::AttributesStyle::kLEDBoostCutStyle);
	std::printf ("Style.switchLatch %s\n", Steinberg::Vst::AttributesStyle::kSwitchLatchStyle);
	std::printf ("Flag.hideable %s\n", Steinberg::Vst::AttributesFlags::kHideableFlag);

	PRINT_TYPE (IXmlRepresentationController);
	print_iid ("IXmlRepresentationController", Steinberg::Vst::IXmlRepresentationController_iid);
	return 0;
}
