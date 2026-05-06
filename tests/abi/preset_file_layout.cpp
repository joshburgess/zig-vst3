#include "public.sdk/source/vst/vstpresetfile.h"

#include <cstring>
#include <cstdio>
#include <cstddef>

static void printChunkID (const char* label, const Steinberg::Vst::ChunkID& id)
{
	std::printf ("%s %.4s\n", label, id);
}

int main ()
{
	Steinberg::Vst::ChunkID header = {'V', 'S', 'T', '3'};
	Steinberg::Vst::ChunkID componentState = {'C', 'o', 'm', 'p'};
	Steinberg::Vst::ChunkID controllerState = {'C', 'o', 'n', 't'};
	Steinberg::Vst::ChunkID programData = {'P', 'r', 'o', 'g'};
	Steinberg::Vst::ChunkID metaInfo = {'I', 'n', 'f', 'o'};
	Steinberg::Vst::ChunkID chunkList = {'L', 'i', 's', 't'};
	std::printf ("sizeof.ChunkID %zu\n", sizeof (Steinberg::Vst::ChunkID));
	std::printf ("sizeof.Entry %zu\n", sizeof (Steinberg::Vst::PresetFile::Entry));
	std::printf ("alignof.Entry %zu\n", alignof (Steinberg::Vst::PresetFile::Entry));
	std::printf ("offsetof.Entry.id %zu\n", offsetof (Steinberg::Vst::PresetFile::Entry, id));
	std::printf ("offsetof.Entry.offset %zu\n", offsetof (Steinberg::Vst::PresetFile::Entry, offset));
	std::printf ("offsetof.Entry.size %zu\n", offsetof (Steinberg::Vst::PresetFile::Entry, size));
	std::printf ("PresetFile.kMaxEntries %d\n", 128);
	std::printf ("PresetFile.kFormatVersion %d\n", 1);
	std::printf ("PresetFile.kClassIDSize %d\n", 32);
	std::printf ("PresetFile.kHeaderSize %zu\n", sizeof (Steinberg::Vst::ChunkID) + sizeof (Steinberg::int32) + 32 + sizeof (Steinberg::TSize));
	std::printf ("PresetFile.kListOffsetPos %zu\n", sizeof (Steinberg::Vst::ChunkID) + sizeof (Steinberg::int32) + 32);
	std::printf ("ChunkType.kHeader %d\n", Steinberg::Vst::kHeader);
	std::printf ("ChunkType.kComponentState %d\n", Steinberg::Vst::kComponentState);
	std::printf ("ChunkType.kControllerState %d\n", Steinberg::Vst::kControllerState);
	std::printf ("ChunkType.kProgramData %d\n", Steinberg::Vst::kProgramData);
	std::printf ("ChunkType.kMetaInfo %d\n", Steinberg::Vst::kMetaInfo);
	std::printf ("ChunkType.kChunkList %d\n", Steinberg::Vst::kChunkList);
	std::printf ("ChunkType.kNumPresetChunks %d\n", Steinberg::Vst::kNumPresetChunks);
	printChunkID ("ChunkID.kHeader", header);
	printChunkID ("ChunkID.kComponentState", componentState);
	printChunkID ("ChunkID.kControllerState", controllerState);
	printChunkID ("ChunkID.kProgramData", programData);
	printChunkID ("ChunkID.kMetaInfo", metaInfo);
	printChunkID ("ChunkID.kChunkList", chunkList);
	std::printf ("isEqualID.header.header %d\n", std::memcmp (header, header, sizeof (Steinberg::Vst::ChunkID)) == 0);
	std::printf ("isEqualID.header.list %d\n", std::memcmp (header, chunkList, sizeof (Steinberg::Vst::ChunkID)) == 0);
	return 0;
}
