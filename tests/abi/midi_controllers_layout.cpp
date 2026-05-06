#include "pluginterfaces/vst/ivstmidicontrollers.h"

#include <cstdio>

int main ()
{
	std::printf ("kCtrlBankSelectMSB %d\n", Steinberg::Vst::kCtrlBankSelectMSB);
	std::printf ("kCtrlModWheel %d\n", Steinberg::Vst::kCtrlModWheel);
	std::printf ("kCtrlBreath %d\n", Steinberg::Vst::kCtrlBreath);
	std::printf ("kCtrlFoot %d\n", Steinberg::Vst::kCtrlFoot);
	std::printf ("kCtrlPortaTime %d\n", Steinberg::Vst::kCtrlPortaTime);
	std::printf ("kCtrlDataEntryMSB %d\n", Steinberg::Vst::kCtrlDataEntryMSB);
	std::printf ("kCtrlVolume %d\n", Steinberg::Vst::kCtrlVolume);
	std::printf ("kCtrlBalance %d\n", Steinberg::Vst::kCtrlBalance);
	std::printf ("kCtrlPan %d\n", Steinberg::Vst::kCtrlPan);
	std::printf ("kCtrlExpression %d\n", Steinberg::Vst::kCtrlExpression);
	std::printf ("kCtrlBankSelectLSB %d\n", Steinberg::Vst::kCtrlBankSelectLSB);
	std::printf ("kCtrlSustainOnOff %d\n", Steinberg::Vst::kCtrlSustainOnOff);
	std::printf ("kCtrlSoundVariation %d\n", Steinberg::Vst::kCtrlSoundVariation);
	std::printf ("kCtrlEff1Depth %d\n", Steinberg::Vst::kCtrlEff1Depth);
	std::printf ("kCtrlAllSoundsOff %d\n", Steinberg::Vst::kCtrlAllSoundsOff);
	std::printf ("kAfterTouch %d\n", Steinberg::Vst::kAfterTouch);
	std::printf ("kPitchBend %d\n", Steinberg::Vst::kPitchBend);
	std::printf ("kCountCtrlNumber %d\n", Steinberg::Vst::kCountCtrlNumber);
	std::printf ("kCtrlProgramChange %d\n", Steinberg::Vst::kCtrlProgramChange);
	std::printf ("kSystemActiveSensing %d\n", Steinberg::Vst::kSystemActiveSensing);
	return 0;
}
