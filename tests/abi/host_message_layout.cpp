#include "pluginterfaces/vst/ivsthostapplication.h"

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
	print_iid ("IAttributeList", Steinberg::Vst::IAttributeList_iid);
	print_iid ("IStreamAttributes", Steinberg::Vst::IStreamAttributes_iid);
	print_iid ("IMessage", Steinberg::Vst::IMessage_iid);
	print_iid ("IConnectionPoint", Steinberg::Vst::IConnectionPoint_iid);
	print_iid ("IHostApplication", Steinberg::Vst::IHostApplication_iid);
	print_iid ("IVst3ToVst2Wrapper", Steinberg::Vst::IVst3ToVst2Wrapper_iid);
	print_iid ("IVst3ToAUWrapper", Steinberg::Vst::IVst3ToAUWrapper_iid);
	print_iid ("IVst3ToAAXWrapper", Steinberg::Vst::IVst3ToAAXWrapper_iid);
	print_iid ("IVst3WrapperMPESupport", Steinberg::Vst::IVst3WrapperMPESupport_iid);
	return 0;
}
