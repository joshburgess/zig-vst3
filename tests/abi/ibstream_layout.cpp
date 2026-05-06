#include "pluginterfaces/base/ibstream.h"

#include <cstddef>
#include <cstdio>

#define PRINT_TYPE(TYPE) \
	std::printf (#TYPE " size %zu align %zu\n", sizeof (TYPE), alignof (TYPE))

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
	PRINT_TYPE (Steinberg::IBStream);
	PRINT_TYPE (Steinberg::ISizeableStream);
	std::printf ("IBStream.kIBSeekSet %d\n", Steinberg::IBStream::kIBSeekSet);
	std::printf ("IBStream.kIBSeekCur %d\n", Steinberg::IBStream::kIBSeekCur);
	std::printf ("IBStream.kIBSeekEnd %d\n", Steinberg::IBStream::kIBSeekEnd);
	print_iid ("IBStream", Steinberg::IBStream_iid);
	print_iid ("ISizeableStream", Steinberg::ISizeableStream_iid);
	return 0;
}
