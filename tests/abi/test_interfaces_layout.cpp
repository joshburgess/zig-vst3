#include "pluginterfaces/test/itest.h"

#include <cstddef>
#include <cstdio>

#define PRINT_TYPE(Type) std::printf (#Type " size %zu align %zu\n", sizeof (Steinberg::Type), alignof (Steinberg::Type))

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
	std::printf ("kTestClass %s\n", kTestClass);
	PRINT_TYPE (ITest);
	PRINT_TYPE (ITestResult);
	PRINT_TYPE (ITestSuite);
	PRINT_TYPE (ITestFactory);

	print_iid ("ITest", Steinberg::ITest_iid);
	print_iid ("ITestResult", Steinberg::ITestResult_iid);
	print_iid ("ITestSuite", Steinberg::ITestSuite_iid);
	print_iid ("ITestFactory", Steinberg::ITestFactory_iid);
	return 0;
}
