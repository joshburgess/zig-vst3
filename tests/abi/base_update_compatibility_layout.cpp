#include "pluginterfaces/base/iplugincompatibility.h"
#include "pluginterfaces/base/iupdatehandler.h"

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
	std::printf ("IDependent.kWillChange %d\n", Steinberg::IDependent::kWillChange);
	std::printf ("IDependent.kChanged %d\n", Steinberg::IDependent::kChanged);
	std::printf ("IDependent.kDestroyed %d\n", Steinberg::IDependent::kDestroyed);
	std::printf ("IDependent.kWillDestroy %d\n", Steinberg::IDependent::kWillDestroy);
	std::printf ("IDependent.kStdChangeMessageLast %d\n", Steinberg::IDependent::kStdChangeMessageLast);
	std::printf ("kPluginCompatibilityClass %s\n", kPluginCompatibilityClass);

	PRINT_TYPE (IUpdateHandler);
	PRINT_TYPE (IDependent);
	PRINT_TYPE (IPluginCompatibility);

	print_iid ("IUpdateHandler", Steinberg::IUpdateHandler_iid);
	print_iid ("IDependent", Steinberg::IDependent_iid);
	print_iid ("IPluginCompatibility", Steinberg::IPluginCompatibility_iid);
	return 0;
}
