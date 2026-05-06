#include "pluginterfaces/vst/ivstinterappaudio.h"

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
	print_iid ("IInterAppAudioHost", Steinberg::Vst::IInterAppAudioHost_iid);
	print_iid ("IInterAppAudioConnectionNotification", Steinberg::Vst::IInterAppAudioConnectionNotification_iid);
	print_iid ("IInterAppAudioPresetManager", Steinberg::Vst::IInterAppAudioPresetManager_iid);
	return 0;
}
