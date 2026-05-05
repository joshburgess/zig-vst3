#include "pluginterfaces/vst/ivstcontextmenu.h"

#include <cstddef>
#include <cstdio>

#define PRINT_TYPE(Type) std::printf (#Type " size %zu align %zu\n", sizeof (Steinberg::Vst::Type), alignof (Steinberg::Vst::Type))
#define PRINT_OFFSET(Type, Field) std::printf (#Type "." #Field " offset %zu\n", offsetof (Steinberg::Vst::Type, Field))

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
	std::printf ("IContextMenuItem.kIsSeparator %d\n", Steinberg::Vst::IContextMenuItem::kIsSeparator);
	std::printf ("IContextMenuItem.kIsDisabled %d\n", Steinberg::Vst::IContextMenuItem::kIsDisabled);
	std::printf ("IContextMenuItem.kIsChecked %d\n", Steinberg::Vst::IContextMenuItem::kIsChecked);
	std::printf ("IContextMenuItem.kIsGroupStart %d\n", Steinberg::Vst::IContextMenuItem::kIsGroupStart);
	std::printf ("IContextMenuItem.kIsGroupEnd %d\n", Steinberg::Vst::IContextMenuItem::kIsGroupEnd);

	PRINT_TYPE (IContextMenuItem);
	PRINT_OFFSET (IContextMenuItem, name);
	PRINT_OFFSET (IContextMenuItem, tag);
	PRINT_OFFSET (IContextMenuItem, flags);

	print_iid ("IComponentHandler3", Steinberg::Vst::IComponentHandler3_iid);
	print_iid ("IContextMenuTarget", Steinberg::Vst::IContextMenuTarget_iid);
	print_iid ("IContextMenu", Steinberg::Vst::IContextMenu_iid);
	return 0;
}
