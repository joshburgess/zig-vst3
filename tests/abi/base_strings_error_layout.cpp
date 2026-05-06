#include "pluginterfaces/base/ierrorcontext.h"
#include "pluginterfaces/base/istringresult.h"

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
	print_iid ("IStringResult", Steinberg::IStringResult_iid);
	print_iid ("IString", Steinberg::IString_iid);
	print_iid ("IErrorContext", Steinberg::IErrorContext_iid);
	return 0;
}
