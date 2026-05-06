#include "pluginterfaces/vst/ivstdataexchange.h"

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
	std::printf ("InvalidDataExchangeQueueID %u\n", Steinberg::Vst::InvalidDataExchangeQueueID);
	std::printf ("InvalidDataExchangeBlockID %u\n", Steinberg::Vst::InvalidDataExchangeBlockID);

	PRINT_TYPE (DataExchangeBlock);
	PRINT_OFFSET (DataExchangeBlock, data);
	PRINT_OFFSET (DataExchangeBlock, size);
	PRINT_OFFSET (DataExchangeBlock, blockID);

	print_iid ("IDataExchangeHandler", Steinberg::Vst::IDataExchangeHandler_iid);
	print_iid ("IDataExchangeReceiver", Steinberg::Vst::IDataExchangeReceiver_iid);
	return 0;
}
