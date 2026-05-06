#include "pluginterfaces/vst/ivsttestplugprovider.h"

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
	PRINT_TYPE (ITestPlugProvider);
	PRINT_TYPE (ITestPlugProvider2);

	print_iid ("ITestPlugProvider", Steinberg::Vst::ITestPlugProvider_iid);
	print_iid ("ITestPlugProvider2", Steinberg::Vst::ITestPlugProvider2_iid);
	return 0;
}
