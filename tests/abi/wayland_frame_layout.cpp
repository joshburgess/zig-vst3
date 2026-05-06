#include "pluginterfaces/gui/iwaylandframe.h"

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
	print_iid ("IWaylandHost", Steinberg::IWaylandHost_iid);
	print_iid ("IWaylandFrame", Steinberg::IWaylandFrame_iid);
	return 0;
}
