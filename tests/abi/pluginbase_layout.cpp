#include "pluginterfaces/base/ipluginbase.h"

#include <cstddef>
#include <cstdio>

#define PRINT_TYPE(Type) std::printf (#Type " size %zu align %zu\n", sizeof (Steinberg::Type), alignof (Steinberg::Type))
#define PRINT_OFFSET(Type, Field) std::printf (#Type "." #Field " offset %zu\n", offsetof (Steinberg::Type, Field))

int main ()
{
	std::printf ("PFactoryInfo.kURLSize %d\n", Steinberg::PFactoryInfo::kURLSize);
	std::printf ("PFactoryInfo.kEmailSize %d\n", Steinberg::PFactoryInfo::kEmailSize);
	std::printf ("PFactoryInfo.kNameSize %d\n", Steinberg::PFactoryInfo::kNameSize);
	std::printf ("PFactoryInfo.kNoFlags %d\n", Steinberg::PFactoryInfo::kNoFlags);
	std::printf ("PFactoryInfo.kClassesDiscardable %d\n", Steinberg::PFactoryInfo::kClassesDiscardable);
	std::printf ("PFactoryInfo.kLicenseCheck %d\n", Steinberg::PFactoryInfo::kLicenseCheck);
	std::printf ("PFactoryInfo.kComponentNonDiscardable %d\n", Steinberg::PFactoryInfo::kComponentNonDiscardable);
	std::printf ("PFactoryInfo.kUnicode %d\n", Steinberg::PFactoryInfo::kUnicode);
	std::printf ("PClassInfo.kManyInstances %d\n", Steinberg::PClassInfo::kManyInstances);
	std::printf ("PClassInfo.kCategorySize %d\n", Steinberg::PClassInfo::kCategorySize);
	std::printf ("PClassInfo.kNameSize %d\n", Steinberg::PClassInfo::kNameSize);
	std::printf ("PClassInfo2.kVendorSize %d\n", Steinberg::PClassInfo2::kVendorSize);
	std::printf ("PClassInfo2.kVersionSize %d\n", Steinberg::PClassInfo2::kVersionSize);
	std::printf ("PClassInfo2.kSubCategoriesSize %d\n", Steinberg::PClassInfo2::kSubCategoriesSize);
	std::printf ("PClassInfoW.kVendorSize %d\n", Steinberg::PClassInfoW::kVendorSize);
	std::printf ("PClassInfoW.kVersionSize %d\n", Steinberg::PClassInfoW::kVersionSize);
	std::printf ("PClassInfoW.kSubCategoriesSize %d\n", Steinberg::PClassInfoW::kSubCategoriesSize);

	PRINT_TYPE (PFactoryInfo);
	PRINT_OFFSET (PFactoryInfo, vendor);
	PRINT_OFFSET (PFactoryInfo, url);
	PRINT_OFFSET (PFactoryInfo, email);
	PRINT_OFFSET (PFactoryInfo, flags);

	PRINT_TYPE (PClassInfo);
	PRINT_OFFSET (PClassInfo, cid);
	PRINT_OFFSET (PClassInfo, cardinality);
	PRINT_OFFSET (PClassInfo, category);
	PRINT_OFFSET (PClassInfo, name);

	PRINT_TYPE (PClassInfo2);
	PRINT_OFFSET (PClassInfo2, cid);
	PRINT_OFFSET (PClassInfo2, cardinality);
	PRINT_OFFSET (PClassInfo2, category);
	PRINT_OFFSET (PClassInfo2, name);
	PRINT_OFFSET (PClassInfo2, classFlags);
	PRINT_OFFSET (PClassInfo2, subCategories);
	PRINT_OFFSET (PClassInfo2, vendor);
	PRINT_OFFSET (PClassInfo2, version);
	PRINT_OFFSET (PClassInfo2, sdkVersion);

	PRINT_TYPE (PClassInfoW);
	PRINT_OFFSET (PClassInfoW, cid);
	PRINT_OFFSET (PClassInfoW, cardinality);
	PRINT_OFFSET (PClassInfoW, category);
	PRINT_OFFSET (PClassInfoW, name);
	PRINT_OFFSET (PClassInfoW, classFlags);
	PRINT_OFFSET (PClassInfoW, subCategories);
	PRINT_OFFSET (PClassInfoW, vendor);
	PRINT_OFFSET (PClassInfoW, version);
	PRINT_OFFSET (PClassInfoW, sdkVersion);

	return 0;
}
