#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "public.sdk/source/vst/vstbypassprocessor.h"

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
	return 0;
}
