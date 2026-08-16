const std = @import("std");
const file_reader_io = @import("file_reader_io.zig");
const file_writer_io = @import("file_writer_io.zig");
const huffman_tables = @import("mp3_huffman_tables.zig");
const mp3_decoder = @import("mp3/decoder.zig");
const mp3_reader = @import("mp3/reader.zig");
const reservoir_support = @import("mp3/reservoir.zig");
const mp3_encoder = @import("mp3_encoder.zig");
const syntax = @import("mp3/syntax.zig");
const synthesis_window_quantized =
    @import("mp3_synthesis_window.zig").values;

pub const Version = syntax.Version;
pub const ChannelMode = syntax.ChannelMode;
pub const maximum_free_format_frame_bytes =
    syntax.maximum_free_format_frame_bytes;
pub const maximum_encoded_frame_bytes =
    syntax.maximum_encoded_frame_bytes;
pub const maximum_encoded_main_data_bytes =
    syntax.maximum_encoded_main_data_bytes;
pub const Limits = syntax.Limits;
pub const default_limits = syntax.default_limits;
const maximum_frame_main_data_bytes =
    syntax.maximum_frame_main_data_bytes;
const decoder_delay_samples = syntax.decoder_delay_samples;
pub const Header = syntax.Header;
const bitrate = syntax.bitrate;
const bitrateIndex = syntax.bitrateIndex;
const sampleRate = syntax.sampleRate;
const sampleRateIndex = syntax.sampleRateIndex;
const headersCompatible = syntax.headersCompatible;
const readU32 = syntax.readU32;
pub const GranuleChannel = syntax.GranuleChannel;
pub const Granule = syntax.Granule;
pub const SideInformation = syntax.SideInformation;
pub const MainData = syntax.MainData;
pub const ScaleFactorChannel = syntax.ScaleFactorChannel;
pub const ScaleFactorGranule = syntax.ScaleFactorGranule;
pub const ScaleFactors = syntax.ScaleFactors;
pub const ScaleFactorBands = syntax.ScaleFactorBands;
pub const QuantizedSpectrum = syntax.QuantizedSpectrum;
pub const RequantizedSpectrum = syntax.RequantizedSpectrum;
pub const StereoSpectrum = syntax.StereoSpectrum;
pub const HybridSamples = syntax.HybridSamples;
pub const PcmGranule = syntax.PcmGranule;
pub const EncoderScaleFactors = syntax.EncoderScaleFactors;
pub const encodeSideInformation = syntax.encodeSideInformation;
const parseSideInformation = syntax.parseSideInformation;
const scaleFactorValueCount = syntax.scaleFactorValueCount;
const scaleFactorLayout = syntax.scaleFactorLayout;
const validateBlockDescription = syntax.validateBlockDescription;
const mixedLongSubbands = syntax.mixedLongSubbands;
const ScaleFactorLayout = syntax.ScaleFactorLayout;
const quantizedMagnitude = syntax.quantizedMagnitude;
const mpeg1_scale_factor_lengths =
    syntax.mpeg1_scale_factor_lengths;
const lsfScaleFactorPlan = syntax.lsfScaleFactorPlan;
const MainDataBitWriter = syntax.MainDataBitWriter;
const MainDataBitReader = syntax.MainDataBitReader;
const byteRangesOverlap = syntax.byteRangesOverlap;
const appendMainDataBits = syntax.appendMainDataBits;
const lsf_scale_factor_counts = syntax.lsf_scale_factor_counts;
const count1_table_a = syntax.count1_table_a;
const decodeMpeg1ScaleFactorChannel =
    syntax.decodeMpeg1ScaleFactorChannel;
const decodeLsfScaleFactorChannel =
    syntax.decodeLsfScaleFactorChannel;
const decodeHuffmanPair = syntax.decodeHuffmanPair;
pub const DecoderFormat = mp3_decoder.DecoderFormat;
pub const HybridSynthesis = mp3_decoder.HybridSynthesis;
pub const PolyphaseSynthesis = mp3_decoder.PolyphaseSynthesis;
pub const FrameDecoder = mp3_decoder.FrameDecoder;
pub const PcmRange = mp3_decoder.PcmRange;
pub const TrimmedPcmFrame = mp3_decoder.TrimmedPcmFrame;
pub const GaplessPlan = mp3_decoder.GaplessPlan;
pub const StreamDecoder = mp3_decoder.StreamDecoder;
pub const requantizeChannel = mp3_decoder.requantizeChannel;
pub const processStereo = mp3_decoder.processStereo;
pub const reduceAliases = mp3_decoder.reduceAliases;
pub const prepareAliasesForEncoding =
    mp3_decoder.prepareAliasesForEncoding;
pub const XingKind = mp3_reader.XingKind;
pub const Xing = mp3_reader.Xing;
pub const Vbri = mp3_reader.Vbri;
pub const VbriSummary = mp3_reader.VbriSummary;
pub const Frame = mp3_reader.Frame;
pub const Summary = mp3_reader.Summary;
pub const SeekPoint = mp3_reader.SeekPoint;
pub const FileFrame = mp3_reader.FileFrame;
pub const FileSummary = mp3_reader.FileSummary;
pub const Stream = mp3_reader.Stream;
pub const FileReader = mp3_reader.FileReader;
pub const requiredSeekPoints = mp3_reader.requiredSeekPoints;
pub const buildSeekIndex = mp3_reader.buildSeekIndex;
pub const findSeekPoint = mp3_reader.findSeekPoint;
pub const requiredFileSeekPoints = mp3_reader.requiredFileSeekPoints;
pub const buildFileSeekIndex = mp3_reader.buildFileSeekIndex;
pub const buildFileSeekIndexTransactional =
    mp3_reader.buildFileSeekIndexTransactional;
const formatFromHeader = mp3_decoder.formatFromHeader;
const mp3SampleRateValid = mp3_decoder.mp3SampleRateValid;
const mp3SamplesPerFrameForRate =
    mp3_decoder.mp3SamplesPerFrameForRate;
const minimumFrameBytes = mp3_reader.minimumFrameBytes;
const crc16 = mp3_reader.crc16;
const referencePolyphaseTimeSlot =
    mp3_decoder.referencePolyphaseTimeSlot;
const analysis_window = mp3_decoder.analysis_window;
const analysis_matrix = mp3_decoder.analysis_matrix;
const analyzeHybridBlock = mp3_decoder.analyzeHybridBlock;
const checkedHybridSample = mp3_decoder.checkedHybridSample;
const mpeg1IntensityGains = mp3_decoder.mpeg1IntensityGains;
const lsfIntensityGains = mp3_decoder.lsfIntensityGains;
const leadingTagBytes = mp3_reader.leadingTagBytes;
const containsNonzero = mp3_decoder.containsNonzero;
const resolvedFrameBytes = mp3_reader.resolvedFrameBytes;
const alias_cs = mp3_decoder.alias_cs;
const alias_ca = mp3_decoder.alias_ca;
const long_imdct = mp3_decoder.long_imdct;
const synthesis_matrix = mp3_decoder.synthesis_matrix;
const frameAtKnownLength = mp3_reader.frameAtKnownLength;
const trailingTagStart = mp3_reader.trailingTagStart;
pub const MainDataReservoir = syntax.MainDataReservoir;
pub const decodeScaleFactors = syntax.decodeScaleFactors;
pub const scaleFactorBands = syntax.scaleFactorBands;
pub const huffmanRegionEnds = syntax.huffmanRegionEnds;
pub const EncodedHuffmanChannel = syntax.EncodedHuffmanChannel;
pub const encodeHuffmanChannel = syntax.encodeHuffmanChannel;
pub const decodeHuffmanChannel = syntax.decodeHuffmanChannel;
pub const EncodedScaleFactors = syntax.EncodedScaleFactors;
pub const encodeScaleFactors = syntax.encodeScaleFactors;
pub const ReservoirQuantizerBudget =
    reservoir_support.ReservoirQuantizerBudget;
pub const ReservoirCreditDecision =
    reservoir_support.ReservoirCreditDecision;
pub const ReservoirCreditTracker =
    reservoir_support.ReservoirCreditTracker;
pub const reservoirQuantizerBudget =
    reservoir_support.reservoirQuantizerBudget;

pub const EncoderConfig = mp3_encoder.EncoderConfig;
pub const FrameEncoder = mp3_encoder.FrameEncoder;
pub const QuantizedFrameParts = mp3_encoder.QuantizedFrameParts;
const StagedQuantizedFrame = mp3_encoder.StagedQuantizedFrame;
pub const QuantizedEncoderChannel = mp3_encoder.QuantizedEncoderChannel;
pub const QuantizedEncoderFrame = mp3_encoder.QuantizedEncoderFrame;
pub const PolyphaseAnalysis = mp3_encoder.PolyphaseAnalysis;
pub const HybridAnalysis = mp3_encoder.HybridAnalysis;
pub const PcmFrame = mp3_encoder.PcmFrame;
pub const EncoderAnalysis = mp3_encoder.EncoderAnalysis;
pub const AnalyzedEncoderChannel = mp3_encoder.AnalyzedEncoderChannel;
pub const AnalyzedEncoderFrame = mp3_encoder.AnalyzedEncoderFrame;
pub const prepareEncoderStereo = mp3_encoder.prepareEncoderStereo;
const encoderIntensityStartBand = mp3_encoder.encoderIntensityStartBand;
const selectEncoderIntensityPosition = mp3_encoder.selectEncoderIntensityPosition;
const encoderIntensityGains = mp3_encoder.encoderIntensityGains;
const validateAnalyzedEncoderFrame = mp3_encoder.validateAnalyzedEncoderFrame;
pub const EncoderBlockClassifier = mp3_encoder.EncoderBlockClassifier;
const hasEncoderAttack = mp3_encoder.hasEncoderAttack;
pub const EncoderPsychoacousticConfig = mp3_encoder.EncoderPsychoacousticConfig;
pub const EncoderPsychoacousticChannel = mp3_encoder.EncoderPsychoacousticChannel;
pub const EncoderPsychoacousticModel = mp3_encoder.EncoderPsychoacousticModel;
pub const EncoderPsychoacousticTimeline = mp3_encoder.EncoderPsychoacousticTimeline;
const validatePsychoacousticHistory = mp3_encoder.validatePsychoacousticHistory;
const validateEncoderPsychoacousticConfig = mp3_encoder.validateEncoderPsychoacousticConfig;
pub const EncoderQuantizer = mp3_encoder.EncoderQuantizer;
pub const PcmEncoder = mp3_encoder.PcmEncoder;
pub const PcmReservoirBatchResult = mp3_encoder.PcmReservoirBatchResult;
pub const requiredPcmReservoirBatchFrameBytes = mp3_encoder.requiredPcmReservoirBatchFrameBytes;
pub const encodePcmReservoirBatch = mp3_encoder.encodePcmReservoirBatch;
pub const requiredPcmAdaptiveReservoirStorage = mp3_encoder.requiredPcmAdaptiveReservoirStorage;
pub const PcmAdaptiveReservoirAppend = mp3_encoder.PcmAdaptiveReservoirAppend;
pub const PcmAdaptiveReservoirFinish = mp3_encoder.PcmAdaptiveReservoirFinish;
pub const PcmAdaptiveReservoirStreamEncoder = mp3_encoder.PcmAdaptiveReservoirStreamEncoder;
pub const PcmAdaptiveReservoirGaplessFinish = mp3_encoder.PcmAdaptiveReservoirGaplessFinish;
pub const PcmAdaptiveReservoirGaplessStreamEncoder = mp3_encoder.PcmAdaptiveReservoirGaplessStreamEncoder;
const Mp3StorageRange = mp3_encoder.Mp3StorageRange;
const validateAdaptiveGaplessStartStorage = mp3_encoder.validateAdaptiveGaplessStartStorage;
const validateAdaptiveGaplessFinishStorage = mp3_encoder.validateAdaptiveGaplessFinishStorage;
const validateDisjointMp3Storage = mp3_encoder.validateDisjointMp3Storage;
const validateAdaptiveReservoirStorage = mp3_encoder.validateAdaptiveReservoirStorage;
pub const PcmAdaptiveReservoirFileSummary = mp3_encoder.PcmAdaptiveReservoirFileSummary;
pub const PcmAdaptiveReservoirFileEncoder = mp3_encoder.PcmAdaptiveReservoirFileEncoder;
pub const PcmAdaptiveReservoirGaplessFileSummary = mp3_encoder.PcmAdaptiveReservoirGaplessFileSummary;
pub const PcmAdaptiveReservoirGaplessFileEncoder = mp3_encoder.PcmAdaptiveReservoirGaplessFileEncoder;
const requiredAdaptiveGaplessFileFinishStorage = mp3_encoder.requiredAdaptiveGaplessFileFinishStorage;
const validateAdaptiveGaplessFileStorage = mp3_encoder.validateAdaptiveGaplessFileStorage;
const validateAdaptiveReservoirFileStorage = mp3_encoder.validateAdaptiveReservoirFileStorage;
pub const VbrEncoderConfig = mp3_encoder.VbrEncoderConfig;
pub const VbrPcmFrame = mp3_encoder.VbrPcmFrame;
pub const VbrPcmFrameParts = mp3_encoder.VbrPcmFrameParts;
pub const VbrPcmEncoder = mp3_encoder.VbrPcmEncoder;
pub const VbrPcmReservoirBatchResult = mp3_encoder.VbrPcmReservoirBatchResult;
pub const encodeVbrPcmReservoirBatch = mp3_encoder.encodeVbrPcmReservoirBatch;
pub const PcmReservoirGaplessBatchResult = mp3_encoder.PcmReservoirGaplessBatchResult;
pub const VbrPcmReservoirGaplessBatchResult = mp3_encoder.VbrPcmReservoirGaplessBatchResult;
pub const encodePcmReservoirGaplessBatch = mp3_encoder.encodePcmReservoirGaplessBatch;
pub const encodeVbrPcmReservoirGaplessBatch = mp3_encoder.encodeVbrPcmReservoirGaplessBatch;
const GaplessReservoirBatchStorage = mp3_encoder.GaplessReservoirBatchStorage;
const validateGaplessReservoirBatchStorage = mp3_encoder.validateGaplessReservoirBatchStorage;
const adaptiveGaplessFlushFrames = mp3_encoder.adaptiveGaplessFlushFrames;
const adaptiveGaplessSummary = mp3_encoder.adaptiveGaplessSummary;
pub const requiredVbrPcmAdaptiveReservoirStorage = mp3_encoder.requiredVbrPcmAdaptiveReservoirStorage;
pub const requiredPcmAdaptiveReservoirGaplessFileFinishStorage = mp3_encoder.requiredPcmAdaptiveReservoirGaplessFileFinishStorage;
pub const requiredVbrPcmAdaptiveReservoirGaplessFileFinishStorage = mp3_encoder.requiredVbrPcmAdaptiveReservoirGaplessFileFinishStorage;
pub const requiredVbrPcmAdaptiveReservoirGaplessFrameOffsets = mp3_encoder.requiredVbrPcmAdaptiveReservoirGaplessFrameOffsets;
pub const VbrPcmAdaptiveReservoirAppend = mp3_encoder.VbrPcmAdaptiveReservoirAppend;
pub const VbrPcmAdaptiveReservoirFinish = mp3_encoder.VbrPcmAdaptiveReservoirFinish;
pub const VbrPcmAdaptiveReservoirStreamEncoder = mp3_encoder.VbrPcmAdaptiveReservoirStreamEncoder;
pub const VbrPcmAdaptiveReservoirGaplessFinish = mp3_encoder.VbrPcmAdaptiveReservoirGaplessFinish;
pub const VbrPcmAdaptiveReservoirGaplessStreamEncoder = mp3_encoder.VbrPcmAdaptiveReservoirGaplessStreamEncoder;
pub const VbrPcmAdaptiveReservoirFileSummary = mp3_encoder.VbrPcmAdaptiveReservoirFileSummary;
pub const VbrPcmAdaptiveReservoirFileEncoder = mp3_encoder.VbrPcmAdaptiveReservoirFileEncoder;
pub const VbrPcmAdaptiveReservoirGaplessFileSummary = mp3_encoder.VbrPcmAdaptiveReservoirGaplessFileSummary;
pub const VbrPcmAdaptiveReservoirGaplessFileEncoder = mp3_encoder.VbrPcmAdaptiveReservoirGaplessFileEncoder;
const validateMp3FrameOffsetStorage = mp3_encoder.validateMp3FrameOffsetStorage;
const mp3FrameOffsetSlicesOverlap = mp3_encoder.mp3FrameOffsetSlicesOverlap;
const validateIndexedMp3FrameOffsets = mp3_encoder.validateIndexedMp3FrameOffsets;
const validateIndexedVbrFrameSpans = mp3_encoder.validateIndexedVbrFrameSpans;
const recordMp3FileFrameOffsets = mp3_encoder.recordMp3FileFrameOffsets;
const xingTocFromFrameOffsets = mp3_encoder.xingTocFromFrameOffsets;
pub const PcmReservoirBatchFileResult = mp3_encoder.PcmReservoirBatchFileResult;
pub const VbrPcmReservoirBatchFileResult = mp3_encoder.VbrPcmReservoirBatchFileResult;
pub const PcmReservoirGaplessBatchFileResult = mp3_encoder.PcmReservoirGaplessBatchFileResult;
pub const VbrPcmReservoirGaplessBatchFileResult = mp3_encoder.VbrPcmReservoirGaplessBatchFileResult;
pub const writePcmReservoirGaplessBatchFile = mp3_encoder.writePcmReservoirGaplessBatchFile;
pub const writePcmReservoirGaplessBatchFileWithOperations = mp3_encoder.writePcmReservoirGaplessBatchFileWithOperations;
pub const writeVbrPcmReservoirGaplessBatchFile = mp3_encoder.writeVbrPcmReservoirGaplessBatchFile;
pub const writeVbrPcmReservoirGaplessBatchFileWithOperations = mp3_encoder.writeVbrPcmReservoirGaplessBatchFileWithOperations;
pub const writePcmReservoirBatchFile = mp3_encoder.writePcmReservoirBatchFile;
pub const writePcmReservoirBatchFileWithOperations = mp3_encoder.writePcmReservoirBatchFileWithOperations;
pub const writeVbrPcmReservoirBatchFile = mp3_encoder.writeVbrPcmReservoirBatchFile;
pub const writeVbrPcmReservoirBatchFileWithOperations = mp3_encoder.writeVbrPcmReservoirBatchFileWithOperations;
pub const writePcmReservoirBatchFileWithInfo = mp3_encoder.writePcmReservoirBatchFileWithInfo;
pub const writePcmReservoirBatchFileWithInfoAndOperations = mp3_encoder.writePcmReservoirBatchFileWithInfoAndOperations;
pub const writeVbrPcmReservoirBatchFileWithXing = mp3_encoder.writeVbrPcmReservoirBatchFileWithXing;
const reservoirBatchXingToc = mp3_encoder.reservoirBatchXingToc;
const writeReservoirBatchBytes = mp3_encoder.writeReservoirBatchBytes;
const writeReservoirBatchFileBytes = mp3_encoder.writeReservoirBatchFileBytes;
const encoderNoiseToMaskRatio = mp3_encoder.encoderNoiseToMaskRatio;
pub const VbrPcmStreamFinish = mp3_encoder.VbrPcmStreamFinish;
pub const VbrPcmStreamEncoder = mp3_encoder.VbrPcmStreamEncoder;
pub const ReservoirRepackRequirements = mp3_encoder.ReservoirRepackRequirements;
pub const ReservoirRepackResult = mp3_encoder.ReservoirRepackResult;
pub const reservoirRepackRequirements = mp3_encoder.reservoirRepackRequirements;
const reservoirPackingRequirements = mp3_encoder.reservoirPackingRequirements;
pub const repackMainDataReservoir = mp3_encoder.repackMainDataReservoir;
pub const packMainDataReservoir = mp3_encoder.packMainDataReservoir;
const packMainDataReservoirStaged = mp3_encoder.packMainDataReservoirStaged;
const ReservoirMainDataWriter = mp3_encoder.ReservoirMainDataWriter;
const setFrameMainDataBegin = mp3_encoder.setFrameMainDataBegin;
pub const PcmReservoirAppend = mp3_encoder.PcmReservoirAppend;
pub const PcmReservoirEncoder = mp3_encoder.PcmReservoirEncoder;
pub const VbrPcmReservoirSelection = mp3_encoder.VbrPcmReservoirSelection;
pub const VbrPcmReservoirAppend = mp3_encoder.VbrPcmReservoirAppend;
pub const VbrPcmReservoirEncoder = mp3_encoder.VbrPcmReservoirEncoder;
pub const VbrPcmReservoirStreamFinish = mp3_encoder.VbrPcmReservoirStreamFinish;
pub const VbrPcmReservoirStreamEncoder = mp3_encoder.VbrPcmReservoirStreamEncoder;
const validatePendingReservoirFrame = mp3_encoder.validatePendingReservoirFrame;
const reservoirBorrowedBytesValid = mp3_encoder.reservoirBorrowedBytesValid;
const reservoirPendingBorrowedBytesValid = mp3_encoder.reservoirPendingBorrowedBytesValid;
const borrowMainData = mp3_encoder.borrowMainData;
const frameMainDataOffset = mp3_encoder.frameMainDataOffset;
const frameXingOffset = mp3_encoder.frameXingOffset;
pub const PcmReservoirStreamFinish = mp3_encoder.PcmReservoirStreamFinish;
pub const PcmReservoirStreamEncoder = mp3_encoder.PcmReservoirStreamEncoder;
pub const EncoderStreamSummary = mp3_encoder.EncoderStreamSummary;
pub const PcmStreamFinish = mp3_encoder.PcmStreamFinish;
pub const PcmStreamEncoder = mp3_encoder.PcmStreamEncoder;
pub const encodeInfoFrame = mp3_encoder.encodeInfoFrame;
pub const encodeInfoFrameWithEncoder = mp3_encoder.encodeInfoFrameWithEncoder;
const storedXingEncoderDelay = mp3_encoder.storedXingEncoderDelay;
const storedXingEncoderPadding = mp3_encoder.storedXingEncoderPadding;
pub const default_xing_encoder_identifier = mp3_encoder.default_xing_encoder_identifier;
pub const XingEncoderMetadata = mp3_encoder.XingEncoderMetadata;
pub const VbriEncoderMetadata = mp3_encoder.VbriEncoderMetadata;
pub const encodeXingFrame = mp3_encoder.encodeXingFrame;
pub const encodeVbriFrame = mp3_encoder.encodeVbriFrame;
pub const requiredVbriTocBytes = mp3_encoder.requiredVbriTocBytes;
pub const buildVbriToc = mp3_encoder.buildVbriToc;
pub const VbriStreamMetadataResult = mp3_encoder.VbriStreamMetadataResult;
pub const finalizeVbriStreamMetadata = mp3_encoder.finalizeVbriStreamMetadata;
const encodeInfoFrameFields = mp3_encoder.encodeInfoFrameFields;
const encodeXingFrameFields = mp3_encoder.encodeXingFrameFields;
const validateXingEncoderIdentifier = mp3_encoder.validateXingEncoderIdentifier;
const isValidXingEncoderIdentifier = mp3_encoder.isValidXingEncoderIdentifier;
const EncoderByteState = mp3_encoder.EncoderByteState;
const encoderByteState = mp3_encoder.encoderByteState;
pub const writeId3v2FilePrefix = mp3_encoder.writeId3v2FilePrefix;
const writeId3v2FilePrefixWithOperations = mp3_encoder.writeId3v2FilePrefixWithOperations;
pub const appendId3v1FileTail = mp3_encoder.appendId3v1FileTail;
const appendId3v1FileTailWithOperations = mp3_encoder.appendId3v1FileTailWithOperations;
pub const PcmFileEncoder = mp3_encoder.PcmFileEncoder;
pub const VbrPcmFileSummary = mp3_encoder.VbrPcmFileSummary;
pub const VbrPcmFileEncoder = mp3_encoder.VbrPcmFileEncoder;
pub const PcmReservoirFileSummary = mp3_encoder.PcmReservoirFileSummary;
pub const VbrPcmReservoirFileSummary = mp3_encoder.VbrPcmReservoirFileSummary;
pub const VbrPcmReservoirFileEncoder = mp3_encoder.VbrPcmReservoirFileEncoder;
pub const PcmReservoirFileEncoder = mp3_encoder.PcmReservoirFileEncoder;
const emittedReservoirBytes = mp3_encoder.emittedReservoirBytes;
const emittedVbrReservoirBytes = mp3_encoder.emittedVbrReservoirBytes;
const initPcmFileEncoder = mp3_encoder.initPcmFileEncoder;
const initVbrPcmFileEncoder = mp3_encoder.initVbrPcmFileEncoder;
const restoreVbrOffsets = mp3_encoder.restoreVbrOffsets;
const initPcmReservoirFileEncoder = mp3_encoder.initPcmReservoirFileEncoder;
const initVbrPcmReservoirFileEncoder = mp3_encoder.initVbrPcmReservoirFileEncoder;
const fileEncoderOffset = mp3_encoder.fileEncoderOffset;
const encoder_analysis_delay = mp3_encoder.encoder_analysis_delay;
const validatePcmEncoderStereo = mp3_encoder.validatePcmEncoderStereo;
const quantizeEncoderChannel = mp3_encoder.quantizeEncoderChannel;
const quantizeEncoderBand = mp3_encoder.quantizeEncoderBand;
const orderEncoderSpectrum = mp3_encoder.orderEncoderSpectrum;
const restoreEncoderSpectrumOrder = mp3_encoder.restoreEncoderSpectrumOrder;
const EncoderBandLayout = mp3_encoder.EncoderBandLayout;
const encoderBandLayout = mp3_encoder.encoderBandLayout;
const encoderScaleFactorWidths = mp3_encoder.encoderScaleFactorWidths;
const EncoderHuffmanSelection = mp3_encoder.EncoderHuffmanSelection;
const selectEncoderHuffman = mp3_encoder.selectEncoderHuffman;
const EncoderRegionSelection = mp3_encoder.EncoderRegionSelection;
const selectShortEncoderTables = mp3_encoder.selectShortEncoderTables;
const selectSwitchedLongEncoderTables = mp3_encoder.selectSwitchedLongEncoderTables;
const selectLongEncoderTables = mp3_encoder.selectLongEncoderTables;
const EncoderTableSelection = mp3_encoder.EncoderTableSelection;
const selectEncoderTable = mp3_encoder.selectEncoderTable;
const encoderPairBitCost = mp3_encoder.encoderPairBitCost;
const encoderCount1BitCost = mp3_encoder.encoderCount1BitCost;
const Mp3FileFaults = mp3_encoder.Mp3FileFaults;
const testHeader = mp3_encoder.testHeader;
const setTestBits = mp3_encoder.setTestBits;
const setMpeg1MonoLongChannel = mp3_encoder.setMpeg1MonoLongChannel;
const readTestI16 = mp3_encoder.readTestI16;
const appendFrame = mp3_encoder.appendFrame;
const appendFreeFormatFrame = mp3_encoder.appendFreeFormatFrame;
const repairTestFrameCrc = mp3_encoder.repairTestFrameCrc;
fn headerStateValid(header: Header) bool {
    if (sampleRateIndex(header.version, header.sample_rate) == null)
        return false;
    if (header.free_format) return header.bitrate_kbps == 0;
    return bitrateIndex(header.version, header.bitrate_kbps) != null;
}

test "serializes every supported MP3 encoder header" {
    const versions = [_]Version{ .mpeg1, .mpeg2, .mpeg25 };
    const modes = [_]ChannelMode{
        .stereo,
        .joint_stereo,
        .dual_channel,
        .mono,
    };
    for (versions) |version| {
        for (0..3) |rate_index_value| {
            const rate_index: u2 = @intCast(rate_index_value);
            for (1..15) |bitrate_index_value| {
                const bitrate_index: u4 =
                    @intCast(bitrate_index_value);
                for (modes) |mode| {
                    for ([_]bool{ false, true }) |crc_present| {
                        const header = Header{
                            .version = version,
                            .crc_present = crc_present,
                            .free_format = false,
                            .bitrate_kbps = bitrate(
                                version,
                                bitrate_index,
                            ),
                            .sample_rate = sampleRate(
                                version,
                                rate_index,
                            ),
                            .padding = true,
                            .private = true,
                            .channel_mode = mode,
                            .mode_extension = 3,
                            .copyright = true,
                            .original = true,
                            .emphasis = 3,
                        };
                        try std.testing.expectEqual(
                            header,
                            try Header.parse(&try header.encode()),
                        );
                    }
                }
            }
        }
    }

    const free = Header{
        .version = .mpeg1,
        .crc_present = false,
        .free_format = true,
        .bitrate_kbps = 0,
        .sample_rate = 44_100,
        .padding = false,
        .private = false,
        .channel_mode = .stereo,
        .mode_extension = 0,
        .copyright = false,
        .original = false,
        .emphasis = 0,
    };
    try std.testing.expectEqual(
        free,
        try Header.parse(&try free.encode()),
    );
}

test "encodes transactional CBR silent MP3 frames" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
        .private = true,
        .copyright = true,
        .original = true,
        .emphasis = 1,
    };
    var encoder = try FrameEncoder.init(config);
    var decoder = FrameDecoder{};
    var storage: [maximum_encoded_frame_bytes]u8 = undefined;
    var encoded_bytes: usize = 0;
    var padded_frames: usize = 0;
    for (0..100) |_| {
        const expected_bytes = try encoder.nextFrameBytes();
        const frame_bytes =
            try encoder.encodeSilentFrame(&storage);
        try std.testing.expectEqual(expected_bytes, frame_bytes.len);
        const frame = try Frame.parse(frame_bytes, 0);
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
        const side = try frame.sideInformation();
        try std.testing.expectEqual(@as(u16, 0), side.main_data_bits);
        padded_frames += @intFromBool(frame.header.padding);
        encoded_bytes += frame_bytes.len;

        const decoded = try decoder.decode(frame);
        try std.testing.expectEqual(@as(u2, 1), decoded.channel_count);
        try std.testing.expectEqual(@as(u16, 1152), decoded.sample_count);
        for (decoded.channels[0]) |sample|
            try std.testing.expectEqual(@as(f32, 0), sample);
    }
    try std.testing.expectEqual(@as(usize, 95), padded_frames);
    try std.testing.expectEqual(
        @as(usize, 41_795),
        encoded_bytes,
    );
    try std.testing.expectEqual(@as(u64, 100), encoder.frames_encoded);

    encoder.reset();
    try std.testing.expectEqual(@as(u64, 0), encoder.frames_encoded);
    try std.testing.expectEqual(
        @as(u32, 0),
        encoder.padding_accumulator,
    );
    try std.testing.expectEqual(@as(usize, 417), try encoder.nextFrameBytes());
}

test "encodes nonzero quantized MP3 frames through the decoder" {
    var encoder = try FrameEncoder.init(.{
        .channel_mode = .mono,
        .crc_present = true,
    });
    var source = QuantizedEncoderFrame{};
    source.private_bits = 7;
    source.scfsi[0] = 0xf;
    source.granules[0][0].description = .{
        .big_values = 1,
        .global_gain = 210,
        .scalefac_compress = 5,
        .table_select = @splat(1),
        .region0_count = 7,
        .region1_count = 5,
    };
    source.granules[0][0].scale_factors.value_count = 22;
    source.granules[0][0].scale_factors.values[0] = 1;
    source.granules[0][0].spectrum[0] = 1;
    source.granules[0][0].spectrum[1] = -1;
    source.granules[1][0].description = .{
        .global_gain = 210,
        .scalefac_compress = 5,
        .region0_count = 7,
        .region1_count = 5,
        .count1_table_select = true,
    };
    source.granules[1][0].scale_factors =
        source.granules[0][0].scale_factors;
    source.granules[1][0].spectrum[0] = 1;
    source.granules[1][0].spectrum[2] = -1;
    source.granules[1][0].spectrum[3] = 1;

    var storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const encoded = try encoder.encodeQuantizedFrame(
        &source,
        &storage,
    );
    const parsed = try Frame.parse(encoded, 0);
    try std.testing.expectEqual(
        @as(?bool, true),
        try parsed.crcValid(),
    );
    const side = try parsed.sideInformation();
    try std.testing.expectEqual(@as(u5, 7), side.private_bits);
    try std.testing.expectEqual(@as(u4, 0xf), side.scfsi[0]);
    try std.testing.expect(side.main_data_bits > 0);
    try std.testing.expectEqual(
        side.main_data_bits,
        side.granules[0].channels[0].part2_3_length +
            side.granules[1].channels[0].part2_3_length,
    );

    var reservoir = MainDataReservoir(511){};
    var main_storage: [512]u8 = undefined;
    const main_data = try reservoir.assemble(
        parsed,
        &main_storage,
    );
    const factors = try decodeScaleFactors(
        parsed.header,
        side,
        main_data,
    );
    try std.testing.expectEqual(
        @as(u8, 1),
        factors.granules[0].channels[0].values[0],
    );
    try std.testing.expectEqual(
        factors.granules[0].channels[0].values,
        factors.granules[1].channels[0].values,
    );
    try std.testing.expectEqual(
        @as(u12, 21),
        factors.granules[0].channels[0].part2_bits,
    );
    try std.testing.expectEqual(
        @as(u12, 0),
        factors.granules[1].channels[0].part2_bits,
    );
    const first_spectrum = try decodeHuffmanChannel(
        parsed.header,
        side.granules[0].channels[0],
        factors.granules[0].channels[0],
        main_data,
    );
    try std.testing.expectEqualSlices(
        i32,
        source.granules[0][0].spectrum[0..2],
        first_spectrum.lines[0..2],
    );
    const second_spectrum = try decodeHuffmanChannel(
        parsed.header,
        side.granules[1].channels[0],
        factors.granules[1].channels[0],
        main_data,
    );
    try std.testing.expectEqualSlices(
        i32,
        source.granules[1][0].spectrum[0..4],
        second_spectrum.lines[0..4],
    );

    var decoder = FrameDecoder{};
    const pcm = try decoder.decode(parsed);
    var nonzero = false;
    for (pcm.channels[0]) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        nonzero = nonzero or sample != 0;
    }
    try std.testing.expect(nonzero);
}

test "rejects oversized and malformed quantized MP3 frames" {
    var encoder = try FrameEncoder.init(.{
        .version = .mpeg2,
        .bitrate_kbps = 8,
        .sample_rate = 24_000,
        .channel_mode = .stereo,
    });
    var source = QuantizedEncoderFrame{};
    for (0..2) |channel| {
        source.granules[0][channel].description = .{
            .big_values = 288,
            .global_gain = 210,
            .table_select = @splat(13),
            .region0_count = 7,
            .region1_count = 5,
        };
        source.granules[0][channel].spectrum = @splat(15);
    }
    const before = encoder;
    var storage: [maximum_encoded_frame_bytes]u8 = @splat(0x5a);
    try std.testing.expectError(
        error.Mp3HuffmanBitCountOverflow,
        encoder.encodeQuantizedFrame(&source, &storage),
    );
    try std.testing.expectEqual(before, encoder);
    try std.testing.expectEqualSlices(
        u8,
        &(@as(
            [maximum_encoded_frame_bytes]u8,
            @splat(0x5a),
        )),
        &storage,
    );

    source = .{};
    source.granules[0][0].description.scalefac_compress = 1;
    source.granules[0][0].scale_factors.values[0] = 1;
    try std.testing.expectError(
        error.InvalidMp3EncoderScaleFactorValue,
        encoder.encodeQuantizedFrame(&source, &storage),
    );

    source = .{};
    source.granules[1][0].spectrum[0] = 1;
    try std.testing.expectError(
        error.InvalidMp3EncoderFrame,
        encoder.encodeQuantizedFrame(&source, &storage),
    );
}

test "encodes silence for every MP3 version and rejects hostile state" {
    const configs = [_]EncoderConfig{
        .{
            .version = .mpeg1,
            .bitrate_kbps = 320,
            .sample_rate = 32_000,
            .channel_mode = .stereo,
        },
        .{
            .version = .mpeg2,
            .bitrate_kbps = 8,
            .sample_rate = 24_000,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .{
            .version = .mpeg25,
            .bitrate_kbps = 160,
            .sample_rate = 8_000,
            .channel_mode = .dual_channel,
        },
    };
    for (configs) |config| {
        var encoder = try FrameEncoder.init(config);
        var storage: [maximum_encoded_frame_bytes]u8 = undefined;
        const encoded = try encoder.encodeSilentFrame(&storage);
        const frame = try Frame.parse(encoded, 0);
        try std.testing.expectEqual(config.version, frame.header.version);
        try std.testing.expectEqual(
            config.channel_mode,
            frame.header.channel_mode,
        );
        try std.testing.expectEqual(
            config.crc_present,
            frame.header.crc_present,
        );
        var decoder = FrameDecoder{};
        const decoded = try decoder.decode(frame);
        try std.testing.expectEqual(
            frame.header.samplesPerFrame(),
            decoded.sample_count,
        );
    }

    try std.testing.expectError(
        error.InvalidMp3EncoderBitrate,
        FrameEncoder.init(.{ .bitrate_kbps = 17 }),
    );
    try std.testing.expectError(
        error.InvalidMp3EncoderSampleRate,
        FrameEncoder.init(.{ .sample_rate = 96_000 }),
    );
    try std.testing.expectError(
        error.InvalidMp3EncoderEmphasis,
        FrameEncoder.init(.{ .emphasis = 2 }),
    );

    var encoder = try FrameEncoder.init(.{});
    try std.testing.expect(encoder.valid());
    const before = encoder;
    var short: [16]u8 = @splat(0x5a);
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encoder.encodeSilentFrame(&short),
    );
    try std.testing.expectEqual(before, encoder);
    try std.testing.expectEqualSlices(
        u8,
        &(@as([16]u8, @splat(0x5a))),
        &short,
    );

    encoder.padding_accumulator = encoder.config.sample_rate;
    const hostile = encoder;
    try std.testing.expect(!encoder.valid());
    var storage: [maximum_encoded_frame_bytes]u8 = @splat(0x33);
    try std.testing.expectError(
        error.InvalidMp3EncoderState,
        encoder.encodeSilentFrame(&storage),
    );
    try std.testing.expectEqual(hostile, encoder);
    try std.testing.expectEqualSlices(
        u8,
        &(@as(
            [maximum_encoded_frame_bytes]u8,
            @splat(0x33),
        )),
        &storage,
    );
    encoder.reset();
    try std.testing.expect(encoder.valid());
}

test "parses MPEG Layer III versions, CRC, padding, and frame sizes" {
    const mpeg1 = try Header.parse(&testHeader(
        3,
        false,
        9,
        0,
        false,
        .stereo,
    ));
    try std.testing.expectEqual(Version.mpeg1, mpeg1.version);
    try std.testing.expect(mpeg1.crc_present);
    try std.testing.expectEqual(@as(u16, 128), mpeg1.bitrate_kbps);
    try std.testing.expectEqual(@as(u32, 44_100), mpeg1.sample_rate);
    try std.testing.expectEqual(@as(usize, 417), mpeg1.frameBytes());
    try std.testing.expectEqual(@as(u16, 1152), mpeg1.samplesPerFrame());
    try std.testing.expectEqual(@as(u8, 32), mpeg1.sideInformationBytes());

    const mpeg2 = try Header.parse(&testHeader(
        2,
        true,
        8,
        0,
        true,
        .mono,
    ));
    try std.testing.expectEqual(Version.mpeg2, mpeg2.version);
    try std.testing.expect(!mpeg2.crc_present);
    try std.testing.expectEqual(@as(u16, 64), mpeg2.bitrate_kbps);
    try std.testing.expectEqual(@as(u32, 22_050), mpeg2.sample_rate);
    try std.testing.expectEqual(@as(usize, 209), mpeg2.frameBytes());
    try std.testing.expectEqual(@as(u16, 576), mpeg2.samplesPerFrame());
    try std.testing.expectEqual(@as(u8, 9), mpeg2.sideInformationBytes());

    const mpeg25 = try Header.parse(&testHeader(
        0,
        true,
        1,
        2,
        false,
        .joint_stereo,
    ));
    try std.testing.expectEqual(@as(u32, 8_000), mpeg25.sample_rate);
    try std.testing.expectEqual(@as(u16, 8), mpeg25.bitrate_kbps);
    try std.testing.expectEqual(@as(usize, 72), mpeg25.frameBytes());
}

test "validates protected Layer III header and side information" {
    const protected_header =
        testHeader(3, false, 9, 0, false, .stereo);
    var encoded: [500]u8 = undefined;
    const frame_end = try appendFrame(
        &encoded,
        0,
        protected_header,
    );
    for (encoded[6..38], 0..) |*byte, index|
        byte.* = @intCast(index);
    encoded[4] = 0x65;
    encoded[5] = 0xe8;

    var frame = try Frame.parse(encoded[0..frame_end], 0);
    try std.testing.expectEqual(@as(?bool, true), try frame.crcValid());
    const file_frame = FileFrame{
        .byte_offset = 0,
        .bytes = frame.bytes,
        .header = frame.header,
        .xing = frame.xing,
        .vbri = frame.vbri,
    };
    try std.testing.expectEqual(
        @as(?bool, true),
        try file_frame.crcValid(),
    );

    encoded[20] ^= 1;
    frame = try Frame.parse(encoded[0..frame_end], 0);
    try std.testing.expectEqual(@as(?bool, false), try frame.crcValid());
    encoded[20] ^= 1;
    encoded[38] ^= 1;
    frame = try Frame.parse(encoded[0..frame_end], 0);
    try std.testing.expectEqual(@as(?bool, true), try frame.crcValid());

    const unprotected_header =
        testHeader(3, true, 9, 0, false, .stereo);
    const unprotected_end = try appendFrame(
        &encoded,
        0,
        unprotected_header,
    );
    frame = try Frame.parse(encoded[0..unprotected_end], 0);
    try std.testing.expectEqual(@as(?bool, null), try frame.crcValid());

    const truncated = Frame{
        .offset = 0,
        .bytes = encoded[0..6],
        .header = try Header.parse(&protected_header),
        .xing = null,
        .vbri = null,
    };
    try std.testing.expectError(
        error.TruncatedMp3Frame,
        truncated.crcValid(),
    );

    const mpeg2_mono_header =
        testHeader(2, false, 8, 0, false, .mono);
    const mpeg2_end = try appendFrame(
        &encoded,
        0,
        mpeg2_mono_header,
    );
    for (encoded[6..15], 0..) |*byte, index|
        byte.* = @intCast(0xa0 + index);
    encoded[4] = 0x2f;
    encoded[5] = 0x43;
    try std.testing.expectEqual(
        @as(?bool, true),
        try (try Frame.parse(encoded[0..mpeg2_end], 0)).crcValid(),
    );

    const mpeg25_stereo_header =
        testHeader(0, false, 8, 0, false, .joint_stereo);
    const mpeg25_end = try appendFrame(
        &encoded,
        0,
        mpeg25_stereo_header,
    );
    for (encoded[6..23], 0..) |*byte, index|
        byte.* = @intCast(0x40 + index);
    encoded[4] = 0x37;
    encoded[5] = 0x89;
    try std.testing.expectEqual(
        @as(?bool, true),
        try (try Frame.parse(encoded[0..mpeg25_end], 0)).crcValid(),
    );
}

test "parses bounded Layer III side information" {
    const header_bytes =
        testHeader(3, true, 9, 0, false, .stereo);
    var encoded: [500]u8 = undefined;
    const frame_end = try appendFrame(&encoded, 0, header_bytes);
    const side = encoded[4..36];
    setTestBits(side, 0, 9, 17);
    setTestBits(side, 9, 3, 5);
    setTestBits(side, 12, 4, 0xa);
    setTestBits(side, 16, 4, 0x3);
    setTestBits(side, 20, 12, 321);
    setTestBits(side, 32, 9, 144);
    setTestBits(side, 41, 8, 200);
    setTestBits(side, 49, 4, 9);
    setTestBits(side, 53, 1, 1);
    setTestBits(side, 54, 2, 2);
    setTestBits(side, 57, 5, 7);
    setTestBits(side, 62, 5, 8);
    setTestBits(side, 67, 3, 1);
    setTestBits(side, 70, 3, 2);
    setTestBits(side, 73, 3, 3);
    setTestBits(side, 76, 1, 1);
    setTestBits(side, 78, 1, 1);

    const frame = try Frame.parse(encoded[0..frame_end], 0);
    const parsed = try frame.sideInformation();
    try std.testing.expectEqual(@as(u2, 2), parsed.channel_count);
    try std.testing.expectEqual(@as(u2, 2), parsed.granule_count);
    try std.testing.expectEqual(@as(u9, 17), parsed.main_data_begin);
    try std.testing.expectEqual(@as(u5, 5), parsed.private_bits);
    try std.testing.expectEqual(@as(u4, 0xa), parsed.scfsi[0]);
    try std.testing.expectEqual(@as(u4, 0x3), parsed.scfsi[1]);
    try std.testing.expectEqual(@as(u16, 321), parsed.main_data_bits);
    const channel = parsed.granules[0].channels[0];
    try std.testing.expectEqual(@as(u12, 321), channel.part2_3_length);
    try std.testing.expectEqual(@as(u9, 144), channel.big_values);
    try std.testing.expectEqual(@as(u8, 200), channel.global_gain);
    try std.testing.expectEqual(@as(u9, 9), channel.scalefac_compress);
    try std.testing.expect(channel.window_switching);
    try std.testing.expectEqual(@as(u2, 2), channel.block_type);
    try std.testing.expect(!channel.mixed_block);
    try std.testing.expectEqual([3]u5{ 7, 8, 0 }, channel.table_select);
    try std.testing.expectEqual([3]u3{ 1, 2, 3 }, channel.subblock_gain);
    try std.testing.expectEqual(@as(u4, 8), channel.region0_count);
    try std.testing.expectEqual(@as(u4, 12), channel.region1_count);
    try std.testing.expect(channel.preflag);
    try std.testing.expect(!channel.scalefac_scale);
    try std.testing.expect(channel.count1_table_select);

    const file_frame = FileFrame{
        .byte_offset = 0,
        .bytes = frame.bytes,
        .header = frame.header,
        .xing = frame.xing,
        .vbri = frame.vbri,
    };
    try std.testing.expectEqual(
        parsed,
        try file_frame.sideInformation(),
    );
}

test "serializes Layer III side information transactionally" {
    const mpeg1 = try Header.parse(
        &testHeader(3, false, 9, 0, false, .mono),
    );
    var mpeg1_side = SideInformation{
        .channel_count = 1,
        .granule_count = 2,
        .main_data_begin = 31,
        .private_bits = 17,
        .scfsi = .{ 0xa, 0 },
        .main_data_bits = 30,
    };
    mpeg1_side.granules[0].channels[0] = .{
        .part2_3_length = 10,
        .big_values = 1,
        .global_gain = 210,
        .scalefac_compress = 3,
        .table_select = .{ 1, 2, 3 },
        .region0_count = 7,
        .region1_count = 5,
        .preflag = true,
        .scalefac_scale = true,
    };
    mpeg1_side.granules[1].channels[0] = .{
        .part2_3_length = 20,
        .big_values = 2,
        .global_gain = 190,
        .scalefac_compress = 7,
        .table_select = .{ 5, 6, 7 },
        .region0_count = 6,
        .region1_count = 4,
        .count1_table_select = true,
    };
    var storage: [32]u8 = undefined;
    const encoded_mpeg1 = try encodeSideInformation(
        mpeg1,
        mpeg1_side,
        &storage,
    );
    try std.testing.expectEqual(
        @as(usize, 17),
        encoded_mpeg1.len,
    );
    var frame_storage: [23]u8 = @splat(0);
    const header_bytes = try mpeg1.encode();
    @memcpy(frame_storage[0..4], &header_bytes);
    @memcpy(frame_storage[6..23], encoded_mpeg1);
    try std.testing.expectEqual(
        mpeg1_side,
        try parseSideInformation(&frame_storage, mpeg1),
    );

    const mpeg2 = try Header.parse(
        &testHeader(2, true, 8, 0, false, .stereo),
    );
    var mpeg2_side = SideInformation{
        .channel_count = 2,
        .granule_count = 1,
        .main_data_begin = 200,
        .private_bits = 2,
        .main_data_bits = 0,
    };
    mpeg2_side.granules[0].channels[0] = .{
        .global_gain = 180,
        .scalefac_compress = 300,
        .window_switching = true,
        .block_type = 2,
        .mixed_block = true,
        .table_select = .{ 13, 15, 0 },
        .subblock_gain = .{ 1, 2, 3 },
        .region0_count = 7,
        .region1_count = 13,
        .scalefac_scale = true,
    };
    mpeg2_side.granules[0].channels[1] = .{
        .global_gain = 181,
        .scalefac_compress = 301,
        .window_switching = true,
        .block_type = 2,
        .table_select = .{ 16, 24, 0 },
        .subblock_gain = .{ 3, 2, 1 },
        .region0_count = 8,
        .region1_count = 12,
        .count1_table_select = true,
    };
    const encoded_mpeg2 = try encodeSideInformation(
        mpeg2,
        mpeg2_side,
        &storage,
    );
    try std.testing.expectEqual(
        @as(usize, 17),
        encoded_mpeg2.len,
    );
    var mpeg2_frame: [21]u8 = @splat(0);
    const mpeg2_header = try mpeg2.encode();
    @memcpy(mpeg2_frame[0..4], &mpeg2_header);
    @memcpy(mpeg2_frame[4..21], encoded_mpeg2);
    try std.testing.expectEqual(
        mpeg2_side,
        try parseSideInformation(&mpeg2_frame, mpeg2),
    );

    var malformed = mpeg1_side;
    malformed.main_data_bits += 1;
    var retained: [32]u8 = @splat(0x5a);
    try std.testing.expectError(
        error.InvalidMp3SideInformation,
        encodeSideInformation(mpeg1, malformed, &retained),
    );
    try std.testing.expectEqualSlices(
        u8,
        &(@as([32]u8, @splat(0x5a))),
        &retained,
    );
    try std.testing.expectError(
        error.InsufficientMp3SideInformationStorage,
        encodeSideInformation(mpeg1, mpeg1_side, retained[0..16]),
    );

    malformed = mpeg1_side;
    malformed.granules[0].channels[1].global_gain = 1;
    try std.testing.expectError(
        error.InvalidMp3SideInformation,
        encodeSideInformation(mpeg1, malformed, &retained),
    );
}

test "rejects malformed Layer III side information" {
    const header_bytes =
        testHeader(3, true, 9, 0, false, .stereo);
    var encoded: [500]u8 = undefined;
    const frame_end = try appendFrame(&encoded, 0, header_bytes);
    const side = encoded[4..36];
    setTestBits(side, 32, 9, 289);
    var frame = try Frame.parse(encoded[0..frame_end], 0);
    try std.testing.expectError(
        error.InvalidMp3BigValues,
        frame.sideInformation(),
    );

    @memset(side, 0);
    setTestBits(side, 53, 1, 1);
    frame = try Frame.parse(encoded[0..frame_end], 0);
    try std.testing.expectError(
        error.InvalidMp3BlockType,
        frame.sideInformation(),
    );

    @memset(side, 0);
    setTestBits(side, 54, 5, 14);
    frame = try Frame.parse(encoded[0..frame_end], 0);
    try std.testing.expectError(
        error.InvalidMp3HuffmanTable,
        frame.sideInformation(),
    );

    @memset(side, 0);
    setTestBits(side, 69, 4, 15);
    setTestBits(side, 73, 3, 7);
    frame = try Frame.parse(encoded[0..frame_end], 0);
    try std.testing.expectError(
        error.InvalidMp3RegionCounts,
        frame.sideInformation(),
    );

    const parsed_header = try Header.parse(&header_bytes);
    const truncated = Frame{
        .offset = 0,
        .bytes = encoded[0..35],
        .header = parsed_header,
        .xing = null,
        .vbri = null,
    };
    try std.testing.expectError(
        error.TruncatedMp3SideInformation,
        truncated.sideInformation(),
    );

    const mpeg2_header =
        testHeader(2, true, 8, 0, false, .stereo);
    const mpeg2_end = try appendFrame(
        &encoded,
        0,
        mpeg2_header,
    );
    const mpeg2 = try (try Frame.parse(
        encoded[0..mpeg2_end],
        0,
    )).sideInformation();
    try std.testing.expectEqual(@as(u2, 1), mpeg2.granule_count);
    try std.testing.expectEqual(@as(u2, 2), mpeg2.channel_count);
    try std.testing.expectEqual(@as(u16, 0), mpeg2.main_data_bits);
}

test "assembles bounded Layer III main-data reservoirs transactionally" {
    const Reservoir = MainDataReservoir(511);
    const header_bytes =
        testHeader(3, true, 9, 0, false, .stereo);
    var first_encoded: [500]u8 = undefined;
    const first_end = try appendFrame(
        &first_encoded,
        0,
        header_bytes,
    );
    setTestBits(first_encoded[4..36], 20, 12, 16);
    first_encoded[first_end - 2] = 0xa1;
    first_encoded[first_end - 1] = 0xb2;
    const first = try Frame.parse(
        first_encoded[0..first_end],
        0,
    );

    var reservoir = Reservoir{};
    var first_output: [2]u8 = @splat(0xff);
    const first_data = try reservoir.assemble(
        first,
        &first_output,
    );
    try std.testing.expectEqual(@as(u16, 16), first_data.bit_count);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0 }, first_data.bytes);

    var partial_encoded = first_encoded;
    setTestBits(partial_encoded[4..36], 20, 12, 9);
    const partial = try Frame.parse(
        partial_encoded[0..first_end],
        0,
    );
    var partial_reservoir = Reservoir{};
    var partial_output: [2]u8 = @splat(0xff);
    const partial_data = try partial_reservoir.assemble(
        partial,
        &partial_output,
    );
    try std.testing.expectEqual(@as(u16, 9), partial_data.bit_count);
    try std.testing.expectEqual(@as(usize, 2), partial_data.bytes.len);

    var second_encoded: [500]u8 = undefined;
    const second_end = try appendFrame(
        &second_encoded,
        0,
        header_bytes,
    );
    setTestBits(second_encoded[4..36], 0, 9, 2);
    setTestBits(second_encoded[4..36], 20, 12, 24);
    second_encoded[36] = 0xc3;
    const second = try Frame.parse(
        second_encoded[0..second_end],
        0,
    );
    var second_output: [3]u8 = @splat(0);
    const second_data = try reservoir.assemble(
        second,
        &second_output,
    );
    try std.testing.expectEqual(@as(u16, 24), second_data.bit_count);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0xa1, 0xb2, 0xc3 },
        second_data.bytes,
    );

    var missing = Reservoir{};
    try std.testing.expect(missing.valid());
    var unchanged: [3]u8 = @splat(0x7a);
    try std.testing.expectError(
        error.Mp3MainDataHistoryUnavailable,
        missing.assemble(second, &unchanged),
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x7a, 0x7a, 0x7a },
        &unchanged,
    );
    try std.testing.expectEqual(@as(usize, 0), missing.length);

    var short = Reservoir{};
    _ = try short.assemble(first, &first_output);
    const retained_length = short.length;
    var short_output: [2]u8 = @splat(0x6b);
    try std.testing.expectError(
        error.InsufficientMp3MainDataStorage,
        short.assemble(second, &short_output),
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x6b, 0x6b },
        &short_output,
    );
    try std.testing.expectEqual(retained_length, short.length);

    var aliased = Reservoir{};
    @memcpy(
        aliased.storage[0..first.bytes.len],
        first.bytes,
    );
    const aliased_frame = try Frame.parse(
        aliased.storage[0..first.bytes.len],
        0,
    );
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        aliased.assemble(aliased_frame, &first_output),
    );
    try std.testing.expectEqual(@as(usize, 0), aliased.length);

    const file_second = FileFrame{
        .byte_offset = 0,
        .bytes = second.bytes,
        .header = second.header,
        .xing = second.xing,
        .vbri = second.vbri,
    };
    _ = try short.assemble(file_second, &second_output);
    short.reset();
    try std.testing.expect(short.valid());
    try std.testing.expectEqual(@as(usize, 0), short.length);

    short.length = short.storage.len + 1;
    try std.testing.expect(!short.valid());
    const invalid_reservoir = short;
    try std.testing.expectError(
        error.InvalidMp3ReservoirState,
        short.assemble(second, &second_output),
    );
    try std.testing.expectEqual(invalid_reservoir, short);
}

test "encodes MPEG-1 scale factors and reuse groups" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    const long_description = GranuleChannel{
        .scalefac_compress = 15,
    };
    var long_factors = EncoderScaleFactors{
        .value_count = 22,
    };
    for (0..11) |index|
        long_factors.values[index] = @intCast((index * 3) % 16);
    for (11..21) |index|
        long_factors.values[index] = @intCast((index * 5) % 8);
    var storage: [64]u8 = @splat(0x5a);
    const encoded_long = try encodeScaleFactors(
        header,
        long_description,
        0,
        0,
        0,
        .{},
        long_factors,
        &storage,
    );
    try std.testing.expectEqual(
        @as(u16, 74),
        encoded_long.main_data.bit_count,
    );
    var long_reader = MainDataBitReader{
        .bytes = encoded_long.main_data.bytes,
        .bit_limit = encoded_long.main_data.bit_count,
    };
    const decoded_long = try decodeMpeg1ScaleFactorChannel(
        &long_reader,
        long_description,
        0,
        0,
        .{},
    );
    try std.testing.expectEqual(
        long_factors.values,
        decoded_long.values,
    );
    try std.testing.expectEqual(
        @as(usize, encoded_long.main_data.bit_count),
        long_reader.bit_offset,
    );

    const reuse_description = GranuleChannel{
        .scalefac_compress = 10,
    };
    var first = EncoderScaleFactors{
        .value_count = 22,
    };
    @memset(first.values[0..21], 1);
    var second = first;
    @memset(second.values[6..11], 2);
    @memset(second.values[16..21], 3);
    const encoded_reuse = try encodeScaleFactors(
        header,
        reuse_description,
        0b1010,
        1,
        0,
        first,
        second,
        &storage,
    );
    try std.testing.expectEqual(
        @as(u16, 25),
        encoded_reuse.main_data.bit_count,
    );
    var reuse_reader = MainDataBitReader{
        .bytes = encoded_reuse.main_data.bytes,
        .bit_limit = encoded_reuse.main_data.bit_count,
    };
    const decoded_reuse = try decodeMpeg1ScaleFactorChannel(
        &reuse_reader,
        reuse_description,
        0b1010,
        1,
        .{
            .values = first.values,
            .value_count = first.value_count,
        },
    );
    try std.testing.expectEqual(second.values, decoded_reuse.values);

    const short_descriptions = [_]GranuleChannel{
        .{
            .scalefac_compress = 5,
            .window_switching = true,
            .block_type = 2,
        },
        .{
            .scalefac_compress = 5,
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
    };
    for (short_descriptions, 0..) |description, case_index| {
        var factors = EncoderScaleFactors{
            .value_count = scaleFactorValueCount(
                header,
                description,
            ),
        };
        @memset(factors.values[0 .. factors.value_count - 3], 1);
        const encoded = try encodeScaleFactors(
            header,
            description,
            0,
            0,
            0,
            .{},
            factors,
            &storage,
        );
        try std.testing.expectEqual(
            @as(u16, if (case_index == 0) 36 else 35),
            encoded.main_data.bit_count,
        );
        var reader = MainDataBitReader{
            .bytes = encoded.main_data.bytes,
            .bit_limit = encoded.main_data.bit_count,
        };
        const decoded = try decodeMpeg1ScaleFactorChannel(
            &reader,
            description,
            0,
            0,
            .{},
        );
        try std.testing.expectEqual(
            factors.values,
            decoded.values,
        );
    }
}

test "encodes every low-sampling-frequency scale-factor family" {
    const descriptions = [_]GranuleChannel{
        .{},
        .{
            .window_switching = true,
            .block_type = 2,
        },
        .{
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
    };
    const non_intensity_compressions =
        [_]u9{ 0, 399, 400, 499, 500, 511 };
    const intensity_compressions =
        [_]u9{ 0, 359, 360, 487, 488, 511 };
    const normal_header = try Header.parse(
        &testHeader(2, true, 8, 0, false, .mono),
    );
    var intensity_header = try Header.parse(
        &testHeader(2, true, 8, 0, false, .joint_stereo),
    );
    intensity_header.mode_extension = 1;
    const headers = [_]Header{ normal_header, intensity_header };
    var storage: [64]u8 = undefined;
    for (headers, 0..) |header, header_index| {
        const intensity = header_index == 1;
        const compressions = if (intensity)
            intensity_compressions
        else
            non_intensity_compressions;
        for (compressions, 0..) |compression, case_index| {
            var description =
                descriptions[case_index % descriptions.len];
            description.scalefac_compress = compression;
            const plan = try lsfScaleFactorPlan(
                compression,
                intensity,
            );
            const layout: usize = if (description.block_type != 2)
                0
            else if (description.mixed_block)
                2
            else
                1;
            var factors = EncoderScaleFactors{
                .value_count = scaleFactorValueCount(
                    header,
                    description,
                ),
            };
            var index: usize = 0;
            for (lsf_scale_factor_counts[plan.table][layout], 0..) |
                count,
                part,
            | {
                const width = plan.lengths[part];
                const maximum: u8 = if (width == 0)
                    0
                else
                    @intCast((@as(u16, 1) << @intCast(width)) - 1);
                for (0..count) |_| {
                    factors.values[index] =
                        if (maximum == 0)
                            0
                        else
                            @intCast((index * 3 + 1) %
                                (@as(usize, maximum) + 1));
                    index += 1;
                }
            }
            if (description.block_type == 2)
                @memset(
                    factors.values[factors.value_count - 3 .. factors.value_count],
                    0,
                );
            const channel: u2 = if (intensity) 1 else 0;
            const encoded = try encodeScaleFactors(
                header,
                description,
                0,
                0,
                channel,
                .{},
                factors,
                &storage,
            );
            var reader = MainDataBitReader{
                .bytes = encoded.main_data.bytes,
                .bit_limit = encoded.main_data.bit_count,
            };
            const decoded = try decodeLsfScaleFactorChannel(
                &reader,
                description,
                intensity,
            );
            try std.testing.expectEqual(
                factors.values,
                decoded.values,
            );
            try std.testing.expectEqual(
                plan.preflag,
                decoded.preflag,
            );
            try std.testing.expectEqual(
                plan.intensity_scale,
                decoded.intensity_scale,
            );
            try std.testing.expectEqual(
                @as(usize, encoded.main_data.bit_count),
                reader.bit_offset,
            );
        }
    }

    const low_rate_header = try Header.parse(
        &testHeader(0, true, 9, 2, false, .mono),
    );
    const low_rate_description = GranuleChannel{
        .scalefac_compress = 401,
        .window_switching = true,
        .block_type = 2,
        .mixed_block = true,
    };
    const low_rate = try encodeScaleFactors(
        low_rate_header,
        low_rate_description,
        0,
        0,
        0,
        .{},
        .{},
        &storage,
    );
    try std.testing.expect(low_rate.main_data.bit_count > 0);
}

test "rejects malformed scale-factor encoding transactionally" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    const description = GranuleChannel{
        .scalefac_compress = 5,
    };
    var storage: [64]u8 = @splat(0x5a);
    const original = storage;

    var excessive = EncoderScaleFactors{
        .value_count = 22,
    };
    excessive.values[0] = 2;
    try std.testing.expectError(
        error.InvalidMp3EncoderScaleFactorValue,
        encodeScaleFactors(
            header,
            description,
            0,
            0,
            0,
            .{},
            excessive,
            &storage,
        ),
    );
    try std.testing.expectEqual(original, storage);

    var wrong_count = excessive;
    wrong_count.values[0] = 0;
    wrong_count.value_count = 21;
    try std.testing.expectError(
        error.InvalidMp3EncoderScaleFactors,
        encodeScaleFactors(
            header,
            description,
            0,
            0,
            0,
            .{},
            wrong_count,
            &storage,
        ),
    );
    try std.testing.expectEqual(original, storage);

    var trailing = EncoderScaleFactors{
        .value_count = 22,
    };
    trailing.values[38] = 1;
    try std.testing.expectError(
        error.InvalidMp3EncoderScaleFactors,
        encodeScaleFactors(
            header,
            description,
            0,
            0,
            0,
            .{},
            trailing,
            &storage,
        ),
    );
    try std.testing.expectEqual(original, storage);

    const first = EncoderScaleFactors{
        .value_count = 22,
    };
    var second = first;
    second.values[0] = 1;
    try std.testing.expectError(
        error.InvalidMp3EncoderScaleFactorReuse,
        encodeScaleFactors(
            header,
            description,
            0b1000,
            1,
            0,
            first,
            second,
            &storage,
        ),
    );
    try std.testing.expectEqual(original, storage);

    try std.testing.expectError(
        error.InvalidMp3EncoderScaleFactorPosition,
        encodeScaleFactors(
            header,
            description,
            0,
            0,
            1,
            .{},
            .{},
            &storage,
        ),
    );
    const lsf_header = try Header.parse(
        &testHeader(2, true, 8, 0, false, .mono),
    );
    try std.testing.expectError(
        error.InvalidMp3EncoderScaleFactors,
        encodeScaleFactors(
            lsf_header,
            .{},
            1,
            0,
            0,
            .{},
            .{},
            &storage,
        ),
    );

    var short_storage: [1]u8 = @splat(0x6b);
    try std.testing.expectError(
        error.InsufficientMp3ScaleFactorStorage,
        encodeScaleFactors(
            header,
            description,
            0,
            0,
            0,
            .{},
            .{},
            &short_storage,
        ),
    );
    try std.testing.expectEqual(
        @as([1]u8, @splat(0x6b)),
        short_storage,
    );
}

test "decodes MPEG-1 scale factors and granule reuse groups" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var side = SideInformation{
        .channel_count = 1,
        .granule_count = 2,
        .main_data_begin = 0,
        .private_bits = 0,
        .main_data_bits = 36,
    };
    side.scfsi[0] = 0b1010;
    side.granules[0].channels[0].part2_3_length = 24;
    side.granules[0].channels[0].scalefac_compress = 5;
    side.granules[1].channels[0].part2_3_length = 12;
    side.granules[1].channels[0].scalefac_compress = 5;

    var encoded: [5]u8 = @splat(0);
    for (0..21) |bit| setTestBits(&encoded, bit, 1, 1);
    for (29..34) |bit| setTestBits(&encoded, bit, 1, 1);
    const decoded = try decodeScaleFactors(
        header,
        side,
        .{ .bytes = &encoded, .bit_count = 36 },
    );
    const first = decoded.granules[0].channels[0];
    try std.testing.expectEqual(@as(u6, 22), first.value_count);
    try std.testing.expectEqual(@as(u12, 21), first.part2_bits);
    try std.testing.expectEqual(@as(u16, 21), first.huffman_bit_offset);
    try std.testing.expectEqual(@as(u12, 3), first.huffman_bit_count);
    try std.testing.expectEqual(@as(u8, 1), first.values[20]);
    try std.testing.expectEqual(@as(u8, 0), first.values[21]);

    const second = decoded.granules[1].channels[0];
    try std.testing.expectEqual(@as(u12, 10), second.part2_bits);
    try std.testing.expectEqual(@as(u16, 34), second.huffman_bit_offset);
    try std.testing.expectEqual(@as(u12, 2), second.huffman_bit_count);
    try std.testing.expectEqual(@as(u8, 1), second.values[0]);
    try std.testing.expectEqual(@as(u8, 0), second.values[6]);
    try std.testing.expectEqual(@as(u8, 1), second.values[11]);
    try std.testing.expectEqual(@as(u8, 1), second.values[16]);
}

test "decodes short and low-sampling-frequency scale factors" {
    const mpeg1_header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var short_side = SideInformation{
        .channel_count = 1,
        .granule_count = 2,
        .main_data_begin = 0,
        .private_bits = 0,
        .main_data_bits = 104,
    };
    short_side.granules[0].channels[0] = .{
        .part2_3_length = 104,
        .scalefac_compress = 14,
        .window_switching = true,
        .block_type = 2,
        .mixed_block = true,
    };
    var short_bits: [13]u8 = @splat(0xff);
    const short = try decodeScaleFactors(
        mpeg1_header,
        short_side,
        .{ .bytes = &short_bits, .bit_count = 104 },
    );
    const short_channel = short.granules[0].channels[0];
    try std.testing.expectEqual(@as(u6, 38), short_channel.value_count);
    try std.testing.expectEqual(@as(u12, 104), short_channel.part2_bits);
    try std.testing.expectEqual(@as(u8, 15), short_channel.values[16]);
    try std.testing.expectEqual(@as(u8, 3), short_channel.values[34]);
    try std.testing.expectEqual(@as(u8, 0), short_channel.values[35]);
    try std.testing.expectEqual(@as(u8, 0), short_channel.values[37]);

    const mpeg2_header = try Header.parse(
        &testHeader(2, true, 8, 0, false, .mono),
    );
    var lsf_side = SideInformation{
        .channel_count = 1,
        .granule_count = 1,
        .main_data_begin = 0,
        .private_bits = 0,
        .main_data_bits = 16,
    };
    lsf_side.granules[0].channels[0] = .{
        .part2_3_length = 16,
        .scalefac_compress = 421,
    };
    var lsf_bits: [2]u8 = @splat(0xff);
    const lsf = try decodeScaleFactors(
        mpeg2_header,
        lsf_side,
        .{ .bytes = &lsf_bits, .bit_count = 16 },
    );
    const lsf_channel = lsf.granules[0].channels[0];
    try std.testing.expectEqual(@as(u6, 21), lsf_channel.value_count);
    try std.testing.expectEqual(@as(u12, 13), lsf_channel.part2_bits);
    try std.testing.expectEqual(@as(u12, 3), lsf_channel.huffman_bit_count);
    try std.testing.expectEqual(@as(u8, 1), lsf_channel.values[5]);
    try std.testing.expectEqual(@as(u8, 0), lsf_channel.values[6]);
    try std.testing.expectEqual(@as(u8, 1), lsf_channel.values[17]);
}

test "decodes low-sampling-frequency intensity scale factors" {
    var header_bytes =
        testHeader(2, true, 8, 0, false, .joint_stereo);
    header_bytes[3] |= 1 << 4;
    const header = try Header.parse(&header_bytes);
    var side = SideInformation{
        .channel_count = 2,
        .granule_count = 1,
        .main_data_begin = 0,
        .private_bits = 0,
        .main_data_bits = 35,
    };
    side.granules[0].channels[1] = .{
        .part2_3_length = 35,
        .scalefac_compress = 100,
    };
    var encoded: [5]u8 = @splat(0xff);
    const decoded = try decodeScaleFactors(
        header,
        side,
        .{ .bytes = &encoded, .bit_count = 35 },
    );
    const right = decoded.granules[0].channels[1];
    try std.testing.expectEqual(@as(u6, 21), right.value_count);
    try std.testing.expectEqual(@as(u12, 35), right.part2_bits);
    for (right.intensity_max[0..21]) |is_max|
        try std.testing.expect(is_max);
}

test "covers low-sampling-frequency compression families and layouts" {
    const Case = struct {
        compression: u9,
        intensity: bool,
        expected_bits: usize,
        expected_count: u6,
        expected_preflag: bool = false,
    };
    const cases = [_]Case{
        .{
            .compression = 100,
            .intensity = false,
            .expected_bits = 16,
            .expected_count = 21,
        },
        .{
            .compression = 421,
            .intensity = false,
            .expected_bits = 13,
            .expected_count = 21,
        },
        .{
            .compression = 503,
            .intensity = false,
            .expected_bits = 11,
            .expected_count = 21,
            .expected_preflag = true,
        },
        .{
            .compression = 100,
            .intensity = true,
            .expected_bits = 35,
            .expected_count = 21,
        },
        .{
            .compression = 401,
            .intensity = true,
            .expected_bits = 12,
            .expected_count = 21,
        },
        .{
            .compression = 501,
            .intensity = true,
            .expected_bits = 16,
            .expected_count = 21,
        },
    };
    var storage: [32]u8 = @splat(0);
    for (cases) |case| {
        var reader = MainDataBitReader{
            .bytes = &storage,
            .bit_limit = storage.len * 8,
        };
        const decoded = try decodeLsfScaleFactorChannel(
            &reader,
            .{ .scalefac_compress = case.compression },
            case.intensity,
        );
        try std.testing.expectEqual(case.expected_bits, reader.bit_offset);
        try std.testing.expectEqual(
            case.expected_count,
            decoded.value_count,
        );
        try std.testing.expectEqual(
            case.expected_preflag,
            decoded.preflag,
        );
        try std.testing.expectEqual(
            case.intensity and case.compression & 1 != 0,
            decoded.intensity_scale,
        );
    }

    var short_reader = MainDataBitReader{
        .bytes = &storage,
        .bit_limit = storage.len * 8,
    };
    const short = try decodeLsfScaleFactorChannel(
        &short_reader,
        .{
            .scalefac_compress = 100,
            .window_switching = true,
            .block_type = 2,
        },
        false,
    );
    try std.testing.expectEqual(@as(u6, 36), short.value_count);
    try std.testing.expectEqual(@as(usize, 27), short_reader.bit_offset);

    var mixed_reader = MainDataBitReader{
        .bytes = &storage,
        .bit_limit = storage.len * 8,
    };
    const mixed = try decodeLsfScaleFactorChannel(
        &mixed_reader,
        .{
            .scalefac_compress = 100,
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
        false,
    );
    try std.testing.expectEqual(@as(u6, 33), mixed.value_count);
    try std.testing.expectEqual(@as(usize, 24), mixed_reader.bit_offset);
}

test "maps every Layer III sample rate to bounded spectral bands" {
    const versions = [_]u2{ 3, 2, 0 };
    for (versions) |version_bits| {
        for (0..3) |rate_index| {
            const header = try Header.parse(&testHeader(
                version_bits,
                true,
                8,
                @intCast(rate_index),
                false,
                .stereo,
            ));
            const bands = try scaleFactorBands(header);
            try std.testing.expectEqual(
                @as(usize, 23),
                bands.long_starts.len,
            );
            try std.testing.expectEqual(
                @as(usize, 14),
                bands.short_starts.len,
            );
            try std.testing.expectEqual(
                @as(u16, 0),
                bands.long_starts[0],
            );
            try std.testing.expectEqual(
                @as(u16, 576),
                bands.long_starts[22],
            );
            try std.testing.expectEqual(
                @as(u16, 192),
                bands.short_starts[13],
            );
            for (bands.long_starts[0..22], bands.long_starts[1..23]) |
                first,
                second,
            | try std.testing.expect(first < second);
            for (
                bands.short_starts[0..13],
                bands.short_starts[1..14],
            ) |first, second| try std.testing.expect(first < second);
        }
    }
}

test "plans long short and low-rate Huffman regions" {
    const mpeg1 = try Header.parse(
        &testHeader(3, true, 9, 0, false, .stereo),
    );
    try std.testing.expectEqual(
        [2]u16{ 36, 110 },
        try huffmanRegionEnds(mpeg1, .{
            .region0_count = 7,
            .region1_count = 5,
        }),
    );
    try std.testing.expectEqual(
        [2]u16{ 36, 576 },
        try huffmanRegionEnds(mpeg1, .{
            .window_switching = true,
            .block_type = 2,
        }),
    );

    const mpeg25 = try Header.parse(
        &testHeader(0, true, 8, 2, false, .stereo),
    );
    try std.testing.expectEqual(@as(u32, 8_000), mpeg25.sample_rate);
    try std.testing.expectEqual(
        [2]u16{ 72, 576 },
        try huffmanRegionEnds(mpeg25, .{
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        }),
    );

    try std.testing.expectError(
        error.InvalidMp3BlockType,
        huffmanRegionEnds(mpeg1, .{ .block_type = 2 }),
    );
    try std.testing.expectError(
        error.InvalidMp3RegionCounts,
        huffmanRegionEnds(mpeg1, .{
            .region0_count = 15,
            .region1_count = 15,
        }),
    );
    var invalid_rate = mpeg1;
    invalid_rate.sample_rate = 12_345;
    try std.testing.expectError(
        error.InvalidMp3SampleRate,
        scaleFactorBands(invalid_rate),
    );
}

test "encodes every Layer III Huffman pair codebook" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    for (0..32) |table_value| {
        const table_index: u5 = @intCast(table_value);
        if (table_index == 4 or table_index == 14) continue;
        const table = try huffman_tables.get(table_index);
        for (table.entries, 0..) |_, entry_index| {
            const x: i32 = @intCast(entry_index / table.side);
            const y: i32 = @intCast(entry_index % table.side);
            var spectrum: [576]i32 = @splat(0);
            spectrum[0] = if (x == 0) 0 else -x;
            spectrum[1] = y;
            var storage: [512]u8 = undefined;
            const encoded = try encodeHuffmanChannel(
                header,
                .{
                    .big_values = 1,
                    .table_select = @splat(table_index),
                    .region0_count = 7,
                    .region1_count = 5,
                },
                &spectrum,
                &storage,
            );
            const decoded = try decodeHuffmanChannel(
                header,
                encoded.description,
                .{
                    .huffman_bit_count = encoded.description.part2_3_length,
                },
                encoded.main_data,
            );
            try std.testing.expectEqualSlices(
                i32,
                spectrum[0..2],
                decoded.lines[0..2],
            );
        }
    }

    var escape_spectrum: [576]i32 = @splat(0);
    escape_spectrum[0] = -(15 + 8191);
    escape_spectrum[1] = 15 + 8191;
    var storage: [512]u8 = undefined;
    const encoded = try encodeHuffmanChannel(
        header,
        .{
            .big_values = 1,
            .table_select = @splat(31),
            .region0_count = 7,
            .region1_count = 5,
        },
        &escape_spectrum,
        &storage,
    );
    const decoded = try decodeHuffmanChannel(
        header,
        encoded.description,
        .{
            .huffman_bit_count = encoded.description.part2_3_length,
        },
        encoded.main_data,
    );
    try std.testing.expectEqualSlices(
        i32,
        escape_spectrum[0..2],
        decoded.lines[0..2],
    );
}

test "encodes both Layer III count1 codebooks" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    for ([_]bool{ false, true }) |table_b| {
        var spectrum: [576]i32 = @splat(0);
        for (0..16) |pattern| {
            for (0..4) |component| {
                const line = pattern * 4 + component;
                const magnitude =
                    (pattern >> @intCast(3 - component)) & 1;
                spectrum[line] = if (magnitude == 0)
                    0
                else if (line & 1 == 0)
                    -1
                else
                    1;
            }
        }
        var storage: [512]u8 = undefined;
        const encoded = try encodeHuffmanChannel(
            header,
            .{
                .count1_table_select = table_b,
                .region0_count = 7,
                .region1_count = 5,
            },
            &spectrum,
            &storage,
        );
        const decoded = try decodeHuffmanChannel(
            header,
            encoded.description,
            .{
                .huffman_bit_count = encoded.description.part2_3_length,
            },
            encoded.main_data,
        );
        try std.testing.expectEqual(@as(u10, 64), decoded.decoded_lines);
        try std.testing.expectEqualSlices(
            i32,
            spectrum[0..64],
            decoded.lines[0..64],
        );
    }
}

test "rejects malformed Huffman encoder inputs transactionally" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var spectrum: [576]i32 = @splat(0);
    spectrum[0] = 2;
    var destination: [8]u8 = @splat(0x5a);
    try std.testing.expectError(
        error.Mp3HuffmanTableTooSmall,
        encodeHuffmanChannel(
            header,
            .{
                .big_values = 1,
                .table_select = @splat(1),
                .region0_count = 7,
                .region1_count = 5,
            },
            &spectrum,
            &destination,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &(@as([8]u8, @splat(0x5a))),
        &destination,
    );

    spectrum[0] = std.math.minInt(i32);
    try std.testing.expectError(
        error.InvalidMp3QuantizedValue,
        encodeHuffmanChannel(
            header,
            .{
                .big_values = 1,
                .table_select = @splat(31),
                .region0_count = 7,
                .region1_count = 5,
            },
            &spectrum,
            &destination,
        ),
    );
    spectrum[0] = 0;
    spectrum[2] = 2;
    try std.testing.expectError(
        error.InvalidMp3Count1Value,
        encodeHuffmanChannel(
            header,
            .{
                .big_values = 1,
                .table_select = @splat(1),
                .region0_count = 7,
                .region1_count = 5,
            },
            &spectrum,
            &destination,
        ),
    );

    spectrum = @splat(0);
    spectrum[0] = 1;
    try std.testing.expectError(
        error.InsufficientMp3HuffmanStorage,
        encodeHuffmanChannel(
            header,
            .{
                .big_values = 1,
                .table_select = @splat(1),
                .region0_count = 7,
                .region1_count = 5,
            },
            &spectrum,
            &.{},
        ),
    );
}

test "decodes bounded Layer III count1 Huffman tables" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var table_a_bits: [1]u8 = @splat(0);
    setTestBits(&table_a_bits, 0, 4, 0b0111);
    setTestBits(&table_a_bits, 4, 1, 1);
    const table_a = try decodeHuffmanChannel(
        header,
        .{ .part2_3_length = 5 },
        .{
            .huffman_bit_offset = 0,
            .huffman_bit_count = 5,
        },
        .{ .bytes = &table_a_bits, .bit_count = 5 },
    );
    try std.testing.expectEqual(@as(u10, 4), table_a.decoded_lines);
    try std.testing.expectEqual(@as(u12, 5), table_a.huffman_bits_consumed);
    try std.testing.expectEqualSlices(
        i32,
        &.{ -1, 0, 0, 0 },
        table_a.lines[0..4],
    );

    var table_b_bits: [1]u8 = @splat(0);
    setTestBits(&table_b_bits, 0, 4, 0b0101);
    setTestBits(&table_b_bits, 4, 2, 0b01);
    const table_b = try decodeHuffmanChannel(
        header,
        .{
            .part2_3_length = 6,
            .count1_table_select = true,
        },
        .{
            .huffman_bit_offset = 0,
            .huffman_bit_count = 6,
        },
        .{ .bytes = &table_b_bits, .bit_count = 6 },
    );
    try std.testing.expectEqualSlices(
        i32,
        &.{ 1, 0, -1, 0 },
        table_b.lines[0..4],
    );

    var incomplete_bits: [1]u8 = @splat(0);
    const incomplete = try decodeHuffmanChannel(
        header,
        .{
            .part2_3_length = 5,
            .count1_table_select = true,
        },
        .{
            .huffman_bit_offset = 0,
            .huffman_bit_count = 5,
        },
        .{ .bytes = &incomplete_bits, .bit_count = 5 },
    );
    try std.testing.expectEqual(@as(u10, 0), incomplete.decoded_lines);
    try std.testing.expectEqual(
        @as(u12, 0),
        incomplete.huffman_bits_consumed,
    );
}

test "decodes zero pair codebooks before the count1 partition" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var encoded: [1]u8 = @splat(0);
    setTestBits(&encoded, 0, 3, 0b111);
    const decoded = try decodeHuffmanChannel(
        header,
        .{
            .part2_3_length = 3,
            .big_values = 2,
        },
        .{
            .huffman_bit_offset = 0,
            .huffman_bit_count = 3,
        },
        .{ .bytes = &encoded, .bit_count = 3 },
    );
    try std.testing.expectEqual(@as(u10, 16), decoded.decoded_lines);
    try std.testing.expectEqual(@as(u12, 3), decoded.huffman_bits_consumed);
    try std.testing.expectEqualSlices(
        i32,
        &@as([16]i32, @splat(0)),
        decoded.lines[0..16],
    );

    try std.testing.expectError(
        error.InvalidMp3HuffmanTable,
        decodeHuffmanChannel(
            header,
            .{
                .big_values = 1,
                .table_select = .{ 4, 0, 0 },
            },
            .{},
            .{ .bytes = &.{}, .bit_count = 0 },
        ),
    );
    try std.testing.expectError(
        error.InvalidMp3Part23Length,
        decodeHuffmanChannel(
            header,
            .{ .part2_3_length = 2 },
            .{ .huffman_bit_count = 1 },
            .{ .bytes = &encoded, .bit_count = 1 },
        ),
    );
    try std.testing.expectError(
        error.InvalidMp3HuffmanRange,
        decodeHuffmanChannel(
            header,
            .{ .part2_3_length = 2 },
            .{
                .huffman_bit_offset = 1,
                .huffman_bit_count = 2,
            },
            .{ .bytes = &encoded, .bit_count = 2 },
        ),
    );
}

test "decodes every Layer III pair codebook and escape width" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    for (0..32) |table_number| {
        if (table_number == 4 or table_number == 14) continue;
        const table = try huffman_tables.get(
            @intCast(table_number),
        );
        const entry = table.entries[table.entries.len - 1];
        var encoded: [8]u8 = @splat(0);
        var bit_offset: usize = 0;
        setTestBits(
            &encoded,
            bit_offset,
            @intCast(entry.length),
            entry.bits,
        );
        bit_offset += entry.length;

        const base_magnitude: u16 = table.side - 1;
        var expected: [2]i32 = @splat(0);
        for (0..2) |component| {
            var magnitude = base_magnitude;
            if (base_magnitude == 15 and table.linbits != 0) {
                const extension: u16 =
                    if (component == 0) 1 else 0;
                setTestBits(
                    &encoded,
                    bit_offset,
                    @intCast(table.linbits),
                    extension,
                );
                bit_offset += table.linbits;
                magnitude += extension;
            }
            if (magnitude == 0) continue;
            const negative = component == 0;
            setTestBits(
                &encoded,
                bit_offset,
                1,
                @intFromBool(negative),
            );
            bit_offset += 1;
            expected[component] =
                if (negative)
                    -@as(i32, magnitude)
                else
                    magnitude;
        }

        const decoded = try decodeHuffmanChannel(
            header,
            .{
                .part2_3_length = @intCast(bit_offset),
                .big_values = 1,
                .table_select = .{
                    @intCast(table_number),
                    0,
                    0,
                },
            },
            .{
                .huffman_bit_offset = 0,
                .huffman_bit_count = @intCast(bit_offset),
            },
            .{
                .bytes = &encoded,
                .bit_count = @intCast(bit_offset),
            },
        );
        try std.testing.expectEqual(
            @as(u10, 2),
            decoded.decoded_lines,
        );
        try std.testing.expectEqual(
            @as(u12, @intCast(bit_offset)),
            decoded.huffman_bits_consumed,
        );
        try std.testing.expectEqualSlices(
            i32,
            &expected,
            decoded.lines[0..2],
        );
    }
}

test "enforces Layer III pair budgets and region transitions" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );

    var signs_truncated: [1]u8 = @splat(0);
    setTestBits(&signs_truncated, 0, 3, 0b000);
    try std.testing.expectError(
        error.InvalidMp3Part23Length,
        decodeHuffmanChannel(
            header,
            .{
                .part2_3_length = 4,
                .big_values = 1,
                .table_select = .{ 1, 0, 0 },
            },
            .{
                .huffman_bit_count = 4,
            },
            .{
                .bytes = &signs_truncated,
                .bit_count = 4,
            },
        ),
    );

    const escape_table = try huffman_tables.get(31);
    const escape_entry =
        escape_table.entries[escape_table.entries.len - 1];
    var escape_truncated: [3]u8 = @splat(0);
    setTestBits(
        &escape_truncated,
        0,
        escape_entry.length,
        escape_entry.bits,
    );
    try std.testing.expectError(
        error.InvalidMp3Part23Length,
        decodeHuffmanChannel(
            header,
            .{
                .part2_3_length = escape_entry.length,
                .big_values = 1,
                .table_select = .{ 31, 0, 0 },
            },
            .{
                .huffman_bit_count = escape_entry.length,
            },
            .{
                .bytes = &escape_truncated,
                .bit_count = escape_entry.length,
            },
        ),
    );

    var region_bits: [1]u8 = @splat(0);
    setTestBits(&region_bits, 0, 1, 0b1);
    const regions = try decodeHuffmanChannel(
        header,
        .{
            .part2_3_length = 1,
            .big_values = 5,
            .table_select = .{ 0, 0, 1 },
        },
        .{
            .huffman_bit_count = 1,
        },
        .{
            .bytes = &region_bits,
            .bit_count = 1,
        },
    );
    try std.testing.expectEqual(
        @as(u10, 10),
        regions.decoded_lines,
    );
    try std.testing.expectEqual(
        @as(u12, 1),
        regions.huffman_bits_consumed,
    );
    try std.testing.expectEqualSlices(
        i32,
        &@as([10]i32, @splat(0)),
        regions.lines[0..10],
    );
}

test "validates Layer III pair codebook prefixes" {
    for (0..32) |table_number| {
        if (table_number == 4 or table_number == 14) {
            try std.testing.expectError(
                error.InvalidMp3HuffmanTable,
                huffman_tables.get(@intCast(table_number)),
            );
            continue;
        }
        const table = try huffman_tables.get(
            @intCast(table_number),
        );
        try std.testing.expectEqual(
            @as(usize, table.side) * table.side,
            table.entries.len,
        );
        for (table.entries, 0..) |entry, first_index| {
            if (table_number == 0) {
                try std.testing.expectEqual(
                    @as(u5, 0),
                    entry.length,
                );
                continue;
            }
            try std.testing.expect(entry.length > 0);
            try std.testing.expect(
                entry.bits < @as(u32, 1) << @intCast(entry.length),
            );
            for (table.entries, 0..) |other, second_index| {
                if (first_index == second_index or
                    entry.length > other.length)
                    continue;
                try std.testing.expect(
                    other.bits >>
                        @intCast(other.length - entry.length) !=
                        entry.bits,
                );
            }

            var encoded: [8]u8 = @splat(0);
            var bit_offset: usize = 0;
            setTestBits(
                &encoded,
                bit_offset,
                @intCast(entry.length),
                entry.bits,
            );
            bit_offset += entry.length;
            const side: usize = table.side;
            const magnitudes = [2]u16{
                @intCast(first_index / side),
                @intCast(first_index % side),
            };
            for (magnitudes) |magnitude| {
                if (magnitude == 15 and table.linbits != 0)
                    bit_offset += table.linbits;
                if (magnitude != 0) bit_offset += 1;
            }
            var reader = MainDataBitReader{
                .bytes = &encoded,
                .bit_limit = bit_offset,
            };
            try std.testing.expectEqual(
                [2]i32{
                    magnitudes[0],
                    magnitudes[1],
                },
                try decodeHuffmanPair(&reader, table),
            );
            try std.testing.expectEqual(
                bit_offset,
                reader.bit_offset,
            );
        }
    }
}

test "requantizes long Layer III spectra with scale factors" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    const bands = try scaleFactorBands(header);
    const preemphasized_line = bands.long_starts[11];
    var quantized = QuantizedSpectrum{
        .decoded_lines = @intCast(preemphasized_line + 1),
    };
    quantized.lines[0] = 1;
    quantized.lines[1] = -8;
    quantized.lines[4] = 1;
    quantized.lines[preemphasized_line] = 1;
    var factors = ScaleFactorChannel{
        .value_count = 22,
        .preflag = true,
    };
    factors.values[1] = 1;
    const decoded = try requantizeChannel(
        header,
        .{
            .global_gain = 210,
            .preflag = true,
        },
        factors,
        quantized,
    );
    try std.testing.expectEqual(@as(f32, 1), decoded.lines[0]);
    try std.testing.expectEqual(@as(f32, -16), decoded.lines[1]);
    try std.testing.expectApproxEqAbs(
        @as(f32, @floatCast(@sqrt(0.5))),
        decoded.lines[4],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, @floatCast(@sqrt(0.5))),
        decoded.lines[preemphasized_line],
        1e-6,
    );
    for ([_]u2{ 1, 3 }) |block_type| {
        const switched = try requantizeChannel(
            header,
            .{
                .global_gain = 210,
                .window_switching = true,
                .block_type = block_type,
                .preflag = true,
            },
            factors,
            quantized,
        );
        try std.testing.expectEqual(@as(f32, 1), switched.lines[0]);
        const mixed = try requantizeChannel(
            header,
            .{
                .global_gain = 210,
                .window_switching = true,
                .block_type = block_type,
                .mixed_block = true,
                .preflag = true,
            },
            factors,
            quantized,
        );
        try std.testing.expectEqual(@as(f32, 1), mixed.lines[0]);
    }
    factors.values[21] = 1;
    try std.testing.expectError(
        error.InvalidMp3ScaleFactors,
        requantizeChannel(
            header,
            .{
                .global_gain = 210,
                .preflag = true,
            },
            factors,
            quantized,
        ),
    );
}

test "requantizes and reorders short Layer III spectra" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var quantized = QuantizedSpectrum{
        .decoded_lines = 9,
    };
    quantized.lines[0] = 1;
    quantized.lines[1] = -1;
    quantized.lines[4] = 1;
    quantized.lines[8] = 1;
    const decoded = try requantizeChannel(
        header,
        .{
            .global_gain = 210,
            .window_switching = true,
            .block_type = 2,
            .subblock_gain = .{ 0, 1, 2 },
        },
        .{ .value_count = 39 },
        quantized,
    );
    try std.testing.expectEqual(@as(f32, 1), decoded.lines[0]);
    try std.testing.expectEqual(@as(f32, 0.25), decoded.lines[1]);
    try std.testing.expectEqual(@as(f32, 0.0625), decoded.lines[2]);
    try std.testing.expectEqual(@as(f32, -1), decoded.lines[3]);

    var invalid = quantized;
    invalid.lines[0] = 8207;
    try std.testing.expectError(
        error.InvalidMp3QuantizedValue,
        requantizeChannel(
            header,
            .{
                .global_gain = 210,
                .window_switching = true,
                .block_type = 2,
            },
            .{ .value_count = 39 },
            invalid,
        ),
    );
    try std.testing.expectError(
        error.InvalidMp3ScaleFactors,
        requantizeChannel(
            header,
            .{},
            .{ .value_count = 20 },
            quantized,
        ),
    );
    try std.testing.expectError(
        error.InvalidMp3ScaleFactors,
        requantizeChannel(
            header,
            .{},
            .{ .value_count = 40 },
            quantized,
        ),
    );
    try std.testing.expectError(
        error.InvalidMp3BlockType,
        requantizeChannel(
            header,
            .{ .block_type = 2 },
            .{ .value_count = 39 },
            quantized,
        ),
    );
    var terminal_factor = ScaleFactorChannel{
        .value_count = 39,
    };
    terminal_factor.values[36] = 1;
    try std.testing.expectError(
        error.InvalidMp3ScaleFactors,
        requantizeChannel(
            header,
            .{
                .window_switching = true,
                .block_type = 2,
            },
            terminal_factor,
            quantized,
        ),
    );
}

test "requantizes mixed blocks at version-specific boundaries" {
    const headers = [_]Header{
        try Header.parse(
            &testHeader(3, true, 9, 0, false, .mono),
        ),
        try Header.parse(
            &testHeader(0, true, 9, 2, false, .mono),
        ),
    };
    for (headers) |header| {
        const bands = try scaleFactorBands(header);
        const boundary: usize = 3 * bands.short_starts[3];
        const width: usize =
            bands.short_starts[4] - bands.short_starts[3];
        var quantized = QuantizedSpectrum{
            .decoded_lines = @intCast(boundary + width + 1),
        };
        quantized.lines[boundary - 1] = -1;
        quantized.lines[boundary + width] = 1;
        const decoded = try requantizeChannel(
            header,
            .{
                .global_gain = 210,
                .window_switching = true,
                .block_type = 2,
                .mixed_block = true,
            },
            .{
                .value_count = if (header.version == .mpeg1) 38 else 33,
            },
            quantized,
        );
        try std.testing.expectEqual(
            @as(f32, -1),
            decoded.lines[boundary - 1],
        );
        try std.testing.expectEqual(
            @as(f32, 1),
            decoded.lines[boundary + 1],
        );
    }

    try std.testing.expectError(
        error.InvalidMp3QuantizedSpectrum,
        requantizeChannel(
            headers[0],
            .{},
            .{ .value_count = 22 },
            .{ .decoded_lines = 577 },
        ),
    );
    var hidden_line = QuantizedSpectrum{};
    hidden_line.lines[0] = 1;
    try std.testing.expectError(
        error.InvalidMp3QuantizedSpectrum,
        requantizeChannel(
            headers[0],
            .{},
            .{ .value_count = 22 },
            hidden_line,
        ),
    );
}

test "reconstructs Layer III mid-side stereo transactionally" {
    var header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .stereo),
    );
    const descriptions: [2]GranuleChannel = @splat(.{});
    const factors: [2]ScaleFactorChannel =
        @splat(.{ .value_count = 22 });
    var spectra: [2]RequantizedSpectrum = @splat(.{});
    spectra[0].lines[0] = 2;
    spectra[1].lines[0] = 1;
    const independent = try processStereo(
        header,
        descriptions,
        factors,
        spectra,
    );
    try std.testing.expectEqual(
        spectra,
        independent.channels,
    );
    header.channel_mode = .joint_stereo;
    header.mode_extension = 2;
    const decoded = try processStereo(
        header,
        descriptions,
        factors,
        spectra,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 3.0 / @sqrt(2.0)),
        decoded.channels[0].lines[0],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0 / @sqrt(2.0)),
        decoded.channels[1].lines[0],
        1e-6,
    );

    var mismatched = descriptions;
    mismatched[1].window_switching = true;
    mismatched[1].block_type = 1;
    try std.testing.expectError(
        error.InvalidMp3StereoBlocks,
        processStereo(header, mismatched, factors, spectra),
    );
    var malformed = spectra;
    malformed[0].lines[0] = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMp3RequantizedSpectrum,
        processStereo(header, descriptions, factors, malformed),
    );
    header.channel_mode = .mono;
    try std.testing.expectError(
        error.InvalidMp3StereoChannels,
        processStereo(header, descriptions, factors, spectra),
    );
}

test "reconstructs MPEG-1 intensity and fallback stereo bands" {
    var header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .stereo),
    );
    header.channel_mode = .joint_stereo;
    header.mode_extension = 3;
    const descriptions: [2]GranuleChannel = @splat(.{});
    var factors: [2]ScaleFactorChannel =
        @splat(.{ .value_count = 22 });
    factors[1].values[1] = 0;
    factors[1].values[2] = 3;
    factors[1].values[3] = 6;
    factors[1].values[4] = 7;
    const bands = try scaleFactorBands(header);
    var spectra: [2]RequantizedSpectrum = @splat(.{});
    spectra[1].lines[0] = 1;
    for (1..5) |band|
        spectra[0].lines[bands.long_starts[band]] = 1;

    const decoded = try processStereo(
        header,
        descriptions,
        factors,
        spectra,
    );
    const position_zero = bands.long_starts[1];
    try std.testing.expectEqual(
        @as(f32, 1),
        decoded.channels[0].lines[position_zero],
    );
    try std.testing.expectEqual(
        @as(f32, 0),
        decoded.channels[1].lines[position_zero],
    );
    const centered = bands.long_starts[2];
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        decoded.channels[0].lines[centered],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        decoded.channels[1].lines[centered],
        1e-6,
    );
    const right = bands.long_starts[3];
    try std.testing.expectEqual(
        @as(f32, 0),
        decoded.channels[0].lines[right],
    );
    try std.testing.expectEqual(
        @as(f32, 1),
        decoded.channels[1].lines[right],
    );
    const fallback = bands.long_starts[4];
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0 / @sqrt(2.0)),
        decoded.channels[0].lines[fallback],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0 / @sqrt(2.0)),
        decoded.channels[1].lines[fallback],
        1e-6,
    );
}

test "reconstructs LSF and per-window short intensity stereo" {
    var lsf_header = try Header.parse(
        &testHeader(2, true, 9, 0, false, .stereo),
    );
    lsf_header.channel_mode = .joint_stereo;
    lsf_header.mode_extension = 1;
    const long_descriptions: [2]GranuleChannel = @splat(.{});
    var long_factors: [2]ScaleFactorChannel =
        @splat(.{ .value_count = 21 });
    long_factors[1].values[1] = 1;
    long_factors[1].values[2] = 2;
    const lsf_bands = try scaleFactorBands(lsf_header);
    var long_spectra: [2]RequantizedSpectrum = @splat(.{});
    long_spectra[0].lines[lsf_bands.long_starts[0]] = 1;
    long_spectra[0].lines[lsf_bands.long_starts[1]] = 1;
    long_spectra[0].lines[lsf_bands.long_starts[2]] = 1;
    const lsf = try processStereo(
        lsf_header,
        long_descriptions,
        long_factors,
        long_spectra,
    );
    try std.testing.expectEqual(
        @as(f32, 1),
        lsf.channels[1].lines[lsf_bands.long_starts[0]],
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, @exp2(-0.25)),
        lsf.channels[0].lines[lsf_bands.long_starts[1]],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, @exp2(-0.25)),
        lsf.channels[1].lines[lsf_bands.long_starts[2]],
        1e-6,
    );
    var fine_scale = long_factors;
    fine_scale[1].intensity_scale = true;
    const fine = try processStereo(
        lsf_header,
        long_descriptions,
        fine_scale,
        long_spectra,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, @exp2(-0.5)),
        fine.channels[0].lines[lsf_bands.long_starts[1]],
        1e-6,
    );
    var fallback_factors = long_factors;
    fallback_factors[1].intensity_max[3] = true;
    var fallback_spectra = long_spectra;
    fallback_spectra[0].lines[lsf_bands.long_starts[3]] = 2;
    fallback_spectra[1].lines[lsf_bands.long_starts[3]] = 1;
    lsf_header.mode_extension = 3;
    const fallback = try processStereo(
        lsf_header,
        long_descriptions,
        fallback_factors,
        fallback_spectra,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 3.0 / @sqrt(2.0)),
        fallback.channels[0].lines[lsf_bands.long_starts[3]],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0 / @sqrt(2.0)),
        fallback.channels[1].lines[lsf_bands.long_starts[3]],
        1e-6,
    );
    lsf_header.mode_extension = 1;
    var invalid_position = long_factors;
    invalid_position[1].values[3] = 16;
    var invalid_spectra = long_spectra;
    invalid_spectra[0].lines[lsf_bands.long_starts[3]] = 1;
    try std.testing.expectError(
        error.InvalidMp3IntensityPosition,
        processStereo(
            lsf_header,
            long_descriptions,
            invalid_position,
            invalid_spectra,
        ),
    );

    var short_header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .stereo),
    );
    short_header.channel_mode = .joint_stereo;
    short_header.mode_extension = 3;
    const short_descriptions: [2]GranuleChannel = @splat(.{
        .window_switching = true,
        .block_type = 2,
    });
    const short_factors: [2]ScaleFactorChannel =
        @splat(.{ .value_count = 39 });
    const short_bands = try scaleFactorBands(short_header);
    var short_spectra: [2]RequantizedSpectrum = @splat(.{});
    short_spectra[0].lines[0] = 1;
    short_spectra[1].lines[0] = 1;
    short_spectra[0].lines[1] = 1;
    const next_band_window_zero =
        3 * @as(usize, short_bands.short_starts[1]);
    short_spectra[0].lines[next_band_window_zero] = 1;
    const short = try processStereo(
        short_header,
        short_descriptions,
        short_factors,
        short_spectra,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, @sqrt(2.0)),
        short.channels[0].lines[0],
        1e-6,
    );
    try std.testing.expectEqual(
        @as(f32, 1),
        short.channels[0].lines[1],
    );
    try std.testing.expectEqual(
        @as(f32, 0),
        short.channels[1].lines[1],
    );
    try std.testing.expectEqual(
        @as(f32, 1),
        short.channels[0].lines[next_band_window_zero],
    );

    const mixed_descriptions: [2]GranuleChannel = @splat(.{
        .window_switching = true,
        .block_type = 2,
        .mixed_block = true,
    });
    const mixed_factors: [2]ScaleFactorChannel =
        @splat(.{ .value_count = 38 });
    const mixed_boundary: usize = 3 * short_bands.short_starts[3];
    var mixed_spectra: [2]RequantizedSpectrum = @splat(.{});
    mixed_spectra[0].lines[0] = 1;
    mixed_spectra[0].lines[mixed_boundary] = 1;
    const mixed = try processStereo(
        short_header,
        mixed_descriptions,
        mixed_factors,
        mixed_spectra,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0 / @sqrt(2.0)),
        mixed.channels[0].lines[0],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0 / @sqrt(2.0)),
        mixed.channels[1].lines[0],
        1e-6,
    );
    try std.testing.expectEqual(
        @as(f32, 1),
        mixed.channels[0].lines[mixed_boundary],
    );
    try std.testing.expectEqual(
        @as(f32, 0),
        mixed.channels[1].lines[mixed_boundary],
    );

    var low_rate_header = try Header.parse(
        &testHeader(0, true, 9, 2, false, .stereo),
    );
    low_rate_header.channel_mode = .joint_stereo;
    low_rate_header.mode_extension = 1;
    const low_rate_bands = try scaleFactorBands(low_rate_header);
    const low_rate_boundary: usize =
        3 * low_rate_bands.short_starts[3];
    const low_rate_factors: [2]ScaleFactorChannel =
        @splat(.{ .value_count = 33 });
    var low_rate_spectra: [2]RequantizedSpectrum = @splat(.{});
    low_rate_spectra[0].lines[low_rate_boundary - 1] = 1;
    low_rate_spectra[0].lines[low_rate_boundary] = 1;
    const low_rate = try processStereo(
        low_rate_header,
        mixed_descriptions,
        low_rate_factors,
        low_rate_spectra,
    );
    try std.testing.expectEqual(@as(usize, 72), low_rate_boundary);
    try std.testing.expectEqual(
        @as(f32, 1),
        low_rate.channels[0].lines[low_rate_boundary - 1],
    );
    try std.testing.expectEqual(
        @as(f32, 0),
        low_rate.channels[1].lines[low_rate_boundary - 1],
    );
    try std.testing.expectEqual(
        @as(f32, 1),
        low_rate.channels[0].lines[low_rate_boundary],
    );
    try std.testing.expectEqual(
        @as(f32, 1),
        low_rate.channels[1].lines[low_rate_boundary],
    );
}

test "reduces Layer III aliases across long and mixed boundaries" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var long_spectrum = RequantizedSpectrum{};
    for (1..32) |subband| {
        const boundary = 18 * subband;
        long_spectrum.lines[boundary - 1] =
            @floatFromInt(subband);
        long_spectrum.lines[boundary] =
            @floatFromInt(subband + 1);
    }
    for (0..8) |index| {
        long_spectrum.lines[17 - index] =
            @floatFromInt(index + 1);
        long_spectrum.lines[18 + index] =
            @floatFromInt(index + 2);
    }
    const reduced = try reduceAliases(
        header,
        .{},
        long_spectrum,
    );
    for (1..32) |subband| {
        const boundary = 18 * subband;
        const upper: f32 = @floatFromInt(subband);
        const lower: f32 = @floatFromInt(subband + 1);
        try std.testing.expectApproxEqAbs(
            upper * alias_cs[0] - lower * alias_ca[0],
            reduced.lines[boundary - 1],
            1e-6,
        );
        try std.testing.expectApproxEqAbs(
            lower * alias_cs[0] + upper * alias_ca[0],
            reduced.lines[boundary],
            1e-6,
        );
    }
    const alias_c = [_]f32{
        -0.6,
        -0.535,
        -0.33,
        -0.185,
        -0.095,
        -0.041,
        -0.0142,
        -0.0037,
    };
    for (alias_c, alias_cs, alias_ca, 0..) |c, cs, ca, index| {
        const wide_c: f64 = c;
        const expected_cs: f32 =
            @floatCast(1.0 / @sqrt(1.0 + wide_c * wide_c));
        try std.testing.expectApproxEqAbs(expected_cs, cs, 1e-7);
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(wide_c * expected_cs)),
            ca,
            1e-7,
        );
        const upper: f32 = @floatFromInt(index + 1);
        const lower: f32 = @floatFromInt(index + 2);
        try std.testing.expectApproxEqAbs(
            upper * cs - lower * ca,
            reduced.lines[17 - index],
            1e-6,
        );
        try std.testing.expectApproxEqAbs(
            lower * cs + upper * ca,
            reduced.lines[18 + index],
            1e-6,
        );
    }

    const pure_short = try reduceAliases(
        header,
        .{
            .window_switching = true,
            .block_type = 2,
        },
        long_spectrum,
    );
    try std.testing.expectEqual(long_spectrum, pure_short);

    var mixed_spectrum = RequantizedSpectrum{};
    mixed_spectrum.lines[17] = 1;
    mixed_spectrum.lines[18] = 2;
    mixed_spectrum.lines[35] = 3;
    mixed_spectrum.lines[36] = 4;
    const mixed = try reduceAliases(
        header,
        .{
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
        mixed_spectrum,
    );
    try std.testing.expect(mixed.lines[17] != 1);
    try std.testing.expect(mixed.lines[18] != 2);
    try std.testing.expectEqual(@as(f32, 3), mixed.lines[35]);
    try std.testing.expectEqual(@as(f32, 4), mixed.lines[36]);

    const low_rate_header = try Header.parse(
        &testHeader(0, true, 9, 2, false, .mono),
    );
    var low_rate_spectrum = RequantizedSpectrum{};
    for (1..5) |subband| {
        const boundary = 18 * subband;
        low_rate_spectrum.lines[boundary - 1] = 1;
        low_rate_spectrum.lines[boundary] = 2;
    }
    const low_rate = try reduceAliases(
        low_rate_header,
        .{
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
        low_rate_spectrum,
    );
    for (1..4) |subband| {
        const boundary = 18 * subband;
        try std.testing.expect(low_rate.lines[boundary - 1] != 1);
        try std.testing.expect(low_rate.lines[boundary] != 2);
    }
    try std.testing.expectEqual(
        @as(f32, 1),
        low_rate.lines[4 * 18 - 1],
    );
    try std.testing.expectEqual(
        @as(f32, 2),
        low_rate.lines[4 * 18],
    );

    const mixed_start = try reduceAliases(
        header,
        .{
            .window_switching = true,
            .block_type = 1,
            .mixed_block = true,
        },
        long_spectrum,
    );
    try std.testing.expect(mixed_start.lines[31 * 18 - 1] !=
        long_spectrum.lines[31 * 18 - 1]);

    const prepared = try prepareAliasesForEncoding(
        header,
        .{},
        reduced,
    );
    for (long_spectrum.lines, prepared.lines) |expected, actual| {
        try std.testing.expectApproxEqAbs(expected, actual, 5e-6);
    }
    const mixed_prepared = try prepareAliasesForEncoding(
        header,
        .{
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
        mixed,
    );
    for (mixed_spectrum.lines, mixed_prepared.lines) |expected, actual| {
        try std.testing.expectApproxEqAbs(expected, actual, 5e-6);
    }
    const short_prepared = try prepareAliasesForEncoding(
        header,
        .{
            .window_switching = true,
            .block_type = 2,
        },
        long_spectrum,
    );
    try std.testing.expectEqual(long_spectrum, short_prepared);

    var malformed = long_spectrum;
    malformed.lines[0] = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMp3RequantizedSpectrum,
        reduceAliases(header, .{}, malformed),
    );
    try std.testing.expectError(
        error.InvalidMp3BlockType,
        reduceAliases(
            header,
            .{ .block_type = 2 },
            long_spectrum,
        ),
    );
    try std.testing.expectError(
        error.InvalidMp3RequantizedSpectrum,
        prepareAliasesForEncoding(header, .{}, malformed),
    );
}

test "synthesizes long MP3 hybrid blocks with overlap and inversion" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var spectrum = RequantizedSpectrum{};
    spectrum.lines[0] = 1;
    spectrum.lines[18] = 1;
    var synthesis = HybridSynthesis{};
    const first = try synthesis.process(header, .{}, spectrum);
    for (0..36) |time| {
        const position: f64 = @floatFromInt(time);
        const transformed = @cos(
            std.math.pi / 18.0 *
                (position + 9.5) * 0.5,
        ) * @sin(
            std.math.pi / 36.0 * (position + 0.5),
        );
        if (time < 18) {
            try std.testing.expectApproxEqAbs(
                @as(f32, @floatCast(transformed)),
                first.time_slots[time][0],
                1e-6,
            );
            try std.testing.expectApproxEqAbs(
                @as(f32, @floatCast(
                    if (time & 1 == 0)
                        transformed
                    else
                        -transformed,
                )),
                first.time_slots[time][1],
                1e-6,
            );
        } else {
            try std.testing.expectApproxEqAbs(
                @as(f32, @floatCast(transformed)),
                synthesis.overlap[0][time - 18],
                1e-6,
            );
            try std.testing.expectApproxEqAbs(
                @as(f32, @floatCast(transformed)),
                synthesis.overlap[1][time - 18],
                1e-6,
            );
        }
    }

    const second = try synthesis.process(
        header,
        .{},
        .{},
    );
    for (0..18) |time| {
        const position: f64 = @floatFromInt(time + 18);
        const tail = @cos(
            std.math.pi / 18.0 *
                (position + 9.5) * 0.5,
        ) * @sin(
            std.math.pi / 36.0 * (position + 0.5),
        );
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(tail)),
            second.time_slots[time][0],
            1e-6,
        );
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(
                if (time & 1 == 0) tail else -tail,
            )),
            second.time_slots[time][1],
            1e-6,
        );
    }
    try std.testing.expectEqual(
        @as([32][18]f32, @splat(@splat(0))),
        synthesis.overlap,
    );

    _ = try synthesis.process(header, .{}, spectrum);
    synthesis.reset();
    try std.testing.expectEqual(HybridSynthesis{}, synthesis);
}

test "synthesizes short transition and mixed MP3 hybrid blocks" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    const short_description = GranuleChannel{
        .window_switching = true,
        .block_type = 2,
    };
    var short_spectrum = RequantizedSpectrum{};
    short_spectrum.lines[0] = 1;
    short_spectrum.lines[1] = 2;
    short_spectrum.lines[2] = 3;
    var short_synthesis = HybridSynthesis{};
    const short = try short_synthesis.process(
        header,
        short_description,
        short_spectrum,
    );
    var expected_short: [36]f64 = @splat(0);
    for (0..3) |window| {
        const magnitude: f64 = @floatFromInt(window + 1);
        for (0..12) |time| {
            const position: f64 = @floatFromInt(time);
            expected_short[6 + window * 6 + time] +=
                magnitude *
                @cos(
                    std.math.pi / 6.0 *
                        (position + 3.5) * 0.5,
                ) *
                @sin(std.math.pi / 12.0 * (position + 0.5));
        }
    }
    for (0..18) |time| {
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(expected_short[time])),
            short.time_slots[time][0],
            1e-6,
        );
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(expected_short[time + 18])),
            short_synthesis.overlap[0][time],
            1e-6,
        );
    }
    for (0..6) |time| {
        try std.testing.expectEqual(
            @as(f32, 0),
            short.time_slots[time][0],
        );
        try std.testing.expectEqual(
            @as(f32, 0),
            short_synthesis.overlap[0][time + 12],
        );
    }

    var transition_spectrum = RequantizedSpectrum{};
    transition_spectrum.lines[0] = 1;
    var start_synthesis = HybridSynthesis{};
    _ = try start_synthesis.process(
        header,
        .{
            .window_switching = true,
            .block_type = 1,
        },
        transition_spectrum,
    );
    for (12..18) |time|
        try std.testing.expectEqual(
            @as(f32, 0),
            start_synthesis.overlap[0][time],
        );
    var stop_synthesis = HybridSynthesis{};
    const stop = try stop_synthesis.process(
        header,
        .{
            .window_switching = true,
            .block_type = 3,
        },
        transition_spectrum,
    );
    for (0..6) |time|
        try std.testing.expectEqual(
            @as(f32, 0),
            stop.time_slots[time][0],
        );

    const mixed_description = GranuleChannel{
        .window_switching = true,
        .block_type = 2,
        .mixed_block = true,
    };
    var mixed_spectrum = RequantizedSpectrum{};
    mixed_spectrum.lines[0] = 1;
    mixed_spectrum.lines[18] = 1;
    mixed_spectrum.lines[36] = 1;
    var mixed_synthesis = HybridSynthesis{};
    const mixed = try mixed_synthesis.process(
        header,
        mixed_description,
        mixed_spectrum,
    );
    try std.testing.expect(mixed.time_slots[0][0] != 0);
    try std.testing.expect(mixed.time_slots[0][1] != 0);
    for (0..6) |time|
        try std.testing.expectEqual(
            @as(f32, 0),
            mixed.time_slots[time][2],
        );

    const low_rate_header = try Header.parse(
        &testHeader(0, true, 9, 2, false, .mono),
    );
    var low_rate_spectrum = RequantizedSpectrum{};
    low_rate_spectrum.lines[3 * 18] = 1;
    low_rate_spectrum.lines[4 * 18] = 1;
    var low_rate_synthesis = HybridSynthesis{};
    const low_rate = try low_rate_synthesis.process(
        low_rate_header,
        mixed_description,
        low_rate_spectrum,
    );
    try std.testing.expect(low_rate.time_slots[0][3] != 0);
    for (0..6) |time|
        try std.testing.expectEqual(
            @as(f32, 0),
            low_rate.time_slots[time][4],
        );

    const preserved = low_rate_synthesis;
    var malformed = RequantizedSpectrum{};
    malformed.lines[0] = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMp3RequantizedSpectrum,
        low_rate_synthesis.process(
            low_rate_header,
            mixed_description,
            malformed,
        ),
    );
    try std.testing.expectEqual(preserved, low_rate_synthesis);

    var overflowing = RequantizedSpectrum{};
    for (0..18) |frequency| {
        overflowing.lines[frequency] =
            if (long_imdct[8][frequency] < 0)
                -std.math.floatMax(f32)
            else
                std.math.floatMax(f32);
    }
    const before_overflow = low_rate_synthesis;
    try std.testing.expectError(
        error.InvalidMp3HybridSample,
        low_rate_synthesis.process(
            low_rate_header,
            .{},
            overflowing,
        ),
    );
    try std.testing.expectEqual(before_overflow, low_rate_synthesis);

    low_rate_synthesis.overlap[0][0] = std.math.inf(f32);
    try std.testing.expect(!low_rate_synthesis.valid());
    const invalid_synthesis = low_rate_synthesis;
    try std.testing.expectError(
        error.InvalidMp3HybridState,
        low_rate_synthesis.process(
            low_rate_header,
            .{},
            .{},
        ),
    );
    try std.testing.expectEqual(invalid_synthesis, low_rate_synthesis);
    low_rate_synthesis.reset();
    try std.testing.expect(low_rate_synthesis.valid());
    try std.testing.expectError(
        error.InvalidMp3BlockType,
        low_rate_synthesis.process(
            low_rate_header,
            .{ .block_type = 2 },
            .{},
        ),
    );
}

test "round trips MP3 hybrid analysis across window transitions" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    const descriptions = [_]GranuleChannel{
        .{},
        .{},
        .{
            .window_switching = true,
            .block_type = 1,
        },
        .{
            .window_switching = true,
            .block_type = 2,
        },
        .{
            .window_switching = true,
            .block_type = 2,
        },
        .{
            .window_switching = true,
            .block_type = 3,
        },
        .{},
        .{},
    };
    var analysis = HybridAnalysis{};
    var synthesis = HybridSynthesis{};
    var maximum_error: f32 = 0;
    for (descriptions, 0..) |description, granule| {
        var input = HybridSamples{};
        for (&input.time_slots, 0..) |*time_slot, time| {
            for (time_slot, 0..) |*sample, band| {
                const phase: f32 = @floatFromInt(
                    (granule * 18 + time) * 7 + band * 11,
                );
                sample.* = 0.4 * @sin(phase * 0.037) +
                    0.15 * @cos(phase * 0.091);
            }
        }
        const encoded = try analysis.process(
            header,
            description,
            input,
        );
        const output = try synthesis.process(
            header,
            description,
            try reduceAliases(header, description, encoded),
        );
        if (granule == 0) continue;
        for (output.time_slots, 0..) |time_slot, time| {
            for (time_slot, 0..) |sample, band| {
                const phase: f32 = @floatFromInt(
                    ((granule - 1) * 18 + time) * 7 +
                        band * 11,
                );
                const expected =
                    0.4 * @sin(phase * 0.037) +
                    0.15 * @cos(phase * 0.091);
                maximum_error = @max(
                    maximum_error,
                    @abs(sample - expected),
                );
            }
        }
    }
    try std.testing.expect(maximum_error < 0.00001);

    analysis.reset();
    try std.testing.expectEqual(HybridAnalysis{}, analysis);
}

test "round trips mixed MP3 hybrid analysis at both boundaries" {
    const headers = [_]Header{
        try Header.parse(
            &testHeader(3, true, 9, 0, false, .mono),
        ),
        try Header.parse(
            &testHeader(0, true, 9, 2, false, .mono),
        ),
    };
    const description = GranuleChannel{
        .window_switching = true,
        .block_type = 2,
        .mixed_block = true,
    };
    for (headers) |header| {
        var analysis = HybridAnalysis{};
        var synthesis = HybridSynthesis{};
        var maximum_error: f32 = 0;
        for (0..4) |granule| {
            var input = HybridSamples{};
            for (&input.time_slots, 0..) |*time_slot, time| {
                for (time_slot, 0..) |*sample, band| {
                    const phase: f32 = @floatFromInt(
                        (granule * 18 + time) * 5 + band * 13,
                    );
                    sample.* = 0.45 * @sin(phase * 0.041);
                }
            }
            const encoded = try analysis.process(
                header,
                description,
                input,
            );
            const output = try synthesis.process(
                header,
                description,
                try reduceAliases(header, description, encoded),
            );
            if (granule == 0) continue;
            for (output.time_slots, 0..) |time_slot, time| {
                for (time_slot, 0..) |sample, band| {
                    const phase: f32 = @floatFromInt(
                        ((granule - 1) * 18 + time) * 5 +
                            band * 13,
                    );
                    maximum_error = @max(
                        maximum_error,
                        @abs(sample -
                            0.45 * @sin(phase * 0.041)),
                    );
                }
            }
        }
        try std.testing.expect(maximum_error < 0.00001);
    }
}

test "rejects invalid MP3 hybrid analysis transactionally" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var analysis = HybridAnalysis{};
    try std.testing.expect(analysis.valid());
    var malformed = HybridSamples{};
    malformed.time_slots[0][0] = std.math.nan(f32);
    const initial = analysis;
    try std.testing.expectError(
        error.InvalidMp3HybridSamples,
        analysis.process(header, .{}, malformed),
    );
    try std.testing.expectEqual(initial, analysis);

    analysis.history[0][0] = std.math.inf(f32);
    try std.testing.expect(!analysis.valid());
    const bad_history = analysis;
    try std.testing.expectError(
        error.InvalidMp3HybridAnalysisState,
        analysis.process(header, .{}, .{}),
    );
    try std.testing.expectEqual(bad_history, analysis);

    analysis = .{};
    try std.testing.expect(analysis.valid());
    var overflowing = HybridSamples{};
    overflowing.time_slots = @splat(
        @splat(std.math.floatMax(f32)),
    );
    const before_overflow = analysis;
    try std.testing.expectError(
        error.InvalidMp3HybridSample,
        analysis.process(header, .{}, overflowing),
    );
    try std.testing.expectEqual(before_overflow, analysis);

    try std.testing.expectError(
        error.InvalidMp3BlockType,
        analysis.process(
            header,
            .{ .block_type = 2 },
            .{},
        ),
    );
    try std.testing.expectEqual(before_overflow, analysis);
}

test "preserves the quantized MP3 synthesis window" {
    try std.testing.expectEqual(
        @as(usize, 512),
        synthesis_window_quantized.len,
    );
    try std.testing.expectEqual(
        @as(i32, 0),
        synthesis_window_quantized[0],
    );
    try std.testing.expectEqual(
        @as(i32, 213),
        synthesis_window_quantized[64],
    );
    try std.testing.expectEqual(
        @as(i32, 2037),
        synthesis_window_quantized[128],
    );
    try std.testing.expectEqual(
        @as(i32, 75_038),
        synthesis_window_quantized[256],
    );
    try std.testing.expectEqual(
        @as(i32, 1),
        synthesis_window_quantized[511],
    );

    var synthesis_hash = std.crypto.hash.sha2.Sha256.init(.{});
    var encoded_value: [4]u8 = undefined;
    for (synthesis_window_quantized) |value| {
        std.mem.writeInt(u32, &encoded_value, @bitCast(value), .big);
        synthesis_hash.update(&encoded_value);
    }
    var synthesis_digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 =
        undefined;
    synthesis_hash.final(&synthesis_digest);
    var expected_digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 =
        undefined;
    _ = try std.fmt.hexToBytes(
        &expected_digest,
        "e8d6792457f2a517d0e36a87d29f83610aa00d6cca6281f0b31802faa4b2ccf3",
    );
    try std.testing.expectEqual(expected_digest, synthesis_digest);
}

test "preserves the MP3 Huffman table codewords" {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    var encoded_bits: [4]u8 = undefined;
    for (0..32) |table_index| {
        const index: u5 = @intCast(table_index);
        const table = huffman_tables.get(index) catch |err| switch (err) {
            error.InvalidMp3HuffmanTable => {
                hash.update(&.{ @intCast(index), 0xff });
                continue;
            },
        };
        hash.update(&.{
            @intCast(index),
            @intCast(table.side),
            @intCast(table.linbits),
        });
        for (table.entries) |entry| {
            hash.update(&.{@intCast(entry.length)});
            std.mem.writeInt(u32, &encoded_bits, entry.bits, .big);
            hash.update(&encoded_bits);
        }
    }
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hash.final(&digest);
    var expected_digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 =
        undefined;
    _ = try std.fmt.hexToBytes(
        &expected_digest,
        "9fdeb0ca3c74ac54a8ee9154544e8dced73aef97837de1311572e75866de76ec",
    );
    try std.testing.expectEqual(expected_digest, digest);
}

test "synthesizes MP3 polyphase PCM against a shift register" {
    var hybrid = HybridSamples{};
    for (&hybrid.time_slots, 0..) |*time_slot, time| {
        for (time_slot, 0..) |*sample, band| {
            const pattern: i16 =
                @intCast((time * 17 + band * 13) % 29);
            sample.* =
                @as(f32, @floatFromInt(pattern - 14)) / 17.0;
        }
    }

    var synthesis = PolyphaseSynthesis{};
    var reference_history: [1024]f64 = @splat(0);
    const first = try synthesis.process(hybrid);
    for (&hybrid.time_slots, 0..) |*time_slot, time| {
        const reference = referencePolyphaseTimeSlot(
            &reference_history,
            time_slot,
        );
        for (reference, 0..) |expected, sample| {
            try std.testing.expectApproxEqAbs(
                @as(f32, @floatCast(expected)),
                first.samples[time * 32 + sample],
                1e-5,
            );
        }
    }

    const second = try synthesis.process(.{});
    const silence = [_]f32{0} ** 32;
    for (0..18) |time| {
        const reference = referencePolyphaseTimeSlot(
            &reference_history,
            &silence,
        );
        for (reference, 0..) |expected, sample| {
            try std.testing.expectApproxEqAbs(
                @as(f32, @floatCast(expected)),
                second.samples[time * 32 + sample],
                1e-5,
            );
        }
    }

    synthesis.reset();
    try std.testing.expectEqual(
        PolyphaseSynthesis{},
        synthesis,
    );
    const zero = try synthesis.process(.{});
    try std.testing.expectEqual(PcmGranule{}, zero);
}

test "rejects invalid MP3 polyphase input and state transactionally" {
    var synthesis = PolyphaseSynthesis{};
    try std.testing.expect(synthesis.valid());
    var malformed = HybridSamples{};
    malformed.time_slots[0][0] = std.math.nan(f32);
    const initial = synthesis;
    try std.testing.expectError(
        error.InvalidMp3HybridSamples,
        synthesis.process(malformed),
    );
    try std.testing.expectEqual(initial, synthesis);

    synthesis.head_block = 16;
    try std.testing.expect(!synthesis.valid());
    const bad_head = synthesis;
    try std.testing.expectError(
        error.InvalidMp3PolyphaseState,
        synthesis.process(.{}),
    );
    try std.testing.expectEqual(bad_head, synthesis);

    synthesis = .{};
    synthesis.history[17] = std.math.inf(f64);
    try std.testing.expect(!synthesis.valid());
    const bad_history = synthesis;
    try std.testing.expectError(
        error.InvalidMp3PolyphaseState,
        synthesis.process(.{}),
    );
    try std.testing.expectEqual(bad_history, synthesis);

    synthesis = .{};
    try std.testing.expect(synthesis.valid());
    var overflowing = HybridSamples{};
    for (&overflowing.time_slots[0], 0..) |*sample, band| {
        sample.* = if (synthesis_matrix[0][band] < 0)
            -std.math.floatMax(f32)
        else
            std.math.floatMax(f32);
    }
    const before_overflow = synthesis;
    try std.testing.expectError(
        error.InvalidMp3PolyphaseSample,
        synthesis.process(overflowing),
    );
    try std.testing.expectEqual(before_overflow, synthesis);
}

test "round trips the MP3 polyphase analysis and synthesis banks" {
    var analysis = PolyphaseAnalysis{};
    var synthesis = PolyphaseSynthesis{};
    var maximum_error: f32 = 0;
    for (0..8) |granule| {
        var pcm = PcmGranule{};
        for (&pcm.samples, 0..) |*sample, index| {
            const absolute: f32 =
                @floatFromInt(granule * 576 + index);
            sample.* = 0.6 * @sin(absolute * 0.071) +
                0.2 * @cos(absolute * 0.193);
        }
        const output = try synthesis.process(
            try analysis.process(pcm),
        );
        for (output.samples, 0..) |sample, index| {
            const absolute = granule * 576 + index;
            if (absolute < 481) continue;
            const source: f32 =
                @floatFromInt(absolute - 481);
            const expected = 0.6 * @sin(source * 0.071) +
                0.2 * @cos(source * 0.193);
            maximum_error = @max(
                maximum_error,
                @abs(sample - expected),
            );
        }
    }
    try std.testing.expect(maximum_error < 0.00007);

    analysis.reset();
    synthesis.reset();
    var impulse = PcmGranule{};
    impulse.samples[0] = 1;
    var peak: f32 = 0;
    var peak_index: usize = 0;
    for (0..2) |granule| {
        const output = try synthesis.process(
            try analysis.process(
                if (granule == 0) impulse else .{},
            ),
        );
        for (output.samples, 0..) |sample, index| {
            if (@abs(sample) > @abs(peak)) {
                peak = sample;
                peak_index = granule * 576 + index;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 481), peak_index);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1),
        peak,
        0.00001,
    );
}

test "rejects invalid MP3 polyphase analysis transactionally" {
    var analysis = PolyphaseAnalysis{};
    try std.testing.expect(analysis.valid());
    var malformed = PcmGranule{};
    malformed.samples[0] = std.math.nan(f32);
    const initial = analysis;
    try std.testing.expectError(
        error.InvalidMp3PcmSamples,
        analysis.process(malformed),
    );
    try std.testing.expectEqual(initial, analysis);

    analysis.history[0] = std.math.inf(f64);
    try std.testing.expect(!analysis.valid());
    const bad_history = analysis;
    try std.testing.expectError(
        error.InvalidMp3PolyphaseAnalysisState,
        analysis.process(.{}),
    );
    try std.testing.expectEqual(bad_history, analysis);

    analysis = .{};
    try std.testing.expect(analysis.valid());
    var overflowing = PcmGranule{};
    overflowing.samples = @splat(std.math.floatMax(f32));
    const before_overflow = analysis;
    try std.testing.expectError(
        error.InvalidMp3HybridSample,
        analysis.process(overflowing),
    );
    try std.testing.expectEqual(before_overflow, analysis);

    analysis.reset();
    try std.testing.expect(analysis.valid());
    try std.testing.expectEqual(PolyphaseAnalysis{}, analysis);
}

test "analyzes complete MP3 PCM frames for decoder reconstruction" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .stereo,
    };
    const header = try config.header(false);
    var analysis = try EncoderAnalysis.init(config);
    var hybrid_synthesis: [2]HybridSynthesis = @splat(.{});
    var polyphase_synthesis: [2]PolyphaseSynthesis = @splat(.{});
    const descriptions: [2][2]GranuleChannel =
        @splat(@splat(.{}));
    var maximum_error: f32 = 0;

    for (0..5) |frame_index| {
        var pcm = PcmFrame{
            .channel_count = 2,
            .sample_count = 1152,
        };
        for (0..2) |channel| {
            for (&pcm.channels[channel], 0..) |*sample, index| {
                const absolute: f32 =
                    @floatFromInt(frame_index * 1152 + index);
                const channel_phase: f32 =
                    @floatFromInt(channel);
                sample.* =
                    0.5 * @sin(absolute * 0.029 +
                        channel_phase * 0.4) +
                    0.1 * @cos(absolute * 0.083 -
                        channel_phase * 0.2);
            }
        }
        const analyzed = try analysis.analyze(
            descriptions,
            pcm,
        );
        try std.testing.expectEqual(
            @as(u2, 2),
            analyzed.channel_count,
        );
        try std.testing.expectEqual(
            @as(u2, 2),
            analyzed.granule_count,
        );
        for (0..2) |granule| {
            for (0..2) |channel| {
                const analyzed_channel =
                    analyzed.granules[granule][channel];
                const hybrid = try hybrid_synthesis[channel].process(
                    header,
                    analyzed_channel.description,
                    try reduceAliases(
                        header,
                        analyzed_channel.description,
                        analyzed_channel.spectrum,
                    ),
                );
                const reconstructed =
                    try polyphase_synthesis[channel].process(hybrid);
                for (reconstructed.samples, 0..) |sample, index| {
                    const absolute =
                        frame_index * 1152 +
                        granule * 576 +
                        index;
                    if (absolute < 1057) continue;
                    const source: f32 =
                        @floatFromInt(absolute - 1057);
                    const channel_phase: f32 =
                        @floatFromInt(channel);
                    const expected =
                        0.5 * @sin(source * 0.029 +
                            channel_phase * 0.4) +
                        0.1 * @cos(source * 0.083 -
                            channel_phase * 0.2);
                    maximum_error = @max(
                        maximum_error,
                        @abs(sample - expected),
                    );
                }
            }
        }
    }
    try std.testing.expect(maximum_error < 0.00008);
    try std.testing.expectEqual(
        @as(u64, 5),
        analysis.frames_analyzed,
    );
}

test "validates MP3 encoder analysis state transactionally" {
    const config = EncoderConfig{
        .version = .mpeg2,
        .bitrate_kbps = 64,
        .sample_rate = 22_050,
        .channel_mode = .mono,
    };
    var analysis = try EncoderAnalysis.init(config);
    try std.testing.expect(analysis.valid());
    const descriptions: [2][2]GranuleChannel =
        @splat(@splat(.{}));
    const pcm = PcmFrame{
        .channel_count = 1,
        .sample_count = 576,
    };
    const first = try analysis.analyze(descriptions, pcm);
    try std.testing.expect(analysis.valid());
    try std.testing.expectEqual(@as(u2, 1), first.channel_count);
    try std.testing.expectEqual(@as(u2, 1), first.granule_count);
    try std.testing.expectEqual(
        AnalyzedEncoderChannel{},
        first.granules[0][1],
    );
    try std.testing.expectEqual(
        AnalyzedEncoderChannel{},
        first.granules[1][0],
    );

    var wrong_count = pcm;
    wrong_count.sample_count = 575;
    const before_count = analysis;
    try std.testing.expectError(
        error.InvalidMp3EncoderPcmFrame,
        analysis.analyze(descriptions, wrong_count),
    );
    try std.testing.expectEqual(before_count, analysis);

    var malformed = pcm;
    malformed.channels[0][0] = std.math.nan(f32);
    const before_malformed = analysis;
    try std.testing.expectError(
        error.InvalidMp3PcmSamples,
        analysis.analyze(descriptions, malformed),
    );
    try std.testing.expectEqual(before_malformed, analysis);

    var hidden_description = descriptions;
    hidden_description[1][0].global_gain = 1;
    const before_hidden = analysis;
    try std.testing.expectError(
        error.InvalidMp3EncoderAnalysisFrame,
        analysis.analyze(hidden_description, pcm),
    );
    try std.testing.expectEqual(before_hidden, analysis);

    analysis.config.sample_rate = 24_000;
    try std.testing.expect(!analysis.valid());
    const before_format = analysis;
    try std.testing.expectError(
        error.Mp3EncoderAnalysisFormatChanged,
        analysis.analyze(descriptions, pcm),
    );
    try std.testing.expectEqual(before_format, analysis);
    analysis.config = config;

    analysis.polyphase[0].history[0] = std.math.inf(f64);
    try std.testing.expect(!analysis.valid());
    const before_history = analysis;
    try std.testing.expectError(
        error.InvalidMp3EncoderAnalysisState,
        analysis.analyze(descriptions, pcm),
    );
    try std.testing.expectEqual(before_history, analysis);
    analysis.polyphase[0].reset();
    try std.testing.expect(analysis.valid());

    analysis.frames_analyzed = std.math.maxInt(u64);
    const before_overflow = analysis;
    try std.testing.expectError(
        error.Mp3EncoderFrameCountOverflow,
        analysis.analyze(descriptions, pcm),
    );
    try std.testing.expectEqual(before_overflow, analysis);

    analysis.frames_analyzed = 3;
    analysis.reset();
    try std.testing.expect(analysis.valid());
    try std.testing.expectEqual(@as(u64, 0), analysis.frames_analyzed);
    try std.testing.expectEqual(config, analysis.config);
    try std.testing.expectEqual(
        formatFromHeader(try config.header(false)),
        analysis.format,
    );
    try std.testing.expectEqual(
        @as([2]PolyphaseAnalysis, @splat(.{})),
        analysis.polyphase,
    );
    try std.testing.expectEqual(
        @as([2]HybridAnalysis, @splat(.{})),
        analysis.hybrid,
    );
}

test "composes silent MP3 frames through the complete decoder" {
    const header_bytes =
        testHeader(3, true, 9, 0, false, .mono);
    var encoded: [500]u8 = undefined;
    const frame_end = try appendFrame(
        &encoded,
        0,
        header_bytes,
    );
    const frame = try Frame.parse(encoded[0..frame_end], 0);

    var decoder = FrameDecoder{};
    try std.testing.expect(decoder.valid());
    const decoded = try decoder.decode(frame);
    try std.testing.expect(decoder.valid());
    try std.testing.expectEqual(@as(u2, 1), decoded.channel_count);
    try std.testing.expectEqual(@as(u16, 1152), decoded.sample_count);
    for (decoded.channels[0]) |sample|
        try std.testing.expectEqual(@as(f32, 0), sample);
    for (decoded.channels[1]) |sample|
        try std.testing.expectEqual(@as(f32, 0), sample);
    try std.testing.expectEqual(
        @as(?DecoderFormat, .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_count = 1,
        }),
        decoder.format,
    );

    var hostile_decoder = decoder;
    hostile_decoder.hybrid[0].overlap[0][0] = std.math.inf(f32);
    try std.testing.expect(!hostile_decoder.valid());
    const hostile_decoder_before = hostile_decoder;
    try std.testing.expectError(
        error.InvalidMp3DecoderState,
        hostile_decoder.decode(frame),
    );
    try std.testing.expectEqual(
        hostile_decoder_before,
        hostile_decoder,
    );

    const file_frame = FileFrame{
        .byte_offset = 0,
        .bytes = frame.bytes,
        .header = frame.header,
        .xing = frame.xing,
        .vbri = frame.vbri,
    };
    var file_decoder = FrameDecoder{};
    try std.testing.expectEqual(
        decoded,
        try file_decoder.decode(file_frame),
    );

    decoder.reset();
    try std.testing.expect(decoder.valid());
    try std.testing.expectEqual(FrameDecoder{}, decoder);
}

test "decodes MP3 main data across frame reservoir boundaries" {
    const header_bytes =
        testHeader(3, true, 9, 0, false, .mono);
    var first_bytes: [500]u8 = undefined;
    const first_end = try appendFrame(
        &first_bytes,
        0,
        header_bytes,
    );
    first_bytes[first_end - 1] = 0x08;
    const first = try Frame.parse(
        first_bytes[0..first_end],
        0,
    );

    var second_bytes: [500]u8 = undefined;
    const second_end = try appendFrame(
        &second_bytes,
        0,
        header_bytes,
    );
    const second_side = second_bytes[4..21];
    setTestBits(second_side, 0, 9, 1);
    setMpeg1MonoLongChannel(
        second_side,
        0,
        5,
        1,
        210,
        1,
    );
    setMpeg1MonoLongChannel(
        second_side,
        1,
        0,
        0,
        210,
        0,
    );
    const second = try Frame.parse(
        second_bytes[0..second_end],
        0,
    );

    var decoder = FrameDecoder{};
    const silent = try decoder.decode(first);
    try std.testing.expectEqual(PcmFrame{
        .channel_count = 1,
        .sample_count = 1152,
    }, silent);
    const decoded = try decoder.decode(second);
    var nonzero = false;
    for (decoded.channels[0]) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        nonzero = nonzero or sample != 0;
    }
    try std.testing.expect(nonzero);
}

test "rejects MP3 frame decoder discontinuities transactionally" {
    const header_bytes =
        testHeader(3, true, 9, 0, false, .mono);
    var encoded: [500]u8 = undefined;
    const frame_end = try appendFrame(
        &encoded,
        0,
        header_bytes,
    );
    const frame = try Frame.parse(encoded[0..frame_end], 0);
    var decoder = FrameDecoder{};
    _ = try decoder.decode(frame);

    var changed_bytes: [300]u8 = undefined;
    const changed_end = try appendFrame(
        &changed_bytes,
        0,
        testHeader(2, true, 8, 0, false, .mono),
    );
    const changed = try Frame.parse(
        changed_bytes[0..changed_end],
        0,
    );
    const before_change = decoder;
    try std.testing.expectError(
        error.Mp3DecoderFormatChanged,
        decoder.decode(changed),
    );
    try std.testing.expectEqual(before_change, decoder);

    var missing_bytes = encoded;
    setTestBits(missing_bytes[4..21], 0, 9, 1);
    const missing = try Frame.parse(
        missing_bytes[0..frame_end],
        0,
    );
    var fresh = FrameDecoder{};
    const fresh_before = fresh;
    try std.testing.expectError(
        error.Mp3MainDataHistoryUnavailable,
        fresh.decode(missing),
    );
    try std.testing.expectEqual(fresh_before, fresh);

    var protected_bytes: [500]u8 = undefined;
    const protected_end = try appendFrame(
        &protected_bytes,
        0,
        testHeader(3, false, 9, 0, false, .mono),
    );
    const protected = try Frame.parse(
        protected_bytes[0..protected_end],
        0,
    );
    try std.testing.expectError(
        error.InvalidMp3FrameCrc,
        fresh.decode(protected),
    );
    try std.testing.expectEqual(fresh_before, fresh);

    fresh.reservoir.length = 512;
    const malformed = fresh;
    try std.testing.expectError(
        error.InvalidMp3ReservoirState,
        fresh.decode(frame),
    );
    try std.testing.expectEqual(malformed, fresh);
}

test "matches independent Layer III conformance PCM" {
    const encoded_base64 = std.mem.trim(
        u8,
        @embedFile(
            "test-fixtures/mp3/layer3-conformance.bit.b64",
        ),
        " \r\n\t",
    );
    const reference_base64 = std.mem.trim(
        u8,
        @embedFile(
            "test-fixtures/mp3/layer3-conformance.pcm.b64",
        ),
        " \r\n\t",
    );
    var encoded: [9600]u8 = undefined;
    var reference: [46_080]u8 = undefined;
    try std.base64.standard.Decoder.decode(
        &encoded,
        encoded_base64,
    );
    try std.base64.standard.Decoder.decode(
        &reference,
        reference_base64,
    );

    var stream = try Stream.init(&encoded);
    var decoder = FrameDecoder{};
    var frame_count: usize = 0;
    var sample_offset: usize = 0;
    var squared_error: f64 = 0;
    var maximum_error: f64 = 0;
    while (try stream.next()) |frame| {
        const decoded = try decoder.decode(frame);
        try std.testing.expectEqual(
            @as(u2, 2),
            decoded.channel_count,
        );
        for (0..decoded.sample_count) |sample| {
            for (0..decoded.channel_count) |channel| {
                const reference_index =
                    (sample_offset + sample) * 2 + channel;
                const reference_sample: f64 = @floatFromInt(
                    readTestI16(
                        reference[reference_index * 2 ..][0..2],
                    ),
                );
                const rendered =
                    @as(f64, decoded.channels[channel][sample]) *
                    32_768.0;
                const difference = rendered - reference_sample;
                squared_error += difference * difference;
                maximum_error =
                    @max(maximum_error, @abs(difference));
            }
        }
        sample_offset += decoded.sample_count;
        frame_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 10), frame_count);
    try std.testing.expectEqual(
        reference.len / 4,
        sample_offset,
    );
    const sample_total: f64 =
        @floatFromInt(reference.len / 2);
    try std.testing.expect(
        @sqrt(squared_error / sample_total) < 0.5,
    );
    try std.testing.expect(maximum_error < 2.0);
}

test "trims MP3 decoder frames with gapless metadata" {
    const summary = Summary{
        .audio_offset = 0,
        .audio_bytes = 3 * 417,
        .frame_count = 3,
        .sample_count = 3 * 1152,
        .sample_rate = 44_100,
        .channels = 1,
        .first_xing = .{
            .kind = .variable,
            .frame_count = 3,
            .stream_bytes = null,
            .toc = null,
            .quality = null,
            .encoder = null,
            .encoder_delay = 100,
            .encoder_padding = 729,
        },
        .first_vbri = null,
    };
    const plan = try GaplessPlan.fromSummary(summary);
    try std.testing.expect(plan.valid());
    try std.testing.expectEqual(@as(u64, 3456), plan.encoded_samples);
    try std.testing.expectEqual(@as(u64, 1475), plan.audible_samples);

    var vbri_summary = summary;
    vbri_summary.first_xing = null;
    vbri_summary.first_vbri = .{
        .version = 1,
        .delay = 0,
        .quality = 0,
        .stream_bytes = 3 * 417,
        .frame_count = 3,
        .toc_entries = 3,
        .toc_scale = 1,
        .entry_bytes = 1,
        .frames_per_entry = 1,
        .toc = &.{ 1, 1, 1 },
    };
    const vbri_plan = try GaplessPlan.fromSummary(vbri_summary);
    try std.testing.expectEqual(@as(u32, 1152), vbri_plan.leading_samples);
    try std.testing.expectEqual(@as(u64, 2304), vbri_plan.audible_samples);

    var encoded: [500]u8 = undefined;
    const frame_end = try appendFrame(
        &encoded,
        0,
        testHeader(3, true, 9, 0, false, .mono),
    );
    const frame = try Frame.parse(encoded[0..frame_end], 0);
    var decoder = try StreamDecoder.init(summary);
    try std.testing.expect(decoder.valid());
    try std.testing.expectError(
        error.Mp3GaplessStreamIncomplete,
        decoder.finish(),
    );
    const first = try decoder.decode(frame);
    try std.testing.expect(decoder.valid());
    try std.testing.expectEqual(
        PcmRange{ .start = 1152, .length = 0 },
        first.audible,
    );
    var fractional_decoder = decoder;
    fractional_decoder.sample_offset = 1;
    try std.testing.expect(!fractional_decoder.valid());
    const fractional_before = fractional_decoder;
    try std.testing.expectError(
        error.InvalidMp3StreamDecoderState,
        fractional_decoder.decode(frame),
    );
    try std.testing.expectEqual(
        fractional_before,
        fractional_decoder,
    );
    const second = try decoder.decode(frame);
    try std.testing.expect(decoder.valid());
    try std.testing.expectEqual(
        PcmRange{ .start = 629, .length = 523 },
        second.audible,
    );
    const third = try decoder.decode(frame);
    try std.testing.expect(decoder.valid());
    try std.testing.expectEqual(
        PcmRange{ .start = 0, .length = 952 },
        third.audible,
    );
    try decoder.finish();

    var hostile_decoder = decoder;
    hostile_decoder.decoder.polyphase[0].head_block = 16;
    try std.testing.expect(!hostile_decoder.valid());
    const hostile_decoder_before = hostile_decoder;
    try std.testing.expectError(
        error.InvalidMp3StreamDecoderState,
        hostile_decoder.decode(frame),
    );
    try std.testing.expectEqual(hostile_decoder_before, hostile_decoder);

    const completed = decoder;
    try std.testing.expectError(
        error.InvalidMp3GaplessPlan,
        decoder.decode(frame),
    );
    try std.testing.expectEqual(completed, decoder);

    decoder.reset();
    try std.testing.expect(decoder.valid());
    try std.testing.expectEqual(@as(u64, 0), decoder.sample_offset);
    try std.testing.expectEqual(FrameDecoder{}, decoder.decoder);
    try std.testing.expectEqual(plan, decoder.plan);
}

test "rejects invalid MP3 gapless metadata and plans" {
    var summary = Summary{
        .audio_offset = 0,
        .audio_bytes = 417,
        .frame_count = 1,
        .sample_count = 1152,
        .sample_rate = 44_100,
        .channels = 1,
        .first_xing = .{
            .kind = .variable,
            .frame_count = 1,
            .stream_bytes = null,
            .toc = null,
            .quality = null,
            .encoder = null,
            .encoder_delay = 100,
            .encoder_padding = null,
        },
        .first_vbri = null,
    };
    try std.testing.expectError(
        error.InvalidMp3GaplessMetadata,
        GaplessPlan.fromSummary(summary),
    );
    var oversized = summary.first_xing orelse
        return error.TestXingMissing;
    oversized.encoder_padding = 1100;
    summary.first_xing = oversized;
    try std.testing.expectError(
        error.InvalidMp3GaplessMetadata,
        GaplessPlan.fromSummary(summary),
    );

    const leading = GaplessPlan{
        .encoded_samples = 100,
        .leading_samples = 100,
        .trailing_samples = 0,
        .audible_samples = 0,
    };
    try std.testing.expectEqual(
        PcmRange{ .start = 100, .length = 0 },
        try leading.frameRange(0, 100),
    );
    const trailing = GaplessPlan{
        .encoded_samples = 100,
        .leading_samples = 0,
        .trailing_samples = 100,
        .audible_samples = 0,
    };
    try std.testing.expectEqual(
        PcmRange{ .start = 0, .length = 0 },
        try trailing.frameRange(0, 100),
    );
    var malformed = trailing;
    malformed.audible_samples = 1;
    try std.testing.expect(!malformed.valid());
    try std.testing.expectError(
        error.InvalidMp3GaplessPlan,
        malformed.frameRange(0, 100),
    );
    const malformed_decoder = StreamDecoder{
        .plan = malformed,
        .sample_rate = 44_100,
        .channel_count = 1,
        .sample_offset = 100,
    };
    try std.testing.expect(!malformed_decoder.valid());
    try std.testing.expectError(
        error.InvalidMp3GaplessPlan,
        malformed_decoder.finish(),
    );

    summary.first_xing = null;
    summary.sample_rate = 0;
    try std.testing.expectError(
        error.InvalidMp3Summary,
        StreamDecoder.init(summary),
    );
    summary.sample_rate = 44_100;
    summary.sample_count = 1151;
    try std.testing.expectError(
        error.InvalidMp3Summary,
        StreamDecoder.init(summary),
    );
    summary.sample_count = 0;
    summary.frame_count = 0;
    try std.testing.expectError(
        error.InvalidMp3Summary,
        StreamDecoder.init(summary),
    );
}

test "rejects inconsistent scale-factor bit ranges" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var side = SideInformation{
        .channel_count = 1,
        .granule_count = 2,
        .main_data_begin = 0,
        .private_bits = 0,
        .main_data_bits = 21,
    };
    side.granules[0].channels[0] = .{
        .part2_3_length = 20,
        .scalefac_compress = 5,
    };
    side.granules[1].channels[0].part2_3_length = 1;
    var encoded: [3]u8 = @splat(0);
    try std.testing.expectError(
        error.InvalidMp3Part23Length,
        decodeScaleFactors(
            header,
            side,
            .{ .bytes = &encoded, .bit_count = 21 },
        ),
    );
    try std.testing.expectError(
        error.InvalidMp3MainDataLength,
        decodeScaleFactors(
            header,
            side,
            .{ .bytes = &encoded, .bit_count = 20 },
        ),
    );
    side.channel_count = 2;
    try std.testing.expectError(
        error.InvalidMp3SideInformation,
        decodeScaleFactors(
            header,
            side,
            .{ .bytes = &encoded, .bit_count = 21 },
        ),
    );
    side.channel_count = 1;
    try std.testing.expectError(
        error.InvalidMp3MainDataLength,
        decodeScaleFactors(
            header,
            side,
            .{ .bytes = encoded[0..2], .bit_count = 21 },
        ),
    );
}

test "rejects malformed and unsupported MPEG headers" {
    try std.testing.expectError(
        error.TruncatedMp3Header,
        Header.parse(&.{ 0xff, 0xfb, 0x90 }),
    );
    try std.testing.expectError(
        error.InvalidMp3Sync,
        Header.parse(&.{ 0, 0, 0, 0 }),
    );
    try std.testing.expectError(
        error.ReservedMp3Version,
        Header.parse(&testHeader(1, true, 9, 0, false, .stereo)),
    );
    var not_layer_three = testHeader(3, true, 9, 0, false, .stereo);
    not_layer_three[1] |= 0x04;
    try std.testing.expectError(
        error.NotMp3LayerThree,
        Header.parse(&not_layer_three),
    );
    const free = try Header.parse(
        &testHeader(3, true, 0, 0, false, .stereo),
    );
    try std.testing.expect(free.free_format);
    try std.testing.expectEqual(@as(u16, 0), free.bitrate_kbps);
    try std.testing.expectEqual(@as(usize, 0), free.frameBytes());
    try std.testing.expectError(
        error.InvalidMp3Bitrate,
        Header.parse(&testHeader(3, true, 15, 0, false, .stereo)),
    );
    try std.testing.expectError(
        error.InvalidMp3SampleRate,
        Header.parse(&testHeader(3, true, 9, 3, false, .stereo)),
    );
}

test "free-format MP3 infers padded frame sizes transactionally" {
    var encoded: [1700]u8 = @splat(0);
    const plain = testHeader(3, true, 0, 0, false, .stereo);
    const padded = testHeader(3, true, 0, 0, true, .stereo);
    var cursor = try appendFreeFormatFrame(
        &encoded,
        0,
        plain,
        500,
    );
    cursor = try appendFreeFormatFrame(
        &encoded,
        cursor,
        padded,
        500,
    );
    cursor = try appendFreeFormatFrame(
        &encoded,
        cursor,
        plain,
        500,
    );
    @memcpy(encoded[100..104], &plain);
    @memcpy(encoded[200..204], &plain);
    setTestBits(encoded[104..136], 32, 9, 511);
    try std.testing.expectError(
        error.InvalidMp3BigValues,
        (try frameAtKnownLength(
            &encoded,
            100,
            try Header.parse(&plain),
            100,
        )).sideInformation(),
    );

    const first = try Frame.parse(encoded[0..cursor], 0);
    try std.testing.expect(first.header.free_format);
    try std.testing.expectEqual(@as(usize, 500), first.bytes.len);

    var stream = try Stream.init(encoded[0..cursor]);
    try std.testing.expectEqual(
        @as(usize, 500),
        (try stream.next()).?.bytes.len,
    );
    try std.testing.expectEqual(
        @as(usize, 501),
        (try stream.next()).?.bytes.len,
    );
    try std.testing.expectEqual(
        @as(usize, 500),
        (try stream.next()).?.bytes.len,
    );
    try std.testing.expect((try stream.next()) == null);
    try std.testing.expectEqual(@as(?usize, 500), stream.free_frame_base_bytes);

    var one_frame: [500]u8 = undefined;
    _ = try appendFreeFormatFrame(&one_frame, 0, plain, 500);
    try std.testing.expectError(
        error.CannotInferFreeFormatMp3FrameSize,
        Frame.parse(&one_frame, 0),
    );
}

test "file-backed free-format MP3 scans summarizes and seeks" {
    var encoded: [1600]u8 = @splat(0);
    const header = testHeader(3, true, 0, 0, false, .stereo);
    var cursor = try appendFreeFormatFrame(
        &encoded,
        0,
        header,
        500,
    );
    cursor = try appendFreeFormatFrame(
        &encoded,
        cursor,
        header,
        500,
    );
    cursor = try appendFreeFormatFrame(
        &encoded,
        cursor,
        header,
        500,
    );
    @memcpy(encoded[100..104], &header);
    @memcpy(encoded[200..204], &header);
    setTestBits(encoded[104..136], 32, 9, 511);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "free-format.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        encoded[0..cursor],
        0,
    );

    var reader = try FileReader.init(std.testing.io, file);
    try std.testing.expectEqual(
        @as(?usize, 500),
        reader.free_frame_base_bytes,
    );
    var storage: [501]u8 = undefined;
    try std.testing.expectEqual(
        @as(usize, 500),
        (try reader.next(&storage)).?.bytes.len,
    );
    const summary = try FileReader.summarize(
        std.testing.io,
        file,
        &storage,
    );
    try std.testing.expectEqual(@as(u64, 3), summary.frame_count);

    var points: [3]SeekPoint = undefined;
    const index = try buildFileSeekIndex(
        std.testing.io,
        file,
        &storage,
        1,
        &points,
    );
    try reader.seek(index[2]);
    try std.testing.expectEqual(
        @as(u64, 1000),
        reader.offset,
    );
    try std.testing.expectEqual(
        @as(usize, 500),
        (try reader.next(&storage)).?.bytes.len,
    );
}

test "protected free-format MP3 preserves CRC validation across readers" {
    var encoded: [1600]u8 = @splat(0);
    const plain = testHeader(3, false, 0, 0, false, .stereo);
    const padded = testHeader(3, false, 0, 0, true, .stereo);
    var cursor = try appendFreeFormatFrame(&encoded, 0, plain, 500);
    try repairTestFrameCrc(&encoded, 0);
    const second_offset = cursor;
    cursor = try appendFreeFormatFrame(&encoded, cursor, padded, 500);
    try repairTestFrameCrc(&encoded, second_offset);
    const third_offset = cursor;
    cursor = try appendFreeFormatFrame(&encoded, cursor, plain, 500);
    try repairTestFrameCrc(&encoded, third_offset);

    const first = try Frame.parse(encoded[0..cursor], 0);
    try std.testing.expectEqual(@as(usize, 500), first.bytes.len);
    try std.testing.expectEqual(@as(?bool, true), try first.crcValid());
    var stream = try Stream.init(encoded[0..cursor]);
    for ([_]usize{ 500, 501, 500 }) |expected_bytes| {
        const frame = (try stream.next()).?;
        try std.testing.expectEqual(expected_bytes, frame.bytes.len);
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
    }
    try std.testing.expect((try stream.next()) == null);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "protected-free-format.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, encoded[0..cursor], 0);
    var reader = try FileReader.init(std.testing.io, file);
    try std.testing.expectEqual(
        @as(?usize, 500),
        reader.free_frame_base_bytes,
    );
    try reader.seek(.{
        .frame_index = 2,
        .sample_offset = 2304,
        .byte_offset = third_offset,
    });
    var frame_storage: [501]u8 = undefined;
    const sought = (try reader.next(&frame_storage)).?;
    try std.testing.expectEqual(@as(usize, 500), sought.bytes.len);
    try std.testing.expectEqual(@as(?bool, true), try sought.crcValid());
    try std.testing.expect((try reader.next(&frame_storage)) == null);
}

test "protected free-format MP3 resynchronizes with retained frame size" {
    const header = testHeader(3, false, 0, 0, false, .stereo);
    var encoded: [2600]u8 = @splat(0);
    var cursor: usize = 0;
    for (0..3) |_| {
        const frame_offset = cursor;
        cursor = try appendFreeFormatFrame(
            &encoded,
            cursor,
            header,
            500,
        );
        try repairTestFrameCrc(&encoded, frame_offset);
    }
    const damaged_offset = cursor;
    const junk = [_]u8{ 0, 1, 2 };
    @memcpy(encoded[cursor..][0..junk.len], &junk);
    cursor += junk.len;
    const recovered_offset = cursor;
    for (0..2) |_| {
        const frame_offset = cursor;
        cursor = try appendFreeFormatFrame(
            &encoded,
            cursor,
            header,
            500,
        );
        try repairTestFrameCrc(&encoded, frame_offset);
    }

    var stream = try Stream.init(encoded[0..cursor]);
    for (0..3) |_| _ = try stream.next();
    try std.testing.expectEqual(damaged_offset, stream.cursor);
    const retained_stream = stream;
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        stream.resynchronize(junk.len - 1),
    );
    try std.testing.expectEqualDeep(retained_stream, stream);
    try std.testing.expectEqual(junk.len, try stream.resynchronize(junk.len));
    try std.testing.expectEqual(recovered_offset, stream.cursor);
    for (0..2) |_| {
        const frame = (try stream.next()).?;
        try std.testing.expectEqual(@as(?bool, true), try frame.crcValid());
    }
    try std.testing.expect((try stream.next()) == null);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "protected-free-format-resync.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, encoded[0..cursor], 0);
    var reader = try FileReader.init(std.testing.io, file);
    var frame_storage: [500]u8 = undefined;
    for (0..3) |_| _ = try reader.next(&frame_storage);
    try std.testing.expectEqual(
        @as(u64, @intCast(damaged_offset)),
        reader.offset,
    );
    const retained_reader = reader;
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        reader.resynchronize(junk.len - 1),
    );
    try std.testing.expectEqualDeep(retained_reader, reader);
    try std.testing.expectEqual(
        @as(u64, junk.len),
        try reader.resynchronize(junk.len),
    );
    try std.testing.expectEqual(
        @as(u64, @intCast(recovered_offset)),
        reader.offset,
    );
    for (0..2) |_| {
        const frame = (try reader.next(&frame_storage)).?;
        try std.testing.expectEqual(@as(?bool, true), try frame.crcValid());
    }
    try std.testing.expect((try reader.next(&frame_storage)) == null);
}

test "parses bounded Xing fields and LAME delay metadata" {
    var storage: [500]u8 = undefined;
    const header_bytes = testHeader(3, false, 9, 0, false, .stereo);
    const end = try appendFrame(&storage, 0, header_bytes);
    const offset = frameXingOffset(try Header.parse(&header_bytes));
    @memcpy(storage[offset..][0..4], "Xing");
    storage[offset + 7] = 0xf;
    storage[offset + 8 ..][0..4].* = .{ 0, 0, 0, 10 };
    storage[offset + 12 ..][0..4].* = .{ 0, 0, 4, 0 };
    for (storage[offset + 16 ..][0..100], 0..) |*byte, index|
        byte.* = @intCast(index);
    storage[offset + 116 ..][0..4].* = .{ 0, 0, 0, 7 };
    @memcpy(storage[offset + 120 ..][0..9], "LAME3.100");
    storage[offset + 141 ..][0..3].* = .{ 0x24, 0x03, 0x21 };

    const frame = try Frame.parse(storage[0..end], 0);
    const xing = frame.xing.?;
    try std.testing.expectEqual(XingKind.variable, xing.kind);
    try std.testing.expectEqual(@as(?u32, 10), xing.frame_count);
    try std.testing.expectEqual(@as(?u32, 1024), xing.stream_bytes);
    try std.testing.expectEqual(@as(u8, 99), xing.toc.?[99]);
    try std.testing.expectEqual(@as(?u32, 7), xing.quality);
    try std.testing.expectEqual(@as(?u12, 0x240), xing.encoder_delay);
    try std.testing.expectEqual(@as(?u12, 0x321), xing.encoder_padding);

    @memcpy(storage[offset + 120 ..][0..9], "Lavc60.31");
    storage[offset + 141 ..][0..3].* = .{ 0, 0, 0 };
    const unspecified = try Frame.parse(storage[0..end], 0);
    try std.testing.expectEqual(
        @as(?u12, null),
        unspecified.xing.?.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(?u12, null),
        unspecified.xing.?.encoder_padding,
    );

    storage[offset + 7] = 0x4f;
    @memcpy(storage[offset + 120 ..][0..9], "LAMEH5.24");
    storage[offset + 141 ..][0..3].* = .{ 0x24, 0x03, 0x21 };
    const info_tag = try Frame.parse(storage[0..end], 0);
    try std.testing.expectEqual(
        "LAMEH5.24".*,
        info_tag.xing.?.encoder.?,
    );

    storage[offset + 7] = 0x10;
    try std.testing.expectError(
        error.InvalidXingFlags,
        Frame.parse(storage[0..end], 0),
    );
    const short_end = try appendFrame(
        &storage,
        0,
        testHeader(3, true, 1, 0, false, .stereo),
    );
    const short_offset = 4 + 32;
    @memcpy(storage[short_offset..][0..4], "Xing");
    storage[short_offset + 7] = 0x4;
    try std.testing.expectError(
        error.TruncatedXingHeader,
        Frame.parse(storage[0..short_end], 0),
    );
}

test "encodes truthful and validated Xing encoder identifiers" {
    const header = try (EncoderConfig{
        .bitrate_kbps = 320,
        .channel_mode = .stereo,
    }).header(false);
    var storage: [maximum_encoded_frame_bytes]u8 = @splat(0xa5);
    const encoded = try encodeXingFrame(
        header,
        .{
            .kind = .variable,
            .frame_count = 17,
            .stream_bytes = 4096,
            .encoder_delay = 0x123,
            .encoder_padding = 0x456,
        },
        &storage,
    );
    const parsed = (try Frame.parse(encoded, 0)).xing.?;
    try std.testing.expectEqual(
        default_xing_encoder_identifier,
        parsed.encoder.?,
    );
    try std.testing.expectEqual(@as(?u12, 0x123), parsed.encoder_delay);
    try std.testing.expectEqual(@as(?u12, 0x456), parsed.encoder_padding);

    const custom: [9]u8 = "StudioX 1".*;
    const custom_encoded = try encodeXingFrame(
        header,
        .{
            .kind = .constant,
            .frame_count = 18,
            .stream_bytes = 8192,
            .encoder_delay = 0x234,
            .encoder_padding = 0x567,
            .encoder = custom,
        },
        &storage,
    );
    const parsed_custom = (try Frame.parse(custom_encoded, 0)).xing.?;
    try std.testing.expectEqual(
        custom,
        parsed_custom.encoder.?,
    );
    try std.testing.expectEqual(
        @as(?u12, 0x234),
        parsed_custom.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(?u12, 0x567),
        parsed_custom.encoder_padding,
    );

    var protected_header = header;
    protected_header.crc_present = true;
    const protected_encoded = try encodeXingFrame(
        protected_header,
        .{
            .kind = .variable,
            .frame_count = 19,
            .stream_bytes = 12_288,
            .encoder_delay = 0x345,
            .encoder_padding = 0x678,
        },
        &storage,
    );
    const protected_offset = frameXingOffset(protected_header);
    try std.testing.expectEqualSlices(
        u8,
        "Xing",
        protected_encoded[protected_offset..][0..4],
    );
    try std.testing.expectEqual(
        protected_offset + 2,
        frameMainDataOffset(protected_header),
    );
    try std.testing.expect(!std.mem.eql(
        u8,
        "Xing",
        protected_encoded[frameMainDataOffset(protected_header)..][0..4],
    ));
    const protected_parsed = try Frame.parse(protected_encoded, 0);
    try std.testing.expectEqual(
        @as(?bool, true),
        try protected_parsed.crcValid(),
    );
    try std.testing.expectEqual(
        @as(?u32, 19),
        protected_parsed.xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u12, 0x345),
        protected_parsed.xing.?.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(?u12, 0x678),
        protected_parsed.xing.?.encoder_padding,
    );

    const before = storage;
    try std.testing.expectError(
        error.InvalidMp3EncoderIdentifier,
        encodeXingFrame(
            header,
            .{
                .kind = .variable,
                .frame_count = 1,
                .stream_bytes = 1,
                .encoder_delay = 0,
                .encoder_padding = 0,
                .encoder = @splat(' '),
            },
            &storage,
        ),
    );
    try std.testing.expectEqual(before, storage);

    var control_identifier = custom;
    control_identifier[4] = '\n';
    try std.testing.expectError(
        error.InvalidMp3EncoderIdentifier,
        encodeXingFrame(
            header,
            .{
                .kind = .variable,
                .frame_count = 1,
                .stream_bytes = 1,
                .encoder_delay = 0,
                .encoder_padding = 0,
                .encoder = control_identifier,
            },
            &storage,
        ),
    );
    try std.testing.expectEqual(before, storage);

    var hostile_cbr = try PcmStreamEncoder.init(.{});
    hostile_cbr.metadata_encoder[0] = 0;
    try std.testing.expectError(
        error.InvalidMp3EncoderStreamState,
        hostile_cbr.summary(),
    );
    var hostile_reservoir = try PcmReservoirStreamEncoder.init(.{});
    hostile_reservoir.metadata_encoder[0] = 0x7f;
    try std.testing.expectError(
        error.InvalidMp3ReservoirStreamState,
        hostile_reservoir.summary(),
    );
    var hostile_offsets: [1]u64 = undefined;
    var hostile_vbr = try VbrPcmStreamEncoder.init(
        .{},
        &hostile_offsets,
    );
    hostile_vbr.metadata_encoder = @splat(' ');
    try std.testing.expectError(
        error.InvalidMp3VbrStreamState,
        hostile_vbr.summary(),
    );
    var hostile_vbr_reservoir =
        try VbrPcmReservoirStreamEncoder.init(
            .{},
            &hostile_offsets,
        );
    hostile_vbr_reservoir.encoder.metadata_encoder[0] = 0;
    try std.testing.expectError(
        error.InvalidMp3VbrReservoirStreamState,
        hostile_vbr_reservoir.summary(),
    );
}

test "parses bounded VBRI header and table" {
    var storage: [500]u8 = undefined;
    const end = try appendFrame(
        &storage,
        0,
        testHeader(3, true, 9, 0, false, .stereo),
    );
    const offset = 36;
    @memcpy(storage[offset..][0..4], "VBRI");
    storage[offset + 4 ..][0..22].* = .{
        0, 1,  0, 2, 0, 3,
        0, 0,  4, 0, 0, 0,
        0, 10, 0, 3, 0, 1,
        0, 2,  0, 4,
    };
    storage[offset + 26 ..][0..6].* = .{ 0, 5, 0, 6, 0, 7 };
    const frame = try Frame.parse(storage[0..end], 0);
    const vbri = frame.vbri.?;
    try std.testing.expectEqual(@as(u16, 1), vbri.version);
    try std.testing.expectEqual(@as(u32, 1024), vbri.stream_bytes);
    try std.testing.expectEqual(@as(u32, 10), vbri.frame_count);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 5, 0, 6, 0, 7 },
        vbri.toc,
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        try vbri.approximateByteOffsetForFrame(0),
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        try vbri.approximateByteOffsetForFrame(2),
    );
    try std.testing.expectEqual(
        @as(u32, 5),
        try vbri.approximateByteOffsetForFrame(4),
    );
    try std.testing.expectEqual(
        @as(u32, 12),
        try vbri.approximateByteOffsetForFrame(9),
    );
    try std.testing.expectEqual(
        @as(u32, 1024),
        try vbri.approximateByteOffsetForFrame(10),
    );
    var one_uncovered = vbri;
    one_uncovered.frame_count = 13;
    try std.testing.expectEqual(
        @as(u32, 16),
        try one_uncovered.approximateByteOffsetForFrame(12),
    );

    try std.testing.expectError(
        error.InvalidVbriTargetFrame,
        vbri.approximateByteOffsetForFrame(11),
    );
    var short_toc = vbri;
    short_toc.toc = short_toc.toc[0..4];
    try std.testing.expectError(
        error.InvalidVbriTocSize,
        short_toc.approximateByteOffsetForFrame(1),
    );
    var incomplete = vbri;
    incomplete.toc_entries = 2;
    incomplete.toc = incomplete.toc[0..4];
    try std.testing.expectError(
        error.IncompleteVbriFrameCoverage,
        incomplete.approximateByteOffsetForFrame(1),
    );
    var oversized = vbri;
    oversized.stream_bytes = 10;
    try std.testing.expectError(
        error.InvalidVbriStreamBytes,
        oversized.approximateByteOffsetForFrame(1),
    );
    const zero_toc = [_]u8{ 0, 5, 0, 0, 0, 7 };
    var zero_entry = vbri;
    zero_entry.toc = &zero_toc;
    try std.testing.expectError(
        error.InvalidVbriTocEntry,
        zero_entry.approximateByteOffsetForFrame(1),
    );

    storage[offset + 28 ..][0..2].* = .{ 0, 0 };
    try std.testing.expectError(
        error.InvalidVbriTocEntry,
        Frame.parse(storage[0..end], 0),
    );
    storage[offset + 28 ..][0..2].* = .{ 0, 6 };
    storage[offset + 14 ..][0..4].* = .{ 0, 0, 0, 14 };
    try std.testing.expectError(
        error.IncompleteVbriFrameCoverage,
        Frame.parse(storage[0..end], 0),
    );
    storage[offset + 14 ..][0..4].* = .{ 0, 0, 0, 10 };
    storage[offset + 10 ..][0..4].* = .{ 0, 0, 0, 10 };
    try std.testing.expectError(
        error.InvalidVbriStreamBytes,
        Frame.parse(storage[0..end], 0),
    );
    storage[offset + 10 ..][0..4].* = .{ 0, 0, 4, 0 };

    storage[offset + 23] = 5;
    try std.testing.expectError(
        error.InvalidVbriEntrySize,
        Frame.parse(storage[0..end], 0),
    );
    storage[offset + 23] = 2;
    storage[offset + 18 ..][0..2].* = .{ 0xff, 0xff };
    try std.testing.expectError(
        error.TruncatedVbriToc,
        Frame.parse(storage[0..end], 0),
    );
    storage[offset + 18 ..][0..2].* = .{ 0, 2 };
    storage[offset + 20 ..][0..2].* = .{ 0, 0 };
    try std.testing.expectError(
        error.InvalidVbriTocScale,
        Frame.parse(storage[0..end], 0),
    );
    storage[offset + 20 ..][0..2].* = .{ 0, 1 };
    storage[offset + 24 ..][0..2].* = .{ 0, 0 };
    try std.testing.expectError(
        error.InvalidVbriFramesPerEntry,
        Frame.parse(storage[0..end], 0),
    );
    storage[offset + 24 ..][0..2].* = .{ 0, 4 };
    storage[offset + 5] = 2;
    try std.testing.expectError(
        error.UnsupportedVbriVersion,
        Frame.parse(storage[0..end], 0),
    );
}

test "VBRI seek lookup decodes every table entry width" {
    for (1..5) |entry_bytes| {
        var toc_storage: [8]u8 = @splat(0);
        toc_storage[entry_bytes - 1] = 3;
        toc_storage[entry_bytes * 2 - 1] = 5;
        const vbri = Vbri{
            .version = 1,
            .delay = 0,
            .quality = 0,
            .stream_bytes = 16,
            .frame_count = 2,
            .toc_entries = 2,
            .toc_scale = 2,
            .entry_bytes = @intCast(entry_bytes),
            .frames_per_entry = 1,
            .toc = toc_storage[0 .. entry_bytes * 2],
        };
        try std.testing.expectEqual(
            @as(u32, 0),
            try vbri.approximateByteOffsetForFrame(0),
        );
        try std.testing.expectEqual(
            @as(u32, 6),
            try vbri.approximateByteOffsetForFrame(1),
        );
        try std.testing.expectEqual(
            @as(u32, 16),
            try vbri.approximateByteOffsetForFrame(2),
        );
    }
}

test "VBRI seek lookup matches generated segment tables" {
    var random_state = std.Random.DefaultPrng.init(0x5642_5249_5345_454b);
    const random = random_state.random();
    for (0..256) |_| {
        const entry_count = random.intRangeAtMost(usize, 1, 8);
        const entry_bytes = random.intRangeAtMost(usize, 1, 4);
        const frames_per_entry = random.intRangeAtMost(u16, 1, 8);
        const scale = random.intRangeAtMost(u16, 1, 16);
        const covered_frames =
            entry_count * @as(usize, frames_per_entry);
        const frame_count = random.intRangeAtMost(
            usize,
            1,
            covered_frames,
        );
        var toc_storage: [32]u8 = @splat(0);
        var segment_sizes: [8]u32 = @splat(0);
        var stream_bytes: u32 = 0;
        for (0..entry_count) |entry_index| {
            const entry = random.intRangeAtMost(u32, 1, 127);
            segment_sizes[entry_index] = entry * scale;
            stream_bytes += segment_sizes[entry_index];
            for (0..entry_bytes) |byte_index| {
                const shift: u5 = @intCast(
                    (entry_bytes - byte_index - 1) * 8,
                );
                toc_storage[entry_index * entry_bytes + byte_index] =
                    @intCast(entry >> shift);
            }
        }
        const vbri = Vbri{
            .version = 1,
            .delay = 0,
            .quality = 0,
            .stream_bytes = stream_bytes,
            .frame_count = @intCast(frame_count),
            .toc_entries = @intCast(entry_count),
            .toc_scale = scale,
            .entry_bytes = @intCast(entry_bytes),
            .frames_per_entry = frames_per_entry,
            .toc = toc_storage[0 .. entry_count * entry_bytes],
        };
        for (0..frame_count + 1) |target_frame| {
            var expected: u32 = 0;
            if (target_frame == frame_count) {
                expected = stream_bytes;
            } else {
                const group =
                    target_frame / @as(usize, frames_per_entry);
                for (segment_sizes[0..group]) |segment_bytes| {
                    expected += segment_bytes;
                }
                expected += segment_sizes[group] *
                    @as(
                        u32,
                        @intCast(
                            target_frame %
                                @as(usize, frames_per_entry),
                        ),
                    ) /
                    frames_per_entry;
            }
            try std.testing.expectEqual(
                expected,
                try vbri.approximateByteOffsetForFrame(
                    @intCast(target_frame),
                ),
            );
        }
    }
}

test "encodes bounded VBRI metadata frames transactionally" {
    const header = try (EncoderConfig{
        .bitrate_kbps = 320,
        .channel_mode = .stereo,
    }).header(false);
    const toc = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var storage: [maximum_encoded_frame_bytes + 4]u8 =
        @splat(0xa5);
    for (1..5) |entry_bytes| {
        var width_toc: [8]u8 = @splat(0);
        width_toc[entry_bytes - 1] = 3;
        width_toc[entry_bytes * 2 - 1] = 5;
        const toc_bytes = width_toc[0 .. entry_bytes * 2];
        const encoded = try encodeVbriFrame(
            header,
            .{
                .delay = 17,
                .quality = 83,
                .stream_bytes = 16,
                .frame_count = 14,
                .toc_scale = 2,
                .entry_bytes = @intCast(entry_bytes),
                .frames_per_entry = 7,
                .toc = toc_bytes,
            },
            &storage,
        );
        try std.testing.expectEqual(
            header.frameBytes(),
            encoded.len,
        );
        try std.testing.expectEqualSlices(
            u8,
            &@as([4]u8, @splat(0xa5)),
            storage[encoded.len..][0..4],
        );
        const frame = try Frame.parse(encoded, 0);
        const vbri = frame.vbri orelse
            return error.TestMp3VbriMissing;
        try std.testing.expectEqual(@as(u16, 1), vbri.version);
        try std.testing.expectEqual(@as(u16, 17), vbri.delay);
        try std.testing.expectEqual(@as(u16, 83), vbri.quality);
        try std.testing.expectEqual(
            @as(u32, 16),
            vbri.stream_bytes,
        );
        try std.testing.expectEqual(
            @as(u32, 14),
            vbri.frame_count,
        );
        try std.testing.expectEqual(
            @as(u16, 2),
            vbri.toc_entries,
        );
        try std.testing.expectEqual(
            @as(u16, @intCast(entry_bytes)),
            vbri.entry_bytes,
        );
        try std.testing.expectEqual(
            @as(u16, 7),
            vbri.frames_per_entry,
        );
        try std.testing.expectEqualSlices(
            u8,
            toc_bytes,
            vbri.toc,
        );
    }

    var unchanged: [64]u8 = @splat(0x5a);
    const before = unchanged;
    const base = VbriEncoderMetadata{
        .quality = 1,
        .stream_bytes = 3,
        .frame_count = 2,
        .toc_scale = 1,
        .entry_bytes = 1,
        .frames_per_entry = 1,
        .toc = toc[0..2],
    };
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encodeVbriFrame(header, base, &unchanged),
    );
    try std.testing.expectEqual(before, unchanged);
    var invalid = base;
    invalid.entry_bytes = 0;
    try std.testing.expectError(
        error.InvalidVbriEntrySize,
        encodeVbriFrame(header, invalid, &storage),
    );
    invalid = base;
    invalid.toc_scale = 0;
    try std.testing.expectError(
        error.InvalidVbriTocScale,
        encodeVbriFrame(header, invalid, &storage),
    );
    invalid = base;
    invalid.frames_per_entry = 0;
    try std.testing.expectError(
        error.InvalidVbriFramesPerEntry,
        encodeVbriFrame(header, invalid, &storage),
    );
    invalid = base;
    invalid.entry_bytes = 3;
    try std.testing.expectError(
        error.InvalidVbriTocSize,
        encodeVbriFrame(header, invalid, &storage),
    );
    invalid = base;
    invalid.frame_count = 4;
    try std.testing.expectError(
        error.IncompleteVbriFrameCoverage,
        encodeVbriFrame(header, invalid, &storage),
    );
    invalid = base;
    invalid.stream_bytes = 2;
    try std.testing.expectError(
        error.InvalidVbriStreamBytes,
        encodeVbriFrame(header, invalid, &storage),
    );
    const zero_entry_toc = [_]u8{ 1, 0 };
    invalid = base;
    invalid.toc = &zero_entry_toc;
    try std.testing.expectError(
        error.InvalidVbriTocEntry,
        encodeVbriFrame(header, invalid, &storage),
    );
    var protected = header;
    protected.crc_present = true;
    try std.testing.expectError(
        error.UnsupportedProtectedVbriFrame,
        encodeVbriFrame(protected, base, &storage),
    );

    var offsets = [_]u64{ 0, 100, 230, 400 };
    try std.testing.expectEqual(
        @as(usize, 4),
        try requiredVbriTocBytes(4, 2, 2),
    );
    var built_storage: [8]u8 = @splat(0xa5);
    const built = try buildVbriToc(
        &offsets,
        4,
        600,
        2,
        10,
        2,
        &built_storage,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 23, 0, 37 },
        built,
    );
    try std.testing.expectEqualSlices(
        u8,
        &@as([4]u8, @splat(0xa5)),
        built_storage[4..],
    );
    var short_toc: [3]u8 = @splat(0x5a);
    const short_before = short_toc;
    try std.testing.expectError(
        error.InsufficientVbriTocStorage,
        buildVbriToc(
            &offsets,
            4,
            600,
            2,
            10,
            2,
            &short_toc,
        ),
    );
    try std.testing.expectEqual(short_before, short_toc);
    try std.testing.expectError(
        error.InexactVbriTocScale,
        buildVbriToc(
            &offsets,
            4,
            600,
            2,
            9,
            2,
            &built_storage,
        ),
    );
    try std.testing.expectError(
        error.VbriTocEntryOverflow,
        buildVbriToc(
            &offsets,
            4,
            600,
            2,
            1,
            1,
            &built_storage,
        ),
    );
    offsets[2] = 100;
    try std.testing.expectError(
        error.InvalidMp3VbrFrameOffsets,
        buildVbriToc(
            &offsets,
            4,
            600,
            2,
            1,
            2,
            &built_storage,
        ),
    );
    offsets[2] = 230;
    try std.testing.expectError(
        error.OverlappingMp3VbrStorage,
        buildVbriToc(
            &offsets,
            4,
            600,
            2,
            1,
            2,
            std.mem.sliceAsBytes(offsets[0..]),
        ),
    );
}

test "finalizes reserved VBRI stream metadata transactionally" {
    const config = EncoderConfig{
        .bitrate_kbps = 320,
        .sample_rate = 44_100,
        .channel_mode = .joint_stereo,
        .mode_extension = 3,
    };
    var encoder = try PcmStreamEncoder.init(config);
    var encoded: [maximum_encoded_frame_bytes * 6]u8 = undefined;
    var cursor: usize = 0;
    const metadata = try encoder.startGaplessMetadata(encoded[cursor..]);
    cursor += metadata.len;
    for (0..2) |_| {
        const frame = try encoder.append(
            .{ .channel_count = 2, .sample_count = 1152 },
            encoded[cursor..],
        );
        cursor += frame.len;
    }
    const finished = try encoder.finish(encoded[cursor..]);
    cursor += finished.frames.len;

    var offsets: [5]u64 = undefined;
    var toc_storage: [20]u8 = undefined;
    const finalized = try finalizeVbriStreamMetadata(
        encoded[0..cursor],
        81,
        1,
        1,
        4,
        &offsets,
        &toc_storage,
    );
    const summary = try Stream.summarize(encoded[0..cursor]);
    const vbri = summary.first_vbri orelse
        return error.TestMp3VbriMissing;
    try std.testing.expectEqual(summary.frame_count, finalized.frame_count);
    try std.testing.expectEqual(summary.audio_bytes, finalized.stream_bytes);
    try std.testing.expectEqual(@as(u16, 81), vbri.quality);
    try std.testing.expectEqual(finalized.frame_count, vbri.frame_count);
    try std.testing.expectEqual(finalized.stream_bytes, vbri.stream_bytes);
    try std.testing.expectEqual(@as(u64, 0), offsets[0]);
    try std.testing.expectEqual(
        finalized.stream_bytes,
        try vbri.approximateByteOffsetForFrame(vbri.frame_count),
    );
    const finalized_bytes = encoded;
    try std.testing.expectError(
        error.OverlappingMp3VbrStorage,
        finalizeVbriStreamMetadata(
            encoded[0..cursor],
            81,
            1,
            1,
            4,
            &offsets,
            encoded[0..toc_storage.len],
        ),
    );
    try std.testing.expectEqual(finalized_bytes, encoded);

    var no_reservation = try PcmStreamEncoder.init(config);
    var plain: [maximum_encoded_frame_bytes]u8 = undefined;
    const plain_frame = try no_reservation.append(
        .{ .channel_count = 2, .sample_count = 1152 },
        &plain,
    );
    var retained: [maximum_encoded_frame_bytes]u8 = undefined;
    @memcpy(retained[0..plain_frame.len], plain_frame);
    try std.testing.expectError(
        error.MissingReservedMp3MetadataFrame,
        finalizeVbriStreamMetadata(
            plain_frame,
            81,
            1,
            1,
            4,
            &offsets,
            &toc_storage,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        retained[0..plain_frame.len],
        plain_frame,
    );

    var protected_config = config;
    protected_config.crc_present = true;
    var protected_encoder = try PcmStreamEncoder.init(protected_config);
    var protected: [maximum_encoded_frame_bytes]u8 = undefined;
    const protected_metadata = try protected_encoder.startGaplessMetadata(
        &protected,
    );
    @memcpy(retained[0..protected_metadata.len], protected_metadata);
    try std.testing.expectError(
        error.UnsupportedProtectedVbriFrame,
        finalizeVbriStreamMetadata(
            protected_metadata,
            81,
            1,
            1,
            4,
            &offsets,
            &toc_storage,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        retained[0..protected_metadata.len],
        protected_metadata,
    );
}

test "stream skips ID3 tags, summarizes frames, and builds seek index" {
    var storage: [1600]u8 = undefined;
    @memset(&storage, 0);
    @memcpy(storage[0..3], "ID3");
    storage[3] = 4;
    storage[5] = 0x10;
    storage[9] = 5;
    @memcpy(storage[15..18], "3DI");
    var cursor: usize = 25;
    const header = testHeader(3, true, 9, 0, false, .stereo);
    cursor = try appendFrame(&storage, cursor, header);
    cursor = try appendFrame(&storage, cursor, header);
    cursor = try appendFrame(&storage, cursor, header);
    @memcpy(storage[cursor..][0..3], "TAG");
    cursor += 128;

    const summary = try Stream.summarize(storage[0..cursor]);
    try std.testing.expectEqual(@as(usize, 25), summary.audio_offset);
    try std.testing.expectEqual(@as(u64, 3), summary.frame_count);
    try std.testing.expectEqual(@as(u64, 3456), summary.sample_count);
    try std.testing.expectEqual(@as(u32, 44_100), summary.sample_rate);
    try std.testing.expectApproxEqAbs(
        @as(f64, 3456.0 / 44_100.0),
        summary.durationSeconds(),
        1e-12,
    );
    try std.testing.expectError(
        error.InvalidMp3Limits,
        Stream.initWithLimits(storage[0..cursor], .{ .max_frames = 0 }),
    );
    try std.testing.expectError(
        error.Mp3StreamLimitExceeded,
        Stream.initWithLimits(storage[0..cursor], .{
            .max_stream_bytes = cursor - 1,
        }),
    );
    try std.testing.expectError(
        error.Mp3FrameLimitExceeded,
        Stream.summarizeWithLimits(storage[0..cursor], .{
            .max_stream_bytes = cursor,
            .max_frames = 2,
        }),
    );
    const limited_summary = try Stream.summarizeWithLimits(
        storage[0..cursor],
        .{ .max_stream_bytes = cursor, .max_frames = 3 },
    );
    try std.testing.expectEqual(@as(u64, 3), limited_summary.frame_count);

    var limited_stream = try Stream.initWithLimits(
        storage[0..cursor],
        .{ .max_stream_bytes = cursor, .max_frames = 2 },
    );
    _ = try limited_stream.next();
    _ = try limited_stream.next();
    const limited_before = limited_stream;
    try std.testing.expectError(
        error.Mp3FrameLimitExceeded,
        limited_stream.next(),
    );
    try std.testing.expectEqualDeep(limited_before, limited_stream);

    try std.testing.expectEqual(
        @as(usize, 2),
        try requiredSeekPoints(storage[0..cursor], 2),
    );
    var points: [2]SeekPoint = undefined;
    const index = try buildSeekIndex(storage[0..cursor], 2, &points);
    try std.testing.expectEqual(@as(usize, 25), index[0].byte_offset);
    try std.testing.expectEqual(@as(u64, 2), index[1].frame_index);
    try std.testing.expectEqual(@as(u64, 2304), index[1].sample_offset);
    try std.testing.expectEqual(
        index[0],
        try findSeekPoint(index, 2303),
    );
    try std.testing.expectEqual(
        index[1],
        try findSeekPoint(index, 2304),
    );
}

test "file reader scans summarizes indexes and seeks without whole-file storage" {
    var encoded: [1600]u8 = undefined;
    @memset(&encoded, 0);
    @memcpy(encoded[0..3], "ID3");
    encoded[3] = 3;
    encoded[9] = 4;
    var cursor: usize = 14;
    const header = testHeader(3, true, 9, 0, false, .stereo);
    cursor = try appendFrame(&encoded, cursor, header);
    cursor = try appendFrame(&encoded, cursor, header);
    cursor = try appendFrame(&encoded, cursor, header);
    @memcpy(encoded[cursor..][0..3], "TAG");
    cursor += 128;

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "framing.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, encoded[0..cursor], 0);

    try std.testing.expectError(
        error.Mp3StreamLimitExceeded,
        FileReader.initWithLimits(std.testing.io, file, .{
            .max_stream_bytes = cursor - 1,
        }),
    );
    var limited_reader = try FileReader.initWithLimits(
        std.testing.io,
        file,
        .{ .max_stream_bytes = cursor, .max_frames = 2 },
    );
    var limited_storage: [maximum_free_format_frame_bytes]u8 = undefined;
    _ = try limited_reader.next(&limited_storage);
    _ = try limited_reader.next(&limited_storage);
    const limited_reader_before = limited_reader;
    try std.testing.expectError(
        error.Mp3FrameLimitExceeded,
        limited_reader.next(&limited_storage),
    );
    try std.testing.expectEqualDeep(limited_reader_before, limited_reader);

    var reader = try FileReader.init(std.testing.io, file);
    try std.testing.expectEqual(@as(u64, 14), reader.audio_start);
    const original_offset = reader.offset;
    var short_storage: [100]u8 = undefined;
    try std.testing.expectError(
        error.Mp3FrameBufferTooSmall,
        reader.next(&short_storage),
    );
    try std.testing.expectEqual(original_offset, reader.offset);

    var frame_storage: [500]u8 = undefined;
    const first = (try reader.next(&frame_storage)).?;
    try std.testing.expectEqual(@as(u64, 14), first.byte_offset);
    try std.testing.expectEqual(@as(usize, 417), first.bytes.len);

    const summary = try FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(@as(u64, 3), summary.frame_count);
    try std.testing.expectEqual(@as(u64, 3456), summary.sample_count);
    try std.testing.expectEqual(@as(u64, 14), summary.audio_offset);

    try std.testing.expectEqual(
        @as(usize, 2),
        try requiredFileSeekPoints(
            std.testing.io,
            file,
            &frame_storage,
            2,
        ),
    );
    var points: [2]SeekPoint = undefined;
    const index = try buildFileSeekIndex(
        std.testing.io,
        file,
        &frame_storage,
        2,
        &points,
    );
    try std.testing.expectEqual(@as(u64, 2), index[1].frame_index);
    try reader.seek(index[1]);
    try std.testing.expectEqual(@as(u64, 2), reader.frame_index);
    const sought = (try reader.next(&frame_storage)).?;
    try std.testing.expectEqual(
        @as(u64, @intCast(index[1].byte_offset)),
        sought.byte_offset,
    );

    const retained_offset = reader.offset;
    try std.testing.expectError(
        error.InvalidMp3SeekPoint,
        reader.seek(.{
            .frame_index = 2,
            .sample_offset = 2304,
            .byte_offset = 14,
        }),
    );
    try std.testing.expectEqual(retained_offset, reader.offset);
    try std.testing.expectError(
        error.InvalidMp3SeekPoint,
        reader.seek(.{
            .frame_index = 1,
            .sample_offset = 1152,
            .byte_offset = 15,
        }),
    );
    try std.testing.expectEqual(retained_offset, reader.offset);
    try std.testing.expectError(
        error.InvalidMp3SeekPoint,
        reader.seek(.{
            .frame_index = index[1].frame_index,
            .sample_offset = index[1].sample_offset + 1,
            .byte_offset = index[1].byte_offset,
        }),
    );
    try std.testing.expectEqual(retained_offset, reader.offset);
}

test "transactional MP3 file iteration preserves state and destination" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var encoded: [1000]u8 = undefined;
    const second_offset = try appendFrame(&encoded, 0, header);
    const encoded_bytes = try appendFrame(
        &encoded,
        second_offset,
        header,
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "transactional-iteration.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        encoded[0..encoded_bytes],
        0,
    );
    try file.setLength(std.testing.io, encoded_bytes);

    var reader = try FileReader.init(std.testing.io, file);
    const initial = reader;
    var short_destination: [100]u8 = @splat(0xa5);
    const short_before = short_destination;
    var scratch: [500]u8 = undefined;
    try std.testing.expectError(
        error.Mp3FrameBufferTooSmall,
        reader.nextTransactional(&short_destination, &scratch),
    );
    try std.testing.expectEqualDeep(initial, reader);
    try std.testing.expectEqual(short_before, short_destination);

    var destination: [500]u8 = @splat(0x5a);
    var short_scratch: [100]u8 = undefined;
    const destination_before = destination;
    try std.testing.expectError(
        error.Mp3FrameBufferTooSmall,
        reader.nextTransactional(&destination, &short_scratch),
    );
    try std.testing.expectEqualDeep(initial, reader);
    try std.testing.expectEqual(destination_before, destination);

    var aliased: [600]u8 = @splat(0x3c);
    const aliased_before = aliased;
    try std.testing.expectError(
        error.OverlappingMp3FileReaderBuffers,
        reader.nextTransactional(
            aliased[0..500],
            aliased[100..600],
        ),
    );
    try std.testing.expectEqualDeep(initial, reader);
    try std.testing.expectEqual(aliased_before, aliased);

    const first = (try reader.nextTransactional(
        &destination,
        &scratch,
    )).?;
    try std.testing.expectEqual(@as(u64, 0), first.byte_offset);
    try std.testing.expectEqual(second_offset, first.bytes.len);
    try std.testing.expectEqual(
        @intFromPtr(destination[0..].ptr),
        @intFromPtr(first.bytes.ptr),
    );
    try std.testing.expectEqualSlices(
        u8,
        encoded[0..second_offset],
        first.bytes,
    );

    const after_first = reader;
    destination = @splat(0x6b);
    const truncated_destination = destination;
    try file.setLength(
        std.testing.io,
        second_offset + 100,
    );
    try std.testing.expectError(
        error.TruncatedMp3File,
        reader.nextTransactional(&destination, &scratch),
    );
    try std.testing.expectEqualDeep(after_first, reader);
    try std.testing.expectEqual(truncated_destination, destination);
}

test "transactional MP3 file iteration rebinds VBRI storage" {
    const header = try (EncoderConfig{
        .bitrate_kbps = 320,
        .channel_mode = .stereo,
    }).header(false);
    const toc = [_]u8{ 3, 5 };
    var encoded: [maximum_encoded_frame_bytes]u8 = undefined;
    const frame = try encodeVbriFrame(
        header,
        .{
            .delay = 17,
            .quality = 83,
            .stream_bytes = 16,
            .frame_count = 2,
            .toc_scale = 2,
            .entry_bytes = 1,
            .frames_per_entry = 1,
            .toc = &toc,
        },
        &encoded,
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "transactional-vbri.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, frame, 0);
    try file.setLength(std.testing.io, frame.len);

    var reader = try FileReader.init(std.testing.io, file);
    var destination: [maximum_encoded_frame_bytes]u8 = @splat(0xa5);
    var scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    const published = (try reader.nextTransactional(
        &destination,
        &scratch,
    )).?;
    const vbri = published.vbri orelse return error.TestMp3VbriMissing;
    try std.testing.expectEqualSlices(u8, &toc, vbri.toc);
    const destination_start = @intFromPtr(destination[0..].ptr);
    const destination_end = destination_start + published.bytes.len;
    const toc_start = @intFromPtr(vbri.toc.ptr);
    try std.testing.expect(toc_start >= destination_start);
    try std.testing.expect(toc_start + vbri.toc.len <= destination_end);

    const finished = reader;
    const destination_before = destination;
    try std.testing.expect(
        try reader.nextTransactional(&destination, &scratch) == null,
    );
    try std.testing.expectEqualDeep(finished, reader);
    try std.testing.expectEqual(destination_before, destination);
}

test "MP3 file seeking rejects malformed complete frames transactionally" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    const protected_header = testHeader(
        3,
        false,
        9,
        0,
        false,
        .stereo,
    );
    var encoded: [2200]u8 = undefined;
    var cursor = try appendFrame(&encoded, 0, header);
    const malformed_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    const metadata_offset = malformed_offset + 4 + 32;
    @memcpy(encoded[metadata_offset..][0..4], "Xing");
    encoded[metadata_offset + 7] = 0x10;
    const invalid_crc_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, protected_header);
    const invalid_crc_frame = try Frame.parse(
        encoded[0..cursor],
        invalid_crc_offset,
    );
    try std.testing.expectEqual(
        @as(?bool, false),
        try invalid_crc_frame.crcValid(),
    );
    const invalid_side_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    setTestBits(
        encoded[invalid_side_offset + 4 .. invalid_side_offset + 36],
        32,
        9,
        511,
    );
    try std.testing.expectError(
        error.InvalidMp3BigValues,
        (try Frame.parse(
            encoded[0..cursor],
            invalid_side_offset,
        )).sideInformation(),
    );
    const valid_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "seek-validation.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, encoded[0..cursor], 0);
    var reader = try FileReader.init(std.testing.io, file);
    const retained = reader;

    try std.testing.expectError(
        error.InvalidMp3SeekPoint,
        reader.seek(.{
            .frame_index = 1,
            .sample_offset = 1152,
            .byte_offset = malformed_offset,
        }),
    );
    try std.testing.expectEqualDeep(retained, reader);
    try std.testing.expectError(
        error.InvalidMp3SeekPoint,
        reader.seek(.{
            .frame_index = 2,
            .sample_offset = 2304,
            .byte_offset = invalid_crc_offset,
        }),
    );
    try std.testing.expectEqualDeep(retained, reader);
    try std.testing.expectError(
        error.InvalidMp3SeekPoint,
        reader.seek(.{
            .frame_index = 3,
            .sample_offset = 3456,
            .byte_offset = invalid_side_offset,
        }),
    );
    try std.testing.expectEqualDeep(retained, reader);

    try reader.seek(.{
        .frame_index = 4,
        .sample_offset = 4608,
        .byte_offset = valid_offset,
    });
    try std.testing.expectEqual(
        @as(u64, @intCast(valid_offset)),
        reader.offset,
    );
    var frame_storage: [500]u8 = undefined;
    _ = try reader.next(&frame_storage);
    try std.testing.expect((try reader.next(&frame_storage)) == null);
}

test "MP3 readers resynchronize across bounded junk transactionally" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    const junk = [_]u8{ 0x00, 0x49, 0x44, 0x33, 0x7f };
    var encoded: [1400]u8 = undefined;
    var cursor = try appendFrame(&encoded, 0, header);
    const junk_offset = cursor;
    @memcpy(encoded[cursor..][0..junk.len], &junk);
    cursor += junk.len;
    const recovered_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    cursor = try appendFrame(&encoded, cursor, header);

    var stream = try Stream.init(encoded[0..cursor]);
    _ = try stream.next();
    try std.testing.expectEqual(junk_offset, stream.cursor);
    const retained_stream = stream;
    try std.testing.expectError(
        error.InvalidMp3Sync,
        stream.next(),
    );
    try std.testing.expectEqual(retained_stream.cursor, stream.cursor);
    try std.testing.expectError(
        error.InvalidMp3ResynchronizationLimit,
        stream.resynchronize(0),
    );
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        stream.resynchronize(junk.len - 1),
    );
    try std.testing.expectEqual(retained_stream.cursor, stream.cursor);
    try std.testing.expectEqual(
        junk.len,
        try stream.resynchronize(junk.len),
    );
    try std.testing.expectEqual(recovered_offset, stream.cursor);
    _ = try stream.next();
    _ = try stream.next();
    try std.testing.expect((try stream.next()) == null);
    try std.testing.expectEqual(@as(u64, 3), stream.frame_index);
    try std.testing.expectEqual(@as(u64, 3456), stream.sample_offset);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "resynchronized.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, encoded[0..cursor], 0);
    var reader = try FileReader.init(std.testing.io, file);
    var frame_storage: [500]u8 = undefined;
    _ = try reader.next(&frame_storage);
    try std.testing.expectEqual(junk_offset, reader.offset);
    const retained_reader = reader;
    try std.testing.expectError(
        error.InvalidMp3Sync,
        reader.next(&frame_storage),
    );
    try std.testing.expectEqual(retained_reader.offset, reader.offset);
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        reader.resynchronize(junk.len - 1),
    );
    try std.testing.expectEqual(retained_reader.offset, reader.offset);
    try std.testing.expectEqual(
        junk.len,
        try reader.resynchronize(junk.len),
    );
    try std.testing.expectEqual(
        @as(u64, @intCast(recovered_offset)),
        reader.offset,
    );
    _ = try reader.next(&frame_storage);
    _ = try reader.next(&frame_storage);
    try std.testing.expect(
        (try reader.next(&frame_storage)) == null,
    );
    try std.testing.expectEqual(@as(u64, 3), reader.frame_index);
    try std.testing.expectEqual(@as(u64, 3456), reader.sample_offset);

    reader.audio_start = reader.audio_end + 1;
    try std.testing.expectError(
        error.InvalidMp3FileReaderState,
        reader.resynchronize(1),
    );
}

test "MP3 readers skip malformed metadata frames while resynchronizing" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var encoded: [2000]u8 = undefined;
    var cursor = try appendFrame(&encoded, 0, header);
    const damaged_offset = cursor;
    encoded[cursor] = 0;
    cursor += 1;
    const malformed_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    const metadata_offset = malformed_offset + 4 + 32;
    @memcpy(encoded[metadata_offset..][0..4], "Xing");
    encoded[metadata_offset + 7] = 0x10;
    const malformed_vbri_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    const vbri_offset = malformed_vbri_offset + 4 + 32;
    @memcpy(encoded[vbri_offset..][0..4], "VBRI");
    try std.testing.expectError(
        error.UnsupportedVbriVersion,
        Frame.parse(encoded[0..cursor], malformed_vbri_offset),
    );
    const recovered_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    const required_skip = recovered_offset - damaged_offset;

    var stream = try Stream.init(encoded[0..cursor]);
    _ = try stream.next();
    const retained_stream = stream;
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        stream.resynchronize(required_skip - 1),
    );
    try std.testing.expectEqual(retained_stream.cursor, stream.cursor);
    try std.testing.expectEqual(
        required_skip,
        try stream.resynchronize(required_skip),
    );
    try std.testing.expectEqual(recovered_offset, stream.cursor);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "metadata-resynchronized.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, encoded[0..cursor], 0);
    var reader = try FileReader.init(std.testing.io, file);
    var frame_storage: [500]u8 = undefined;
    _ = try reader.next(&frame_storage);
    const retained_reader = reader;
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        reader.resynchronize(required_skip - 1),
    );
    try std.testing.expectEqual(retained_reader.offset, reader.offset);
    try std.testing.expectEqual(
        @as(u64, @intCast(required_skip)),
        try reader.resynchronize(required_skip),
    );
    try std.testing.expectEqual(
        @as(u64, @intCast(recovered_offset)),
        reader.offset,
    );
    _ = try reader.next(&frame_storage);
    try std.testing.expect((try reader.next(&frame_storage)) == null);
}

test "MP3 readers skip invalid protected and side-information frames while resynchronizing" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    const protected_header = testHeader(
        3,
        false,
        9,
        0,
        false,
        .stereo,
    );
    var encoded: [2000]u8 = undefined;
    var cursor = try appendFrame(&encoded, 0, header);
    const damaged_offset = cursor;
    encoded[cursor] = 0;
    cursor += 1;
    const invalid_crc_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, protected_header);
    const invalid_crc_frame = try Frame.parse(
        encoded[0..cursor],
        invalid_crc_offset,
    );
    try std.testing.expectEqual(
        @as(?bool, false),
        try invalid_crc_frame.crcValid(),
    );
    const invalid_side_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    setTestBits(
        encoded[invalid_side_offset + 4 .. invalid_side_offset + 36],
        32,
        9,
        511,
    );
    try std.testing.expectError(
        error.InvalidMp3BigValues,
        (try Frame.parse(
            encoded[0..cursor],
            invalid_side_offset,
        )).sideInformation(),
    );
    const recovered_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    const required_skip = recovered_offset - damaged_offset;

    var stream = try Stream.init(encoded[0..cursor]);
    _ = try stream.next();
    const retained_stream = stream;
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        stream.resynchronize(required_skip - 1),
    );
    try std.testing.expectEqual(retained_stream.cursor, stream.cursor);
    try std.testing.expectEqual(
        required_skip,
        try stream.resynchronize(required_skip),
    );
    try std.testing.expectEqual(recovered_offset, stream.cursor);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "crc-resynchronized.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, encoded[0..cursor], 0);
    var reader = try FileReader.init(std.testing.io, file);
    var frame_storage: [500]u8 = undefined;
    _ = try reader.next(&frame_storage);
    const retained_reader = reader;
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        reader.resynchronize(required_skip - 1),
    );
    try std.testing.expectEqual(retained_reader.offset, reader.offset);
    try std.testing.expectEqual(
        @as(u64, @intCast(required_skip)),
        try reader.resynchronize(required_skip),
    );
    try std.testing.expectEqual(
        @as(u64, @intCast(recovered_offset)),
        reader.offset,
    );
    _ = try reader.next(&frame_storage);
    try std.testing.expect((try reader.next(&frame_storage)) == null);
}

test "MP3 stream contains deterministic frame mutations" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var baseline: [1000]u8 = undefined;
    const second_offset = try appendFrame(&baseline, 0, header);
    const encoded_bytes = try appendFrame(
        &baseline,
        second_offset,
        header,
    );

    for (second_offset..encoded_bytes) |byte_index| {
        for ([_]u8{ 0x01, 0x80, 0xff }) |mask| {
            var candidate = baseline;
            candidate[byte_index] ^= mask;
            var stream = try Stream.init(candidate[0..encoded_bytes]);
            _ = try stream.next();
            const retained = stream;
            if (stream.next()) |frame| {
                if (frame) |accepted| {
                    try std.testing.expect(accepted.bytes.len >= 4);
                    try std.testing.expect(stream.cursor <= stream.audio_end);
                    try std.testing.expectEqual(
                        @as(u64, 2),
                        stream.frame_index,
                    );
                } else {
                    try std.testing.expectEqual(
                        stream.audio_end,
                        stream.cursor,
                    );
                }
            } else |_| {
                try std.testing.expectEqual(retained.cursor, stream.cursor);
                try std.testing.expectEqual(
                    retained.first_header,
                    stream.first_header,
                );
                try std.testing.expectEqual(
                    retained.frame_index,
                    stream.frame_index,
                );
                try std.testing.expectEqual(
                    retained.sample_offset,
                    stream.sample_offset,
                );
                try std.testing.expectEqual(
                    retained.free_frame_base_bytes,
                    stream.free_frame_base_bytes,
                );
            }
        }
    }

    for (second_offset + 1..encoded_bytes) |prefix_bytes| {
        var stream = try Stream.init(baseline[0..prefix_bytes]);
        _ = try stream.next();
        const retained = stream;
        if (stream.next()) |frame| {
            if (frame) |_| {
                try std.testing.expect(stream.cursor <= stream.audio_end);
            } else {
                try std.testing.expectEqual(
                    stream.audio_end,
                    stream.cursor,
                );
            }
        } else |_| {
            try std.testing.expectEqual(retained.cursor, stream.cursor);
            try std.testing.expectEqual(
                retained.first_header,
                stream.first_header,
            );
            try std.testing.expectEqual(
                retained.frame_index,
                stream.frame_index,
            );
            try std.testing.expectEqual(
                retained.sample_offset,
                stream.sample_offset,
            );
            try std.testing.expectEqual(
                retained.free_frame_base_bytes,
                stream.free_frame_base_bytes,
            );
        }
    }
}

test "MP3 file reader contains deterministic frame mutations" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var baseline: [1000]u8 = undefined;
    const second_offset = try appendFrame(&baseline, 0, header);
    const encoded_bytes = try appendFrame(
        &baseline,
        second_offset,
        header,
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "mutated-framing.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var frame_storage: [500]u8 = undefined;
    var frame_scratch: [500]u8 = undefined;

    for (second_offset..encoded_bytes) |byte_index| {
        for ([_]u8{ 0x01, 0x80, 0xff }) |mask| {
            var candidate = baseline;
            candidate[byte_index] ^= mask;
            try file.setLength(std.testing.io, encoded_bytes);
            try file.writePositionalAll(
                std.testing.io,
                candidate[0..encoded_bytes],
                0,
            );

            var reader = try FileReader.init(std.testing.io, file);
            _ = try reader.next(&frame_scratch);
            const retained = reader;
            frame_storage = @splat(0xa5);
            const storage_before = frame_storage;
            if (reader.nextTransactional(
                &frame_storage,
                &frame_scratch,
            )) |frame| {
                if (frame) |accepted| {
                    try std.testing.expect(accepted.bytes.len >= 4);
                    try std.testing.expect(reader.offset <= reader.audio_end);
                    try std.testing.expectEqual(
                        @as(u64, 2),
                        reader.frame_index,
                    );
                    try std.testing.expect(reader.valid());
                } else {
                    try std.testing.expectEqual(
                        reader.audio_end,
                        reader.offset,
                    );
                    try std.testing.expectEqual(
                        storage_before,
                        frame_storage,
                    );
                }
            } else |_| {
                try std.testing.expectEqualDeep(retained, reader);
                try std.testing.expectEqual(
                    storage_before,
                    frame_storage,
                );
            }
        }
    }

    for (second_offset + 1..encoded_bytes) |prefix_bytes| {
        try file.setLength(std.testing.io, encoded_bytes);
        try file.writePositionalAll(
            std.testing.io,
            baseline[0..encoded_bytes],
            0,
        );
        try file.setLength(std.testing.io, prefix_bytes);

        var reader = try FileReader.init(std.testing.io, file);
        _ = try reader.next(&frame_scratch);
        const retained = reader;
        frame_storage = @splat(0x5a);
        const storage_before = frame_storage;
        if (reader.nextTransactional(
            &frame_storage,
            &frame_scratch,
        )) |frame| {
            if (frame) |_| {
                try std.testing.expect(reader.offset <= reader.audio_end);
            } else {
                try std.testing.expectEqual(
                    reader.audio_end,
                    reader.offset,
                );
                try std.testing.expectEqual(
                    storage_before,
                    frame_storage,
                );
            }
        } else |_| {
            try std.testing.expectEqualDeep(retained, reader);
            try std.testing.expectEqual(
                storage_before,
                frame_storage,
            );
        }
    }
}

test "MP3 readers reject malformed retained counters transactionally" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var encoded: [500]u8 = undefined;
    const encoded_bytes = try appendFrame(&encoded, 0, header);

    var stream = try Stream.init(encoded[0..encoded_bytes]);
    try std.testing.expect(stream.valid());
    stream.frame_index = std.math.maxInt(u64);
    try std.testing.expect(!stream.valid());
    try std.testing.expectError(
        error.InvalidMp3StreamState,
        stream.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), stream.cursor);
    try std.testing.expect(stream.first_header == null);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        stream.frame_index,
    );
    try std.testing.expectEqual(@as(u64, 0), stream.sample_offset);

    stream.frame_index = 0;
    stream.sample_offset = std.math.maxInt(u64);
    try std.testing.expect(!stream.valid());
    try std.testing.expectError(
        error.InvalidMp3StreamState,
        stream.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), stream.cursor);
    try std.testing.expect(stream.first_header == null);
    try std.testing.expectEqual(@as(u64, 0), stream.frame_index);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        stream.sample_offset,
    );

    var impossible_stream_progress =
        try Stream.init(encoded[0..encoded_bytes]);
    _ = try impossible_stream_progress.next();
    impossible_stream_progress.cursor =
        impossible_stream_progress.audio_start;
    const impossible_stream_progress_before = impossible_stream_progress;
    try std.testing.expect(!impossible_stream_progress.valid());
    try std.testing.expectError(
        error.InvalidMp3StreamState,
        impossible_stream_progress.next(),
    );
    try std.testing.expectEqualDeep(
        impossible_stream_progress_before,
        impossible_stream_progress,
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "counter-rollover.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        encoded[0..encoded_bytes],
        0,
    );

    var reader = try FileReader.init(std.testing.io, file);
    try std.testing.expect(reader.valid());
    var frame_storage: [500]u8 = @splat(0xaa);
    var impossible_file_progress = reader;
    impossible_file_progress.frame_index = 1;
    impossible_file_progress.sample_offset = 1152;
    const impossible_file_progress_before = impossible_file_progress;
    try std.testing.expect(!impossible_file_progress.valid());
    try std.testing.expectError(
        error.InvalidMp3FileReaderState,
        impossible_file_progress.next(&frame_storage),
    );
    try std.testing.expectEqualDeep(
        impossible_file_progress_before,
        impossible_file_progress,
    );
    const original_storage = frame_storage;
    reader.frame_index = std.math.maxInt(u64);
    try std.testing.expect(!reader.valid());
    try std.testing.expectError(
        error.InvalidMp3FileReaderState,
        reader.next(&frame_storage),
    );
    try std.testing.expectEqual(@as(u64, 0), reader.offset);
    try std.testing.expectEqualSlices(
        u8,
        &original_storage,
        &frame_storage,
    );

    reader.frame_index = 0;
    reader.sample_offset = std.math.maxInt(u64);
    try std.testing.expect(!reader.valid());
    try std.testing.expectError(
        error.InvalidMp3FileReaderState,
        reader.next(&frame_storage),
    );
    try std.testing.expectEqual(@as(u64, 0), reader.offset);
    try std.testing.expectEqual(@as(u64, 0), reader.frame_index);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        reader.sample_offset,
    );
    try std.testing.expectEqualSlices(
        u8,
        &original_storage,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        trailingTagStart(&.{}, std.math.maxInt(usize)),
    );
}

test "stream and seek indexing reject invalid boundaries transactionally" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var storage: [900]u8 = undefined;
    var cursor = try appendFrame(&storage, 0, header);
    cursor = try appendFrame(&storage, cursor, header);

    var changed = storage;
    const second = (try Header.parse(&header)).frameBytes();
    changed[second + 2] = 0x94;
    try std.testing.expectError(
        error.Mp3StreamFormatChanged,
        Stream.summarize(changed[0..cursor]),
    );

    var trailing = storage;
    trailing[cursor] = 0;
    try std.testing.expectError(
        error.TrailingMp3Data,
        Stream.summarize(trailing[0 .. cursor + 1]),
    );
    var short_destination = [_]SeekPoint{.{
        .frame_index = 99,
        .sample_offset = 99,
        .byte_offset = 99,
    }};
    try std.testing.expectError(
        error.Mp3SeekIndexTooSmall,
        buildSeekIndex(storage[0..cursor], 1, &short_destination),
    );
    try std.testing.expectEqual(@as(u64, 99), short_destination[0].frame_index);
    try std.testing.expectError(
        error.InvalidMp3SeekStride,
        requiredSeekPoints(storage[0..cursor], 0),
    );
    try std.testing.expectError(
        error.InvalidMp3SeekIndex,
        findSeekPoint(&.{.{
            .frame_index = 1,
            .sample_offset = 0,
            .byte_offset = 0,
        }}, 0),
    );

    var stream = try Stream.init(storage[0..cursor]);
    try std.testing.expect(stream.valid());
    stream.audio_end = stream.encoded.len + 1;
    try std.testing.expect(!stream.valid());
    try std.testing.expectError(
        error.InvalidMp3StreamState,
        stream.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), stream.cursor);

    stream.audio_end = stream.encoded.len;
    stream.audio_start = 1;
    try std.testing.expect(!stream.valid());
    try std.testing.expectError(
        error.InvalidMp3StreamState,
        stream.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), stream.cursor);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "invalid-reader-state.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        storage[0..cursor],
        0,
    );
    var reader = try FileReader.init(std.testing.io, file);
    try std.testing.expect(reader.valid());
    const original_offset = reader.offset;
    reader.audio_start = original_offset + 1;
    try std.testing.expect(!reader.valid());
    var frame_storage: [500]u8 = @splat(0xaa);
    const original_frame_storage = frame_storage;
    try std.testing.expectError(
        error.InvalidMp3FileReaderState,
        reader.next(&frame_storage),
    );
    try std.testing.expectEqual(original_offset, reader.offset);
    try std.testing.expectEqualSlices(
        u8,
        &original_frame_storage,
        &frame_storage,
    );
    try std.testing.expectError(
        error.InvalidMp3FileReaderState,
        reader.seek(.{
            .frame_index = 0,
            .sample_offset = 0,
            .byte_offset = original_offset,
        }),
    );
    try std.testing.expectEqual(original_offset, reader.offset);
}

test "MP3 seek index builders reject overlapping storage" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var aliased: [900]u8 align(@alignOf(SeekPoint)) = undefined;
    const aliased_points: *[2]SeekPoint = @ptrCast(&aliased);
    var encoded_bytes = try appendFrame(&aliased, 0, header);
    encoded_bytes = try appendFrame(
        &aliased,
        encoded_bytes,
        header,
    );
    const original = aliased;
    try std.testing.expectError(
        error.OverlappingMp3SeekStorage,
        buildSeekIndex(
            aliased[0..encoded_bytes],
            1,
            aliased_points,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &original,
        &aliased,
    );

    var file_bytes: [900]u8 = undefined;
    var file_length = try appendFrame(&file_bytes, 0, header);
    file_length = try appendFrame(&file_bytes, file_length, header);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "overlapping-index.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        file_bytes[0..file_length],
        0,
    );

    var file_alias: [500]u8 align(@alignOf(SeekPoint)) =
        @splat(0xaa);
    const file_alias_points: *[2]SeekPoint =
        @ptrCast(&file_alias);
    const original_file_alias = file_alias;
    try std.testing.expectError(
        error.OverlappingMp3SeekStorage,
        buildFileSeekIndex(
            std.testing.io,
            file,
            &file_alias,
            1,
            file_alias_points,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &original_file_alias,
        &file_alias,
    );
}

test "transactional MP3 file seek index preserves destination" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var encoded: [1300]u8 = undefined;
    var encoded_bytes = try appendFrame(&encoded, 0, header);
    encoded_bytes = try appendFrame(&encoded, encoded_bytes, header);
    encoded_bytes = try appendFrame(&encoded, encoded_bytes, header);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "transactional-index.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        encoded[0..encoded_bytes],
        0,
    );
    try file.setLength(std.testing.io, encoded_bytes);

    var frame_storage: [500]u8 = undefined;
    var expected_storage: [3]SeekPoint = undefined;
    const expected = try buildFileSeekIndex(
        std.testing.io,
        file,
        &frame_storage,
        1,
        &expected_storage,
    );
    var destination: [3]SeekPoint = undefined;
    var index_scratch: [3]SeekPoint = undefined;
    const index = try buildFileSeekIndexTransactional(
        std.testing.io,
        file,
        &frame_storage,
        1,
        &destination,
        &index_scratch,
    );
    try std.testing.expectEqualSlices(SeekPoint, expected, index);
    try std.testing.expectEqual(
        @intFromPtr(destination[0..].ptr),
        @intFromPtr(index.ptr),
    );

    const sentinel = SeekPoint{
        .frame_index = 99,
        .sample_offset = 99,
        .byte_offset = 99,
    };
    var short_destination = [_]SeekPoint{sentinel};
    const short_destination_before = short_destination;
    try std.testing.expectError(
        error.Mp3SeekIndexTooSmall,
        buildFileSeekIndexTransactional(
            std.testing.io,
            file,
            &frame_storage,
            1,
            &short_destination,
            &index_scratch,
        ),
    );
    try std.testing.expectEqual(
        short_destination_before,
        short_destination,
    );

    destination = @splat(sentinel);
    const destination_before = destination;
    var short_scratch: [2]SeekPoint = undefined;
    try std.testing.expectError(
        error.Mp3SeekIndexTooSmall,
        buildFileSeekIndexTransactional(
            std.testing.io,
            file,
            &frame_storage,
            1,
            &destination,
            &short_scratch,
        ),
    );
    try std.testing.expectEqual(destination_before, destination);

    var aliased = [_]SeekPoint{sentinel} ** 4;
    const aliased_before = aliased;
    try std.testing.expectError(
        error.OverlappingMp3SeekStorage,
        buildFileSeekIndexTransactional(
            std.testing.io,
            file,
            &frame_storage,
            1,
            aliased[0..3],
            aliased[1..4],
        ),
    );
    try std.testing.expectEqual(aliased_before, aliased);

    var aliased_frame_storage: [500]u8 align(@alignOf(SeekPoint)) =
        undefined;
    const frame_aliased_scratch = std.mem.bytesAsSlice(
        SeekPoint,
        aliased_frame_storage[0 .. 3 * @sizeOf(SeekPoint)],
    );
    destination = @splat(sentinel);
    const frame_alias_destination_before = destination;
    try std.testing.expectError(
        error.OverlappingMp3SeekStorage,
        buildFileSeekIndexTransactional(
            std.testing.io,
            file,
            &aliased_frame_storage,
            1,
            &destination,
            frame_aliased_scratch,
        ),
    );
    try std.testing.expectEqual(
        frame_alias_destination_before,
        destination,
    );

    destination = @splat(sentinel);
    const truncated_before = destination;
    try file.setLength(std.testing.io, encoded_bytes - 1);
    try std.testing.expectError(
        error.TruncatedMp3Frame,
        buildFileSeekIndexTransactional(
            std.testing.io,
            file,
            &frame_storage,
            1,
            &destination,
            &index_scratch,
        ),
    );
    try std.testing.expectEqual(truncated_before, destination);
}

test "leading ID3 validation and truncated frames are bounded" {
    try std.testing.expectError(
        error.TruncatedLeadingId3Tag,
        Stream.init("ID3"),
    );
    try std.testing.expectError(
        error.InvalidLeadingId3Size,
        Stream.init(&.{ 'I', 'D', '3', 4, 0, 0, 0x80, 0, 0, 0 }),
    );
    try std.testing.expectError(
        error.TruncatedLeadingId3Tag,
        Stream.init(&.{ 'I', 'D', '3', 4, 0, 0, 0, 0, 0, 1 }),
    );

    var frame: [32]u8 = undefined;
    @memset(&frame, 0);
    const header = testHeader(3, true, 9, 0, false, .stereo);
    @memcpy(frame[0..4], &header);
    try std.testing.expectError(
        error.TruncatedMp3Frame,
        Frame.parse(&frame, 0),
    );
}

test "classifies MP3 encoder block transitions transactionally" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .stereo),
    );
    var classifier = EncoderBlockClassifier{};
    try std.testing.expect(classifier.valid());
    var pcm = PcmFrame{
        .channel_count = 2,
        .sample_count = 1152,
    };
    pcm.channels[0][192] = 1;
    pcm.channels[0][576 + 192] = 1;
    const first = try classifier.classify(header, pcm);
    try std.testing.expectEqual(@as(u2, 1), first[0][0].block_type);
    try std.testing.expectEqual(@as(u2, 2), first[1][0].block_type);
    try std.testing.expectEqual(GranuleChannel{}, first[0][1]);
    try std.testing.expectEqual(GranuleChannel{}, first[1][1]);
    try std.testing.expect(classifier.short_active[0]);
    try std.testing.expect(classifier.valid());

    const silence = PcmFrame{
        .channel_count = 2,
        .sample_count = 1152,
    };
    const second = try classifier.classify(header, silence);
    try std.testing.expectEqual(@as(u2, 3), second[0][0].block_type);
    try std.testing.expectEqual(GranuleChannel{}, second[1][0]);
    try std.testing.expect(!classifier.short_active[0]);

    classifier.attack_ratio = 1;
    const before = classifier;
    try std.testing.expect(!classifier.valid());
    try std.testing.expectError(
        error.InvalidMp3EncoderAttackRatio,
        classifier.classify(header, silence),
    );
    try std.testing.expectEqual(before, classifier);
    classifier.attack_ratio = 8;
    try std.testing.expect(classifier.valid());
    var malformed = silence;
    malformed.channels[0][0] = std.math.nan(f32);
    const before_malformed = classifier;
    try std.testing.expectError(
        error.InvalidMp3EncoderPcmSample,
        classifier.classify(header, malformed),
    );
    try std.testing.expectEqual(before_malformed, classifier);

    var joint_header = header;
    joint_header.channel_mode = .joint_stereo;
    var joint_classifier = EncoderBlockClassifier{};
    const joint = try joint_classifier.classify(
        joint_header,
        pcm,
    );
    try std.testing.expectEqual(
        joint[0][0],
        joint[0][1],
    );
    try std.testing.expectEqual(
        joint[1][0],
        joint[1][1],
    );
    try std.testing.expectEqual(
        joint_classifier.short_active[0],
        joint_classifier.short_active[1],
    );
}

test "prepares MP3 mid-side encoder spectra transactionally" {
    var header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .joint_stereo),
    );
    header.mode_extension = 2;
    var analyzed = AnalyzedEncoderFrame{
        .channel_count = 2,
        .granule_count = 2,
    };
    for (0..2) |granule| {
        analyzed.granules[granule][0].spectrum.lines[0] = 3;
        analyzed.granules[granule][1].spectrum.lines[0] = 1;
    }
    const prepared = try prepareEncoderStereo(
        header,
        analyzed,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 2 * @sqrt(2.0)),
        prepared.granules[0][0].spectrum.lines[0],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, @sqrt(2.0)),
        prepared.granules[0][1].spectrum.lines[0],
        1e-6,
    );
    const restored = try processStereo(
        header,
        @splat(.{}),
        @splat(.{ .value_count = 22 }),
        .{
            prepared.granules[0][0].spectrum,
            prepared.granules[0][1].spectrum,
        },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 3),
        restored.channels[0].lines[0],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1),
        restored.channels[1].lines[0],
        1e-6,
    );

    var mismatched = analyzed;
    mismatched.granules[0][1].description = .{
        .window_switching = true,
        .block_type = 1,
    };
    try std.testing.expectError(
        error.InvalidMp3EncoderStereoBlocks,
        prepareEncoderStereo(header, mismatched),
    );
    var malformed = analyzed;
    malformed.granules[0][0].spectrum.lines[0] =
        std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMp3RequantizedSpectrum,
        prepareEncoderStereo(header, malformed),
    );
    header.mode_extension = 0;
    try std.testing.expectEqual(
        analyzed,
        try prepareEncoderStereo(header, analyzed),
    );
}

test "prepares MP3 intensity stereo above the joint-stereo cutoff" {
    var header = try Header.parse(
        &testHeader(3, true, 11, 0, false, .joint_stereo),
    );
    header.mode_extension = 3;
    const bands = try scaleFactorBands(header);
    const intensity_line = bands.long_starts[14];
    const gains = mpeg1IntensityGains(2);
    var analyzed = AnalyzedEncoderFrame{
        .channel_count = 2,
        .granule_count = 2,
    };
    for (0..2) |granule| {
        analyzed.granules[granule][0].spectrum.lines[0] = 3;
        analyzed.granules[granule][1].spectrum.lines[0] = 1;
        analyzed.granules[granule][0]
            .spectrum.lines[intensity_line] = 2 * gains[0];
        analyzed.granules[granule][1]
            .spectrum.lines[intensity_line] = 2 * gains[1];
    }

    const prepared = try prepareEncoderStereo(header, analyzed);
    try std.testing.expect(
        prepared.granules[0][1].intensity_enabled[14],
    );
    try std.testing.expectEqual(
        @as(u8, 2),
        prepared.granules[0][1].intensity_positions[14],
    );
    try std.testing.expectEqual(
        @as(f32, 0),
        prepared.granules[0][1].spectrum.lines[intensity_line],
    );

    var factors: [2]ScaleFactorChannel =
        @splat(.{ .value_count = 22 });
    for (0..22) |band|
        factors[1].values[band] =
            prepared.granules[0][1].intensity_positions[band];
    const restored = try processStereo(
        header,
        @splat(.{}),
        factors,
        .{
            prepared.granules[0][0].spectrum,
            prepared.granules[0][1].spectrum,
        },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 3),
        restored.channels[0].lines[0],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1),
        restored.channels[1].lines[0],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        2 * gains[0],
        restored.channels[0].lines[intensity_line],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        2 * gains[1],
        restored.channels[1].lines[intensity_line],
        1e-6,
    );

    var malformed = prepared;
    malformed.granules[0][1].intensity_positions[14] = 7;
    try std.testing.expectError(
        error.InvalidMp3EncoderIntensityStereo,
        EncoderQuantizer.quantize(header, malformed),
    );
    malformed = prepared;
    malformed.granules[0][0].intensity_enabled[14] = true;
    try std.testing.expectError(
        error.InvalidMp3EncoderIntensityStereo,
        EncoderQuantizer.quantize(header, malformed),
    );
}

test "prepares short and low-rate MP3 intensity stereo layouts" {
    const header_bytes = [_][4]u8{
        testHeader(3, true, 11, 0, false, .joint_stereo),
        testHeader(2, true, 8, 0, false, .joint_stereo),
        testHeader(0, true, 8, 0, false, .joint_stereo),
    };
    const descriptions = [_]GranuleChannel{
        .{
            .window_switching = true,
            .block_type = 2,
        },
        .{
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
    };
    for (header_bytes) |bytes| {
        var header = try Header.parse(&bytes);
        header.mode_extension = 1;
        const granule_count: u2 =
            if (header.version == .mpeg1) 2 else 1;
        const bands = try scaleFactorBands(header);
        const line: usize = 3 * bands.short_starts[8];
        const gains = encoderIntensityGains(header, 2);
        for (descriptions) |description| {
            const layout = try encoderBandLayout(
                header,
                description,
            );
            const factor_index =
                encoderIntensityStartBand(description, layout);
            var analyzed = AnalyzedEncoderFrame{
                .channel_count = 2,
                .granule_count = granule_count,
            };
            for (0..granule_count) |granule| {
                analyzed.granules[granule][0].description =
                    description;
                analyzed.granules[granule][1].description =
                    description;
                analyzed.granules[granule][0]
                    .spectrum.lines[line] = 2 * gains[0];
                analyzed.granules[granule][1]
                    .spectrum.lines[line] = 2 * gains[1];
            }
            const prepared =
                try prepareEncoderStereo(header, analyzed);
            try std.testing.expect(
                prepared.granules[0][1]
                    .intensity_enabled[factor_index],
            );
            try std.testing.expectEqual(
                @as(u8, 2),
                prepared.granules[0][1]
                    .intensity_positions[factor_index],
            );
            try std.testing.expectEqual(
                @as(f32, 0),
                prepared.granules[0][1].spectrum.lines[line],
            );

            const factor_count =
                scaleFactorValueCount(header, description);
            var factors: [2]ScaleFactorChannel =
                @splat(.{});
            factors[0].value_count = factor_count;
            factors[1].value_count = factor_count;
            for (0..factor_count) |band|
                factors[1].values[band] =
                    prepared.granules[0][1]
                        .intensity_positions[band];
            const restored = try processStereo(
                header,
                @splat(description),
                factors,
                .{
                    prepared.granules[0][0].spectrum,
                    prepared.granules[0][1].spectrum,
                },
            );
            try std.testing.expectApproxEqAbs(
                2 * gains[0],
                restored.channels[0].lines[line],
                1e-6,
            );
            try std.testing.expectApproxEqAbs(
                2 * gains[1],
                restored.channels[1].lines[line],
                1e-6,
            );
        }
    }
}

test "analyzes bounded MP3 psychoacoustic bands" {
    const headers = [_]Header{
        try Header.parse(
            &testHeader(3, true, 9, 0, false, .mono),
        ),
        try Header.parse(
            &testHeader(0, true, 9, 2, false, .mono),
        ),
    };
    const descriptions = [_]GranuleChannel{
        .{},
        .{
            .window_switching = true,
            .block_type = 2,
        },
        .{
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
    };
    const model = EncoderPsychoacousticModel{};
    for (headers) |header| {
        for (descriptions) |description| {
            var channel = AnalyzedEncoderChannel{
                .description = description,
            };
            channel.spectrum.lines[0] = 2;
            channel.spectrum.lines[1] = -1;
            channel.spectrum.lines[40] = 0.25;
            const analyzed = try model.analyze(header, channel);
            const layout = try encoderBandLayout(
                header,
                description,
            );
            try std.testing.expectEqual(
                layout.band_count,
                analyzed.band_count,
            );
            try std.testing.expect(analyzed.energy[0] > 0);
            for (analyzed.threshold[0..analyzed.band_count]) |value|
                try std.testing.expect(
                    std.math.isFinite(value) and value > 0,
                );
            for (analyzed.energy[analyzed.band_count..]) |value|
                try std.testing.expectEqual(@as(f32, 0), value);
        }
    }

    var invalid_model = model;
    invalid_model.config.masking_ratio = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMp3EncoderPsychoacousticConfig,
        invalid_model.analyze(headers[0], .{}),
    );
    var malformed = AnalyzedEncoderChannel{};
    malformed.spectrum.lines[0] = std.math.inf(f32);
    try std.testing.expectError(
        error.InvalidMp3RequantizedSpectrum,
        model.analyze(headers[0], malformed),
    );
    const invalid_quantizer = EncoderQuantizer{
        .psychoacoustics = invalid_model,
    };
    const invalid_frame = AnalyzedEncoderFrame{
        .channel_count = 1,
        .granule_count = 2,
    };
    try std.testing.expectError(
        error.InvalidMp3EncoderPsychoacousticConfig,
        invalid_quantizer.process(headers[0], invalid_frame),
    );
}

test "MP3 psychoacoustics distinguish tonal and noise-like bands" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    const layout = try encoderBandLayout(header, .{});
    const line_count =
        layout.starts[1] - layout.starts[0];
    try std.testing.expect(line_count > 1);

    var tonal = AnalyzedEncoderChannel{};
    tonal.spectrum.lines[layout.starts[0]] =
        @sqrt(@as(f32, @floatFromInt(line_count)));
    var noise = AnalyzedEncoderChannel{};
    for (
        noise.spectrum.lines[layout.starts[0]..layout.starts[1]],
    ) |*line|
        line.* = 1.0;

    const model = EncoderPsychoacousticModel{
        .config = .{ .tonal_masking_reduction = 0.5 },
    };
    const tonal_result = try model.analyze(header, tonal);
    const noise_result = try model.analyze(header, noise);
    try std.testing.expectApproxEqAbs(
        tonal_result.energy[0],
        noise_result.energy[0],
        0.000_001,
    );
    try std.testing.expect(
        tonal_result.tonality[0] >
            noise_result.tonality[0] + 0.9,
    );
    try std.testing.expect(
        tonal_result.threshold[0] <
            noise_result.threshold[0],
    );
}

test "MP3 psychoacoustic timeline applies forward masking transactionally" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var analyzed = AnalyzedEncoderFrame{
        .channel_count = 1,
        .granule_count = 2,
    };
    analyzed.granules[0][0].spectrum.lines[0] = 10.0;
    analyzed.granules[1][0].spectrum.lines[0] = 0.001;
    var timeline = EncoderPsychoacousticTimeline{
        .model = .{
            .config = .{ .forward_masking_ratio = 0.1 },
        },
    };
    try std.testing.expect(timeline.valid());
    const result = try timeline.analyzeFrame(header, analyzed);
    try std.testing.expect(timeline.valid());
    try std.testing.expect(
        result[1][0].threshold[0] >=
            result[0][0].energy[0] * 0.099,
    );
    try std.testing.expect(timeline.history_present[0]);
    try std.testing.expectEqual(
        result[1][0],
        timeline.previous[0],
    );

    const retained = timeline;
    timeline.history_present[1] = false;
    timeline.previous[1].energy[0] = 1.0;
    const invalid = timeline;
    try std.testing.expect(!timeline.valid());
    try std.testing.expectError(
        error.InvalidMp3PsychoacousticHistory,
        timeline.analyzeFrame(header, analyzed),
    );
    try std.testing.expectEqual(invalid, timeline);
    timeline = retained;
    timeline.previous[1] = timeline.previous[0];
    timeline.history_present = .{ false, true };
    const impossible_channel_order = timeline;
    try std.testing.expect(!timeline.valid());
    try std.testing.expectError(
        error.InvalidMp3PsychoacousticHistory,
        timeline.analyzeFrame(header, analyzed),
    );
    try std.testing.expectEqual(impossible_channel_order, timeline);
    timeline = retained;
    timeline.reset();
    try std.testing.expect(timeline.valid());
    try std.testing.expectEqual(
        EncoderPsychoacousticTimeline{
            .model = retained.model,
        },
        timeline,
    );
}

test "quantizes analyzed MP3 spectra with automatic codebooks" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    };
    const header = try config.header(false);
    var analyzed = AnalyzedEncoderFrame{
        .channel_count = 1,
        .granule_count = 2,
    };
    for (0..2) |granule| {
        for (0..240) |line| {
            analyzed.granules[granule][0].spectrum.lines[line] =
                0.2 * @sin(
                    @as(f32, @floatFromInt(line)) * 0.37,
                );
        }
        analyzed.granules[granule][0].spectrum.lines[0] = 2.5;
        analyzed.granules[granule][0].spectrum.lines[1] = -1.5;
        analyzed.granules[granule][0].spectrum.lines[40] = 0.25;
        analyzed.granules[granule][0].spectrum.lines[43] = -0.25;
        analyzed.granules[granule][0].spectrum.lines[350] = 0.001;
    }
    const quantized = try EncoderQuantizer.quantize(
        header,
        analyzed,
    );
    for (0..2) |granule| {
        const channel = quantized.granules[granule][0];
        try std.testing.expect(channel.description.big_values > 0);
        try std.testing.expect(
            channel.description.table_select[0] != 0,
        );
        try std.testing.expect(
            channel.spectrum[0] != 0 or
                channel.spectrum[1] != 0,
        );
        var nonzero_factor = false;
        for (channel.scale_factors.values) |factor|
            nonzero_factor = nonzero_factor or factor != 0;
        try std.testing.expect(nonzero_factor);
    }

    var encoder = try FrameEncoder.init(config);
    var storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const bytes = try encoder.encodeQuantizedFrame(
        &quantized,
        &storage,
    );
    const parsed = try Frame.parse(bytes, 0);
    const side = try parsed.sideInformation();
    try std.testing.expect(side.main_data_bits > 0);
    var reservoir = MainDataReservoir(511){};
    var main_storage: [512]u8 = undefined;
    const main_data = try reservoir.assemble(
        parsed,
        &main_storage,
    );
    const decoded_factors = try decodeScaleFactors(
        parsed.header,
        side,
        main_data,
    );
    for (0..2) |granule| {
        try std.testing.expectEqual(
            quantized.granules[granule][0].scale_factors.values,
            decoded_factors.granules[granule].channels[0].values,
        );
        const reconstructed = try requantizeChannel(
            header,
            quantized.granules[granule][0].description,
            decoded_factors.granules[granule].channels[0],
            .{
                .lines = quantized.granules[granule][0].spectrum,
                .decoded_lines = 576,
            },
        );
        try std.testing.expect(reconstructed.lines[350] != 0);
    }
    var decoder = FrameDecoder{};
    const pcm = try decoder.decode(parsed);
    for (pcm.channels[0]) |sample|
        try std.testing.expect(std.math.isFinite(sample));

    var transitions = analyzed;
    transitions.granules[0][0].description = .{
        .window_switching = true,
        .block_type = 1,
    };
    transitions.granules[1][0].description = .{
        .window_switching = true,
        .block_type = 2,
    };
    const transition_quantized = try EncoderQuantizer.quantize(
        header,
        transitions,
    );
    try std.testing.expectEqual(
        @as(u4, 7),
        transition_quantized.granules[0][0]
            .description.region0_count,
    );
    try std.testing.expectEqual(
        @as(u5, 0),
        transition_quantized.granules[0][0]
            .description.table_select[2],
    );
    const short_quantized = QuantizedSpectrum{
        .lines = transition_quantized.granules[1][0].spectrum,
        .decoded_lines = 576,
    };
    const short_reconstructed = try requantizeChannel(
        header,
        transition_quantized.granules[1][0].description,
        .{
            .values = transition_quantized.granules[1][0]
                .scale_factors.values,
            .value_count = transition_quantized.granules[1][0]
                .scale_factors.value_count,
        },
        short_quantized,
    );
    try std.testing.expect(short_reconstructed.lines[40] != 0);
    try std.testing.expect(short_reconstructed.lines[43] != 0);
    const transition_bytes = try encoder.encodeQuantizedFrame(
        &transition_quantized,
        &storage,
    );
    const transition_parsed = try Frame.parse(
        transition_bytes,
        0,
    );
    const transition_side =
        try transition_parsed.sideInformation();
    try std.testing.expectEqual(
        @as(u4, 7),
        transition_side.granules[0].channels[0]
            .region0_count,
    );
    const transition_pcm = try decoder.decode(
        transition_parsed,
    );
    for (transition_pcm.channels[0]) |sample|
        try std.testing.expect(std.math.isFinite(sample));

    var malformed = analyzed;
    malformed.granules[0][0].spectrum.lines[0] =
        std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMp3RequantizedSpectrum,
        EncoderQuantizer.quantize(header, malformed),
    );
    malformed = analyzed;
    malformed.channel_count = 2;
    try std.testing.expectError(
        error.InvalidMp3EncoderAnalysisFrame,
        EncoderQuantizer.quantize(header, malformed),
    );
}

test "spends bounded MP3 reservoir history on quantization" {
    const header = try (EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 64,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    }).header(false);
    const physical_budget = try reservoirQuantizerBudget(
        header,
        0,
    );
    const reservoir_budget = try reservoirQuantizerBudget(
        header,
        511,
    );
    try std.testing.expectEqual(
        physical_budget.physical_bits,
        physical_budget.logical_bits,
    );
    try std.testing.expectEqual(
        @as(usize, 511 * 8),
        reservoir_budget.history_bits,
    );
    try std.testing.expectEqual(
        physical_budget.logical_bits + 511 * 8,
        reservoir_budget.logical_bits,
    );

    var analyzed = AnalyzedEncoderFrame{
        .channel_count = 1,
        .granule_count = 2,
    };
    for (0..2) |granule| {
        for (0..576) |line| {
            const position: f32 = @floatFromInt(line);
            analyzed.granules[granule][0].spectrum.lines[line] =
                0.7 * @sin(position * 0.17) +
                0.3 * @cos(position * 0.41);
        }
    }
    var timeline = EncoderPsychoacousticTimeline{};
    const masking = try timeline.analyzeFrame(
        header,
        analyzed,
    );
    const quantizer = EncoderQuantizer{};
    const physical = try quantizer.processWithMasking(
        header,
        analyzed,
        masking,
    );
    const expanded = try quantizer.processWithReservoirMasking(
        header,
        analyzed,
        masking,
        511,
    );
    const physical_ratio = try encoderNoiseToMaskRatio(
        header,
        analyzed,
        physical,
        masking,
    );
    const expanded_ratio = try encoderNoiseToMaskRatio(
        header,
        analyzed,
        expanded,
        masking,
    );
    try std.testing.expect(expanded_ratio < physical_ratio);
    try std.testing.expect(!std.meta.eql(physical, expanded));

    var parts_encoder = try FrameEncoder.init(.{
        .version = .mpeg1,
        .bitrate_kbps = 64,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    });
    var frame_storage: [maximum_encoded_frame_bytes]u8 =
        @splat(0xa5);
    var main_data_storage: [maximum_encoded_main_data_bytes + 8]u8 =
        @splat(0x5a);
    const parts = try parts_encoder.encodeQuantizedFrameParts(
        &expanded,
        &frame_storage,
        &main_data_storage,
    );
    try std.testing.expect(
        parts.main_data_bits > physical_budget.physical_bits,
    );
    try std.testing.expectEqual(
        @as(usize, parts.main_data_bits + 7) / 8,
        parts.main_data.len,
    );
    const parts_frame = try Frame.parse(parts.frame, 0);
    const parts_side = try parts_frame.sideInformation();
    try std.testing.expectEqual(
        parts.main_data_bits,
        parts_side.main_data_bits,
    );
    for (parts.frame[frameMainDataOffset(header)..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    try std.testing.expectEqualSlices(
        u8,
        &@as([8]u8, @splat(0x5a)),
        main_data_storage[parts.main_data.len..][0..8],
    );

    var ordinary_encoder = try FrameEncoder.init(.{
        .version = .mpeg1,
        .bitrate_kbps = 64,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    });
    const ordinary_encoder_before = ordinary_encoder;
    var ordinary_storage: [maximum_encoded_frame_bytes]u8 =
        @splat(0x3c);
    const ordinary_storage_before = ordinary_storage;
    try std.testing.expectError(
        error.Mp3HuffmanBitCountOverflow,
        ordinary_encoder.encodeQuantizedFrame(
            &expanded,
            &ordinary_storage,
        ),
    );
    try std.testing.expectEqual(
        ordinary_encoder_before,
        ordinary_encoder,
    );
    try std.testing.expectEqual(
        ordinary_storage_before,
        ordinary_storage,
    );

    var short_encoder = try FrameEncoder.init(.{
        .version = .mpeg1,
        .bitrate_kbps = 64,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    });
    const short_encoder_before = short_encoder;
    var short_frame_storage: [maximum_encoded_frame_bytes]u8 =
        @splat(0x6b);
    const short_frame_before = short_frame_storage;
    try std.testing.expectError(
        error.InsufficientMp3MainDataStorage,
        short_encoder.encodeQuantizedFrameParts(
            &expanded,
            &short_frame_storage,
            main_data_storage[0 .. parts.main_data.len - 1],
        ),
    );
    try std.testing.expectEqual(short_encoder_before, short_encoder);
    try std.testing.expectEqual(short_frame_before, short_frame_storage);

    var batch_encoder = try FrameEncoder.init(.{
        .version = .mpeg1,
        .bitrate_kbps = 64,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    });
    var batch_frames: [maximum_encoded_frame_bytes * 4]u8 =
        undefined;
    var batch_main_data: [maximum_encoded_main_data_bytes * 4]u8 =
        undefined;
    var batch_frame_length: usize = 0;
    var batch_main_data_length: usize = 0;
    const silent_quantized = QuantizedEncoderFrame{};
    for (0..4) |index| {
        const batch_parts = try batch_encoder.encodeQuantizedFrameParts(
            if (index == 3) &expanded else &silent_quantized,
            batch_frames[batch_frame_length..],
            batch_main_data[batch_main_data_length..],
        );
        batch_frame_length += batch_parts.frame.len;
        batch_main_data_length += batch_parts.main_data.len;
    }
    var batch_scratch: [maximum_encoded_frame_bytes * 4]u8 =
        @splat(0x27);
    const batch_shells = batch_frames;
    const packed_result = try packMainDataReservoir(
        batch_frames[0..batch_frame_length],
        batch_main_data[0..batch_main_data_length],
        511,
        &batch_scratch,
    );
    try std.testing.expectEqual(@as(u64, 4), packed_result.frame_count);
    try std.testing.expectEqual(@as(u16, 511), packed_result.maximum_backpointer);
    var packed_reader = try Stream.init(
        batch_frames[0..batch_frame_length],
    );
    var packed_decoder = FrameDecoder{};
    var frame_index: usize = 0;
    var final_frame_nonzero = false;
    while (try packed_reader.next()) |packed_frame| : (frame_index += 1) {
        const packed_side = try packed_frame.sideInformation();
        if (frame_index < 3)
            try std.testing.expectEqual(
                @as(u16, 0),
                packed_side.main_data_begin,
            )
        else {
            try std.testing.expectEqual(
                @as(u16, 511),
                packed_side.main_data_begin,
            );
            try std.testing.expect(
                packed_side.main_data_bits >
                    (packed_frame.bytes.len -
                        frameMainDataOffset(packed_frame.header)) * 8,
            );
        }
        const decoded = try packed_decoder.decode(packed_frame);
        if (frame_index == 3) {
            for (decoded.channels[0]) |sample| {
                try std.testing.expect(std.math.isFinite(sample));
                final_frame_nonzero = final_frame_nonzero or sample != 0;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 4), frame_index);
    try std.testing.expect(final_frame_nonzero);

    var rejected_frames: [maximum_encoded_frame_bytes * 4]u8 = undefined;
    @memcpy(
        rejected_frames[0..batch_frame_length],
        batch_shells[0..batch_frame_length],
    );
    const rejected_frames_before = rejected_frames;
    try std.testing.expectError(
        error.InvalidMp3LogicalMainDataLength,
        packMainDataReservoir(
            rejected_frames[0..batch_frame_length],
            batch_main_data[0 .. batch_main_data_length - 1],
            511,
            &batch_scratch,
        ),
    );
    try std.testing.expectEqual(rejected_frames_before, rejected_frames);

    try std.testing.expectError(
        error.InvalidMp3ReservoirHistoryLimit,
        reservoirQuantizerBudget(header, 512),
    );
    const low_rate_header = try (EncoderConfig{
        .version = .mpeg2,
        .bitrate_kbps = 64,
        .sample_rate = 22_050,
        .channel_mode = .mono,
    }).header(false);
    const low_rate_budget = try reservoirQuantizerBudget(
        low_rate_header,
        255,
    );
    try std.testing.expectEqual(
        @as(usize, 255 * 8),
        low_rate_budget.history_bits,
    );
    try std.testing.expectError(
        error.InvalidMp3ReservoirHistoryLimit,
        reservoirQuantizerBudget(low_rate_header, 256),
    );
    const maximum_header = try (EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 320,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    }).header(false);
    try std.testing.expectEqual(
        @as(usize, 2 * std.math.maxInt(u12)),
        (try reservoirQuantizerBudget(
            maximum_header,
            511,
        )).logical_bits,
    );
    var free_format = header;
    free_format.free_format = true;
    free_format.bitrate_kbps = 0;
    try std.testing.expectError(
        error.UnsupportedFreeFormatMp3,
        reservoirQuantizerBudget(free_format, 0),
    );
}

test "orders pure and mixed short spectra for MP3 encoding" {
    const headers = [_]Header{
        try Header.parse(
            &testHeader(3, true, 9, 0, false, .mono),
        ),
        try Header.parse(
            &testHeader(0, true, 9, 2, false, .mono),
        ),
    };
    var spectrum = RequantizedSpectrum{};
    for (&spectrum.lines, 0..) |*line, index|
        line.* = @floatFromInt(index);
    for (headers) |header| {
        const bands = try scaleFactorBands(header);
        const pure = try orderEncoderSpectrum(
            header,
            .{
                .window_switching = true,
                .block_type = 2,
            },
            spectrum,
        );
        const first_width: usize =
            bands.short_starts[1] - bands.short_starts[0];
        try std.testing.expectEqual(@as(f32, 0), pure[0]);
        try std.testing.expectEqual(
            @as(f32, 1),
            pure[first_width],
        );
        try std.testing.expectEqual(
            @as(f32, 2),
            pure[first_width * 2],
        );

        const mixed = try orderEncoderSpectrum(
            header,
            .{
                .window_switching = true,
                .block_type = 2,
                .mixed_block = true,
            },
            spectrum,
        );
        const boundary: usize = 3 * bands.short_starts[3];
        try std.testing.expectEqual(
            @as(f32, @floatFromInt(boundary - 1)),
            mixed[boundary - 1],
        );
        try std.testing.expectEqual(
            @as(f32, @floatFromInt(boundary)),
            mixed[boundary],
        );
        try std.testing.expectEqual(
            @as(f32, @floatFromInt(boundary + 1)),
            mixed[
                boundary +
                    bands.short_starts[4] -
                    bands.short_starts[3]
            ],
        );
    }
}

test "keeps low-rate mixed terminal scale factors zero" {
    const header = try Header.parse(
        &testHeader(0, true, 9, 2, false, .mono),
    );
    var analyzed = AnalyzedEncoderFrame{
        .channel_count = 1,
        .granule_count = 1,
    };
    analyzed.granules[0][0].description = .{
        .window_switching = true,
        .block_type = 2,
        .mixed_block = true,
    };
    analyzed.granules[0][0].spectrum.lines[0] = 1;
    analyzed.granules[0][0].spectrum.lines[575] = 0.1;
    const quantized = try EncoderQuantizer.quantize(
        header,
        analyzed,
    );
    const channel = quantized.granules[0][0];
    try std.testing.expectEqual(
        @as(u6, 33),
        channel.scale_factors.value_count,
    );
    const layout = try encoderBandLayout(
        header,
        channel.description,
    );
    for (channel.scale_factors.values[layout.band_count - 3 ..]) |factor|
        try std.testing.expectEqual(@as(u8, 0), factor);
    var storage: [64]u8 = undefined;
    _ = try encodeScaleFactors(
        header,
        channel.description,
        0,
        0,
        0,
        .{},
        channel.scale_factors,
        &storage,
    );
}

test "encodes PCM into complete MP3 frames transactionally" {
    const config = EncoderConfig{
        .version = .mpeg2,
        .bitrate_kbps = 64,
        .sample_rate = 22_050,
        .channel_mode = .mono,
    };
    var encoder = try PcmEncoder.init(config);
    try std.testing.expect(encoder.valid());
    var pcm = PcmFrame{
        .channel_count = 1,
        .sample_count = 576,
    };
    for (&pcm.channels[0], 0..) |*sample, index| {
        sample.* = 0.2 * @sin(
            @as(f32, @floatFromInt(index)) * 0.07,
        );
    }
    var storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const first = try encoder.encode(pcm, &storage);
    try std.testing.expect(encoder.valid());
    const parsed = try Frame.parse(first, 0);
    try std.testing.expectEqual(config.version, parsed.header.version);
    try std.testing.expectEqual(
        @as(u64, 1),
        encoder.frames.frames_encoded,
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        encoder.analysis.frames_analyzed,
    );
    var decoder = FrameDecoder{};
    const decoded = try decoder.decode(parsed);
    for (decoded.channels[0]) |sample|
        try std.testing.expect(std.math.isFinite(sample));

    const before = encoder;
    var short_storage: [8]u8 = undefined;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encoder.encode(pcm, &short_storage),
    );
    try std.testing.expectEqual(before, encoder);

    var hostile = encoder;
    hostile.analysis.frames_analyzed += 1;
    try std.testing.expect(!hostile.valid());
    const hostile_before = hostile;
    try std.testing.expectError(
        error.InvalidMp3PcmEncoderState,
        hostile.encode(pcm, &storage),
    );
    try std.testing.expectEqual(hostile_before, hostile);

    encoder.reset();
    try std.testing.expect(encoder.valid());
    try std.testing.expectEqual(
        @as(u64, 0),
        encoder.frames.frames_encoded,
    );
    try std.testing.expectEqual(
        @as(u64, 0),
        encoder.analysis.frames_analyzed,
    );
}

test "selects bounded MP3 VBR frames transactionally" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 14,
        .maximum_noise_to_mask_ratio = 0.25,
    };
    var encoder = try VbrPcmEncoder.init(config);
    try std.testing.expect(encoder.valid());
    const silence = PcmFrame{
        .channel_count = 1,
        .sample_count = 1152,
    };
    var storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const quiet = try encoder.encode(silence, &storage);
    try std.testing.expect(encoder.valid());
    try std.testing.expectEqual(@as(u4, 1), quiet.bitrate_index);
    try std.testing.expect(quiet.quality_met);
    try std.testing.expectEqual(
        bitrate(.mpeg1, quiet.bitrate_index),
        quiet.header.bitrate_kbps,
    );
    try std.testing.expectEqual(
        quiet.header.frameBytes(),
        quiet.frame.len,
    );
    try std.testing.expectEqual(
        @as(?bool, true),
        try (try Frame.parse(quiet.frame, 0)).crcValid(),
    );

    var complex = silence;
    for (&complex.channels[0], 0..) |*sample, index| {
        const position: f32 = @floatFromInt(index);
        sample.* =
            0.18 * @sin(position * 0.031) +
            0.16 * @sin(position * 0.173) +
            0.12 * @sin(position * 0.419);
        if (index % 37 == 0)
            sample.* += if (index % 74 == 0) 0.3 else -0.3;
    }
    const detailed = try encoder.encode(complex, &storage);
    try std.testing.expect(encoder.valid());
    try std.testing.expect(
        detailed.bitrate_index > quiet.bitrate_index,
    );
    try std.testing.expect(
        std.math.isFinite(
            detailed.maximum_noise_to_mask_ratio,
        ),
    );
    try std.testing.expectEqual(
        @as(u64, 2),
        encoder.frames.frames_encoded,
    );
    try std.testing.expectEqual(
        @as(u64, 2),
        encoder.analysis.frames_analyzed,
    );
    var histogram_frames: u64 = 0;
    for (encoder.bitrate_histogram) |count|
        histogram_frames += count;
    try std.testing.expectEqual(@as(u64, 2), histogram_frames);

    const before = encoder;
    var short_storage: [8]u8 = undefined;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encoder.encode(complex, &short_storage),
    );
    try std.testing.expectEqual(before, encoder);
    try std.testing.expectError(
        error.Mp3VbrBitrateOutsidePolicy,
        encoder.encodeAtBitrateIndex(
            complex,
            &storage,
            0,
        ),
    );
    try std.testing.expectEqual(before, encoder);

    var hostile = encoder;
    hostile.bitrate_histogram[0] = 1;
    try std.testing.expect(!hostile.valid());
    const hostile_before = hostile;
    try std.testing.expectError(
        error.InvalidMp3VbrEncoderState,
        hostile.encode(complex, &storage),
    );
    try std.testing.expectEqual(hostile_before, hostile);
    try std.testing.expectError(
        error.InvalidMp3VbrEncoderConfig,
        VbrPcmEncoder.init(.{
            .minimum_bitrate_index = 14,
            .maximum_bitrate_index = 1,
        }),
    );
    try std.testing.expectError(
        error.InvalidMp3VbrEncoderConfig,
        VbrPcmEncoder.init(.{
            .maximum_noise_to_mask_ratio = std.math.nan(f32),
        }),
    );

    var low_rate = try VbrPcmEncoder.init(.{
        .template = .{
            .version = .mpeg2,
            .sample_rate = 22_050,
            .channel_mode = .mono,
        },
        .minimum_bitrate_index = 8,
        .maximum_bitrate_index = 8,
    });
    const low_rate_frame = try low_rate.encode(
        .{
            .channel_count = 1,
            .sample_count = 576,
        },
        &storage,
    );
    try std.testing.expectEqual(
        Version.mpeg2,
        low_rate_frame.header.version,
    );
    try std.testing.expectEqual(
        @as(u16, 64),
        low_rate_frame.header.bitrate_kbps,
    );
}

test "finishes MP3 VBR streams with Xing metadata" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .maximum_noise_to_mask_ratio = 0.25,
    };
    var offsets: [8]u64 = undefined;
    var encoder = try VbrPcmStreamEncoder.init(
        config,
        &offsets,
    );
    var encoded: [maximum_encoded_frame_bytes * 5]u8 = @splat(0x5a);
    var cursor: usize = 0;
    const metadata_encoder: [9]u8 = "VBRTest 1".*;
    const placeholder = try encoder.startXingMetadataWithEncoder(
        metadata_encoder,
        encoded[cursor..],
    );
    cursor += placeholder.len;
    const provisional = try Frame.parse(
        encoded[0..cursor],
        0,
    );
    try std.testing.expectEqual(
        XingKind.variable,
        provisional.xing.?.kind,
    );
    try std.testing.expectEqual(
        @as(?u32, 0),
        provisional.xing.?.frame_count,
    );
    try std.testing.expect(
        provisional.xing.?.toc != null,
    );
    try std.testing.expectEqual(
        metadata_encoder,
        provisional.xing.?.encoder.?,
    );

    const silence = PcmFrame{
        .channel_count = 1,
        .sample_count = 1152,
    };
    const quiet = try encoder.append(
        silence,
        encoded[cursor..],
    );
    cursor += quiet.frame.len;
    var detailed_pcm = silence;
    for (&detailed_pcm.channels[0], 0..) |*sample, index| {
        const position: f32 = @floatFromInt(index);
        sample.* =
            0.2 * @sin(position * 0.039) +
            0.17 * @sin(position * 0.211);
        if (index % 41 == 0)
            sample.* += 0.25;
    }
    const detailed = try encoder.append(
        detailed_pcm,
        encoded[cursor..],
    );
    cursor += detailed.frame.len;
    try std.testing.expect(
        detailed.bitrate_index > quiet.bitrate_index,
    );

    const before_finish = encoder;
    const offsets_before_finish = offsets;
    var short_storage: [8]u8 = undefined;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encoder.finish(&short_storage),
    );
    try std.testing.expectEqual(before_finish, encoder);
    try std.testing.expectEqual(
        offsets_before_finish,
        offsets,
    );

    const finished = try encoder.finish(encoded[cursor..]);
    cursor += finished.frames.len;
    try std.testing.expectEqual(@as(u64, 4), finished.summary.frame_count);
    try std.testing.expectEqual(@as(u64, 2304), finished.summary.input_samples);
    try std.testing.expectEqual(@as(u16, 2209), finished.summary.encoder_delay);
    try std.testing.expectEqual(@as(u16, 95), finished.summary.end_padding);
    try std.testing.expectEqual(
        @as(u64, cursor),
        finished.summary.byte_count,
    );

    var final_metadata: [maximum_encoded_frame_bytes]u8 =
        undefined;
    const replacement = try encoder.xingMetadataFrame(
        37,
        &final_metadata,
    );
    try std.testing.expectEqual(placeholder.len, replacement.len);
    @memcpy(encoded[0..replacement.len], replacement);
    const summary = try Stream.summarize(encoded[0..cursor]);
    const xing = summary.first_xing.?;
    try std.testing.expectEqual(metadata_encoder, xing.encoder.?);
    try std.testing.expectEqual(XingKind.variable, xing.kind);
    try std.testing.expectEqual(
        @as(?u32, 4),
        xing.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(cursor)),
        xing.stream_bytes,
    );
    try std.testing.expectEqual(@as(?u32, 37), xing.quality);
    try std.testing.expectEqual(
        @as(?u12, 528),
        xing.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(?u12, 624),
        xing.encoder_padding,
    );
    const toc = xing.toc.?;
    try std.testing.expectEqual(@as(u8, 0), toc[0]);
    for (1..toc.len) |index|
        try std.testing.expect(toc[index] >= toc[index - 1]);

    const repeated = try encoder.finish(encoded[cursor..]);
    try std.testing.expectEqual(@as(usize, 0), repeated.frames.len);
    const hostile = encoder;
    offsets[1] = 0;
    try std.testing.expectError(
        error.InvalidMp3VbrStreamState,
        hostile.summary(),
    );
}

test "encodes correlated PCM through MP3 mid-side stereo" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .joint_stereo,
        .mode_extension = 2,
    };
    var encoder = try PcmEncoder.init(config);
    var pcm = PcmFrame{
        .channel_count = 2,
        .sample_count = 1152,
    };
    for (0..1152) |index| {
        const sample = 0.2 * @sin(
            @as(f32, @floatFromInt(index)) * 0.05,
        );
        pcm.channels[0][index] = sample;
        pcm.channels[1][index] = sample;
    }
    var storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const bytes = try encoder.encode(pcm, &storage);
    const parsed = try Frame.parse(bytes, 0);
    try std.testing.expectEqual(
        ChannelMode.joint_stereo,
        parsed.header.channel_mode,
    );
    try std.testing.expectEqual(
        @as(u2, 2),
        parsed.header.mode_extension,
    );
    var decoder = FrameDecoder{};
    const decoded = try decoder.decode(parsed);
    var nonzero = false;
    for (
        decoded.channels[0],
        decoded.channels[1],
    ) |left, right| {
        try std.testing.expectApproxEqAbs(left, right, 1e-6);
        nonzero = nonzero or left != 0;
    }
    try std.testing.expect(nonzero);

    var intensity_encoder = try PcmEncoder.init(.{
        .bitrate_kbps = 192,
        .channel_mode = .joint_stereo,
        .mode_extension = 1,
    });
    const intensity_bytes =
        try intensity_encoder.encode(pcm, &storage);
    const intensity_frame =
        try Frame.parse(intensity_bytes, 0);
    try std.testing.expectEqual(
        @as(u2, 1),
        intensity_frame.header.mode_extension,
    );
    var intensity_decoder = FrameDecoder{};
    const intensity_decoded =
        try intensity_decoder.decode(intensity_frame);
    var intensity_nonzero = false;
    for (
        intensity_decoded.channels[0],
        intensity_decoded.channels[1],
    ) |left, right| {
        try std.testing.expect(std.math.isFinite(left));
        try std.testing.expect(std.math.isFinite(right));
        intensity_nonzero =
            intensity_nonzero or left != 0 or right != 0;
    }
    try std.testing.expect(intensity_nonzero);
}

test "encodes MP3 intensity stereo through VBR selection" {
    var encoder = try VbrPcmEncoder.init(.{
        .template = .{
            .channel_mode = .joint_stereo,
            .mode_extension = 1,
        },
        .minimum_bitrate_index = 11,
        .maximum_bitrate_index = 11,
    });
    var pcm = PcmFrame{
        .channel_count = 2,
        .sample_count = 1152,
    };
    for (0..1152) |index| {
        const position: f32 = @floatFromInt(index);
        pcm.channels[0][index] =
            0.18 * @sin(position * 0.05);
        pcm.channels[1][index] =
            0.12 * @sin(position * 0.05 + 0.3);
    }
    var storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const selected = try encoder.encode(pcm, &storage);
    try std.testing.expectEqual(@as(u4, 11), selected.bitrate_index);
    try std.testing.expectEqual(
        @as(u2, 1),
        selected.header.mode_extension,
    );
    try std.testing.expect(
        std.math.isFinite(
            selected.maximum_noise_to_mask_ratio,
        ),
    );
}

test "encodes low-rate MP3 intensity stereo through the decoder" {
    const configs = [_]EncoderConfig{
        .{
            .version = .mpeg2,
            .bitrate_kbps = 64,
            .sample_rate = 22_050,
            .channel_mode = .joint_stereo,
            .mode_extension = 1,
        },
        .{
            .version = .mpeg25,
            .bitrate_kbps = 32,
            .sample_rate = 11_025,
            .channel_mode = .joint_stereo,
            .mode_extension = 1,
        },
    };
    for (configs) |config| {
        var encoder = try PcmEncoder.init(config);
        var pcm = PcmFrame{
            .channel_count = 2,
            .sample_count = 576,
        };
        for (0..576) |index| {
            const position: f32 = @floatFromInt(index);
            pcm.channels[0][index] =
                0.16 * @sin(position * 0.07);
            pcm.channels[1][index] =
                0.1 * @sin(position * 0.07 + 0.5);
        }
        var storage: [maximum_encoded_frame_bytes]u8 = undefined;
        const bytes = try encoder.encode(pcm, &storage);
        const frame = try Frame.parse(bytes, 0);
        try std.testing.expectEqual(config.version, frame.header.version);
        try std.testing.expectEqual(
            ChannelMode.joint_stereo,
            frame.header.channel_mode,
        );
        var decoder = FrameDecoder{};
        const decoded = try decoder.decode(frame);
        var nonzero = false;
        for (decoded.channels[0], decoded.channels[1]) |left, right| {
            try std.testing.expect(std.math.isFinite(left));
            try std.testing.expect(std.math.isFinite(right));
            nonzero = nonzero or left != 0 or right != 0;
        }
        try std.testing.expect(nonzero);
    }
}

test "reuses MP3 main-data capacity across pending PCM frames" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    const samples_per_frame =
        (try config.header(false)).samplesPerFrame();
    var pcm_frames: [3]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = samples_per_frame,
    });
    for (0..samples_per_frame) |sample| {
        const phase =
            2.0 * std.math.pi *
            @as(f32, @floatFromInt(sample)) / 37.0;
        pcm_frames[1].channels[0][sample] =
            0.6 * @sin(phase);
        pcm_frames[2].channels[0][sample] =
            0.4 * @sin(phase * 1.7);
    }

    var ordinary = try PcmEncoder.init(config);
    var ordinary_bytes: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var ordinary_length: usize = 0;
    for (pcm_frames) |pcm| {
        const frame = try ordinary.encode(
            pcm,
            ordinary_bytes[ordinary_length..],
        );
        ordinary_length += frame.len;
    }

    var reservoir = try PcmReservoirEncoder.init(config);
    try std.testing.expect(reservoir.valid());
    var reservoir_bytes: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var reservoir_length: usize = 0;
    const primed = try reservoir.append(
        pcm_frames[0],
        reservoir_bytes[0..0],
    );
    try std.testing.expect(reservoir.valid());
    try std.testing.expectEqual(@as(?[]u8, null), primed.frame);
    const pending_snapshot = reservoir.pending;
    const received_snapshot = reservoir.frames_received;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        reservoir.append(
            pcm_frames[1],
            reservoir_bytes[0..0],
        ),
    );
    try std.testing.expectEqual(
        received_snapshot,
        reservoir.frames_received,
    );
    try std.testing.expectEqualSlices(
        u8,
        pending_snapshot[0..reservoir.pending_length],
        reservoir.pending[0..reservoir.pending_length],
    );

    var total_borrowed: u64 = 0;
    for (pcm_frames[1..]) |pcm| {
        const emitted = try reservoir.append(
            pcm,
            reservoir_bytes[reservoir_length..],
        );
        const frame = emitted.frame orelse
            return error.TestMp3ReservoirFrameMissing;
        reservoir_length += frame.len;
        total_borrowed += emitted.borrowed_bytes;
        if (emitted.borrowed_bytes != 0) {
            var mismatched_borrow = reservoir;
            mismatched_borrow.borrowed_bytes -=
                emitted.borrowed_bytes;
            try std.testing.expect(!mismatched_borrow.valid());
            const mismatched_before = mismatched_borrow;
            try std.testing.expectError(
                error.InvalidMp3ReservoirEncoderState,
                mismatched_borrow.finish(&reservoir_bytes),
            );
            try std.testing.expectEqual(
                mismatched_before,
                mismatched_borrow,
            );
        }
    }
    const final_frame = (try reservoir.finish(
        reservoir_bytes[reservoir_length..],
    )) orelse return error.TestMp3ReservoirFrameMissing;
    try std.testing.expect(reservoir.valid());
    reservoir_length += final_frame.len;
    try std.testing.expectEqual(
        ordinary_length,
        reservoir_length,
    );
    try std.testing.expect(total_borrowed > 0);
    try std.testing.expectEqual(
        total_borrowed,
        reservoir.borrowed_bytes,
    );
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        reservoir.frames_received,
    );
    try std.testing.expectEqual(
        reservoir.frames_received,
        reservoir.frames_emitted,
    );
    try std.testing.expect(
        (try reservoir.finish(
            reservoir_bytes[reservoir_length..],
        )) == null,
    );
    try std.testing.expectError(
        error.Mp3ReservoirEncoderFinalized,
        reservoir.append(
            pcm_frames[0],
            reservoir_bytes[reservoir_length..],
        ),
    );

    var ordinary_stream = try Stream.init(
        ordinary_bytes[0..ordinary_length],
    );
    var reservoir_stream = try Stream.init(
        reservoir_bytes[0..reservoir_length],
    );
    var ordinary_decoder = FrameDecoder{};
    var reservoir_decoder = FrameDecoder{};
    var borrowed_frame_seen = false;
    while (try ordinary_stream.next()) |ordinary_frame| {
        const reservoir_frame =
            (try reservoir_stream.next()) orelse
            return error.TestMp3ReservoirFrameMissing;
        const reservoir_side =
            try reservoir_frame.sideInformation();
        borrowed_frame_seen = borrowed_frame_seen or
            reservoir_side.main_data_begin != 0;
        try std.testing.expectEqual(
            @as(?bool, true),
            try reservoir_frame.crcValid(),
        );
        const ordinary_pcm =
            try ordinary_decoder.decode(ordinary_frame);
        const reservoir_pcm =
            try reservoir_decoder.decode(reservoir_frame);
        try std.testing.expectEqual(
            ordinary_pcm.channel_count,
            reservoir_pcm.channel_count,
        );
        try std.testing.expectEqual(
            ordinary_pcm.sample_count,
            reservoir_pcm.sample_count,
        );
        for (
            ordinary_pcm.channels[0][0..ordinary_pcm.sample_count],
            reservoir_pcm.channels[0][0..reservoir_pcm.sample_count],
        ) |expected, actual|
            try std.testing.expectEqual(expected, actual);
    }
    try std.testing.expect(
        (try reservoir_stream.next()) == null,
    );
    try std.testing.expect(borrowed_frame_seen);

    var malformed = try PcmReservoirEncoder.init(config);
    malformed.pending_length =
        maximum_encoded_frame_bytes + 1;
    try std.testing.expect(!malformed.valid());
    const malformed_before = malformed;
    try std.testing.expectError(
        error.InvalidMp3ReservoirEncoderState,
        malformed.finish(&reservoir_bytes),
    );
    try std.testing.expectEqual(malformed_before, malformed);
    var impossible_borrow = try PcmReservoirEncoder.init(config);
    impossible_borrow.borrowed_bytes = 1;
    try std.testing.expect(!impossible_borrow.valid());
    const impossible_borrow_before = impossible_borrow;
    try std.testing.expectError(
        error.InvalidMp3ReservoirEncoderState,
        impossible_borrow.finish(&reservoir_bytes),
    );
    try std.testing.expectEqual(
        impossible_borrow_before,
        impossible_borrow,
    );
    var corrupted = try PcmReservoirEncoder.init(config);
    _ = try corrupted.append(
        pcm_frames[0],
        reservoir_bytes[0..0],
    );
    corrupted.pending[4] ^= 1;
    try std.testing.expect(!corrupted.valid());
    const corrupted_before = corrupted;
    try std.testing.expectError(
        error.InvalidMp3ReservoirEncoderState,
        corrupted.finish(&reservoir_bytes),
    );
    try std.testing.expectEqual(corrupted_before, corrupted);
}

test "repacks MP3 main data across multiple frame boundaries" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    const samples_per_frame =
        (try config.header(false)).samplesPerFrame();
    var pcm_frames: [5]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = samples_per_frame,
    });
    for (0..samples_per_frame) |sample| {
        const position: f32 = @floatFromInt(sample);
        pcm_frames[3].channels[0][sample] =
            0.55 * @sin(position * 0.17);
        pcm_frames[4].channels[0][sample] =
            0.35 * @sin(position * 0.31) +
            0.15 * @cos(position * 0.07);
    }

    var encoder = try PcmEncoder.init(config);
    var ordinary: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        @splat(0xa5);
    var ordinary_length: usize = 0;
    for (pcm_frames) |pcm| {
        const frame = try encoder.encode(
            pcm,
            ordinary[ordinary_length..],
        );
        ordinary_length += frame.len;
    }
    const ordinary_stream = ordinary[0..ordinary_length];
    const requirements = try reservoirRepackRequirements(
        ordinary_stream,
    );
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        requirements.frame_count,
    );
    try std.testing.expect(requirements.payload_bytes > 0);
    try std.testing.expect(
        requirements.payload_bytes < requirements.main_data_bytes,
    );

    var repacked = ordinary;
    var encoded_scratch: [maximum_encoded_frame_bytes * pcm_frames.len + 8]u8 =
        @splat(0x4c);
    var payload_scratch: [maximum_encoded_frame_bytes * pcm_frames.len + 8]u8 =
        @splat(0x7d);
    const result = try repackMainDataReservoir(
        repacked[0..ordinary_length],
        511,
        &encoded_scratch,
        &payload_scratch,
    );
    try std.testing.expectEqual(
        requirements.frame_count,
        result.frame_count,
    );
    try std.testing.expect(result.borrowed_bytes > 0);
    const first_frame = try Frame.parse(ordinary_stream, 0);
    const first_capacity =
        first_frame.bytes.len - frameMainDataOffset(first_frame.header);
    try std.testing.expect(result.maximum_backpointer > first_capacity);
    try std.testing.expectEqualSlices(
        u8,
        &@as([8]u8, @splat(0x4c)),
        encoded_scratch[ordinary_length..][0..8],
    );
    try std.testing.expectEqualSlices(
        u8,
        &@as([8]u8, @splat(0x7d)),
        payload_scratch[requirements.payload_bytes..][0..8],
    );

    var ordinary_reader = try Stream.init(ordinary_stream);
    var repacked_reader = try Stream.init(repacked[0..ordinary_length]);
    var ordinary_decoder = FrameDecoder{};
    var repacked_decoder = FrameDecoder{};
    while (try ordinary_reader.next()) |ordinary_frame| {
        const repacked_frame = (try repacked_reader.next()) orelse
            return error.TestMp3ReservoirFrameMissing;
        try std.testing.expectEqual(
            @as(?bool, true),
            try repacked_frame.crcValid(),
        );
        const expected = try ordinary_decoder.decode(ordinary_frame);
        const actual = try repacked_decoder.decode(repacked_frame);
        try std.testing.expectEqual(
            expected.sample_count,
            actual.sample_count,
        );
        try std.testing.expectEqualSlices(
            f32,
            expected.channels[0][0..expected.sample_count],
            actual.channels[0][0..actual.sample_count],
        );
    }
    try std.testing.expect((try repacked_reader.next()) == null);
    try std.testing.expectError(
        error.Mp3ReservoirAlreadyPacked,
        reservoirRepackRequirements(repacked[0..ordinary_length]),
    );

    var independent = ordinary;
    var independent_staged: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var independent_payload: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    const independent_result = try repackMainDataReservoir(
        independent[0..ordinary_length],
        0,
        &independent_staged,
        &independent_payload,
    );
    try std.testing.expectEqual(@as(u64, 0), independent_result.borrowed_bytes);
    try std.testing.expectEqual(@as(u16, 0), independent_result.maximum_backpointer);
    try std.testing.expectEqualSlices(
        u8,
        ordinary_stream,
        independent[0..ordinary_length],
    );

    var rejected = ordinary;
    const rejected_before = rejected;
    try std.testing.expectError(
        error.InvalidMp3ReservoirHistoryLimit,
        repackMainDataReservoir(
            rejected[0..ordinary_length],
            512,
            &encoded_scratch,
            &payload_scratch,
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected);
    try std.testing.expectError(
        error.Mp3ReservoirEncodedScratchTooSmall,
        repackMainDataReservoir(
            rejected[0..ordinary_length],
            511,
            encoded_scratch[0 .. ordinary_length - 1],
            &payload_scratch,
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected);
    try std.testing.expectError(
        error.Mp3ReservoirPayloadScratchTooSmall,
        repackMainDataReservoir(
            rejected[0..ordinary_length],
            511,
            &encoded_scratch,
            payload_scratch[0 .. requirements.payload_bytes - 1],
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected);
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        repackMainDataReservoir(
            rejected[0..ordinary_length],
            511,
            rejected[0..ordinary_length],
            &payload_scratch,
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected);
}

test "encodes PCM with adaptive multi-frame MP3 reservoir credit" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 32,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    const samples_per_frame =
        (try config.header(false)).samplesPerFrame();
    const initial_header = try config.header(false);
    var credit = try ReservoirCreditTracker.init(
        initial_header,
        511,
    );
    try std.testing.expect(credit.valid());
    const initial_budget = try credit.budget(initial_header);
    try std.testing.expectEqual(
        initial_budget.physical_bits,
        initial_budget.logical_bits,
    );
    const silent_credit = try credit.commit(initial_header, 0);
    try std.testing.expect(silent_credit.next_history_bytes > 0);
    try std.testing.expectEqual(
        silent_credit.next_history_bytes,
        credit.available_history_bytes,
    );
    var hostile_credit = credit;
    hostile_credit.available_history_bytes = 512;
    try std.testing.expect(!hostile_credit.valid());
    const hostile_credit_before = hostile_credit;
    try std.testing.expectError(
        error.InvalidMp3ReservoirCreditState,
        hostile_credit.commit(initial_header, 0),
    );
    try std.testing.expectEqual(hostile_credit_before, hostile_credit);
    credit.reset();
    try std.testing.expect(credit.valid());
    var pcm_frames: [9]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = samples_per_frame,
    });
    for (5..pcm_frames.len) |frame_index| {
        for (0..samples_per_frame) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * samples_per_frame + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.45 * @sin(position * 0.113) +
                0.3 * @cos(position * 0.271) +
                0.15 * @sin(position * 0.419);
        }
    }
    const required_frame_bytes =
        try requiredPcmReservoirBatchFrameBytes(
            config,
            pcm_frames.len,
        );
    var destination: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        @splat(0xa1);
    var frame_scratch: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var pack_scratch: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var main_data_scratch: [maximum_encoded_main_data_bytes * pcm_frames.len]u8 = undefined;
    const encoded = try encodePcmReservoirBatch(
        config,
        &pcm_frames,
        511,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_data_scratch,
    );
    try std.testing.expectEqual(required_frame_bytes, encoded.stream.len);
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        encoded.frame_count,
    );
    try std.testing.expect(encoded.borrowed_bytes > 0);
    try std.testing.expect(encoded.maximum_backpointer > 0);
    try std.testing.expect(encoded.retained_history_bytes <= 511);

    var stream = try Stream.init(encoded.stream);
    var decoder = FrameDecoder{};
    var expanded_frame_seen = false;
    var nonzero_pcm_seen = false;
    while (try stream.next()) |frame| {
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
        const side = try frame.sideInformation();
        const physical_bits =
            (frame.bytes.len - frameMainDataOffset(frame.header)) * 8;
        expanded_frame_seen = expanded_frame_seen or
            side.main_data_bits > physical_bits;
        const decoded = try decoder.decode(frame);
        for (decoded.channels[0]) |sample| {
            try std.testing.expect(std.math.isFinite(sample));
            nonzero_pcm_seen = nonzero_pcm_seen or sample != 0;
        }
    }
    try std.testing.expect(expanded_frame_seen);
    try std.testing.expect(nonzero_pcm_seen);

    var rejected_destination = destination;
    const rejected_before = rejected_destination;
    try std.testing.expectError(
        error.InvalidMp3ReservoirHistoryLimit,
        encodePcmReservoirBatch(
            config,
            &pcm_frames,
            512,
            &rejected_destination,
            &frame_scratch,
            &pack_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected_destination);
    try std.testing.expectError(
        error.InsufficientMp3MainDataStorage,
        encodePcmReservoirBatch(
            config,
            &pcm_frames,
            511,
            &rejected_destination,
            &frame_scratch,
            &pack_scratch,
            main_data_scratch[0..0],
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected_destination);
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        encodePcmReservoirBatch(
            config,
            &pcm_frames,
            511,
            &rejected_destination,
            &rejected_destination,
            &pack_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected_destination);
    var pcm_alias_storage: [@sizeOf(PcmFrame)]u8 align(@alignOf(PcmFrame)) =
        undefined;
    const aliased_pcm = std.mem.bytesAsSlice(
        PcmFrame,
        &pcm_alias_storage,
    );
    aliased_pcm[0] = pcm_frames[0];
    const pcm_alias_before = pcm_alias_storage;
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        encodePcmReservoirBatch(
            config,
            aliased_pcm,
            511,
            &rejected_destination,
            &pcm_alias_storage,
            &pack_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(pcm_alias_before, pcm_alias_storage);
    const empty = try encodePcmReservoirBatch(
        config,
        &.{},
        511,
        &rejected_destination,
        &frame_scratch,
        &pack_scratch,
        &main_data_scratch,
    );
    try std.testing.expectEqual(@as(usize, 0), empty.stream.len);
    try std.testing.expectEqual(rejected_before, rejected_destination);
}

test "publishes adaptive MP3 reservoir frames outside future reach" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 32,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    var pcm_frames: [12]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (6..pcm_frames.len) |frame_index| {
        for (0..1152) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * 1152 + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.48 * @sin(position * 0.131) +
                0.26 * @cos(position * 0.337);
        }
    }
    const required_storage =
        try requiredPcmAdaptiveReservoirStorage(config, 511);
    var short_storage: [maximum_encoded_frame_bytes * 12]u8 =
        @splat(0x72);
    try std.testing.expectError(
        error.Mp3AdaptiveReservoirStorageTooSmall,
        PcmAdaptiveReservoirStreamEncoder.init(
            config,
            511,
            short_storage[0 .. required_storage - 1],
        ),
    );
    var pending_storage: [maximum_encoded_frame_bytes * 12]u8 =
        @splat(0x81);
    var pending_scratch: [maximum_encoded_frame_bytes * 12]u8 =
        undefined;
    var frame_scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    var main_data_scratch: [maximum_encoded_main_data_bytes]u8 = undefined;
    var encoder = try PcmAdaptiveReservoirStreamEncoder.init(
        config,
        511,
        pending_storage[0..required_storage],
    );
    try std.testing.expect(encoder.valid());
    var encoded: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var encoded_length: usize = 0;
    var emitted_before_finish = false;
    var first_emission_index: ?usize = null;
    for (pcm_frames, 0..) |pcm, frame_index| {
        const appended = try encoder.append(
            pcm,
            encoded[encoded_length..],
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        );
        try std.testing.expect(encoder.valid());
        if (appended.frames.len != 0) {
            emitted_before_finish = true;
            if (first_emission_index == null)
                first_emission_index = frame_index;
        }
        encoded_length += appended.frames.len;
    }
    try std.testing.expect(emitted_before_finish);
    const finished = try encoder.finish(encoded[encoded_length..]);
    encoded_length += finished.frames.len;
    try std.testing.expect(encoder.valid());
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        finished.frame_count,
    );
    try std.testing.expectEqual(
        finished.byte_count,
        encoded_length,
    );
    try std.testing.expect(finished.borrowed_bytes > 0);
    try std.testing.expect(finished.maximum_backpointer > 0);
    var hostile_byte_count = encoder;
    hostile_byte_count.byte_count += 1;
    try std.testing.expect(!hostile_byte_count.valid());
    var hostile_destination: [1]u8 = .{0x5a};
    try std.testing.expectError(
        error.InvalidMp3AdaptiveReservoirState,
        hostile_byte_count.finish(&hostile_destination),
    );
    try std.testing.expectEqual(@as(u8, 0x5a), hostile_destination[0]);
    const repeated = try encoder.finish(encoded[encoded_length..]);
    try std.testing.expectEqual(@as(usize, 0), repeated.frames.len);
    try std.testing.expectEqual(finished.frame_count, repeated.frame_count);

    var batch_destination: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_frames: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_pack: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_main: [maximum_encoded_main_data_bytes * pcm_frames.len]u8 =
        undefined;
    const batch = try encodePcmReservoirBatch(
        config,
        &pcm_frames,
        511,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
    );
    try std.testing.expectEqualSlices(u8, batch.stream, encoded[0..encoded_length]);
    try std.testing.expectEqual(batch.frame_count, finished.frame_count);
    try std.testing.expectEqual(
        batch.logical_main_data_bits,
        finished.logical_main_data_bits,
    );
    try std.testing.expectEqual(batch.borrowed_bytes, finished.borrowed_bytes);
    try std.testing.expectEqual(
        batch.maximum_backpointer,
        finished.maximum_backpointer,
    );

    var stream = try Stream.init(encoded[0..encoded_length]);
    var decoder = FrameDecoder{};
    var nonzero_pcm_seen = false;
    while (try stream.next()) |frame| {
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
        const decoded = try decoder.decode(frame);
        for (decoded.channels[0]) |sample| {
            try std.testing.expect(std.math.isFinite(sample));
            nonzero_pcm_seen = nonzero_pcm_seen or sample != 0;
        }
    }
    try std.testing.expect(nonzero_pcm_seen);

    var retry_storage: [maximum_encoded_frame_bytes * 12]u8 =
        @splat(0x93);
    var retry_encoder = try PcmAdaptiveReservoirStreamEncoder.init(
        config,
        511,
        retry_storage[0..required_storage],
    );
    const failure_index = first_emission_index orelse
        return error.TestAdaptiveReservoirEmissionMissing;
    for (pcm_frames[0..failure_index]) |pcm| {
        _ = try retry_encoder.append(
            pcm,
            &encoded,
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        );
    }
    const state_before = retry_encoder;
    const pending_before = retry_storage;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        retry_encoder.append(
            pcm_frames[failure_index],
            encoded[0..0],
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(state_before.encoder, retry_encoder.encoder);
    try std.testing.expectEqual(state_before.credit, retry_encoder.credit);
    try std.testing.expectEqual(
        state_before.pending_length,
        retry_encoder.pending_length,
    );
    try std.testing.expectEqual(pending_before, retry_storage);
    try std.testing.expect(retry_encoder.valid());
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        retry_encoder.append(
            pcm_frames[failure_index],
            retry_storage[0..required_storage],
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(pending_before, retry_storage);
    try std.testing.expect(retry_encoder.valid());

    const zero_storage_bytes =
        try requiredPcmAdaptiveReservoirStorage(config, 0);
    var zero_pending: [maximum_encoded_frame_bytes]u8 = undefined;
    var zero_staging: [maximum_encoded_frame_bytes]u8 = undefined;
    var zero_output: [maximum_encoded_frame_bytes]u8 = undefined;
    var zero_encoder = try PcmAdaptiveReservoirStreamEncoder.init(
        config,
        0,
        zero_pending[0..zero_storage_bytes],
    );
    const immediate = try zero_encoder.append(
        pcm_frames[0],
        &zero_output,
        zero_staging[0..zero_storage_bytes],
        &frame_scratch,
        &main_data_scratch,
    );
    try std.testing.expectEqual(@as(u16, 1), immediate.frame_count);
    try std.testing.expectEqual(@as(usize, 0), zero_encoder.pending_length);
    var ordinary_encoder = try PcmEncoder.init(config);
    var ordinary_storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const ordinary = try ordinary_encoder.encode(
        pcm_frames[0],
        &ordinary_storage,
    );
    try std.testing.expectEqualSlices(u8, ordinary, immediate.frames);
}

test "combines adaptive VBR selection with multi-frame reservoir credit" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 5,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    const samples_per_frame: u16 = 1152;
    var pcm_frames: [9]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = samples_per_frame,
    });
    for (5..pcm_frames.len) |frame_index| {
        for (0..samples_per_frame) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * samples_per_frame + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.5 * @sin(position * 0.137) +
                0.25 * @cos(position * 0.293);
        }
    }
    var destination: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        @splat(0x91);
    var frame_scratch: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var pack_scratch: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var main_data_scratch: [maximum_encoded_main_data_bytes * pcm_frames.len]u8 = undefined;
    const encoded = try encodeVbrPcmReservoirBatch(
        config,
        &pcm_frames,
        511,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_data_scratch,
    );
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        encoded.frame_count,
    );
    try std.testing.expect(encoded.borrowed_bytes > 0);
    try std.testing.expect(encoded.maximum_backpointer > 0);
    try std.testing.expect(std.math.isFinite(
        encoded.maximum_noise_to_mask_ratio,
    ));
    var histogram_frames: u64 = 0;
    for (encoded.bitrate_histogram) |count|
        histogram_frames += count;
    try std.testing.expectEqual(encoded.frame_count, histogram_frames);
    try std.testing.expectEqual(
        encoded.quality_misses != 0,
        encoded.maximum_noise_to_mask_ratio >
            config.maximum_noise_to_mask_ratio,
    );

    var stream = try Stream.init(encoded.stream);
    var decoder = FrameDecoder{};
    var decoded_frames: usize = 0;
    var nonzero_pcm_seen = false;
    while (try stream.next()) |frame| : (decoded_frames += 1) {
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
        const decoded = try decoder.decode(frame);
        for (decoded.channels[0]) |sample| {
            try std.testing.expect(std.math.isFinite(sample));
            nonzero_pcm_seen = nonzero_pcm_seen or sample != 0;
        }
    }
    try std.testing.expectEqual(pcm_frames.len, decoded_frames);
    try std.testing.expect(nonzero_pcm_seen);

    var rejected = destination;
    const rejected_before = rejected;
    try std.testing.expectError(
        error.InvalidMp3ReservoirHistoryLimit,
        encodeVbrPcmReservoirBatch(
            config,
            &pcm_frames,
            512,
            &rejected,
            &frame_scratch,
            &pack_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected);
}

test "publishes adaptive VBR reservoir frames outside future reach" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 5,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    var pcm_frames: [12]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (6..pcm_frames.len) |frame_index| {
        for (0..1152) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * 1152 + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.48 * @sin(position * 0.131) +
                0.26 * @cos(position * 0.337);
        }
    }

    const required_storage =
        try requiredVbrPcmAdaptiveReservoirStorage(config, 511);
    var short_storage: [maximum_encoded_frame_bytes * 12]u8 =
        @splat(0x72);
    try std.testing.expectError(
        error.Mp3AdaptiveReservoirStorageTooSmall,
        VbrPcmAdaptiveReservoirStreamEncoder.init(
            config,
            511,
            short_storage[0 .. required_storage - 1],
        ),
    );
    var pending_storage: [maximum_encoded_frame_bytes * 12]u8 =
        @splat(0x81);
    var pending_scratch: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var frame_scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    var main_data_scratch: [maximum_encoded_main_data_bytes]u8 = undefined;
    var encoder = try VbrPcmAdaptiveReservoirStreamEncoder.init(
        config,
        511,
        pending_storage[0..required_storage],
    );
    var encoded: [maximum_encoded_frame_bytes * pcm_frames.len]u8 = undefined;
    var encoded_length: usize = 0;
    var first_emission_index: ?usize = null;
    for (pcm_frames, 0..) |pcm, frame_index| {
        const appended = try encoder.append(
            pcm,
            encoded[encoded_length..],
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        );
        try std.testing.expect(encoder.valid());
        try std.testing.expect(
            appended.selection.bitrate_index >=
                config.minimum_bitrate_index and
                appended.selection.bitrate_index <=
                    config.maximum_bitrate_index,
        );
        try std.testing.expect(std.math.isFinite(
            appended.selection.maximum_noise_to_mask_ratio,
        ));
        if (appended.frames.len != 0 and first_emission_index == null)
            first_emission_index = frame_index;
        encoded_length += appended.frames.len;
    }
    try std.testing.expect(first_emission_index != null);
    const finished = try encoder.finish(encoded[encoded_length..]);
    encoded_length += finished.frames.len;
    try std.testing.expect(encoder.valid());
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        finished.frame_count,
    );
    try std.testing.expectEqual(finished.byte_count, encoded_length);
    try std.testing.expect(finished.borrowed_bytes > 0);
    try std.testing.expect(finished.maximum_backpointer > 0);
    var histogram_frames: u64 = 0;
    for (finished.bitrate_histogram) |count| histogram_frames += count;
    try std.testing.expectEqual(finished.frame_count, histogram_frames);
    const repeated = try encoder.finish(encoded[encoded_length..]);
    try std.testing.expectEqual(@as(usize, 0), repeated.frames.len);

    var batch_destination: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_frames: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_pack: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_main: [maximum_encoded_main_data_bytes * pcm_frames.len]u8 =
        undefined;
    const batch = try encodeVbrPcmReservoirBatch(
        config,
        &pcm_frames,
        511,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
    );
    try std.testing.expectEqualSlices(u8, batch.stream, encoded[0..encoded_length]);
    try std.testing.expectEqual(batch.frame_count, finished.frame_count);
    try std.testing.expectEqual(
        batch.logical_main_data_bits,
        finished.logical_main_data_bits,
    );
    try std.testing.expectEqual(batch.borrowed_bytes, finished.borrowed_bytes);
    try std.testing.expectEqual(
        batch.maximum_backpointer,
        finished.maximum_backpointer,
    );
    try std.testing.expectEqual(
        batch.bitrate_histogram,
        finished.bitrate_histogram,
    );
    try std.testing.expectEqual(batch.quality_misses, finished.quality_misses);
    try std.testing.expectEqual(
        batch.maximum_noise_to_mask_ratio,
        finished.maximum_noise_to_mask_ratio,
    );

    var stream = try Stream.init(encoded[0..encoded_length]);
    var decoder = FrameDecoder{};
    var decoded_frames: usize = 0;
    var nonzero_pcm_seen = false;
    while (try stream.next()) |frame| : (decoded_frames += 1) {
        try std.testing.expectEqual(@as(?bool, true), try frame.crcValid());
        const decoded = try decoder.decode(frame);
        for (decoded.channels[0]) |sample| {
            try std.testing.expect(std.math.isFinite(sample));
            nonzero_pcm_seen = nonzero_pcm_seen or sample != 0;
        }
    }
    try std.testing.expectEqual(pcm_frames.len, decoded_frames);
    try std.testing.expect(nonzero_pcm_seen);

    var retry_storage: [maximum_encoded_frame_bytes * 12]u8 =
        @splat(0x93);
    var retry_encoder = try VbrPcmAdaptiveReservoirStreamEncoder.init(
        config,
        511,
        retry_storage[0..required_storage],
    );
    const failure_index = first_emission_index orelse
        return error.TestAdaptiveVbrReservoirEmissionMissing;
    for (pcm_frames[0..failure_index]) |pcm| {
        _ = try retry_encoder.append(
            pcm,
            &encoded,
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        );
    }
    const state_before = retry_encoder;
    const pending_before = retry_storage;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        retry_encoder.append(
            pcm_frames[failure_index],
            encoded[0..0],
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(state_before.encoder, retry_encoder.encoder);
    try std.testing.expectEqual(state_before.credit, retry_encoder.credit);
    try std.testing.expectEqual(
        state_before.pending_length,
        retry_encoder.pending_length,
    );
    try std.testing.expectEqual(pending_before, retry_storage);
    try std.testing.expect(retry_encoder.valid());
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        retry_encoder.append(
            pcm_frames[failure_index],
            retry_storage[0..required_storage],
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(pending_before, retry_storage);
    try std.testing.expect(retry_encoder.valid());

    const zero_storage_bytes =
        try requiredVbrPcmAdaptiveReservoirStorage(config, 0);
    var zero_pending: [maximum_encoded_frame_bytes]u8 = undefined;
    var zero_staging: [maximum_encoded_frame_bytes]u8 = undefined;
    var zero_output: [maximum_encoded_frame_bytes]u8 = undefined;
    var zero_encoder = try VbrPcmAdaptiveReservoirStreamEncoder.init(
        config,
        0,
        zero_pending[0..zero_storage_bytes],
    );
    const immediate = try zero_encoder.append(
        pcm_frames[0],
        &zero_output,
        zero_staging[0..zero_storage_bytes],
        &frame_scratch,
        &main_data_scratch,
    );
    try std.testing.expectEqual(@as(u16, 1), immediate.frame_count);
    var ordinary_encoder = try VbrPcmEncoder.init(config);
    var ordinary_storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const ordinary = try ordinary_encoder.encode(
        pcm_frames[0],
        &ordinary_storage,
    );
    try std.testing.expectEqualSlices(u8, ordinary.frame, immediate.frames);
    try std.testing.expectEqual(
        ordinary.bitrate_index,
        immediate.selection.bitrate_index,
    );
}

test "composes exact gapless adaptive reservoir metadata" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 32,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    var pcm_frames: [8]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (4..pcm_frames.len) |frame_index| {
        for (0..1152) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * 1152 + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.48 * @sin(position * 0.131) +
                0.26 * @cos(position * 0.337);
        }
    }
    const maximum_frames = pcm_frames.len + 3;
    var destination: [maximum_encoded_frame_bytes * maximum_frames]u8 =
        undefined;
    var frame_scratch: [maximum_encoded_frame_bytes * maximum_frames]u8 =
        undefined;
    var pack_scratch: [maximum_encoded_frame_bytes * maximum_frames]u8 =
        undefined;
    var main_scratch: [maximum_encoded_main_data_bytes * maximum_frames]u8 =
        undefined;
    var metadata_scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    const encoder_identifier: [9]u8 = "Gapless 1".*;
    const encoded = try encodePcmReservoirGaplessBatch(
        config,
        &pcm_frames,
        511,
        encoder_identifier,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_scratch,
        &metadata_scratch,
    );
    try std.testing.expectEqual(encoded.stream.len, encoded.summary.byte_count);
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len * 1152),
        encoded.summary.input_samples,
    );
    try std.testing.expect(encoded.borrowed_bytes > 0);
    const parsed = try Stream.summarize(encoded.stream);
    try std.testing.expectEqual(
        @as(?u32, @intCast(encoded.summary.frame_count)),
        parsed.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(encoded.summary.byte_count)),
        parsed.first_xing.?.stream_bytes,
    );
    try std.testing.expectEqual(
        encoder_identifier,
        parsed.first_xing.?.encoder.?,
    );
    const gapless = try GaplessPlan.fromSummary(parsed);
    try std.testing.expectEqual(
        encoded.summary.input_samples,
        gapless.audible_samples,
    );
    var stream = try Stream.init(encoded.stream);
    var frames: u64 = 0;
    while (try stream.next()) |frame| : (frames += 1)
        try std.testing.expectEqual(@as(?bool, true), try frame.crcValid());
    try std.testing.expectEqual(encoded.summary.frame_count, frames);

    const vbr_config = VbrEncoderConfig{
        .template = config,
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 5,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    const vbr = try encodeVbrPcmReservoirGaplessBatch(
        vbr_config,
        &pcm_frames,
        511,
        73,
        encoder_identifier,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_scratch,
        &metadata_scratch,
    );
    try std.testing.expectEqual(vbr.stream.len, vbr.summary.byte_count);
    try std.testing.expect(vbr.borrowed_bytes > 0);
    var histogram_frames: u64 = 0;
    for (vbr.bitrate_histogram) |count| histogram_frames += count;
    try std.testing.expectEqual(vbr.summary.frame_count, histogram_frames);
    const parsed_vbr = try Stream.summarize(vbr.stream);
    try std.testing.expectEqual(
        @as(?XingKind, .variable),
        parsed_vbr.first_xing.?.kind,
    );
    try std.testing.expectEqual(
        @as(?u32, 73),
        parsed_vbr.first_xing.?.quality,
    );
    try std.testing.expect(parsed_vbr.first_xing.?.toc != null);
    const vbr_gapless = try GaplessPlan.fromSummary(parsed_vbr);
    try std.testing.expectEqual(
        vbr.summary.input_samples,
        vbr_gapless.audible_samples,
    );

    const destination_before = destination;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encodePcmReservoirGaplessBatch(
            config,
            &pcm_frames,
            511,
            encoder_identifier,
            destination[0..1],
            &frame_scratch,
            &pack_scratch,
            &main_scratch,
            &metadata_scratch,
        ),
    );
    try std.testing.expectEqual(destination_before, destination);
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        encodePcmReservoirGaplessBatch(
            config,
            &pcm_frames,
            511,
            encoder_identifier,
            &destination,
            &destination,
            &pack_scratch,
            &main_scratch,
            &metadata_scratch,
        ),
    );
    try std.testing.expectEqual(destination_before, destination);
    var pcm_alias_storage: [@sizeOf(PcmFrame)]u8 align(@alignOf(PcmFrame)) =
        undefined;
    const aliased_pcm = std.mem.bytesAsSlice(
        PcmFrame,
        &pcm_alias_storage,
    );
    aliased_pcm[0] = pcm_frames[0];
    const pcm_alias_before = pcm_alias_storage;
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        encodePcmReservoirGaplessBatch(
            config,
            aliased_pcm,
            511,
            encoder_identifier,
            &destination,
            &frame_scratch,
            &pack_scratch,
            &main_scratch,
            &pcm_alias_storage,
        ),
    );
    try std.testing.expectEqual(pcm_alias_before, pcm_alias_storage);

    const prefix = [_]u8{ 'I', 'D', '3', 4, 0, 0, 0, 0, 0, 0 };
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "gapless-adaptive.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, &prefix, 0);
    var faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 7,
    };
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        writePcmReservoirGaplessBatchFileWithOperations(
            std.testing.io,
            file,
            config,
            &pcm_frames,
            511,
            prefix.len,
            encoder_identifier,
            &destination,
            &frame_scratch,
            &pack_scratch,
            &main_scratch,
            &metadata_scratch,
            faults.operations(),
        ),
    );
    try std.testing.expectEqual(
        @as(u64, prefix.len),
        try file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    const written = try writePcmReservoirGaplessBatchFileWithOperations(
        std.testing.io,
        file,
        config,
        &pcm_frames,
        511,
        prefix.len,
        encoder_identifier,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_scratch,
        &metadata_scratch,
        faults.operations(),
    );
    try std.testing.expectEqual(
        written.file_end,
        try file.length(std.testing.io),
    );
    var file_frame: [maximum_encoded_frame_bytes]u8 = undefined;
    const file_summary = try FileReader.summarize(
        std.testing.io,
        file,
        &file_frame,
    );
    try std.testing.expectEqual(
        written.batch.summary.input_samples,
        (try GaplessPlan.fromSummary(.{
            .audio_offset = @intCast(file_summary.audio_offset),
            .audio_bytes = @intCast(file_summary.audio_bytes),
            .frame_count = file_summary.frame_count,
            .sample_count = file_summary.sample_count,
            .sample_rate = file_summary.sample_rate,
            .channels = file_summary.channels,
            .first_xing = file_summary.first_xing,
            .first_vbri = null,
        })).audible_samples,
    );

    var vbr_file = try temporary.dir.createFile(
        std.testing.io,
        "gapless-adaptive-vbr.mp3",
        .{ .read = true },
    );
    defer vbr_file.close(std.testing.io);
    const vbr_written = try writeVbrPcmReservoirGaplessBatchFile(
        std.testing.io,
        vbr_file,
        vbr_config,
        &pcm_frames,
        511,
        0,
        73,
        encoder_identifier,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_scratch,
        &metadata_scratch,
    );
    try std.testing.expectEqual(
        vbr_written.file_end,
        try vbr_file.length(std.testing.io),
    );
    const vbr_file_summary = try FileReader.summarize(
        std.testing.io,
        vbr_file,
        &file_frame,
    );
    try std.testing.expectEqual(
        vbr_written.batch.summary.input_samples,
        (try GaplessPlan.fromSummary(.{
            .audio_offset = @intCast(vbr_file_summary.audio_offset),
            .audio_bytes = @intCast(vbr_file_summary.audio_bytes),
            .frame_count = vbr_file_summary.frame_count,
            .sample_count = vbr_file_summary.sample_count,
            .sample_rate = vbr_file_summary.sample_rate,
            .channels = vbr_file_summary.channels,
            .first_xing = vbr_file_summary.first_xing,
            .first_vbri = null,
        })).audible_samples,
    );
}

test "streams exact gapless adaptive reservoir metadata transactionally" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 32,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    var pcm_frames: [8]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (4..pcm_frames.len) |frame_index| {
        for (0..1152) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * 1152 + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.48 * @sin(position * 0.131) +
                0.26 * @cos(position * 0.337);
        }
    }

    const storage_bytes = maximum_encoded_frame_bytes * 16;
    var pending: [storage_bytes]u8 = undefined;
    var pending_scratch: [storage_bytes]u8 = undefined;
    var rollback: [storage_bytes]u8 = undefined;
    var frame_scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    var main_data_scratch: [maximum_encoded_main_data_bytes]u8 = undefined;
    var output_scratch: [storage_bytes]u8 = undefined;
    var streamed: [storage_bytes]u8 = @splat(0x5a);
    const identifier: [9]u8 = "GapStrm 1".*;
    var encoder = try PcmAdaptiveReservoirGaplessStreamEncoder.init(
        config,
        511,
        &pending,
    );
    try std.testing.expectError(
        error.Mp3EncoderMetadataNotStarted,
        encoder.append(
            pcm_frames[0],
            &streamed,
            &pending_scratch,
            &frame_scratch,
            &main_data_scratch,
        ),
    );
    var cursor: usize = 0;
    const placeholder = try encoder.startMetadataWithEncoder(
        identifier,
        streamed[cursor..],
        &frame_scratch,
        &main_data_scratch,
    );
    cursor += placeholder.len;
    try std.testing.expect(encoder.valid());
    for (pcm_frames) |pcm| {
        const appended = try encoder.append(
            pcm,
            streamed[cursor..],
            &pending_scratch,
            &frame_scratch,
            &main_data_scratch,
        );
        cursor += appended.frames.len;
    }
    const pending_before = pending;
    const cursor_before = cursor;
    const destination_before = streamed;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encoder.finish(
            streamed[cursor .. cursor + 1],
            &pending_scratch,
            &rollback,
            &frame_scratch,
            &main_data_scratch,
            &output_scratch,
        ),
    );
    try std.testing.expectEqual(pending_before, pending);
    try std.testing.expectEqual(destination_before, streamed);
    try std.testing.expectEqual(cursor_before, cursor);
    try std.testing.expect(encoder.valid());
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        encoder.finish(
            streamed[cursor..],
            &pending_scratch,
            &rollback,
            &frame_scratch,
            &main_data_scratch,
            streamed[cursor..],
        ),
    );
    try std.testing.expectEqual(pending_before, pending);
    try std.testing.expectEqual(destination_before, streamed);

    const finished = try encoder.finish(
        streamed[cursor..],
        &pending_scratch,
        &rollback,
        &frame_scratch,
        &main_data_scratch,
        &output_scratch,
    );
    cursor += finished.frames.len;
    const metadata = try encoder.metadataFrame(streamed[0..placeholder.len]);
    try std.testing.expectEqual(placeholder.len, metadata.len);
    try std.testing.expectEqual(cursor, finished.summary.byte_count);
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len * 1152),
        finished.summary.input_samples,
    );
    try std.testing.expect(finished.borrowed_bytes > 0);
    try std.testing.expect(encoder.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        (try encoder.finish(
            streamed[cursor..],
            &pending_scratch,
            &rollback,
            &frame_scratch,
            &main_data_scratch,
            &output_scratch,
        )).frames.len,
    );

    const summary = try Stream.summarize(streamed[0..cursor]);
    try std.testing.expectEqual(
        @as(?u32, @intCast(finished.summary.frame_count)),
        summary.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(identifier, summary.first_xing.?.encoder.?);
    try std.testing.expectEqual(
        finished.summary.input_samples,
        (try GaplessPlan.fromSummary(summary)).audible_samples,
    );
    var reader = try Stream.init(streamed[0..cursor]);
    while (try reader.next()) |frame|
        try std.testing.expectEqual(@as(?bool, true), try frame.crcValid());

    var batch_destination: [storage_bytes]u8 = undefined;
    var batch_frames: [storage_bytes]u8 = undefined;
    var batch_pack: [storage_bytes]u8 = undefined;
    var batch_main: [maximum_encoded_main_data_bytes * 16]u8 = undefined;
    var batch_metadata: [maximum_encoded_frame_bytes]u8 = undefined;
    const batch = try encodePcmReservoirGaplessBatch(
        config,
        &pcm_frames,
        511,
        identifier,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
        &batch_metadata,
    );
    try std.testing.expectEqualSlices(u8, batch.stream, streamed[0..cursor]);

    const vbr_config = VbrEncoderConfig{
        .template = config,
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 5,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    streamed = @splat(0x5a);
    var vbr_encoder =
        try VbrPcmAdaptiveReservoirGaplessStreamEncoder.init(
            vbr_config,
            511,
            &pending,
        );
    cursor = 0;
    const vbr_placeholder = try vbr_encoder.startMetadataWithEncoder(
        identifier,
        streamed[cursor..],
        &frame_scratch,
    );
    cursor += vbr_placeholder.len;
    for (pcm_frames) |pcm| {
        const appended = try vbr_encoder.append(
            pcm,
            streamed[cursor..],
            &pending_scratch,
            &frame_scratch,
            &main_data_scratch,
        );
        cursor += appended.frames.len;
    }
    const vbr_pending_before = pending;
    const vbr_destination_before = streamed;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        vbr_encoder.finish(
            streamed[cursor .. cursor + 1],
            &pending_scratch,
            &rollback,
            &frame_scratch,
            &main_data_scratch,
            &output_scratch,
        ),
    );
    try std.testing.expectEqual(vbr_pending_before, pending);
    try std.testing.expectEqual(vbr_destination_before, streamed);
    try std.testing.expect(vbr_encoder.valid());
    const vbr_finished = try vbr_encoder.finish(
        streamed[cursor..],
        &pending_scratch,
        &rollback,
        &frame_scratch,
        &main_data_scratch,
        &output_scratch,
    );
    cursor += vbr_finished.frames.len;
    _ = try vbr_encoder.metadataFrame(
        73,
        streamed[0..cursor],
        streamed[0..vbr_placeholder.len],
    );
    const vbr_summary = try Stream.summarize(streamed[0..cursor]);
    try std.testing.expectEqual(
        @as(?u32, 73),
        vbr_summary.first_xing.?.quality,
    );
    try std.testing.expect(vbr_summary.first_xing.?.toc != null);
    try std.testing.expectEqual(
        vbr_finished.summary.input_samples,
        (try GaplessPlan.fromSummary(vbr_summary)).audible_samples,
    );
    const vbr_batch = try encodeVbrPcmReservoirGaplessBatch(
        vbr_config,
        &pcm_frames,
        511,
        73,
        identifier,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
        &batch_metadata,
    );
    try std.testing.expectEqualSlices(
        u8,
        vbr_batch.stream,
        streamed[0..cursor],
    );

    var hostile = encoder;
    hostile.stream.independent_frames = 0;
    try std.testing.expect(!hostile.valid());
}

test "recovers incremental adaptive reservoir file publication" {
    const prefix = [_]u8{ 'I', 'D', '3', 4, 0, 0, 0, 0, 0, 0 };
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 32,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    var pcm_frames: [12]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (6..pcm_frames.len) |frame_index| {
        for (0..1152) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * 1152 + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.48 * @sin(position * 0.131) +
                0.26 * @cos(position * 0.337);
        }
    }
    const required = try requiredPcmAdaptiveReservoirStorage(config, 511);
    var pending: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var staging: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var rollback: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var frame_scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    var main_scratch: [maximum_encoded_main_data_bytes]u8 = undefined;
    var output: [maximum_encoded_frame_bytes * 12]u8 = undefined;

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-incremental.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, &prefix, 0);
    var faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 7,
    };
    var encoder = try PcmAdaptiveReservoirFileEncoder.initAtWithOperations(
        std.testing.io,
        file,
        config,
        511,
        pending[0..required],
        staging[0..required],
        rollback[0..required],
        &frame_scratch,
        &main_scratch,
        output[0..required],
        prefix.len,
        faults.operations(),
    );
    var failed_index: ?usize = null;
    for (pcm_frames, 0..) |pcm, index| {
        _ = encoder.append(pcm) catch |failure| {
            try std.testing.expectEqual(
                error.InjectedMp3FileWriteFailure,
                failure,
            );
            failed_index = index;
            break;
        };
    }
    const retry_index = failed_index orelse
        return error.TestAdaptiveReservoirFileWriteMissing;
    try std.testing.expect(encoder.failed);
    try std.testing.expect(encoder.valid());
    try encoder.recover();
    try std.testing.expectEqual(
        @as(u64, prefix.len),
        try file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    for (pcm_frames[retry_index..]) |pcm| _ = try encoder.append(pcm);
    const summary = try encoder.finalize();
    try std.testing.expect(encoder.valid());
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        summary.frame_count,
    );
    try std.testing.expectEqual(
        @as(u64, prefix.len) + summary.byte_count,
        summary.file_end,
    );
    try std.testing.expectEqual(
        summary.file_end,
        try file.length(std.testing.io),
    );

    var batch_destination: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_frames: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_pack: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_main: [maximum_encoded_main_data_bytes * pcm_frames.len]u8 =
        undefined;
    const batch = try encodePcmReservoirBatch(
        config,
        &pcm_frames,
        511,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
    );
    var stored: [maximum_encoded_frame_bytes * pcm_frames.len]u8 = undefined;
    try file_reader_io.readExactAt(
        std.testing.io,
        file,
        prefix.len,
        stored[0..batch.stream.len],
        error.TestTruncatedAdaptiveIncrementalMp3,
    );
    try std.testing.expectEqualSlices(
        u8,
        batch.stream,
        stored[0..batch.stream.len],
    );

    const vbr_config = VbrEncoderConfig{
        .template = config,
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 5,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    const vbr_required =
        try requiredVbrPcmAdaptiveReservoirStorage(vbr_config, 511);
    var vbr_file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-incremental-vbr.mp3",
        .{ .read = true },
    );
    defer vbr_file.close(std.testing.io);
    try vbr_file.writePositionalAll(std.testing.io, &prefix, 0);
    faults.write_calls = 0;
    faults.fail_write_call = 1;
    var vbr_encoder =
        try VbrPcmAdaptiveReservoirFileEncoder.initAtWithOperations(
            std.testing.io,
            vbr_file,
            vbr_config,
            511,
            pending[0..vbr_required],
            staging[0..vbr_required],
            rollback[0..vbr_required],
            &frame_scratch,
            &main_scratch,
            output[0..vbr_required],
            prefix.len,
            faults.operations(),
        );
    failed_index = null;
    for (pcm_frames, 0..) |pcm, index| {
        _ = vbr_encoder.append(pcm) catch |failure| {
            try std.testing.expectEqual(
                error.InjectedMp3FileWriteFailure,
                failure,
            );
            failed_index = index;
            break;
        };
    }
    const vbr_retry_index = failed_index orelse
        return error.TestAdaptiveVbrReservoirFileWriteMissing;
    try std.testing.expect(vbr_encoder.failed);
    try std.testing.expect(vbr_encoder.valid());
    try vbr_encoder.recover();
    try std.testing.expectEqual(
        @as(u64, prefix.len),
        try vbr_file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    for (pcm_frames[vbr_retry_index..]) |pcm|
        _ = try vbr_encoder.append(pcm);
    const vbr_summary = try vbr_encoder.finalize();
    try std.testing.expect(vbr_encoder.valid());
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        vbr_summary.frame_count,
    );
    var histogram_frames: u64 = 0;
    for (vbr_summary.bitrate_histogram) |count|
        histogram_frames += count;
    try std.testing.expectEqual(vbr_summary.frame_count, histogram_frames);
    try std.testing.expect(std.math.isFinite(
        vbr_summary.maximum_noise_to_mask_ratio,
    ));

    const vbr_batch = try encodeVbrPcmReservoirBatch(
        vbr_config,
        &pcm_frames,
        511,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
    );
    try file_reader_io.readExactAt(
        std.testing.io,
        vbr_file,
        prefix.len,
        stored[0..vbr_batch.stream.len],
        error.TestTruncatedAdaptiveIncrementalVbrMp3,
    );
    try std.testing.expectEqualSlices(
        u8,
        vbr_batch.stream,
        stored[0..vbr_batch.stream.len],
    );
}

test "recovers exact gapless adaptive CBR file publication" {
    const prefix = [_]u8{ 'I', 'D', '3', 4, 0, 0, 0, 0, 0, 0 };
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 32,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    var pcm_frames: [8]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (4..pcm_frames.len) |frame_index| {
        for (0..1152) |sample| {
            const position: f32 = @floatFromInt(frame_index * 1152 + sample);
            pcm_frames[frame_index].channels[0][sample] =
                0.48 * @sin(position * 0.131) +
                0.26 * @cos(position * 0.337);
        }
    }
    const required = try requiredPcmAdaptiveReservoirStorage(config, 511);
    const finish_required =
        try requiredPcmAdaptiveReservoirGaplessFileFinishStorage(
            config,
            511,
        );
    try std.testing.expectEqual(
        required + maximum_encoded_frame_bytes,
        finish_required,
    );
    var pending: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var staging: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var rollback: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var frame_scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    var main_scratch: [maximum_encoded_main_data_bytes]u8 = undefined;
    var output: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var finish_storage: [maximum_encoded_frame_bytes * 12]u8 = undefined;

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-gapless-cbr.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, &prefix, 0);
    var faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 7,
    };
    var encoder =
        try PcmAdaptiveReservoirGaplessFileEncoder.initAtWithOperations(
            std.testing.io,
            file,
            config,
            511,
            &pending,
            &staging,
            &rollback,
            &frame_scratch,
            &main_scratch,
            output[0..finish_required],
            finish_storage[0..finish_required],
            prefix.len,
            faults.operations(),
        );
    try std.testing.expectError(
        error.InvalidMp3AdaptiveReservoirGaplessFileEncoderState,
        encoder.append(pcm_frames[0]),
    );
    const identifier: [9]u8 = "File CBR ".*;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        encoder.startMetadataWithEncoder(identifier),
    );
    try std.testing.expect(encoder.failed);
    try std.testing.expect(encoder.valid());
    try encoder.recover();
    try std.testing.expectEqual(
        @as(u64, prefix.len),
        try file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    const placeholder = try encoder.startMetadataWithEncoder(identifier);
    try std.testing.expect(placeholder.len != 0);
    for (pcm_frames) |pcm| _ = try encoder.append(pcm);
    const committed_before = encoder.committed_bytes;
    faults.fail_write_call = faults.write_calls + 2;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        encoder.finalize(),
    );
    try std.testing.expect(encoder.failed);
    try std.testing.expect(encoder.valid());
    try encoder.recover();
    try std.testing.expectEqual(
        @as(u64, prefix.len) + committed_before,
        try file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    faults.fail_sync_call = 1;
    try std.testing.expectError(
        error.InjectedMp3FileSyncFailure,
        encoder.finalize(),
    );
    try std.testing.expect(encoder.failed);
    try std.testing.expect(encoder.valid());
    try encoder.recover();
    try std.testing.expectEqual(
        @as(u64, prefix.len) + committed_before,
        try file.length(std.testing.io),
    );
    faults.fail_sync_call = null;
    const summary = try encoder.finalize();
    try std.testing.expect(encoder.valid());
    try std.testing.expectEqual(
        @as(u64, prefix.len) + summary.stream.byte_count,
        summary.file_end,
    );

    const maximum_frames = pcm_frames.len + 3;
    var batch_destination: [maximum_encoded_frame_bytes * maximum_frames]u8 =
        undefined;
    var batch_frames: [maximum_encoded_frame_bytes * maximum_frames]u8 =
        undefined;
    var batch_pack: [maximum_encoded_frame_bytes * maximum_frames]u8 =
        undefined;
    var batch_main: [maximum_encoded_main_data_bytes * maximum_frames]u8 =
        undefined;
    var batch_metadata: [maximum_encoded_frame_bytes]u8 = undefined;
    const batch = try encodePcmReservoirGaplessBatch(
        config,
        &pcm_frames,
        511,
        identifier,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
        &batch_metadata,
    );
    var stored: [maximum_encoded_frame_bytes * maximum_frames]u8 = undefined;
    try file_reader_io.readExactAt(
        std.testing.io,
        file,
        prefix.len,
        stored[0..batch.stream.len],
        error.TestTruncatedAdaptiveGaplessCbrMp3,
    );
    try std.testing.expectEqualSlices(
        u8,
        batch.stream,
        stored[0..batch.stream.len],
    );

    const vbr_config = VbrEncoderConfig{
        .template = config,
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 5,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    const vbr_required =
        try requiredVbrPcmAdaptiveReservoirStorage(vbr_config, 511);
    const vbr_finish_required =
        try requiredVbrPcmAdaptiveReservoirGaplessFileFinishStorage(
            vbr_config,
            511,
        );
    try std.testing.expectEqual(
        vbr_required + maximum_encoded_frame_bytes,
        vbr_finish_required,
    );
    const required_frame_offsets =
        try requiredVbrPcmAdaptiveReservoirGaplessFrameOffsets(
            vbr_config,
            pcm_frames.len,
        );
    try std.testing.expectEqual(
        pcm_frames.len + 2,
        required_frame_offsets,
    );
    var vbr_file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-gapless-vbr.mp3",
        .{ .read = true },
    );
    defer vbr_file.close(std.testing.io);
    try vbr_file.writePositionalAll(std.testing.io, &prefix, 0);
    var frame_offsets: [maximum_frames]u64 = undefined;
    faults = .{};
    try std.testing.expectError(
        error.Mp3VbrFrameIndexStorageTooSmall,
        VbrPcmAdaptiveReservoirGaplessFileEncoder.initAtWithOperations(
            std.testing.io,
            vbr_file,
            vbr_config,
            511,
            &pending,
            &staging,
            &rollback,
            &frame_scratch,
            &main_scratch,
            output[0..vbr_finish_required],
            finish_storage[0..vbr_finish_required],
            frame_offsets[0..0],
            prefix.len,
            faults.operations(),
        ),
    );
    var initial_frame_offsets: [1]u64 = undefined;
    var vbr_encoder =
        try VbrPcmAdaptiveReservoirGaplessFileEncoder.initAtWithOperations(
            std.testing.io,
            vbr_file,
            vbr_config,
            511,
            &pending,
            &staging,
            &rollback,
            &frame_scratch,
            &main_scratch,
            output[0..vbr_finish_required],
            finish_storage[0..vbr_finish_required],
            &initial_frame_offsets,
            prefix.len,
            faults.operations(),
        );
    _ = try vbr_encoder.startMetadataWithEncoder(identifier);
    var retry_index: ?usize = null;
    for (pcm_frames, 0..) |pcm, index| {
        _ = vbr_encoder.append(pcm) catch |failure| {
            try std.testing.expectEqual(
                error.Mp3VbrFrameIndexStorageTooSmall,
                failure,
            );
            retry_index = index;
            break;
        };
    }
    const capacity_retry = retry_index orelse
        return error.TestAdaptiveGaplessVbrCapacityFailureMissing;
    try std.testing.expect(vbr_encoder.valid());
    try std.testing.expectEqual(
        @as(u64, prefix.len) + vbr_encoder.committed_bytes,
        try vbr_file.length(std.testing.io),
    );
    try std.testing.expectError(
        error.Mp3VbrFrameIndexStorageTooSmall,
        vbr_encoder.replaceFrameOffsetStorage(frame_offsets[0..0]),
    );
    try vbr_encoder.replaceFrameOffsetStorage(
        frame_offsets[0..required_frame_offsets],
    );
    for (pcm_frames[capacity_retry..]) |pcm|
        _ = try vbr_encoder.append(pcm);
    const vbr_committed_before = vbr_encoder.committed_bytes;
    faults.fail_write_call = faults.write_calls + 2;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        vbr_encoder.finalize(73),
    );
    try std.testing.expect(vbr_encoder.failed);
    try std.testing.expect(vbr_encoder.valid());
    try vbr_encoder.recover();
    try std.testing.expectEqual(
        @as(u64, prefix.len) + vbr_committed_before,
        try vbr_file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    faults.fail_sync_call = 1;
    try std.testing.expectError(
        error.InjectedMp3FileSyncFailure,
        vbr_encoder.finalize(73),
    );
    try std.testing.expect(vbr_encoder.failed);
    try std.testing.expect(vbr_encoder.valid());
    try vbr_encoder.recover();
    try std.testing.expectEqual(
        @as(u64, prefix.len) + vbr_committed_before,
        try vbr_file.length(std.testing.io),
    );
    faults.fail_sync_call = null;
    const vbr_summary = try vbr_encoder.finalize(73);
    try std.testing.expect(vbr_encoder.valid());
    try std.testing.expectEqual(
        @as(u64, prefix.len) + vbr_summary.stream.byte_count,
        vbr_summary.file_end,
    );
    const vbr_batch = try encodeVbrPcmReservoirGaplessBatch(
        vbr_config,
        &pcm_frames,
        511,
        73,
        identifier,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
        &batch_metadata,
    );
    try file_reader_io.readExactAt(
        std.testing.io,
        vbr_file,
        prefix.len,
        stored[0..vbr_batch.stream.len],
        error.TestTruncatedAdaptiveGaplessVbrMp3,
    );
    try std.testing.expectEqualSlices(
        u8,
        vbr_batch.stream,
        stored[0..vbr_batch.stream.len],
    );
    var hostile_vbr = vbr_encoder;
    hostile_vbr.indexed_frames -= 1;
    try std.testing.expect(!hostile_vbr.valid());
    var hostile_offsets = frame_offsets;
    hostile_vbr = vbr_encoder;
    hostile_vbr.frame_offsets = &hostile_offsets;
    hostile_offsets[1] = 0;
    try std.testing.expect(!hostile_vbr.valid());
    hostile_offsets = frame_offsets;
    hostile_offsets[1] += 1;
    try std.testing.expect(!hostile_vbr.valid());
}

test "writes adaptive MP3 reservoir batches atomically at file offsets" {
    const prefix = [_]u8{
        'I', 'D', '3', 4, 0, 0, 0, 0, 0, 0,
    };
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 32,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    var pcm_frames: [9]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (5..pcm_frames.len) |frame_index| {
        for (0..1152) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * 1152 + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.47 * @sin(position * 0.119) +
                0.29 * @cos(position * 0.307);
        }
    }
    var destination: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var frame_scratch: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var pack_scratch: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var main_data_scratch: [maximum_encoded_main_data_bytes * pcm_frames.len]u8 = undefined;

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-reservoir.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, &prefix, 0);
    var faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 7,
    };
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        writePcmReservoirBatchFileWithOperations(
            std.testing.io,
            file,
            config,
            &pcm_frames,
            511,
            prefix.len,
            &destination,
            &frame_scratch,
            &pack_scratch,
            &main_data_scratch,
            faults.operations(),
        ),
    );
    try std.testing.expectEqual(
        @as(u64, prefix.len),
        try file.length(std.testing.io),
    );
    var retained_prefix: [prefix.len]u8 = undefined;
    try file_reader_io.readExactAt(
        std.testing.io,
        file,
        0,
        &retained_prefix,
        error.TestTruncatedAdaptiveMp3Prefix,
    );
    try std.testing.expectEqualSlices(u8, &prefix, &retained_prefix);

    faults.fail_write_call = null;
    const written = try writePcmReservoirBatchFileWithOperations(
        std.testing.io,
        file,
        config,
        &pcm_frames,
        511,
        prefix.len,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_data_scratch,
        faults.operations(),
    );
    try std.testing.expectEqual(
        @as(u64, prefix.len) + written.batch.stream.len,
        written.file_end,
    );
    try std.testing.expectEqual(
        written.file_end,
        try file.length(std.testing.io),
    );
    var stored: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    try file_reader_io.readExactAt(
        std.testing.io,
        file,
        prefix.len,
        stored[0..written.batch.stream.len],
        error.TestTruncatedAdaptiveMp3Batch,
    );
    try std.testing.expectEqualSlices(
        u8,
        written.batch.stream,
        stored[0..written.batch.stream.len],
    );
    var frame_storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const summary = try FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(written.batch.frame_count, summary.frame_count);
    try std.testing.expectEqual(@as(u64, prefix.len), summary.audio_offset);

    var vbr_file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-vbr-reservoir.mp3",
        .{ .read = true },
    );
    defer vbr_file.close(std.testing.io);
    const vbr_written = try writeVbrPcmReservoirBatchFile(
        std.testing.io,
        vbr_file,
        .{
            .template = .{
                .version = .mpeg1,
                .sample_rate = 44_100,
                .channel_mode = .mono,
                .crc_present = true,
            },
            .minimum_bitrate_index = 1,
            .maximum_bitrate_index = 5,
            .maximum_noise_to_mask_ratio = 0.5,
        },
        &pcm_frames,
        511,
        0,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_data_scratch,
    );
    try std.testing.expectEqual(
        vbr_written.batch.frame_count,
        (try FileReader.summarize(
            std.testing.io,
            vbr_file,
            &frame_storage,
        )).frame_count,
    );
    try std.testing.expectEqual(
        vbr_written.file_end,
        try vbr_file.length(std.testing.io),
    );

    var metadata_scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    var info_file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-info-reservoir.mp3",
        .{ .read = true },
    );
    defer info_file.close(std.testing.io);
    try info_file.writePositionalAll(std.testing.io, &prefix, 0);
    try info_file.writePositionalAll(
        std.testing.io,
        "stale audio",
        prefix.len,
    );
    var metadata_faults = Mp3FileFaults{
        .fail_write_call = 2,
        .partial_write_bytes = 9,
    };
    const info_encoder: [9]u8 = "BatchCBR1".*;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        writePcmReservoirBatchFileWithInfoAndOperations(
            std.testing.io,
            info_file,
            config,
            &pcm_frames,
            511,
            prefix.len,
            info_encoder,
            &destination,
            &frame_scratch,
            &pack_scratch,
            &main_data_scratch,
            &metadata_scratch,
            metadata_faults.operations(),
        ),
    );
    try std.testing.expectEqual(
        @as(u64, prefix.len),
        try info_file.length(std.testing.io),
    );
    metadata_faults.fail_write_call = null;
    const info_written =
        try writePcmReservoirBatchFileWithInfoAndOperations(
            std.testing.io,
            info_file,
            config,
            &pcm_frames,
            511,
            prefix.len,
            info_encoder,
            &destination,
            &frame_scratch,
            &pack_scratch,
            &main_data_scratch,
            &metadata_scratch,
            metadata_faults.operations(),
        );
    const info_summary = try FileReader.summarize(
        std.testing.io,
        info_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        info_written.batch.frame_count + 1,
        info_summary.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(info_summary.frame_count)),
        info_summary.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(
            info_written.file_end - prefix.len,
        )),
        info_summary.first_xing.?.stream_bytes,
    );
    try std.testing.expectEqual(
        info_encoder,
        info_summary.first_xing.?.encoder.?,
    );
    try std.testing.expect(info_summary.first_xing.?.encoder_delay == null);
    try std.testing.expect(info_summary.first_xing.?.encoder_padding == null);

    var xing_file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-xing-reservoir.mp3",
        .{ .read = true },
    );
    defer xing_file.close(std.testing.io);
    const xing_encoder: [9]u8 = "BatchVBR1".*;
    const xing_written = try writeVbrPcmReservoirBatchFileWithXing(
        std.testing.io,
        xing_file,
        .{
            .template = .{
                .version = .mpeg1,
                .sample_rate = 44_100,
                .channel_mode = .mono,
                .crc_present = true,
            },
            .minimum_bitrate_index = 1,
            .maximum_bitrate_index = 5,
            .maximum_noise_to_mask_ratio = 0.5,
        },
        &pcm_frames,
        511,
        0,
        73,
        xing_encoder,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_data_scratch,
        &metadata_scratch,
    );
    const xing_summary = try FileReader.summarize(
        std.testing.io,
        xing_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        xing_written.batch.frame_count + 1,
        xing_summary.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, 73),
        xing_summary.first_xing.?.quality,
    );
    try std.testing.expect(xing_summary.first_xing.?.toc != null);
    try std.testing.expectEqual(
        xing_encoder,
        xing_summary.first_xing.?.encoder.?,
    );
    try std.testing.expect(xing_summary.first_xing.?.encoder_delay == null);
    try std.testing.expect(xing_summary.first_xing.?.encoder_padding == null);
}

test "bounds cumulative MP3 reservoir borrowing by version" {
    try std.testing.expect(reservoirBorrowedBytesValid(
        .mpeg1,
        2,
        511,
    ));
    try std.testing.expect(!reservoirBorrowedBytesValid(
        .mpeg1,
        2,
        512,
    ));
    try std.testing.expect(reservoirBorrowedBytesValid(
        .mpeg2,
        2,
        255,
    ));
    try std.testing.expect(!reservoirBorrowedBytesValid(
        .mpeg25,
        2,
        256,
    ));
    try std.testing.expect(reservoirBorrowedBytesValid(
        .mpeg1,
        0,
        0,
    ));
    try std.testing.expect(!reservoirBorrowedBytesValid(
        .mpeg1,
        0,
        1,
    ));
    try std.testing.expect(reservoirBorrowedBytesValid(
        .mpeg1,
        std.math.maxInt(u64),
        std.math.maxInt(u64),
    ));
    try std.testing.expect(reservoirPendingBorrowedBytesValid(
        .mpeg1,
        2,
        511,
        511,
    ));
    try std.testing.expect(!reservoirPendingBorrowedBytesValid(
        .mpeg1,
        2,
        510,
        511,
    ));
    try std.testing.expect(reservoirPendingBorrowedBytesValid(
        .mpeg1,
        3,
        700,
        200,
    ));
    try std.testing.expect(!reservoirPendingBorrowedBytesValid(
        .mpeg1,
        3,
        712,
        200,
    ));
}

test "composes VBR selection with MP3 main-data reuse" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .minimum_bitrate_index = 8,
        .maximum_bitrate_index = 11,
    };
    const bitrate_indexes = [_]u4{ 8, 11, 9 };
    var pcm_frames: [3]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (0..1152) |sample| {
        const position: f32 = @floatFromInt(sample);
        pcm_frames[1].channels[0][sample] =
            0.4 * @sin(position * 0.17) +
            0.2 * @sin(position * 0.41);
        pcm_frames[2].channels[0][sample] =
            0.3 * @sin(position * 0.09);
    }

    var ordinary = try VbrPcmEncoder.init(config);
    var ordinary_bytes: [maximum_encoded_frame_bytes * pcm_frames.len]u8 = undefined;
    var ordinary_length: usize = 0;
    for (pcm_frames, bitrate_indexes) |pcm, index| {
        const selected = try ordinary.encodeAtBitrateIndex(
            pcm,
            ordinary_bytes[ordinary_length..],
            index,
        );
        try std.testing.expectEqual(index, selected.bitrate_index);
        ordinary_length += selected.frame.len;
    }

    var reservoir = try VbrPcmReservoirEncoder.init(config);
    try std.testing.expect(reservoir.valid());
    var reservoir_bytes: [maximum_encoded_frame_bytes * pcm_frames.len]u8 = undefined;
    var reservoir_length: usize = 0;
    var total_borrowed: u64 = 0;
    for (pcm_frames, bitrate_indexes, 0..) |pcm, index, frame_index| {
        const appended = try reservoir.appendAtBitrateIndex(
            pcm,
            reservoir_bytes[reservoir_length..],
            index,
        );
        try std.testing.expect(reservoir.valid());
        try std.testing.expectEqual(
            index,
            appended.selection.bitrate_index,
        );
        try std.testing.expectEqual(
            bitrate(.mpeg1, index),
            appended.selection.header.bitrate_kbps,
        );
        if (frame_index == 0) {
            try std.testing.expect(appended.frame == null);
            const before = reservoir;
            try std.testing.expectError(
                error.InsufficientMp3EncoderStorage,
                reservoir.appendAtBitrateIndex(
                    pcm_frames[1],
                    reservoir_bytes[0..0],
                    bitrate_indexes[1],
                ),
            );
            try std.testing.expectEqual(
                before.encoder,
                reservoir.encoder,
            );
            try std.testing.expectEqual(
                before.frames_received,
                reservoir.frames_received,
            );
            try std.testing.expectEqual(
                before.frames_emitted,
                reservoir.frames_emitted,
            );
            try std.testing.expectEqualSlices(
                u8,
                before.pending[0..before.pending_length],
                reservoir.pending[0..reservoir.pending_length],
            );
        } else {
            const frame = appended.frame orelse
                return error.TestMp3ReservoirFrameMissing;
            reservoir_length += frame.len;
            total_borrowed += appended.borrowed_bytes;
            if (appended.borrowed_bytes != 0) {
                var mismatched_borrow = reservoir;
                mismatched_borrow.borrowed_bytes -=
                    appended.borrowed_bytes;
                try std.testing.expect(!mismatched_borrow.valid());
            }
        }
    }
    const final_frame = (try reservoir.finish(
        reservoir_bytes[reservoir_length..],
    )) orelse return error.TestMp3ReservoirFrameMissing;
    try std.testing.expect(reservoir.valid());
    reservoir_length += final_frame.len;
    try std.testing.expectEqual(
        ordinary_length,
        reservoir_length,
    );
    try std.testing.expect(total_borrowed > 0);
    try std.testing.expectEqual(
        total_borrowed,
        reservoir.borrowed_bytes,
    );
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        reservoir.frames_received,
    );
    try std.testing.expectEqual(
        reservoir.frames_received,
        reservoir.frames_emitted,
    );

    var ordinary_stream = try Stream.init(
        ordinary_bytes[0..ordinary_length],
    );
    var reservoir_stream = try Stream.init(
        reservoir_bytes[0..reservoir_length],
    );
    var ordinary_decoder = FrameDecoder{};
    var reservoir_decoder = FrameDecoder{};
    var borrowed_frame_seen = false;
    while (try ordinary_stream.next()) |ordinary_frame| {
        const reservoir_frame =
            (try reservoir_stream.next()) orelse
            return error.TestMp3ReservoirFrameMissing;
        try std.testing.expectEqual(
            ordinary_frame.header.bitrate_kbps,
            reservoir_frame.header.bitrate_kbps,
        );
        const side = try reservoir_frame.sideInformation();
        borrowed_frame_seen =
            borrowed_frame_seen or side.main_data_begin != 0;
        try std.testing.expectEqual(
            @as(?bool, true),
            try reservoir_frame.crcValid(),
        );
        const ordinary_pcm =
            try ordinary_decoder.decode(ordinary_frame);
        const reservoir_pcm =
            try reservoir_decoder.decode(reservoir_frame);
        for (
            ordinary_pcm.channels[0][0..ordinary_pcm.sample_count],
            reservoir_pcm.channels[0][0..reservoir_pcm.sample_count],
        ) |expected, actual|
            try std.testing.expectEqual(expected, actual);
    }
    try std.testing.expect(
        (try reservoir_stream.next()) == null,
    );
    try std.testing.expect(borrowed_frame_seen);
    try std.testing.expect(
        (try reservoir.finish(
            reservoir_bytes[reservoir_length..],
        )) == null,
    );
    try std.testing.expectError(
        error.Mp3VbrReservoirEncoderFinalized,
        reservoir.append(
            pcm_frames[0],
            reservoir_bytes[reservoir_length..],
        ),
    );

    var malformed = try VbrPcmReservoirEncoder.init(config);
    _ = try malformed.appendAtBitrateIndex(
        pcm_frames[0],
        reservoir_bytes[0..0],
        bitrate_indexes[0],
    );
    malformed.pending[4] ^= 1;
    try std.testing.expect(!malformed.valid());
    const malformed_before = malformed;
    try std.testing.expectError(
        error.InvalidMp3VbrReservoirEncoderState,
        malformed.finish(&reservoir_bytes),
    );
    try std.testing.expectEqual(malformed_before, malformed);
    var impossible_borrow = try VbrPcmReservoirEncoder.init(config);
    impossible_borrow.borrowed_bytes = 1;
    try std.testing.expect(!impossible_borrow.valid());
    const impossible_borrow_before = impossible_borrow;
    try std.testing.expectError(
        error.InvalidMp3VbrReservoirEncoderState,
        impossible_borrow.finish(&reservoir_bytes),
    );
    try std.testing.expectEqual(
        impossible_borrow_before,
        impossible_borrow,
    );
}

test "finishes reservoir-backed MP3 VBR streams with Xing metadata" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .minimum_bitrate_index = 8,
        .maximum_bitrate_index = 11,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    var offsets: [8]u64 = undefined;
    var encoder = try VbrPcmReservoirStreamEncoder.init(
        config,
        &offsets,
    );
    var encoded: [maximum_encoded_frame_bytes * 6]u8 =
        undefined;
    var cursor: usize = 0;
    const metadata_encoder: [9]u8 = "Reservr 1".*;
    const placeholder = try encoder.startXingMetadataWithEncoder(
        metadata_encoder,
        encoded[cursor..],
    );
    cursor += placeholder.len;
    const silence = PcmFrame{
        .channel_count = 1,
        .sample_count = 1152,
    };
    const primed = try encoder.append(
        silence,
        encoded[cursor..],
    );
    try std.testing.expect(primed.frame == null);
    var detailed = silence;
    for (&detailed.channels[0], 0..) |*sample, index| {
        const position: f32 = @floatFromInt(index);
        sample.* =
            0.25 * @sin(position * 0.11) +
            0.2 * @sin(position * 0.37);
    }
    const emitted = try encoder.append(
        detailed,
        encoded[cursor..],
    );
    const previous = emitted.frame orelse
        return error.TestMp3ReservoirFrameMissing;
    cursor += previous.len;
    try std.testing.expect(emitted.borrowed_bytes > 0);

    var mismatched_borrow = encoder;
    mismatched_borrow.borrowed_bytes -= emitted.borrowed_bytes;
    try std.testing.expect(!mismatched_borrow.valid());
    const mismatched_before = mismatched_borrow;
    try std.testing.expectError(
        error.InvalidMp3VbrReservoirStreamState,
        mismatched_borrow.finish(encoded[cursor..]),
    );
    try std.testing.expectEqual(
        mismatched_before,
        mismatched_borrow,
    );

    const before_finish = encoder;
    var short: [1]u8 = .{0x5a};
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encoder.finish(&short),
    );
    try std.testing.expectEqual(@as(u8, 0x5a), short[0]);
    try std.testing.expectEqual(
        before_finish.encoder.encoder,
        encoder.encoder.encoder,
    );
    try std.testing.expectEqual(
        before_finish.frames_emitted,
        encoder.frames_emitted,
    );
    try std.testing.expectEqualSlices(
        u8,
        before_finish.pending[0..before_finish.pending_length],
        encoder.pending[0..encoder.pending_length],
    );

    const finished = try encoder.finish(encoded[cursor..]);
    cursor += finished.frames.len;
    try std.testing.expectEqual(@as(u64, 4), finished.summary.frame_count);
    try std.testing.expectEqual(
        @as(u64, 2304),
        finished.summary.input_samples,
    );
    try std.testing.expectEqual(
        @as(u16, 2209),
        finished.summary.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(u16, 95),
        finished.summary.end_padding,
    );
    try std.testing.expectEqual(
        @as(u64, cursor),
        finished.summary.byte_count,
    );
    try std.testing.expect(finished.borrowed_bytes > 0);
    try std.testing.expectEqual(
        finished.summary.frame_count,
        encoder.frames_emitted,
    );

    var final_metadata: [maximum_encoded_frame_bytes]u8 =
        undefined;
    const replacement = try encoder.xingMetadataFrame(
        23,
        &final_metadata,
    );
    try std.testing.expectEqual(placeholder.len, replacement.len);
    @memcpy(encoded[0..replacement.len], replacement);
    const summary = try Stream.summarize(encoded[0..cursor]);
    try std.testing.expectEqual(
        metadata_encoder,
        summary.first_xing.?.encoder.?,
    );
    try std.testing.expectEqual(
        @as(?u32, 4),
        summary.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(cursor)),
        summary.first_xing.?.stream_bytes,
    );
    try std.testing.expectEqual(
        @as(?u32, 23),
        summary.first_xing.?.quality,
    );

    var stream = try Stream.init(encoded[0..cursor]);
    var decoder = FrameDecoder{};
    var frame_count: u64 = 0;
    var borrowed_seen = false;
    while (try stream.next()) |frame| {
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
        borrowed_seen = borrowed_seen or
            (try frame.sideInformation()).main_data_begin != 0;
        const pcm = try decoder.decode(frame);
        for (pcm.channels[0]) |sample|
            try std.testing.expect(std.math.isFinite(sample));
        frame_count += 1;
    }
    try std.testing.expectEqual(@as(u64, 4), frame_count);
    try std.testing.expect(borrowed_seen);

    const repeated = try encoder.finish(encoded[cursor..]);
    try std.testing.expectEqual(
        @as(usize, 0),
        repeated.frames.len,
    );
    try std.testing.expectEqual(
        finished.borrowed_bytes,
        repeated.borrowed_bytes,
    );

    var corrupted_offsets: [4]u64 = undefined;
    var corrupted = try VbrPcmReservoirStreamEncoder.init(
        config,
        &corrupted_offsets,
    );
    _ = try corrupted.append(silence, encoded[0..0]);
    corrupted.pending[4] ^= 1;
    try std.testing.expectError(
        error.InvalidMp3VbrReservoirStreamState,
        corrupted.finish(&encoded),
    );

    var impossible_offsets: [4]u64 = undefined;
    var impossible_borrow = try VbrPcmReservoirStreamEncoder.init(
        config,
        &impossible_offsets,
    );
    impossible_borrow.borrowed_bytes = 1;
    try std.testing.expect(!impossible_borrow.valid());
    const impossible_borrow_before = impossible_borrow;
    try std.testing.expectError(
        error.InvalidMp3VbrReservoirStreamState,
        impossible_borrow.finish(&encoded),
    );
    try std.testing.expectEqual(
        impossible_borrow_before.encoder,
        impossible_borrow.encoder,
    );
    try std.testing.expectEqual(
        impossible_borrow_before.borrowed_bytes,
        impossible_borrow.borrowed_bytes,
    );

    var unprotected_config = config;
    unprotected_config.template.crc_present = false;
    var malformed_offsets: [4]u64 = undefined;
    var malformed = try VbrPcmReservoirStreamEncoder.init(
        unprotected_config,
        &malformed_offsets,
    );
    _ = try malformed.append(silence, encoded[0..0]);
    malformed.pending[3] ^= 0xc0;
    try std.testing.expectError(
        error.InvalidMp3VbrReservoirStreamState,
        malformed.finish(&encoded),
    );
}

test "finishes MP3 reservoir streams transactionally" {
    const configs = [_]EncoderConfig{
        .{
            .version = .mpeg1,
            .bitrate_kbps = 128,
            .sample_rate = 44_100,
            .channel_mode = .mono,
        },
        .{
            .version = .mpeg2,
            .bitrate_kbps = 64,
            .sample_rate = 22_050,
            .channel_mode = .mono,
        },
    };
    for (configs) |config| {
        const samples_per_frame =
            (try config.header(false)).samplesPerFrame();
        var pcm = PcmFrame{
            .channel_count = 1,
            .sample_count = samples_per_frame,
        };
        for (0..samples_per_frame) |sample| {
            pcm.channels[0][sample] =
                0.5 * @sin(
                    2.0 * std.math.pi *
                        @as(f32, @floatFromInt(sample)) /
                        41.0,
                );
        }
        var encoder =
            try PcmReservoirStreamEncoder.init(config);
        var encoded: [maximum_encoded_frame_bytes * 6]u8 =
            undefined;
        var encoded_bytes: usize = 0;
        const first = try encoder.append(
            .{
                .channel_count = 1,
                .sample_count = samples_per_frame,
            },
            encoded[0..0],
        );
        try std.testing.expect(first.frame == null);
        const second = try encoder.append(
            pcm,
            encoded[encoded_bytes..],
        );
        const emitted = second.frame orelse
            return error.TestMp3ReservoirFrameMissing;
        encoded_bytes += emitted.len;
        try std.testing.expect(second.borrowed_bytes > 0);
        try std.testing.expectError(
            error.Mp3EncoderStreamIncomplete,
            encoder.summary(),
        );

        var short: [1]u8 = .{0x5a};
        const before_finish = encoder;
        try std.testing.expectError(
            error.InsufficientMp3EncoderStorage,
            encoder.finish(&short),
        );
        try std.testing.expectEqual(
            before_finish.frame_count,
            encoder.frame_count,
        );
        try std.testing.expectEqual(
            before_finish.encoder.pending_length,
            encoder.encoder.pending_length,
        );
        try std.testing.expectEqual(@as(u8, 0x5a), short[0]);

        const finished = try encoder.finish(
            encoded[encoded_bytes..],
        );
        encoded_bytes += finished.frames.len;
        try std.testing.expect(
            finished.borrowed_bytes > 0,
        );
        try std.testing.expectEqual(
            @as(u64, samples_per_frame) * 2,
            finished.summary.input_samples,
        );
        try std.testing.expectEqual(
            @as(u16, encoder_analysis_delay),
            finished.summary.encoder_delay,
        );
        try std.testing.expectEqual(
            @as(u16, 95),
            finished.summary.end_padding,
        );
        try std.testing.expectEqual(
            @as(u64, encoded_bytes),
            finished.summary.byte_count,
        );
        const parsed = try Stream.summarize(
            encoded[0..encoded_bytes],
        );
        try std.testing.expectEqual(
            finished.summary.frame_count,
            parsed.frame_count,
        );
        try std.testing.expectEqual(
            finished.summary.encoded_samples,
            parsed.sample_count,
        );
        const repeated = try encoder.finish(
            encoded[encoded_bytes..],
        );
        try std.testing.expectEqual(
            @as(usize, 0),
            repeated.frames.len,
        );
        try std.testing.expectEqual(
            finished.summary,
            repeated.summary,
        );
    }
}

test "writes and recovers MP3 VBR files" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .maximum_noise_to_mask_ratio = 0.25,
    };
    const silence = PcmFrame{
        .channel_count = 1,
        .sample_count = 1152,
    };
    var signal = silence;
    for (&signal.channels[0], 0..) |*sample, index| {
        const position: f32 = @floatFromInt(index);
        sample.* =
            0.19 * @sin(position * 0.047) +
            0.13 * @sin(position * 0.233);
        if (index % 43 == 0)
            sample.* -= 0.28;
    }

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "vbr.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var storage: [maximum_encoded_frame_bytes * 2]u8 =
        undefined;
    var offsets: [8]u64 = @splat(0xdead);
    var writer = try VbrPcmFileEncoder.init(
        std.testing.io,
        file,
        config,
        &storage,
        &offsets,
    );
    const metadata_encoder: [9]u8 = "VBRFile 1".*;
    try writer.startXingMetadataWithEncoder(
        61,
        metadata_encoder,
    );
    const quiet = try writer.append(silence);
    const detailed = try writer.append(signal);
    try std.testing.expect(
        detailed.bitrate_index > quiet.bitrate_index,
    );
    const summary = try writer.finalize();
    try std.testing.expectEqual(
        summary.stream.byte_count,
        try file.length(std.testing.io),
    );
    var frame_storage: [maximum_encoded_frame_bytes]u8 =
        undefined;
    const parsed = try FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        XingKind.variable,
        parsed.first_xing.?.kind,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(summary.stream.frame_count)),
        parsed.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, 61),
        parsed.first_xing.?.quality,
    );
    try std.testing.expect(
        parsed.first_xing.?.toc != null,
    );
    try std.testing.expectEqual(
        metadata_encoder,
        parsed.first_xing.?.encoder.?,
    );
    try std.testing.expectEqual(
        summary,
        try writer.finalize(),
    );

    var recovered_file = try temporary.dir.createFile(
        std.testing.io,
        "vbr-recovered.mp3",
        .{ .read = true },
    );
    defer recovered_file.close(std.testing.io);
    var recovered_offsets: [8]u64 = @splat(0xbeef);
    var faults = Mp3FileFaults{};
    var recovered = try VbrPcmFileEncoder.initWithOperations(
        std.testing.io,
        recovered_file,
        config,
        &storage,
        &recovered_offsets,
        faults.operations(),
    );
    const recovered_encoder: [9]u8 = "VBRRecov1".*;
    try recovered.startXingMetadataWithEncoder(
        29,
        recovered_encoder,
    );
    _ = try recovered.append(silence);
    _ = try recovered.append(signal);
    const committed = recovered.committed_bytes;
    const flush_index =
        recovered.stream.encoder.frames.frames_encoded;
    const retained_offset = recovered_offsets[flush_index];
    faults.fail_write_call = faults.write_calls + 2;
    faults.partial_write_bytes = 8;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        recovered.finalize(),
    );
    try std.testing.expect(recovered.failed);
    try std.testing.expectEqual(
        retained_offset,
        recovered_offsets[flush_index],
    );
    faults.fail_write_call = null;
    try recovered.recover();
    try std.testing.expectEqual(
        committed,
        try recovered_file.length(std.testing.io),
    );
    const provisional = try FileReader.summarize(
        std.testing.io,
        recovered_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, 0),
        provisional.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        recovered_encoder,
        provisional.first_xing.?.encoder.?,
    );
    const recovered_summary = try recovered.finalize();
    const final = try FileReader.summarize(
        std.testing.io,
        recovered_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(
            recovered_summary.stream.frame_count,
        )),
        final.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        recovered_encoder,
        final.first_xing.?.encoder.?,
    );
    try std.testing.expectEqual(
        recovered_summary.stream.byte_count,
        try recovered_file.length(std.testing.io),
    );
}

test "writes and recovers reservoir-backed MP3 VBR files" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .minimum_bitrate_index = 8,
        .maximum_bitrate_index = 11,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    const silence = PcmFrame{
        .channel_count = 1,
        .sample_count = 1152,
    };
    var signal = silence;
    for (&signal.channels[0], 0..) |*sample, index| {
        const position: f32 = @floatFromInt(index);
        sample.* =
            0.23 * @sin(position * 0.071) +
            0.17 * @sin(position * 0.293);
    }

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "vbr-reservoir.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var storage: [maximum_encoded_frame_bytes * 3]u8 =
        undefined;
    var offsets: [8]u64 = @splat(0xdead);
    var writer = try VbrPcmReservoirFileEncoder.init(
        std.testing.io,
        file,
        config,
        &storage,
        &offsets,
    );
    const metadata_encoder: [9]u8 = "VBRResv 1".*;
    try writer.startXingMetadataWithEncoder(
        37,
        metadata_encoder,
    );
    const metadata_bytes = writer.committed_bytes;
    const primed = try writer.append(silence);
    try std.testing.expect(primed.frame == null);
    try std.testing.expectEqual(
        metadata_bytes,
        try file.length(std.testing.io),
    );
    const emitted = try writer.append(signal);
    try std.testing.expect(emitted.frame != null);
    try std.testing.expect(emitted.borrowed_bytes > 0);
    try std.testing.expectEqual(
        writer.committed_bytes,
        try file.length(std.testing.io),
    );
    const summary = try writer.finalize();
    try std.testing.expect(summary.borrowed_bytes > 0);
    try std.testing.expectEqual(
        summary.stream.byte_count,
        try file.length(std.testing.io),
    );
    var frame_storage: [maximum_encoded_frame_bytes]u8 =
        undefined;
    const parsed = try FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(summary.stream.frame_count)),
        parsed.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, 37),
        parsed.first_xing.?.quality,
    );
    try std.testing.expectEqual(
        metadata_encoder,
        parsed.first_xing.?.encoder.?,
    );
    var reader = try FileReader.init(std.testing.io, file);
    var borrowed_seen = false;
    while (try reader.next(&frame_storage)) |frame| {
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
        borrowed_seen = borrowed_seen or
            (try frame.sideInformation()).main_data_begin != 0;
    }
    try std.testing.expect(borrowed_seen);
    try std.testing.expectEqual(
        summary,
        try writer.finalize(),
    );

    var recovered_file = try temporary.dir.createFile(
        std.testing.io,
        "vbr-reservoir-recovered.mp3",
        .{ .read = true },
    );
    defer recovered_file.close(std.testing.io);
    var recovered_offsets: [8]u64 = @splat(0xbeef);
    var faults = Mp3FileFaults{};
    var recovered =
        try VbrPcmReservoirFileEncoder.initWithOperations(
            std.testing.io,
            recovered_file,
            config,
            &storage,
            &recovered_offsets,
            faults.operations(),
        );
    const recovered_encoder: [9]u8 = "VRRecover".*;
    try recovered.startXingMetadataWithEncoder(
        19,
        recovered_encoder,
    );
    _ = try recovered.append(silence);
    const committed = recovered.committed_bytes;
    const failed_index =
        recovered.stream.encoder.encoder.frames.frames_encoded;
    const retained_offset = recovered_offsets[failed_index];
    faults.fail_write_call = faults.write_calls + 1;
    faults.partial_write_bytes = 7;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        recovered.append(signal),
    );
    try std.testing.expect(recovered.failed);
    try std.testing.expectEqual(
        retained_offset,
        recovered_offsets[failed_index],
    );
    try std.testing.expectEqual(
        committed + 7,
        try recovered_file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    try recovered.recover();
    try std.testing.expectEqual(
        committed,
        try recovered_file.length(std.testing.io),
    );
    const provisional = try FileReader.summarize(
        std.testing.io,
        recovered_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, 0),
        provisional.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        recovered_encoder,
        provisional.first_xing.?.encoder.?,
    );
    _ = try recovered.append(signal);
    const recovered_summary = try recovered.finalize();
    try std.testing.expectEqual(
        recovered_summary.stream.byte_count,
        try recovered_file.length(std.testing.io),
    );
}

test "writes and recovers MP3 reservoir files" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    };
    const samples_per_frame =
        (try config.header(false)).samplesPerFrame();
    const silence = PcmFrame{
        .channel_count = 1,
        .sample_count = samples_per_frame,
    };
    var signal = silence;
    for (0..samples_per_frame) |sample| {
        signal.channels[0][sample] =
            0.5 * @sin(
                2.0 * std.math.pi *
                    @as(f32, @floatFromInt(sample)) /
                    43.0,
            );
    }

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "reservoir.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var storage: [maximum_encoded_frame_bytes * 3]u8 =
        undefined;
    var writer = try PcmReservoirFileEncoder.init(
        std.testing.io,
        file,
        config,
        &storage,
    );
    try std.testing.expectEqual(
        @as(u16, 0),
        try writer.append(silence),
    );
    try std.testing.expectEqual(
        @as(u64, 0),
        try file.length(std.testing.io),
    );
    try std.testing.expect(try writer.append(signal) > 0);
    try std.testing.expectEqual(
        writer.committed_bytes,
        try file.length(std.testing.io),
    );
    const summary = try writer.finalize();
    try std.testing.expect(summary.borrowed_bytes > 0);
    try std.testing.expectEqual(
        summary.stream.byte_count,
        try file.length(std.testing.io),
    );
    var frame_storage: [maximum_encoded_frame_bytes]u8 =
        undefined;
    var reader = try FileReader.init(std.testing.io, file);
    var borrowed_frame_seen = false;
    while (try reader.next(&frame_storage)) |frame| {
        borrowed_frame_seen = borrowed_frame_seen or
            (try frame.sideInformation())
                .main_data_begin != 0;
    }
    try std.testing.expect(borrowed_frame_seen);
    try std.testing.expectEqual(
        summary,
        try writer.finalize(),
    );

    var metadata_file = try temporary.dir.createFile(
        std.testing.io,
        "reservoir-metadata.mp3",
        .{ .read = true },
    );
    defer metadata_file.close(std.testing.io);
    var metadata_writer = try PcmReservoirFileEncoder.init(
        std.testing.io,
        metadata_file,
        config,
        &storage,
    );
    const metadata_encoder: [9]u8 = "ResFile 1".*;
    try metadata_writer.startGaplessMetadataWithEncoder(
        metadata_encoder,
    );
    _ = try metadata_writer.append(silence);
    try std.testing.expect(
        try metadata_writer.append(signal) > 0,
    );
    const metadata_summary =
        try metadata_writer.finalize();
    const parsed_metadata = try FileReader.summarize(
        std.testing.io,
        metadata_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(
            metadata_summary.stream.frame_count,
        )),
        parsed_metadata.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u12, try storedXingEncoderDelay(
            try config.header(false),
            metadata_summary.stream.encoder_delay,
        )),
        parsed_metadata.first_xing.?.encoder_delay,
    );
    try std.testing.expectEqual(
        metadata_encoder,
        parsed_metadata.first_xing.?.encoder.?,
    );
    const gapless =
        try GaplessPlan.fromSummary(.{
            .audio_offset = 0,
            .audio_bytes = @intCast(
                parsed_metadata.audio_bytes,
            ),
            .frame_count = parsed_metadata.frame_count,
            .sample_count = parsed_metadata.sample_count,
            .sample_rate = parsed_metadata.sample_rate,
            .channels = parsed_metadata.channels,
            .first_xing = parsed_metadata.first_xing,
            .first_vbri = null,
        });
    try std.testing.expectEqual(
        metadata_summary.stream.input_samples,
        gapless.audible_samples,
    );

    var metadata_fault_file = try temporary.dir.createFile(
        std.testing.io,
        "reservoir-metadata-recovered.mp3",
        .{ .read = true },
    );
    defer metadata_fault_file.close(std.testing.io);
    var metadata_faults = Mp3FileFaults{};
    var metadata_failed =
        try PcmReservoirFileEncoder.initWithOperations(
            std.testing.io,
            metadata_fault_file,
            config,
            &storage,
            metadata_faults.operations(),
        );
    const recovered_encoder: [9]u8 = "ResRecov1".*;
    try metadata_failed.startGaplessMetadataWithEncoder(
        recovered_encoder,
    );
    _ = try metadata_failed.append(silence);
    _ = try metadata_failed.append(signal);
    const metadata_committed =
        metadata_failed.committed_bytes;
    metadata_faults.fail_write_call =
        metadata_faults.write_calls + 2;
    metadata_faults.partial_write_bytes = 8;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        metadata_failed.finalize(),
    );
    try std.testing.expect(metadata_failed.failed);
    try std.testing.expectEqual(
        metadata_committed,
        metadata_failed.committed_bytes,
    );
    metadata_faults.fail_write_call = null;
    try metadata_failed.recover();
    try std.testing.expectEqual(
        metadata_committed,
        try metadata_fault_file.length(std.testing.io),
    );
    const provisional = try FileReader.summarize(
        std.testing.io,
        metadata_fault_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, 0),
        provisional.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        recovered_encoder,
        provisional.first_xing.?.encoder.?,
    );
    const metadata_recovered =
        try metadata_failed.finalize();
    const final_metadata = try FileReader.summarize(
        std.testing.io,
        metadata_fault_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(
            metadata_recovered.stream.frame_count,
        )),
        final_metadata.first_xing.?.frame_count,
    );

    var failed_file = try temporary.dir.createFile(
        std.testing.io,
        "reservoir-recovered.mp3",
        .{ .read = true },
    );
    defer failed_file.close(std.testing.io);
    var faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 7,
    };
    var failed =
        try PcmReservoirFileEncoder.initWithOperations(
            std.testing.io,
            failed_file,
            config,
            &storage,
            faults.operations(),
        );
    _ = try failed.append(silence);
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        failed.append(signal),
    );
    try std.testing.expect(failed.failed);
    try std.testing.expectEqual(
        @as(u64, 0),
        failed.committed_bytes,
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        failed.stream.frame_count,
    );
    try std.testing.expectEqual(
        @as(u64, 7),
        try failed_file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    try failed.recover();
    try std.testing.expectEqual(
        @as(u64, 0),
        try failed_file.length(std.testing.io),
    );
    try std.testing.expect(try failed.append(signal) > 0);
    const recovered = try failed.finalize();
    try std.testing.expectEqual(
        recovered.stream.byte_count,
        try failed_file.length(std.testing.io),
    );
}

test "finishes bounded MP3 PCM streams with gapless counts" {
    const configs = [_]EncoderConfig{
        .{
            .version = .mpeg1,
            .bitrate_kbps = 128,
            .sample_rate = 44_100,
            .channel_mode = .mono,
        },
        .{
            .version = .mpeg2,
            .bitrate_kbps = 64,
            .sample_rate = 22_050,
            .channel_mode = .mono,
        },
    };
    for (configs) |config| {
        const samples_per_frame =
            (try config.header(false)).samplesPerFrame();
        var encoder = try PcmStreamEncoder.init(config);
        var encoded: [maximum_encoded_frame_bytes * 4]u8 = undefined;
        var encoded_bytes: usize = 0;
        const pcm = PcmFrame{
            .channel_count = 1,
            .sample_count = samples_per_frame,
        };
        for (0..2) |_| {
            const frame = try encoder.append(
                pcm,
                encoded[encoded_bytes..],
            );
            encoded_bytes += frame.len;
        }
        try std.testing.expectError(
            error.Mp3EncoderStreamIncomplete,
            encoder.summary(),
        );
        const finished = try encoder.finish(
            encoded[encoded_bytes..],
        );
        encoded_bytes += finished.frames.len;
        const flush_frames: u64 =
            if (config.version == .mpeg1) 1 else 2;
        try std.testing.expectEqual(
            @as(u64, 2) + flush_frames,
            finished.summary.frame_count,
        );
        try std.testing.expectEqual(
            @as(u64, samples_per_frame) * 2,
            finished.summary.input_samples,
        );
        try std.testing.expectEqual(
            @as(u16, encoder_analysis_delay),
            finished.summary.encoder_delay,
        );
        try std.testing.expectEqual(
            @as(u16, 95),
            finished.summary.end_padding,
        );
        try std.testing.expectEqual(
            @as(u64, encoded_bytes),
            finished.summary.byte_count,
        );
        var parsed = try Stream.init(encoded[0..encoded_bytes]);
        while (try parsed.next()) |_| {}
        try std.testing.expectEqual(
            finished.summary.frame_count,
            parsed.frame_index,
        );
        try std.testing.expectEqual(
            finished.summary.encoded_samples,
            parsed.sample_offset,
        );
        const repeated = try encoder.finish(
            encoded[encoded_bytes..],
        );
        try std.testing.expectEqual(@as(usize, 0), repeated.frames.len);
        try std.testing.expectEqual(finished.summary, repeated.summary);
        const before_append = encoder;
        try std.testing.expectError(
            error.Mp3EncoderStreamFinalized,
            encoder.append(pcm, encoded[encoded_bytes..]),
        );
        try std.testing.expectEqual(before_append, encoder);
    }

    var short = try PcmStreamEncoder.init(configs[1]);
    var frame_output: [maximum_encoded_frame_bytes]u8 = undefined;
    _ = try short.append(
        .{
            .channel_count = 1,
            .sample_count = 576,
        },
        &frame_output,
    );
    var short_output: [1]u8 = .{0x5a};
    const before_short = short;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        short.finish(&short_output),
    );
    try std.testing.expectEqual(before_short, short);
    try std.testing.expectEqual(@as(u8, 0x5a), short_output[0]);
    short.byte_count += 1;
    try std.testing.expectError(
        error.InvalidMp3EncoderStreamState,
        short.finish(&short_output),
    );
}

test "emits exact gapless MP3 stream metadata" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    const samples_per_frame =
        (try config.header(false)).samplesPerFrame();
    var encoder = try PcmStreamEncoder.init(config);
    var encoded: [maximum_encoded_frame_bytes * 5]u8 = @splat(0x5a);
    const before_invalid = encoder;
    const invalid_destination = encoded;
    try std.testing.expectError(
        error.InvalidMp3EncoderIdentifier,
        encoder.startGaplessMetadataWithEncoder(
            @splat(' '),
            &encoded,
        ),
    );
    try std.testing.expectEqual(before_invalid, encoder);
    try std.testing.expectEqual(invalid_destination, encoded);

    const metadata_encoder: [9]u8 = "Stream 01".*;
    const metadata = try encoder.startGaplessMetadataWithEncoder(
        metadata_encoder,
        &encoded,
    );
    const metadata_bytes = metadata.len;
    const placeholder = try Frame.parse(metadata, 0);
    try std.testing.expectEqual(@as(?u32, 0), placeholder.xing.?.frame_count);
    try std.testing.expectEqual(@as(?u32, 0), placeholder.xing.?.stream_bytes);
    try std.testing.expectEqual(@as(?bool, true), try placeholder.crcValid());
    try std.testing.expectEqual(
        metadata_encoder,
        placeholder.xing.?.encoder.?,
    );
    try std.testing.expectError(
        error.Mp3EncoderMetadataAlreadyStarted,
        encoder.startGaplessMetadata(encoded[metadata_bytes..]),
    );
    try std.testing.expectError(
        error.Mp3EncoderStreamIncomplete,
        encoder.gaplessMetadataFrame(encoded[0..metadata_bytes]),
    );

    var encoded_bytes = metadata_bytes;
    const pcm = PcmFrame{
        .channel_count = 1,
        .sample_count = samples_per_frame,
    };
    for (0..2) |_| {
        const frame = try encoder.append(
            pcm,
            encoded[encoded_bytes..],
        );
        encoded_bytes += frame.len;
    }
    const finished = try encoder.finish(
        encoded[encoded_bytes..],
    );
    encoded_bytes += finished.frames.len;
    const final_metadata = try encoder.gaplessMetadataFrame(
        encoded[0..metadata_bytes],
    );
    try std.testing.expectEqual(metadata_bytes, final_metadata.len);

    const summary = try Stream.summarize(encoded[0..encoded_bytes]);
    const xing = summary.first_xing.?;
    try std.testing.expectEqual(metadata_encoder, xing.encoder.?);
    try std.testing.expectEqual(XingKind.constant, xing.kind);
    try std.testing.expectEqual(
        @as(?u32, @intCast(finished.summary.frame_count)),
        xing.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(finished.summary.byte_count)),
        xing.stream_bytes,
    );
    try std.testing.expectEqual(
        @as(?u12, try storedXingEncoderDelay(
            try config.header(false),
            finished.summary.encoder_delay,
        )),
        xing.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(?u12, try storedXingEncoderPadding(
            finished.summary.end_padding,
        )),
        xing.encoder_padding,
    );
    try std.testing.expectEqual(
        @as(u16, encoder_analysis_delay + samples_per_frame),
        finished.summary.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(u16, 95),
        finished.summary.end_padding,
    );
    const gapless = try GaplessPlan.fromSummary(summary);
    try std.testing.expectEqual(
        finished.summary.input_samples,
        gapless.audible_samples,
    );
    try std.testing.expectEqual(
        @as(u16, 0),
        (try placeholder.sideInformation()).main_data_bits,
    );

    var retained: [maximum_encoded_frame_bytes]u8 = @splat(0x5a);
    try std.testing.expectError(
        error.Mp3EncoderMetadataFrameCountOverflow,
        encodeInfoFrame(
            config,
            .{
                .frame_count = @as(u64, std.math.maxInt(u32)) + 1,
                .input_samples = 0,
                .encoded_samples = 0,
                .byte_count = 0,
                .encoder_delay = 0,
                .end_padding = 0,
            },
            &retained,
        ),
    );
    try std.testing.expectEqual(
        @as(u8, 0x5a),
        retained[0],
    );
    const valid_counts = EncoderStreamSummary{
        .frame_count = 1,
        .input_samples = 0,
        .encoded_samples = samples_per_frame,
        .byte_count = 0,
        .encoder_delay = samples_per_frame - 1,
        .end_padding = 0,
    };
    try std.testing.expectError(
        error.Mp3EncoderMetadataDelayUnderflow,
        encodeInfoFrame(config, valid_counts, &retained),
    );
    var oversized_delay = valid_counts;
    oversized_delay.encoder_delay =
        samples_per_frame +
        decoder_delay_samples +
        std.math.maxInt(u12) +
        1;
    try std.testing.expectError(
        error.Mp3EncoderMetadataGaplessOverflow,
        encodeInfoFrame(config, oversized_delay, &retained),
    );
    var oversized_padding = valid_counts;
    oversized_padding.encoder_delay =
        samples_per_frame + decoder_delay_samples;
    oversized_padding.end_padding =
        std.math.maxInt(u12) - decoder_delay_samples + 1;
    try std.testing.expectError(
        error.Mp3EncoderMetadataGaplessOverflow,
        encodeInfoFrame(config, oversized_padding, &retained),
    );
    try std.testing.expectEqual(@as(u8, 0x5a), retained[0]);
}

test "writes and recovers transactional MP3 PCM files" {
    const config = EncoderConfig{
        .version = .mpeg2,
        .bitrate_kbps = 64,
        .sample_rate = 22_050,
        .channel_mode = .mono,
    };
    const pcm = PcmFrame{
        .channel_count = 1,
        .sample_count = 576,
    };
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "encoded.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var storage: [maximum_encoded_frame_bytes * 2]u8 = undefined;
    var writer = try PcmFileEncoder.init(
        std.testing.io,
        file,
        config,
        &storage,
    );
    const metadata_encoder: [9]u8 = "CBRFile 1".*;
    try writer.startGaplessMetadataWithEncoder(
        metadata_encoder,
    );
    try writer.append(pcm);
    try writer.append(pcm);
    const summary = try writer.finalize();
    try std.testing.expectEqual(
        summary.byte_count,
        try file.length(std.testing.io),
    );
    var frame_storage: [maximum_encoded_frame_bytes]u8 = undefined;
    var reader = try FileReader.init(std.testing.io, file);
    var frame_count: u64 = 0;
    while (try reader.next(&frame_storage)) |_| frame_count += 1;
    try std.testing.expectEqual(summary.frame_count, frame_count);
    try std.testing.expectEqual(summary, try writer.finalize());
    const file_summary = try FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(summary.frame_count)),
        file_summary.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        metadata_encoder,
        file_summary.first_xing.?.encoder.?,
    );
    try std.testing.expectEqual(
        @as(?u12, try storedXingEncoderDelay(
            try config.header(false),
            summary.encoder_delay,
        )),
        file_summary.first_xing.?.encoder_delay,
    );
    try std.testing.expectEqual(
        summary.input_samples,
        file_summary.sample_count -
            (try config.header(false)).samplesPerFrame() -
            file_summary.first_xing.?.encoder_delay.? -
            file_summary.first_xing.?.encoder_padding.?,
    );

    var failed_file = try temporary.dir.createFile(
        std.testing.io,
        "recovered.mp3",
        .{ .read = true },
    );
    defer failed_file.close(std.testing.io);
    var faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 7,
    };
    var failed = try PcmFileEncoder.initWithOperations(
        std.testing.io,
        failed_file,
        config,
        &storage,
        faults.operations(),
    );
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        failed.append(pcm),
    );
    try std.testing.expect(failed.failed);
    try std.testing.expectEqual(@as(u64, 0), failed.committed_bytes);
    try std.testing.expectEqual(@as(u64, 0), failed.stream.frame_count);
    try std.testing.expectEqual(
        @as(u64, 7),
        try failed_file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    try failed.recover();
    try std.testing.expect(!failed.failed);
    try std.testing.expectEqual(
        @as(u64, 0),
        try failed_file.length(std.testing.io),
    );
    try failed.append(pcm);
    const committed = failed.committed_bytes;
    faults.fail_write_call = faults.write_calls + 1;
    faults.partial_write_bytes = 5;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        failed.finalize(),
    );
    try std.testing.expectEqual(committed, failed.committed_bytes);
    try std.testing.expect(!failed.stream.finalized);
    try std.testing.expect(
        try failed_file.length(std.testing.io) > committed,
    );
    faults.fail_write_call = null;
    try failed.recover();
    try std.testing.expectEqual(
        committed,
        try failed_file.length(std.testing.io),
    );
    const recovered_summary = try failed.finalize();
    try std.testing.expectEqual(
        recovered_summary.byte_count,
        try failed_file.length(std.testing.io),
    );

    var metadata_file = try temporary.dir.createFile(
        std.testing.io,
        "recovered-metadata.mp3",
        .{ .read = true },
    );
    defer metadata_file.close(std.testing.io);
    var metadata_faults = Mp3FileFaults{};
    var metadata_writer = try PcmFileEncoder.initWithOperations(
        std.testing.io,
        metadata_file,
        config,
        &storage,
        metadata_faults.operations(),
    );
    const recovered_encoder: [9]u8 = "CBRRecov1".*;
    try metadata_writer.startGaplessMetadataWithEncoder(
        recovered_encoder,
    );
    try metadata_writer.append(pcm);
    const metadata_committed = metadata_writer.committed_bytes;
    metadata_faults.fail_write_call =
        metadata_faults.write_calls + 2;
    metadata_faults.partial_write_bytes = 8;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        metadata_writer.finalize(),
    );
    try std.testing.expect(metadata_writer.failed);
    try std.testing.expectEqual(
        metadata_committed,
        metadata_writer.committed_bytes,
    );
    metadata_faults.fail_write_call = null;
    try metadata_writer.recover();
    try std.testing.expectEqual(
        metadata_committed,
        try metadata_file.length(std.testing.io),
    );
    const recovered_placeholder = try FileReader.summarize(
        std.testing.io,
        metadata_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, 0),
        recovered_placeholder.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        recovered_encoder,
        recovered_placeholder.first_xing.?.encoder.?,
    );
    const metadata_summary = try metadata_writer.finalize();
    const recovered_metadata = try FileReader.summarize(
        std.testing.io,
        metadata_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(metadata_summary.frame_count)),
        recovered_metadata.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(metadata_summary.byte_count)),
        recovered_metadata.first_xing.?.stream_bytes,
    );
    try std.testing.expectEqual(
        recovered_encoder,
        recovered_metadata.first_xing.?.encoder.?,
    );
}

test "composes ID3 prefixes and tails with offset MP3 files" {
    const prefix = [_]u8{
        'I', 'D', '3', 4, 0, 0, 0, 0, 0, 0,
    };
    var tail: [128]u8 = @splat(0);
    @memcpy(tail[0..3], "TAG");
    @memcpy(tail[3..8], "title");
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    };
    const pcm = PcmFrame{
        .channel_count = 1,
        .sample_count = 1152,
    };

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "id3-composed.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, "keep", 0);
    try std.testing.expectError(
        error.InvalidMp3Id3v2Prefix,
        writeId3v2FilePrefix(
            std.testing.io,
            file,
            "not a tag",
        ),
    );
    try std.testing.expectEqual(
        @as(u64, 4),
        try file.length(std.testing.io),
    );

    const audio_offset = try writeId3v2FilePrefix(
        std.testing.io,
        file,
        &prefix,
    );
    var storage: [maximum_encoded_frame_bytes * 2]u8 =
        undefined;
    var writer = try PcmFileEncoder.initAt(
        std.testing.io,
        file,
        config,
        &storage,
        audio_offset,
    );
    try writer.startGaplessMetadata();
    try writer.append(pcm);
    const summary = try writer.finalize();
    const audio_end = try fileEncoderOffset(
        audio_offset,
        summary.byte_count,
    );
    try std.testing.expectEqual(
        audio_end,
        try file.length(std.testing.io),
    );
    var frame_storage: [maximum_encoded_frame_bytes]u8 =
        undefined;
    const parsed = try FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(summary.frame_count, parsed.frame_count);
    try std.testing.expectEqual(audio_offset, parsed.audio_offset);

    const file_end = try appendId3v1FileTail(
        std.testing.io,
        file,
        audio_offset,
        summary.byte_count,
        &tail,
    );
    try std.testing.expectEqual(
        file_end,
        try file.length(std.testing.io),
    );
    const with_tail = try FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(summary.frame_count, with_tail.frame_count);
    try std.testing.expectEqual(
        audio_end,
        with_tail.audio_offset + with_tail.audio_bytes,
    );
    try std.testing.expectEqual(
        file_end,
        try appendId3v1FileTail(
            std.testing.io,
            file,
            audio_offset,
            summary.byte_count,
            &tail,
        ),
    );

    var prefix_bytes: [10]u8 = undefined;
    try file_reader_io.readExactAt(
        std.testing.io,
        file,
        0,
        &prefix_bytes,
        error.TestTruncatedId3Prefix,
    );
    try std.testing.expectEqualSlices(u8, &prefix, &prefix_bytes);
    var tail_bytes: [128]u8 = undefined;
    try file_reader_io.readExactAt(
        std.testing.io,
        file,
        audio_end,
        &tail_bytes,
        error.TestTruncatedId3Tail,
    );
    try std.testing.expectEqualSlices(u8, &tail, &tail_bytes);

    var variants_file = try temporary.dir.createFile(
        std.testing.io,
        "id3-offset-variants.mp3",
        .{ .read = true },
    );
    defer variants_file.close(std.testing.io);
    _ = try writeId3v2FilePrefix(
        std.testing.io,
        variants_file,
        &prefix,
    );
    var variant_storage: [maximum_encoded_frame_bytes * 3]u8 = undefined;
    var variant_offsets: [4]u64 = undefined;
    const vbr_config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
        },
    };
    const vbr_writer = try VbrPcmFileEncoder.initAt(
        std.testing.io,
        variants_file,
        vbr_config,
        &variant_storage,
        &variant_offsets,
        audio_offset,
    );
    try std.testing.expectEqual(
        audio_offset,
        vbr_writer.audio_offset,
    );
    const reservoir_writer =
        try PcmReservoirFileEncoder.initAt(
            std.testing.io,
            variants_file,
            config,
            &variant_storage,
            audio_offset,
        );
    try std.testing.expectEqual(
        audio_offset,
        reservoir_writer.audio_offset,
    );
    const vbr_reservoir_writer =
        try VbrPcmReservoirFileEncoder.initAt(
            std.testing.io,
            variants_file,
            vbr_config,
            &variant_storage,
            &variant_offsets,
            audio_offset,
        );
    try std.testing.expectEqual(
        audio_offset,
        vbr_reservoir_writer.audio_offset,
    );
    try std.testing.expectEqual(
        audio_offset,
        try variants_file.length(std.testing.io),
    );

    try std.testing.expectError(
        error.Mp3FileOffsetOverflow,
        appendId3v1FileTail(
            std.testing.io,
            file,
            std.math.maxInt(u64),
            1,
            &tail,
        ),
    );
    try std.testing.expectEqual(
        file_end,
        try file.length(std.testing.io),
    );

    var failed_prefix = try temporary.dir.createFile(
        std.testing.io,
        "id3-prefix-retry.mp3",
        .{ .read = true },
    );
    defer failed_prefix.close(std.testing.io);
    var prefix_faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 4,
    };
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        writeId3v2FilePrefixWithOperations(
            std.testing.io,
            failed_prefix,
            &prefix,
            prefix_faults.operations(),
        ),
    );
    prefix_faults.fail_write_call = null;
    try std.testing.expectEqual(
        audio_offset,
        try writeId3v2FilePrefixWithOperations(
            std.testing.io,
            failed_prefix,
            &prefix,
            prefix_faults.operations(),
        ),
    );
    try std.testing.expectEqual(
        audio_offset,
        try failed_prefix.length(std.testing.io),
    );

    var tail_faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 7,
    };
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        appendId3v1FileTailWithOperations(
            std.testing.io,
            file,
            audio_offset,
            summary.byte_count,
            &tail,
            tail_faults.operations(),
        ),
    );
    try std.testing.expectEqual(
        audio_end + 7,
        try file.length(std.testing.io),
    );
    tail_faults.fail_write_call = null;
    try std.testing.expectEqual(
        file_end,
        try appendId3v1FileTailWithOperations(
            std.testing.io,
            file,
            audio_offset,
            summary.byte_count,
            &tail,
            tail_faults.operations(),
        ),
    );
}

const mp3_fuzz_header = [_]u8{ 0xff, 0xfb, 0x90, 0x00 };

test "fuzz bounded MP3 framing and decoding" {
    try std.testing.fuzz({}, fuzzMp3, .{
        .corpus = &.{&mp3_fuzz_header},
    });
}

fn fuzzMp3(_: void, smith: *std.testing.Smith) !void {
    @disableInstrumentation();
    var storage: [64 * 1024]u8 = undefined;
    var length: usize = switch (smith.valueRangeAtMost(u8, 0, 1)) {
        0 => smith.slice(&storage),
        1 => seed: {
            var end: usize = 0;
            const header = testHeader(3, true, 9, 0, false, .stereo);
            end = try appendFrame(&storage, end, header);
            end = try appendFrame(&storage, end, header);
            break :seed end;
        },
        else => smith.slice(&storage),
    };
    if (length != 0 and smith.value(bool)) {
        const mutation_count = smith.valueRangeAtMost(u8, 1, 32);
        for (0..mutation_count) |_|
            storage[smith.index(length)] ^= smith.value(u8);
    }
    if (smith.value(bool)) {
        const maximum: u16 = @intCast(@min(length, std.math.maxInt(u16)));
        length = smith.valueRangeAtMost(u16, 0, maximum);
    } else if (length < storage.len and smith.value(bool)) {
        const maximum_append: u16 = @intCast(@min(
            storage.len - length,
            std.math.maxInt(u16),
        ));
        const append_length = smith.valueRangeAtMost(u16, 0, maximum_append);
        smith.bytes(storage[length..][0..append_length]);
        length += append_length;
    }

    const limits = Limits{
        .max_stream_bytes = storage.len,
        .max_frames = 256,
    };
    var stream = Stream.initWithLimits(storage[0..length], limits) catch return;
    var decoder = FrameDecoder{};
    var previous_cursor = stream.cursor;
    while (stream.next() catch return) |frame| {
        if (stream.cursor <= previous_cursor)
            return error.Mp3FuzzParserDidNotAdvance;
        previous_cursor = stream.cursor;
        _ = frame.crcValid() catch return;
        _ = frame.sideInformation() catch return;
        const decoder_before = decoder;
        _ = decoder.decode(frame) catch {
            if (!std.meta.eql(decoder_before, decoder))
                return error.Mp3FuzzDecoderFailureWasNotTransactional;
            continue;
        };
    }
}
