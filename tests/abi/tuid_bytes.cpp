#include "pluginterfaces/base/funknown.h"
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"

#include <cstdio>

static void print_tuid (const char* name, const Steinberg::TUID tuid)
{
	std::printf ("%s", name);
	for (int index = 0; index < 16; ++index)
		std::printf (" %02X", static_cast<unsigned char> (tuid[index]));
	std::printf ("\n");
}

int main ()
{
	print_tuid ("FUnknown", Steinberg::FUnknown_iid);
	print_tuid ("IPluginBase", Steinberg::IPluginBase_iid);
	print_tuid ("IComponent", Steinberg::Vst::IComponent_iid);
	print_tuid ("IAudioProcessor", Steinberg::Vst::IAudioProcessor_iid);
	print_tuid ("IEditController", Steinberg::Vst::IEditController_iid);
	return 0;
}
