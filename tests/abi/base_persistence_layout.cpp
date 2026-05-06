#include "pluginterfaces/base/fvariant.h"
#include "pluginterfaces/base/icloneable.h"
#include "pluginterfaces/base/ipersistent.h"

#include <cstddef>
#include <cstdio>

#define PRINT_TYPE(Type) std::printf (#Type " size %zu align %zu\n", sizeof (Steinberg::Type), alignof (Steinberg::Type))
#define PRINT_OFFSET(Type, Field) std::printf (#Type "." #Field " offset %zu\n", offsetof (Steinberg::Type, Field))

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
	std::printf ("FVariant.kEmpty %u\n", Steinberg::FVariant::kEmpty);
	std::printf ("FVariant.kInteger %u\n", Steinberg::FVariant::kInteger);
	std::printf ("FVariant.kFloat %u\n", Steinberg::FVariant::kFloat);
	std::printf ("FVariant.kString8 %u\n", Steinberg::FVariant::kString8);
	std::printf ("FVariant.kObject %u\n", Steinberg::FVariant::kObject);
	std::printf ("FVariant.kOwner %u\n", Steinberg::FVariant::kOwner);
	std::printf ("FVariant.kString16 %u\n", Steinberg::FVariant::kString16);
	PRINT_TYPE (FVariant);
	PRINT_OFFSET (FVariant, type);
	PRINT_OFFSET (FVariant, intValue);
	PRINT_OFFSET (FVariant, floatValue);
	PRINT_OFFSET (FVariant, string8);
	PRINT_OFFSET (FVariant, string16);
	PRINT_OFFSET (FVariant, object);

	PRINT_TYPE (ICloneable);
	PRINT_TYPE (IPersistent);
	PRINT_TYPE (IAttributes);
	PRINT_TYPE (IAttributes2);
	print_iid ("ICloneable", Steinberg::ICloneable_iid);
	print_iid ("IPersistent", Steinberg::IPersistent_iid);
	print_iid ("IAttributes", Steinberg::IAttributes_iid);
	print_iid ("IAttributes2", Steinberg::IAttributes2_iid);
	return 0;
}
