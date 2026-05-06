#include "pluginterfaces/gui/iwaylandframe.h"

#include <cstddef>
#include <cstdio>

#define PRINT_TYPE(Type) std::printf (#Type " size %zu align %zu\n", sizeof (Steinberg::Type), alignof (Steinberg::Type))

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
	PRINT_TYPE (IWaylandHost);
	PRINT_TYPE (IWaylandFrame);

	print_iid ("IWaylandHost", Steinberg::IWaylandHost_iid);
	print_iid ("IWaylandFrame", Steinberg::IWaylandFrame_iid);
	return 0;
}
