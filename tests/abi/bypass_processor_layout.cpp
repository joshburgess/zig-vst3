#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "public.sdk/source/vst/vstbypassprocessor.h"

template <typename T>
struct DelayAccess : Steinberg::Vst::BypassProcessor<T>
{
	using Delay = typename Steinberg::Vst::BypassProcessor<T>::Delay;
};

int main ()
{
	std::printf ("kMaxChannelsSupported %d\n", kMaxChannelsSupported);

	float in32[5] {1.f, 2.f, 3.f, 4.f, 5.f};
	float out32[5] {};
	float delay32[4] {10.f, 20.f, 30.f, 40.f};
	bool result32 = Steinberg::Vst::delay<float> (5, in32, out32, delay32, 4, 2, 0);
	std::printf ("delay32.result %d\n", result32);
	std::printf ("delay32.out0 %.1f\n", out32[0]);
	std::printf ("delay32.out1 %.1f\n", out32[1]);
	std::printf ("delay32.out4 %.1f\n", out32[4]);
	std::printf ("delay32.buffer0 %.1f\n", delay32[0]);
	std::printf ("delay32.buffer3 %.1f\n", delay32[3]);

	double in64[4] {1.5, 2.5, 3.5, 4.5};
	double out64[4] {};
	double delay64[3] {9.5, 8.5, 7.5};
	bool result64 = Steinberg::Vst::delay<double> (4, in64, out64, delay64, 3, 1, 0);
	std::printf ("delay64.result %d\n", result64);
	std::printf ("delay64.out0 %.1f\n", out64[0]);
	std::printf ("delay64.out3 %.1f\n", out64[3]);
	std::printf ("delay64.buffer0 %.1f\n", delay64[0]);
	std::printf ("delay64.buffer2 %.1f\n", delay64[2]);
	DelayAccess<float>::Delay processorDelay32 (5, 3);
	processorDelay32.flush ();
	float delayInput32[5] {1.f, 2.f, 3.f, 4.f, 5.f};
	float delayOutput32[5] {};
	bool silent32 = processorDelay32.process (delayInput32, delayOutput32, 5, false);
	std::printf ("Delay32.hasDelay %d\n", processorDelay32.hasDelay ());
	std::printf ("Delay32.bufferSamples %d\n", processorDelay32.getBufferSamples ());
	std::printf ("Delay32.process.silent %d\n", silent32);
	std::printf ("Delay32.output0 %.1f\n", delayOutput32[0]);
	std::printf ("Delay32.output4 %.1f\n", delayOutput32[4]);
	DelayAccess<float>::Delay noDelay32 (5, 0);
	float noDelayOutput32[3] {};
	bool noDelaySilent32 = noDelay32.process (delayInput32, noDelayOutput32, 3, false);
	std::printf ("Delay32.noDelay.silent %d\n", noDelaySilent32);
	std::printf ("Delay32.noDelay.output2 %.1f\n", noDelayOutput32[2]);
	bool nullSilent32 = noDelay32.process (nullptr, noDelayOutput32, 3, true);
	std::printf ("Delay32.nullInput.silent %d\n", nullSilent32);
	std::printf ("Delay32.nullInput.output2 %.1f\n", noDelayOutput32[2]);
	return 0;
}
