#include "pluginterfaces/vst/ivstunits.h"

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
	std::printf ("kRootUnitId %d\n", Steinberg::Vst::kRootUnitId);
	std::printf ("kNoParentUnitId %d\n", Steinberg::Vst::kNoParentUnitId);
	std::printf ("kNoProgramListId %d\n", Steinberg::Vst::kNoProgramListId);
	std::printf ("kAllProgramInvalid %d\n", Steinberg::Vst::kAllProgramInvalid);

	PRINT_TYPE (UnitInfo);
	PRINT_OFFSET (UnitInfo, id);
	PRINT_OFFSET (UnitInfo, parentUnitId);
	PRINT_OFFSET (UnitInfo, name);
	PRINT_OFFSET (UnitInfo, programListId);

	PRINT_TYPE (ProgramListInfo);
	PRINT_OFFSET (ProgramListInfo, id);
	PRINT_OFFSET (ProgramListInfo, name);
	PRINT_OFFSET (ProgramListInfo, programCount);

	print_iid ("IUnitHandler", Steinberg::Vst::IUnitHandler_iid);
	print_iid ("IUnitHandler2", Steinberg::Vst::IUnitHandler2_iid);
	print_iid ("IUnitInfo", Steinberg::Vst::IUnitInfo_iid);
	print_iid ("IProgramListData", Steinberg::Vst::IProgramListData_iid);
	print_iid ("IUnitData", Steinberg::Vst::IUnitData_iid);
	return 0;
}
