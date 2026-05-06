#include "pluginterfaces/vst/ivstparameterfunctionname.h"
#include "pluginterfaces/vst/ivstplugview.h"
#include "pluginterfaces/vst/ivstremapparamid.h"

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
	std::printf ("FunctionNameType.kCompGainReduction %s\n", Steinberg::Vst::FunctionNameType::kCompGainReduction);
	std::printf ("FunctionNameType.kCompGainReductionMax %s\n", Steinberg::Vst::FunctionNameType::kCompGainReductionMax);
	std::printf ("FunctionNameType.kCompGainReductionPeakHold %s\n", Steinberg::Vst::FunctionNameType::kCompGainReductionPeakHold);
	std::printf ("FunctionNameType.kCompResetGainReductionMax %s\n", Steinberg::Vst::FunctionNameType::kCompResetGainReductionMax);
	std::printf ("FunctionNameType.kLowLatencyMode %s\n", Steinberg::Vst::FunctionNameType::kLowLatencyMode);
	std::printf ("FunctionNameType.kDryWetMix %s\n", Steinberg::Vst::FunctionNameType::kDryWetMix);
	std::printf ("FunctionNameType.kRandomize %s\n", Steinberg::Vst::FunctionNameType::kRandomize);
	std::printf ("FunctionNameType.kPanPosCenterX %s\n", Steinberg::Vst::FunctionNameType::kPanPosCenterX);
	std::printf ("FunctionNameType.kPanPosCenterY %s\n", Steinberg::Vst::FunctionNameType::kPanPosCenterY);
	std::printf ("FunctionNameType.kPanPosCenterZ %s\n", Steinberg::Vst::FunctionNameType::kPanPosCenterZ);

	PRINT_TYPE (IParameterFunctionName);
	PRINT_TYPE (IParameterFinder);
	PRINT_TYPE (IRemapParamID);

	print_iid ("IParameterFunctionName", Steinberg::Vst::IParameterFunctionName_iid);
	print_iid ("IParameterFinder", Steinberg::Vst::IParameterFinder_iid);
	print_iid ("IRemapParamID", Steinberg::Vst::IRemapParamID_iid);
	return 0;
}
