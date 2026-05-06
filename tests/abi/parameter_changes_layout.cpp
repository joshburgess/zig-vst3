#include "pluginterfaces/vst/ivstparameterchanges.h"

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
	PRINT_TYPE (IParamValueQueue);
	PRINT_TYPE (IParameterChanges);

	print_iid ("IParamValueQueue", Steinberg::Vst::IParamValueQueue_iid);
	print_iid ("IParameterChanges", Steinberg::Vst::IParameterChanges_iid);
	return 0;
}
