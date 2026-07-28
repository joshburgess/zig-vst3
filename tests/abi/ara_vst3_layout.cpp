#include "ARAVST3.h"

#include <cstddef>
#include <cstdio>

DEF_CLASS_IID (ARA::IMainFactory)
DEF_CLASS_IID (ARA::IPlugInEntryPoint)
DEF_CLASS_IID (ARA::IPlugInEntryPoint2)

template <typename T>
static void print_type (const char* name)
{
	std::printf ("%s size %zu align %zu\n", name, sizeof (T), alignof (T));
}

template <typename T>
static void print_iid (const char* name, const T& tuid)
{
	std::printf ("%s iid", name);
	for (int index = 0; index < 16; ++index)
		std::printf (" %02X", static_cast<unsigned char> (tuid[index]));
	std::printf ("\n");
}

class PlugInEntryPointProbe final: public ARA::IPlugInEntryPoint
{
public:
	Steinberg::tresult PLUGIN_API queryInterface (const Steinberg::TUID, void**) override
	{
		return Steinberg::kNoInterface;
	}

	Steinberg::uint32 PLUGIN_API addRef () override
	{
		return 1;
	}

	Steinberg::uint32 PLUGIN_API release () override
	{
		return 1;
	}

	const ARA::ARAFactory* PLUGIN_API getFactory () override
	{
		return reinterpret_cast<const ARA::ARAFactory*> (0x1000);
	}

	const ARA::ARAPlugInExtensionInstance* PLUGIN_API bindToDocumentController (
	    ARA::ARADocumentControllerRef) override
	{
		return reinterpret_cast<const ARA::ARAPlugInExtensionInstance*> (0x2000);
	}
};

int main ()
{
	print_type<ARA::IMainFactory> ("ARA::IMainFactory");
	print_type<ARA::IPlugInEntryPoint> ("ARA::IPlugInEntryPoint");
	print_type<ARA::IPlugInEntryPoint2> ("ARA::IPlugInEntryPoint2");
	print_iid ("ARA::IMainFactory", ARA::IMainFactory::iid);
	print_iid ("ARA::IPlugInEntryPoint", ARA::IPlugInEntryPoint::iid);
	print_iid ("ARA::IPlugInEntryPoint2", ARA::IPlugInEntryPoint2::iid);
	PlugInEntryPointProbe entryPointProbe;
	if ((entryPointProbe.getFactory () !=
	     reinterpret_cast<const ARA::ARAFactory*> (0x1000)) ||
	    (entryPointProbe.bindToDocumentController (nullptr) !=
	     reinterpret_cast<const ARA::ARAPlugInExtensionInstance*> (0x2000)))
		return 1;
	std::printf ("ARA::IPlugInEntryPoint getFactory slot 3 bind slot 4\n");

	print_type<ARA::ARAInterfaceConfiguration> ("ARAInterfaceConfiguration");
	print_type<ARA::ARAFactory> ("ARAFactory");
	print_type<ARA::ARADocumentControllerHostInstance> ("ARADocumentControllerHostInstance");
	print_type<ARA::ARADocumentControllerInterface> ("ARADocumentControllerInterface");
	print_type<ARA::ARADocumentControllerInstance> ("ARADocumentControllerInstance");
	print_type<ARA::ARAPlaybackRegionProperties> ("ARAPlaybackRegionProperties");
	print_type<ARA::ARAPlugInExtensionInstance> ("ARAPlugInExtensionInstance");

	std::printf ("ARAFactory.supportedPlaybackTransformationFlags offset %zu\n",
	             offsetof (ARA::ARAFactory, supportedPlaybackTransformationFlags));
	std::printf ("ARADocumentControllerInterface.destroyContentReader offset %zu\n",
	             offsetof (ARA::ARADocumentControllerInterface, destroyContentReader));
	std::printf ("ARAPlugInExtensionInstance.editorViewInterface offset %zu\n",
	             offsetof (ARA::ARAPlugInExtensionInstance, editorViewInterface));
	std::printf ("ARA generation current %d\n", ARA::kARAAPIGeneration_2_3_Final);
	std::printf ("ARA role flags %d %d %d\n",
	             ARA::kARAPlaybackRendererRole,
	             ARA::kARAEditorRendererRole,
	             ARA::kARAEditorViewRole);
	return 0;
}
