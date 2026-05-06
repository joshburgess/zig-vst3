#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/gui/iplugviewcontentscalesupport.h"

#include <cstddef>
#include <cstdio>

#define PRINT_TYPE(Type) std::printf (#Type " size %zu align %zu\n", sizeof (Steinberg::Type), alignof (Steinberg::Type))
#define PRINT_OFFSET(Type, Field) std::printf (#Type "." #Field " offset %zu\n", offsetof (Steinberg::Type, Field))

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
	std::printf ("Platform.kPlatformTypeHWND %s\n", Steinberg::kPlatformTypeHWND);
	std::printf ("Platform.kPlatformTypeHIView %s\n", Steinberg::kPlatformTypeHIView);
	std::printf ("Platform.kPlatformTypeNSView %s\n", Steinberg::kPlatformTypeNSView);
	std::printf ("Platform.kPlatformTypeUIView %s\n", Steinberg::kPlatformTypeUIView);
	std::printf ("Platform.kPlatformTypeX11EmbedWindowID %s\n", Steinberg::kPlatformTypeX11EmbedWindowID);
	std::printf ("Platform.kPlatformTypeWaylandSurfaceID %s\n", Steinberg::kPlatformTypeWaylandSurfaceID);

	PRINT_TYPE (ViewRect);
	PRINT_OFFSET (ViewRect, left);
	PRINT_OFFSET (ViewRect, top);
	PRINT_OFFSET (ViewRect, right);
	PRINT_OFFSET (ViewRect, bottom);

	PRINT_TYPE (IPlugView);
	PRINT_TYPE (IPlugFrame);
	PRINT_TYPE (Linux::IEventHandler);
	PRINT_TYPE (Linux::ITimerHandler);
	PRINT_TYPE (Linux::IRunLoop);
	PRINT_TYPE (IPlugViewContentScaleSupport);

	print_iid ("IPlugView", Steinberg::IPlugView_iid);
	print_iid ("IPlugFrame", Steinberg::IPlugFrame_iid);
	print_iid ("IEventHandler", Steinberg::Linux::IEventHandler_iid);
	print_iid ("ITimerHandler", Steinberg::Linux::ITimerHandler_iid);
	print_iid ("IRunLoop", Steinberg::Linux::IRunLoop_iid);
	print_iid ("IPlugViewContentScaleSupport", Steinberg::IPlugViewContentScaleSupport_iid);
	return 0;
}
