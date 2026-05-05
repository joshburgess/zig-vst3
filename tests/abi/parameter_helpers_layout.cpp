#include "pluginterfaces/vst/ivstparameterfunctionname.h"
#include "pluginterfaces/vst/ivstplugview.h"
#include "pluginterfaces/vst/ivstremapparamid.h"

#include <cstdio>

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
	std::printf ("FunctionNameType.kCompGainReduction %s\n", Steinberg::Vst::FunctionNameType::kCompGainReduction);
	std::printf ("FunctionNameType.kLowLatencyMode %s\n", Steinberg::Vst::FunctionNameType::kLowLatencyMode);
	std::printf ("FunctionNameType.kDryWetMix %s\n", Steinberg::Vst::FunctionNameType::kDryWetMix);
	std::printf ("FunctionNameType.kRandomize %s\n", Steinberg::Vst::FunctionNameType::kRandomize);
	std::printf ("FunctionNameType.kPanPosCenterX %s\n", Steinberg::Vst::FunctionNameType::kPanPosCenterX);

	print_iid ("IParameterFunctionName", Steinberg::Vst::IParameterFunctionName_iid);
	print_iid ("IParameterFinder", Steinberg::Vst::IParameterFinder_iid);
	print_iid ("IRemapParamID", Steinberg::Vst::IRemapParamID_iid);
	return 0;
}
