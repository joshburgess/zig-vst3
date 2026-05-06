#include "pluginterfaces/vst/vstpresetkeys.h"

#include <cstdio>

int main ()
{
	std::printf ("PresetAttributes.kPlugInName %s\n", Steinberg::Vst::PresetAttributes::kPlugInName);
	std::printf ("PresetAttributes.kPlugInCategory %s\n", Steinberg::Vst::PresetAttributes::kPlugInCategory);
	std::printf ("PresetAttributes.kInstrument %s\n", Steinberg::Vst::PresetAttributes::kInstrument);
	std::printf ("PresetAttributes.kStyle %s\n", Steinberg::Vst::PresetAttributes::kStyle);
	std::printf ("PresetAttributes.kCharacter %s\n", Steinberg::Vst::PresetAttributes::kCharacter);
	std::printf ("PresetAttributes.kStateType %s\n", Steinberg::Vst::PresetAttributes::kStateType);
	std::printf ("PresetAttributes.kFilePathStringType %s\n", Steinberg::Vst::PresetAttributes::kFilePathStringType);
	std::printf ("PresetAttributes.kName %s\n", Steinberg::Vst::PresetAttributes::kName);
	std::printf ("PresetAttributes.kFileName %s\n", Steinberg::Vst::PresetAttributes::kFileName);
	std::printf ("StateType.kProject %s\n", Steinberg::Vst::StateType::kProject);
	std::printf ("StateType.kDefault %s\n", Steinberg::Vst::StateType::kDefault);
	std::printf ("StateType.kTrackPreset %s\n", Steinberg::Vst::StateType::kTrackPreset);
	return 0;
}
