#include "pluginterfaces/vst/vstspeaker.h"
#include <cstring>
#include "public.sdk/source/vst/vstspeakerarray.h"

#include <cstdio>

int main ()
{
	std::printf ("kSpeakerL %llu\n", static_cast<unsigned long long> (Steinberg::Vst::kSpeakerL));
	std::printf ("kSpeakerR %llu\n", static_cast<unsigned long long> (Steinberg::Vst::kSpeakerR));
	std::printf ("kSpeakerLfe %llu\n", static_cast<unsigned long long> (Steinberg::Vst::kSpeakerLfe));
	std::printf ("kSpeakerTfl %llu\n", static_cast<unsigned long long> (Steinberg::Vst::kSpeakerTfl));
	std::printf ("kSpeakerBfl %llu\n", static_cast<unsigned long long> (Steinberg::Vst::kSpeakerBfl));
	std::printf ("kSpeakerACN24 %llu\n", static_cast<unsigned long long> (Steinberg::Vst::kSpeakerACN24));
	std::printf ("kSpeakerRw %llu\n", static_cast<unsigned long long> (Steinberg::Vst::kSpeakerRw));
	std::printf ("kStereo %llu\n", static_cast<unsigned long long> (Steinberg::Vst::SpeakerArr::kStereo));
	std::printf ("k51 %llu\n", static_cast<unsigned long long> (Steinberg::Vst::SpeakerArr::k51));
	std::printf ("k71Music %llu\n", static_cast<unsigned long long> (Steinberg::Vst::SpeakerArr::k71Music));
	std::printf ("kAmbi1stOrderACN %llu\n", static_cast<unsigned long long> (Steinberg::Vst::SpeakerArr::kAmbi1stOrderACN));
	std::printf ("kAmbi7thOrderACN %llu\n", static_cast<unsigned long long> (Steinberg::Vst::SpeakerArr::kAmbi7thOrderACN));
	std::printf ("k50_4 %llu\n", static_cast<unsigned long long> (Steinberg::Vst::SpeakerArr::k50_4));
	std::printf ("k71_4 %llu\n", static_cast<unsigned long long> (Steinberg::Vst::SpeakerArr::k71_4));
	std::printf ("getChannelCount.k51 %d\n", Steinberg::Vst::SpeakerArr::getChannelCount (Steinberg::Vst::SpeakerArr::k51));
	std::printf ("getSpeakerIndex.R.stereo %d\n", Steinberg::Vst::SpeakerArr::getSpeakerIndex (Steinberg::Vst::kSpeakerR, Steinberg::Vst::SpeakerArr::kStereo));
	std::printf ("getSpeaker.k51.2 %llu\n", static_cast<unsigned long long> (Steinberg::Vst::SpeakerArr::getSpeaker (Steinberg::Vst::SpeakerArr::k51, 2)));
	std::printf ("isSubsetOf.stereo.51 %d\n", Steinberg::Vst::SpeakerArr::isSubsetOf (Steinberg::Vst::SpeakerArr::kStereo, Steinberg::Vst::SpeakerArr::k51));
	std::printf ("hasTopSpeakers.50_4 %d\n", Steinberg::Vst::SpeakerArr::hasTopSpeakers (Steinberg::Vst::SpeakerArr::k50_4));
	std::printf ("hasBottomSpeakers.50_4 %d\n", Steinberg::Vst::SpeakerArr::hasBottomSpeakers (Steinberg::Vst::SpeakerArr::k50_4));
	std::printf ("hasMiddleSpeakers.50_4 %d\n", Steinberg::Vst::SpeakerArr::hasMiddleSpeakers (Steinberg::Vst::SpeakerArr::k50_4));
	std::printf ("hasLfe.51 %d\n", Steinberg::Vst::SpeakerArr::hasLfe (Steinberg::Vst::SpeakerArr::k51));
	std::printf ("is3D.50_4 %d\n", Steinberg::Vst::SpeakerArr::is3D (Steinberg::Vst::SpeakerArr::k50_4));
	std::printf ("isAmbisonics.ambi1 %d\n", Steinberg::Vst::SpeakerArr::isAmbisonics (Steinberg::Vst::SpeakerArr::kAmbi1stOrderACN));
	Steinberg::Vst::SpeakerArray speakerArray (Steinberg::Vst::SpeakerArr::k51);
	std::printf ("SpeakerArray.total.51 %d\n", speakerArray.total ());
	std::printf ("SpeakerArray.at.51.0 %llu\n", static_cast<unsigned long long> (speakerArray.at (0)));
	std::printf ("SpeakerArray.at.51.3 %llu\n", static_cast<unsigned long long> (speakerArray.at (3)));
	std::printf ("SpeakerArray.getArrangement.51 %llu\n", static_cast<unsigned long long> (speakerArray.getArrangement ()));
	std::printf ("SpeakerArray.getSpeakerIndex.Lfe %d\n", speakerArray.getSpeakerIndex (Steinberg::Vst::kSpeakerLfe));
	speakerArray.setArrangement (Steinberg::Vst::SpeakerArr::k50_4);
	std::printf ("SpeakerArray.total.50_4 %d\n", speakerArray.total ());
	std::printf ("SpeakerArray.getArrangement.50_4 %llu\n", static_cast<unsigned long long> (speakerArray.getArrangement ()));
	return 0;
}
