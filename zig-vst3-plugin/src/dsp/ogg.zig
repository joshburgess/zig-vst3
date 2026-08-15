const std = @import("std");
const fft = @import("fft.zig");
const file_reader_io = @import("file_reader_io.zig");
const file_writer_io = @import("file_writer_io.zig");
const ogg_container = @import("ogg/container.zig");
const vorbis = @import("ogg/vorbis.zig");

pub const unknown_granule = ogg_container.unknown_granule;
pub const maximum_page_segments = ogg_container.maximum_page_segments;
pub const maximum_page_body_bytes = ogg_container.maximum_page_body_bytes;
pub const maximum_page_bytes = ogg_container.maximum_page_bytes;
pub const Limits = ogg_container.Limits;
pub const default_limits = ogg_container.default_limits;
pub const Page = ogg_container.Page;
pub const PageIterator = ogg_container.PageIterator;
const validateEncodedLimits = ogg_container.validateEncodedLimits;
pub const Packet = ogg_container.Packet;
pub const PacketIterator = ogg_container.PacketIterator;
const RetainedOggPageState = ogg_container.RetainedOggPageState;
const validateRetainedOggPage = ogg_container.validateRetainedOggPage;
const validateRetainedPageStorageRanges = ogg_container.validateRetainedPageStorageRanges;
pub const VorbisPacketLocation = ogg_container.VorbisPacketLocation;
pub const VorbisSeekPoint = ogg_container.VorbisSeekPoint;
const VorbisSeekIndexer = ogg_container.VorbisSeekIndexer;
const vorbisPacketLocation = ogg_container.vorbisPacketLocation;
pub const requiredVorbisSeekPoints = ogg_container.requiredVorbisSeekPoints;
pub const requiredVorbisSeekPointsWithLimits = ogg_container.requiredVorbisSeekPointsWithLimits;
pub const buildVorbisSeekIndex = ogg_container.buildVorbisSeekIndex;
pub const buildVorbisSeekIndexWithLimits = ogg_container.buildVorbisSeekIndexWithLimits;
pub const findVorbisSeekPoint = ogg_container.findVorbisSeekPoint;
pub const FilePageReader = ogg_container.FilePageReader;
const oggReaderLifecycleValid = ogg_container.oggReaderLifecycleValid;
pub const requiredVorbisFileSeekPoints = ogg_container.requiredVorbisFileSeekPoints;
pub const requiredVorbisFileSeekPointsWithLimits = ogg_container.requiredVorbisFileSeekPointsWithLimits;
pub const buildVorbisFileSeekIndex = ogg_container.buildVorbisFileSeekIndex;
pub const buildVorbisFileSeekIndexWithLimits = ogg_container.buildVorbisFileSeekIndexWithLimits;
pub const buildVorbisFileSeekIndexTransactional = ogg_container.buildVorbisFileSeekIndexTransactional;
pub const buildVorbisFileSeekIndexTransactionalWithLimits = ogg_container.buildVorbisFileSeekIndexTransactionalWithLimits;
pub const FilePacketReader = ogg_container.FilePacketReader;
const FilePacketCheckpoint = ogg_container.FilePacketCheckpoint;
const validatePacketPageCursor = ogg_container.validatePacketPageCursor;
const PacketLayout = ogg_container.PacketLayout;
const packetLayout = ogg_container.packetLayout;
const committedPageStateValid = ogg_container.committedPageStateValid;
pub const StreamWriter = ogg_container.StreamWriter;
pub const FileWriter = ogg_container.FileWriter;

pub const VorbisIdentification = vorbis.VorbisIdentification;
pub const encodeVorbisIdentificationPacket = vorbis.encodeVorbisIdentificationPacket;
pub const VorbisComment = vorbis.VorbisComment;
pub const requiredVorbisCommentPacketBytes = vorbis.requiredVorbisCommentPacketBytes;
pub const encodeVorbisCommentPacket = vorbis.encodeVorbisCommentPacket;
pub const VorbisCommentIterator = vorbis.VorbisCommentIterator;
const sameByteRange = vorbis.sameByteRange;
const validVorbisBitrate = vorbis.validVorbisBitrate;
const validVorbisBlockSize = vorbis.validVorbisBlockSize;
const vorbisBlockExponent = vorbis.vorbisBlockExponent;
const validateVorbisCommentName = vorbis.validateVorbisCommentName;
const validateVorbisCommentText = vorbis.validateVorbisCommentText;
pub const VorbisHeaders = vorbis.VorbisHeaders;
pub const VorbisCodebook = vorbis.VorbisCodebook;
pub const VorbisCodebookEntry = vorbis.VorbisCodebookEntry;
pub const VorbisHuffmanNode = vorbis.VorbisHuffmanNode;
pub const VorbisFloorZero = vorbis.VorbisFloorZero;
pub const VorbisFloorOneClass = vorbis.VorbisFloorOneClass;
pub const VorbisFloorOne = vorbis.VorbisFloorOne;
pub const VorbisFloor = vorbis.VorbisFloor;
pub const VorbisResidueKind = vorbis.VorbisResidueKind;
pub const VorbisResidue = vorbis.VorbisResidue;
pub const VorbisCouplingStep = vorbis.VorbisCouplingStep;
pub const VorbisSubmap = vorbis.VorbisSubmap;
pub const VorbisMapping = vorbis.VorbisMapping;
pub const VorbisSetupSummary = vorbis.VorbisSetupSummary;
pub const VorbisSetup = vorbis.VorbisSetup;
pub const VorbisMode = vorbis.VorbisMode;
pub const VorbisSetupStorage = vorbis.VorbisSetupStorage;
pub const parseVorbisSetup = vorbis.parseVorbisSetup;
pub const validateVorbisSetup = vorbis.validateVorbisSetup;
pub const requiredVorbisSetupPacketBytes = vorbis.requiredVorbisSetupPacketBytes;
pub const encodeVorbisSetupPacket = vorbis.encodeVorbisSetupPacket;
const VorbisSetupPacketEncoder = vorbis.VorbisSetupPacketEncoder;
const validateVorbisSetupSliceCounts = vorbis.validateVorbisSetupSliceCounts;
const vorbisSetupSlice = vorbis.vorbisSetupSlice;
const rejectVorbisSetupOverlap = vorbis.rejectVorbisSetupOverlap;
const VorbisBitReader = vorbis.VorbisBitReader;
const VorbisSetupDestination = vorbis.VorbisSetupDestination;
const parseVorbisSetupInternal = vorbis.parseVorbisSetupInternal;
const VorbisVectorCursor = vorbis.VorbisVectorCursor;
pub const VorbisVectorQuantization = vorbis.VorbisVectorQuantization;
pub const VorbisVectorBatchQuantization = vorbis.VorbisVectorBatchQuantization;
pub const quantizeVorbisVector = vorbis.quantizeVorbisVector;
pub const quantizeVorbisVectors = vorbis.quantizeVorbisVectors;
pub const VorbisFloorZeroEncoding = vorbis.VorbisFloorZeroEncoding;
pub const VorbisFloorOneEncoding = vorbis.VorbisFloorOneEncoding;
pub const VorbisFloorOneFit = vorbis.VorbisFloorOneFit;
pub const VorbisAudioFloorOneStorageRequirements = vorbis.VorbisAudioFloorOneStorageRequirements;
pub const VorbisAudioFloorOneScratch = vorbis.VorbisAudioFloorOneScratch;
pub const VorbisAudioFloorOneStorage = vorbis.VorbisAudioFloorOneStorage;
pub const VorbisAudioFloorOnePlan = vorbis.VorbisAudioFloorOnePlan;
pub const VorbisAudioResiduePreparationStorageRequirements = vorbis.VorbisAudioResiduePreparationStorageRequirements;
pub const VorbisAudioResiduePreparationScratch = vorbis.VorbisAudioResiduePreparationScratch;
pub const VorbisAudioResiduePreparationStorage = vorbis.VorbisAudioResiduePreparationStorage;
pub const VorbisAudioResiduePreparationPlan = vorbis.VorbisAudioResiduePreparationPlan;
pub const VorbisResidueEncoding = vorbis.VorbisResidueEncoding;
pub const VorbisResidueQuantizationScratch = vorbis.VorbisResidueQuantizationScratch;
pub const VorbisResidueQuantizationScratchRequirements = vorbis.VorbisResidueQuantizationScratchRequirements;
pub const VorbisResidueQuantization = vorbis.VorbisResidueQuantization;
pub const VorbisAdaptiveResidueScratch = vorbis.VorbisAdaptiveResidueScratch;
pub const VorbisAdaptiveResidueConfig = vorbis.VorbisAdaptiveResidueConfig;
pub const VorbisAdaptiveResidueQuantization = vorbis.VorbisAdaptiveResidueQuantization;
pub const VorbisAudioResidueQuantizationConfig = vorbis.VorbisAudioResidueQuantizationConfig;
pub const VorbisAudioResidueSubmapResult = vorbis.VorbisAudioResidueSubmapResult;
pub const VorbisAudioResidueQuantizationStorageRequirements = vorbis.VorbisAudioResidueQuantizationStorageRequirements;
pub const VorbisAudioResidueQuantizationScratch = vorbis.VorbisAudioResidueQuantizationScratch;
pub const VorbisAudioResidueQuantizationStorage = vorbis.VorbisAudioResidueQuantizationStorage;
pub const VorbisAudioResidueQuantizationPlan = vorbis.VorbisAudioResidueQuantizationPlan;
pub const VorbisPcmPacketEncodingStorageRequirements = vorbis.VorbisPcmPacketEncodingStorageRequirements;
pub const VorbisPcmPacketEncodingScratch = vorbis.VorbisPcmPacketEncodingScratch;
pub const VorbisPcmPacketEncodingStorage = vorbis.VorbisPcmPacketEncodingStorage;
pub const VorbisPcmPacketEncodingTrial = vorbis.VorbisPcmPacketEncodingTrial;
pub const VorbisPcmPacketOrchestrationScratch = vorbis.VorbisPcmPacketOrchestrationScratch;
pub const VorbisFloorPacketEncoding = vorbis.VorbisFloorPacketEncoding;
pub const VorbisAudioPacketEncoding = vorbis.VorbisAudioPacketEncoding;
pub const VorbisAudioPacketPrefixEncoding = vorbis.VorbisAudioPacketPrefixEncoding;
pub const VorbisAudioPacketEncodingResult = vorbis.VorbisAudioPacketEncodingResult;
pub const VorbisAudioPacketFixedCost = vorbis.VorbisAudioPacketFixedCost;
pub const VorbisPacketWriter = vorbis.VorbisPacketWriter;
pub const requiredVorbisAudioPacketBytes = vorbis.requiredVorbisAudioPacketBytes;
pub const encodeVorbisAudioPacket = vorbis.encodeVorbisAudioPacket;
pub const measureVorbisAudioPacketFixedCost = vorbis.measureVorbisAudioPacketFixedCost;
const writeVorbisAudioPacket = vorbis.writeVorbisAudioPacket;
const writeVorbisAudioPacketPrefix = vorbis.writeVorbisAudioPacketPrefix;
const rejectVorbisAudioPacketPrefixOutputOverlap = vorbis.rejectVorbisAudioPacketPrefixOutputOverlap;
const rejectVorbisAudioPacketEncodingOverlap = vorbis.rejectVorbisAudioPacketEncodingOverlap;
const rejectVorbisPacketSetupOverlap = vorbis.rejectVorbisPacketSetupOverlap;
const walkVorbisResidueEncoding = vorbis.walkVorbisResidueEncoding;
const findVorbisResidueClassword = vorbis.findVorbisResidueClassword;
const WritableVorbisCodeword = vorbis.WritableVorbisCodeword;
const writableVorbisCodeword = vorbis.writableVorbisCodeword;
const findVorbisFloorOneClassword = vorbis.findVorbisFloorOneClassword;
const addVorbisPacketBits = vorbis.addVorbisPacketBits;
const validateVorbisCodewordForWrite = vorbis.validateVorbisCodewordForWrite;
pub const VorbisPacketReader = vorbis.VorbisPacketReader;
pub const VorbisFloorZeroPacket = vorbis.VorbisFloorZeroPacket;
pub const VorbisFloorOnePacket = vorbis.VorbisFloorOnePacket;
pub const VorbisResiduePacket = vorbis.VorbisResiduePacket;
const VorbisResidueShape = vorbis.VorbisResidueShape;
pub const requiredVorbisResidueClassifications = vorbis.requiredVorbisResidueClassifications;
pub const requiredVorbisResidueQuantizationScratch = vorbis.requiredVorbisResidueQuantizationScratch;
pub const requiredVorbisResidueQuantizationEntries = vorbis.requiredVorbisResidueQuantizationEntries;
pub const quantizeVorbisResidue = vorbis.quantizeVorbisResidue;
pub const quantizeVorbisResidueAdaptive = vorbis.quantizeVorbisResidueAdaptive;
pub const requiredVorbisCouplingScratch = vorbis.requiredVorbisCouplingScratch;
pub const forwardCoupleVorbisChannels = vorbis.forwardCoupleVorbisChannels;
pub const forwardCoupleVorbisNoiseThresholds = vorbis.forwardCoupleVorbisNoiseThresholds;
pub const inverseCoupleVorbisChannels = vorbis.inverseCoupleVorbisChannels;
pub const VorbisAudioPacketHeader = vorbis.VorbisAudioPacketHeader;
pub const inferVorbisMissingPacketLargeBlock = vorbis.inferVorbisMissingPacketLargeBlock;
pub const inferVorbisMissingPacketLargeBlockFromFollowingGranule = vorbis.inferVorbisMissingPacketLargeBlockFromFollowingGranule;
pub const VorbisPcmBlockAnalysisConfig = vorbis.VorbisPcmBlockAnalysisConfig;
pub const VorbisPcmBlockAnalysis = vorbis.VorbisPcmBlockAnalysis;
pub const VorbisPcmBlockClassifierConfig = vorbis.VorbisPcmBlockClassifierConfig;
pub const VorbisPcmBlockClassification = vorbis.VorbisPcmBlockClassification;
pub const VorbisPcmBlockClassifier = vorbis.VorbisPcmBlockClassifier;
pub const VorbisPsychoacousticConfig = vorbis.VorbisPsychoacousticConfig;
pub const VorbisQualityPreset = vorbis.VorbisQualityPreset;
pub const VorbisPcmQualityMeasurement = vorbis.VorbisPcmQualityMeasurement;
pub const VorbisPcmQualityMeter = vorbis.VorbisPcmQualityMeter;
pub const VorbisPsychoacousticAnalysis = vorbis.VorbisPsychoacousticAnalysis;
pub const VorbisAudioPsychoacousticStorageRequirements = vorbis.VorbisAudioPsychoacousticStorageRequirements;
pub const VorbisAudioPsychoacousticScratch = vorbis.VorbisAudioPsychoacousticScratch;
pub const VorbisAudioPsychoacousticStorage = vorbis.VorbisAudioPsychoacousticStorage;
pub const VorbisAudioPsychoacousticPlan = vorbis.VorbisAudioPsychoacousticPlan;
pub const VorbisRateDistortion = vorbis.VorbisRateDistortion;
pub const analyzeVorbisPsychoacoustics = vorbis.analyzeVorbisPsychoacoustics;
pub const requiredVorbisAudioPsychoacousticStorage = vorbis.requiredVorbisAudioPsychoacousticStorage;
pub const analyzeVorbisAudioPsychoacoustics = vorbis.analyzeVorbisAudioPsychoacoustics;
const rejectVorbisAudioPsychoacousticOverlap = vorbis.rejectVorbisAudioPsychoacousticOverlap;
const vorbisPsychoacousticBand = vorbis.vorbisPsychoacousticBand;
pub const evaluateVorbisRateDistortion = vorbis.evaluateVorbisRateDistortion;
pub const VorbisRateControlConfig = vorbis.VorbisRateControlConfig;
pub const VorbisAdaptiveRatePolicyConfig = vorbis.VorbisAdaptiveRatePolicyConfig;
pub const VorbisAdaptiveRateDecision = vorbis.VorbisAdaptiveRateDecision;
pub const VorbisQualityRateControllerConfig = vorbis.VorbisQualityRateControllerConfig;
pub const VorbisQualityRateAction = vorbis.VorbisQualityRateAction;
pub const VorbisQualityRateDecision = vorbis.VorbisQualityRateDecision;
pub const VorbisQualitySignalDecision = vorbis.VorbisQualitySignalDecision;
pub const VorbisQualityRateController = vorbis.VorbisQualityRateController;
pub const VorbisPacketBitBudget = vorbis.VorbisPacketBitBudget;
pub const adaptVorbisPacketBitBudget = vorbis.adaptVorbisPacketBitBudget;
pub const VorbisRateCommit = vorbis.VorbisRateCommit;
pub const VorbisResidueBitAllocation = vorbis.VorbisResidueBitAllocation;
pub const allocateVorbisResidueBitBudgets = vorbis.allocateVorbisResidueBitBudgets;
pub const requiredVorbisAudioResidueQuantizationStorage = vorbis.requiredVorbisAudioResidueQuantizationStorage;
pub const quantizeVorbisAudioResiduesAdaptive = vorbis.quantizeVorbisAudioResiduesAdaptive;
const rejectVorbisAudioResidueQuantizationOverlap = vorbis.rejectVorbisAudioResidueQuantizationOverlap;
pub const VorbisBitReservoir = vorbis.VorbisBitReservoir;
const validateVorbisRateControlConfig = vorbis.validateVorbisRateControlConfig;
const validateVorbisAdaptiveRatePolicyConfig = vorbis.validateVorbisAdaptiveRatePolicyConfig;
const validateVorbisQualityRateControllerConfig = vorbis.validateVorbisQualityRateControllerConfig;
const validateVorbisPcmBlockClassifierConfig = vorbis.validateVorbisPcmBlockClassifierConfig;
pub const analyzeVorbisPcmBlock = vorbis.analyzeVorbisPcmBlock;
pub const selectVorbisEncodingMode = vorbis.selectVorbisEncodingMode;
pub const planVorbisEncodingBlock = vorbis.planVorbisEncodingBlock;
pub const VorbisPcmFramePlan = vorbis.VorbisPcmFramePlan;
pub const VorbisPcmFramePlanner = vorbis.VorbisPcmFramePlanner;
pub const VorbisPcmBlockLookahead = vorbis.VorbisPcmBlockLookahead;
pub const VorbisPcmPacketSequenceConfig = vorbis.VorbisPcmPacketSequenceConfig;
pub const VorbisPcmPacketPlan = vorbis.VorbisPcmPacketPlan;
pub const VorbisPcmPacketCommit = vorbis.VorbisPcmPacketCommit;
pub const VorbisPcmPacketSequence = vorbis.VorbisPcmPacketSequence;
const validateVorbisPcmFrameTransition = vorbis.validateVorbisPcmFrameTransition;
const vorbisPcmBlockClassificationValid = vorbis.vorbisPcmBlockClassificationValid;
const vorbisPcmBlockDecision = vorbis.vorbisPcmBlockDecision;
const vorbisPcmPacketGranule = vorbis.vorbisPcmPacketGranule;
const vorbisPcmFrameGranule = vorbis.vorbisPcmFrameGranule;
pub const extractVorbisPcmBlock = vorbis.extractVorbisPcmBlock;
pub const parseVorbisAudioPacketHeader = vorbis.parseVorbisAudioPacketHeader;
pub const synthesizeVorbisWindow = vorbis.synthesizeVorbisWindow;
pub const VorbisWindowPlan = vorbis.VorbisWindowPlan;
const fillVorbisWindow = vorbis.fillVorbisWindow;
const fillVorbisWindowSlope = vorbis.fillVorbisWindowSlope;
pub const VorbisInverseMdct = vorbis.VorbisInverseMdct;
pub const VorbisForwardMdct = vorbis.VorbisForwardMdct;
pub const VorbisPcmBlockTransform = vorbis.VorbisPcmBlockTransform;
pub const VorbisPcmFrameAnalysisStorageRequirements = vorbis.VorbisPcmFrameAnalysisStorageRequirements;
pub const VorbisPcmFrameAnalysisScratch = vorbis.VorbisPcmFrameAnalysisScratch;
pub const VorbisPcmFrameAnalysisStorage = vorbis.VorbisPcmFrameAnalysisStorage;
pub const VorbisPcmFrameAnalysisPlan = vorbis.VorbisPcmFrameAnalysisPlan;
pub const VorbisPcmFrameAnalyzer = vorbis.VorbisPcmFrameAnalyzer;
const rejectVorbisPcmFrameAnalysisOverlap = vorbis.rejectVorbisPcmFrameAnalysisOverlap;
pub const VorbisOverlapAdd = vorbis.VorbisOverlapAdd;
pub const VorbisChannelOverlapAdd = vorbis.VorbisChannelOverlapAdd;
pub const VorbisGranuleRange = vorbis.VorbisGranuleRange;
pub const VorbisGranuleTracker = vorbis.VorbisGranuleTracker;
const vorbisDecodedSampleTimelineValid = vorbis.vorbisDecodedSampleTimelineValid;
const vorbisGranuleOutputUpperBound = vorbis.vorbisGranuleOutputUpperBound;
pub const VorbisPcmStreamScratch = vorbis.VorbisPcmStreamScratch;
pub const VorbisPcmStreamResult = vorbis.VorbisPcmStreamResult;
pub const VorbisPcmConcealmentResult = vorbis.VorbisPcmConcealmentResult;
pub const VorbisPcmSignalConcealmentConfig = vorbis.VorbisPcmSignalConcealmentConfig;
pub const VorbisChainedPcmStreamResult = vorbis.VorbisChainedPcmStreamResult;
pub const VorbisChainedPcmConcealmentResult = vorbis.VorbisChainedPcmConcealmentResult;
pub const VorbisPcmSeekCursor = vorbis.VorbisPcmSeekCursor;
pub const VorbisPcmStreamDecoder = vorbis.VorbisPcmStreamDecoder;
const validateVorbisPcmSignalConcealmentConfig = vorbis.validateVorbisPcmSignalConcealmentConfig;
const synthesizeVorbisPreviousSignal = vorbis.synthesizeVorbisPreviousSignal;
pub const VorbisChainedPcmStreamDecoder = vorbis.VorbisChainedPcmStreamDecoder;
pub const applyVorbisFloor = vorbis.applyVorbisFloor;
pub const VorbisAudioPacketScratchRequirements = vorbis.VorbisAudioPacketScratchRequirements;
pub const VorbisAudioPacketScratch = vorbis.VorbisAudioPacketScratch;
pub const VorbisAudioPacketResult = vorbis.VorbisAudioPacketResult;
pub const requiredVorbisAudioPacketScratch = vorbis.requiredVorbisAudioPacketScratch;
pub const VorbisAudioPacketDecoder = vorbis.VorbisAudioPacketDecoder;
const validateVorbisAudioDecodeState = vorbis.validateVorbisAudioDecodeState;
const validateVorbisAudioPacketBuffers = vorbis.validateVorbisAudioPacketBuffers;
const vorbisResidueShape = vorbis.vorbisResidueShape;
const VorbisResidueRateMetrics = vorbis.VorbisResidueRateMetrics;
const VorbisAdaptiveResidueCandidate = vorbis.VorbisAdaptiveResidueCandidate;
const planVorbisAdaptiveResidueCandidate = vorbis.planVorbisAdaptiveResidueCandidate;
const selectVorbisResidueClassificationsRateDistortion = vorbis.selectVorbisResidueClassificationsRateDistortion;
const measureVorbisResidueRateDistortion = vorbis.measureVorbisResidueRateDistortion;
const measureVorbisResiduePartitionRateDistortion = vorbis.measureVorbisResiduePartitionRateDistortion;
const selectVorbisResidueClassifications = vorbis.selectVorbisResidueClassifications;
const countVorbisResidueQuantizedEntries = vorbis.countVorbisResidueQuantizedEntries;
const measureVorbisResidueQuantization = vorbis.measureVorbisResidueQuantization;
const assembleVorbisResidueEntries = vorbis.assembleVorbisResidueEntries;
const quantizeVorbisResiduePartition = vorbis.quantizeVorbisResiduePartition;
const vorbisResiduePartitionIndex = vorbis.vorbisResiduePartitionIndex;
const vorbisResidueInputValue = vorbis.vorbisResidueInputValue;
const rejectVorbisResidueQuantizationOverlap = vorbis.rejectVorbisResidueQuantizationOverlap;
const rejectVorbisAdaptiveResidueQuantizationOverlap = vorbis.rejectVorbisAdaptiveResidueQuantizationOverlap;
const validateVorbisResidueState = vorbis.validateVorbisResidueState;
const validateVorbisScalarCodebookState = vorbis.validateVorbisScalarCodebookState;
const validateVorbisVectorCodebookState = vorbis.validateVorbisVectorCodebookState;
const vorbisSlicesOverlap = vorbis.vorbisSlicesOverlap;
const vorbisConstSlicesOverlap = vorbis.vorbisConstSlicesOverlap;
const vorbisSliceOverlapsBytes = vorbis.vorbisSliceOverlapsBytes;
const vorbisTypedSlicesOverlap = vorbis.vorbisTypedSlicesOverlap;
const byteRangesOverlap = vorbis.byteRangesOverlap;
const validateVorbisFloorZeroState = vorbis.validateVorbisFloorZeroState;
const validateVorbisFloorZeroSynthesisState = vorbis.validateVorbisFloorZeroSynthesisState;
const validateVorbisFloorOneState = vorbis.validateVorbisFloorOneState;
pub const synthesizeVorbisFloorZero = vorbis.synthesizeVorbisFloorZero;
const vorbisLogAbsolute = vorbis.vorbisLogAbsolute;
const vorbisLogAddExp = vorbis.vorbisLogAddExp;
const vorbisBark = vorbis.vorbisBark;
pub const synthesizeVorbisFloorOne = vorbis.synthesizeVorbisFloorOne;
pub const requiredVorbisAudioFloorOneStorage = vorbis.requiredVorbisAudioFloorOneStorage;
pub const fitVorbisAudioFloorOne = vorbis.fitVorbisAudioFloorOne;
pub const requiredVorbisAudioResiduePreparationStorage = vorbis.requiredVorbisAudioResiduePreparationStorage;
pub const prepareVorbisAudioResidue = vorbis.prepareVorbisAudioResidue;
pub const requiredVorbisPcmPacketEncodingStorage = vorbis.requiredVorbisPcmPacketEncodingStorage;
pub const encodeVorbisPcmPacket = vorbis.encodeVorbisPcmPacket;
pub const encodeVorbisPcmPacketTrial = vorbis.encodeVorbisPcmPacketTrial;
const validateVorbisPcmPacketEncodingStorage = vorbis.validateVorbisPcmPacketEncodingStorage;
const retainVorbisAudioResiduePreparation = vorbis.retainVorbisAudioResiduePreparation;
const retainVorbisAudioResidueQuantization = vorbis.retainVorbisAudioResidueQuantization;
const rejectVorbisAudioResiduePreparationOverlap = vorbis.rejectVorbisAudioResiduePreparationOverlap;
const validateVorbisAudioFloorOneState = vorbis.validateVorbisAudioFloorOneState;
const rejectVorbisAudioFloorOneOverlap = vorbis.rejectVorbisAudioFloorOneOverlap;
pub const fitVorbisFloorOne = vorbis.fitVorbisFloorOne;
pub const normalizeVorbisResidue = vorbis.normalizeVorbisResidue;
pub const normalizeVorbisNoiseThresholds = vorbis.normalizeVorbisNoiseThresholds;
const fitVorbisFloorOneClass = vorbis.fitVorbisFloorOneClass;
const fitVorbisFloorOneClassword = vorbis.fitVorbisFloorOneClassword;
const VorbisFloorOneValueFit = vorbis.VorbisFloorOneValueFit;
const fitVorbisFloorOneValue = vorbis.fitVorbisFloorOneValue;
const decodeVorbisFloorOneValue = vorbis.decodeVorbisFloorOneValue;
const vorbisFloorOneTargetY = vorbis.vorbisFloorOneTargetY;
const rejectVorbisFloorFitOverlap = vorbis.rejectVorbisFloorFitOverlap;
const vorbisFloorLowNeighbor = vorbis.vorbisFloorLowNeighbor;
const vorbisFloorHighNeighbor = vorbis.vorbisFloorHighNeighbor;
const vorbisFloorRenderPoint = vorbis.vorbisFloorRenderPoint;
const renderVorbisFloorLine = vorbis.renderVorbisFloorLine;
const vorbisFloorOneInverseDb = vorbis.vorbisFloorOneInverseDb;
const vorbis_floor_one_inverse_db = vorbis.vorbis_floor_one_inverse_db;
const readVorbisAudioBits = vorbis.readVorbisAudioBits;
const parseVorbisCodebook = vorbis.parseVorbisCodebook;
const invalid_huffman_branch = vorbis.invalid_huffman_branch;
const huffman_leaf_flag = vorbis.huffman_leaf_flag;
const buildVorbisHuffmanTree = vorbis.buildVorbisHuffmanTree;
const vorbisFloat32Unpack = vorbis.vorbisFloat32Unpack;
const vorbisFloat32PackExact = vorbis.vorbisFloat32PackExact;
const assignVorbisCodewords = vorbis.assignVorbisCodewords;
const validateVorbisCodebookTree = vorbis.validateVorbisCodebookTree;
const parseVorbisFloorZero = vorbis.parseVorbisFloorZero;
const parseVorbisFloorOne = vorbis.parseVorbisFloorOne;
const parseVorbisResidue = vorbis.parseVorbisResidue;
const parseVorbisMapping = vorbis.parseVorbisMapping;
const vorbisILog = vorbis.vorbisILog;
const vorbisLookupOneValues = vorbis.vorbisLookupOneValues;
const powerAtMost = vorbis.powerAtMost;
pub const pageChecksum = vorbis.pageChecksum;
const encodePage = vorbis.encodePage;
const readExactAt = vorbis.readExactAt;
const appendTestOggPage = vorbis.appendTestOggPage;
const TestVorbisCodebookEncoding = vorbis.TestVorbisCodebookEncoding;
const OggFileFaults = vorbis.OggFileFaults;
const TestVorbisSetupPacket = vorbis.TestVorbisSetupPacket;
const TestVorbisBitWriter = vorbis.TestVorbisBitWriter;
const makeTestVorbisSetup = vorbis.makeTestVorbisSetup;
const flipTestBit = vorbis.flipTestBit;

test "Ogg writer and packet iterator preserve continued packets" {
    var encoded: [70_000]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 0x12345678);
    const first = [_]u8{0xaa} ** 65_100;
    try writer.appendPacket(&first, 100, true, false);
    try writer.appendPacket("tail", 104, false, true);
    var packet_storage: [65_100]u8 = undefined;
    var packets = PacketIterator.init(writer.bytes(), &packet_storage);
    try std.testing.expect(packets.valid());
    const decoded_first = (try packets.next()).?;
    try std.testing.expect(decoded_first.beginning);
    try std.testing.expectEqual(@as(u64, 100), decoded_first.granule_position);
    try std.testing.expectEqualSlices(u8, &first, decoded_first.bytes);
    const tail = (try packets.next()).?;
    try std.testing.expect(tail.end);
    try std.testing.expectEqualStrings("tail", tail.bytes);
    try std.testing.expect((try packets.next()) == null);
    try std.testing.expect(packets.valid());
}

test "Ogg memory and file readers enforce whole-stream limits" {
    var encoded: [256]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 0x12345678);
    try writer.appendPacket("first", 5, true, false);
    try writer.appendPacket("second", 11, false, true);
    const bytes = writer.bytes();

    try std.testing.expectError(
        error.InvalidOggLimits,
        PageIterator.initWithLimits(bytes, .{ .max_pages = 0 }),
    );
    try std.testing.expectError(
        error.OggStreamLimitExceeded,
        PageIterator.initWithLimits(bytes, .{
            .max_stream_bytes = bytes.len - 1,
        }),
    );

    var page_limited = try PageIterator.initWithLimits(bytes, .{
        .max_stream_bytes = bytes.len,
        .max_pages = 1,
        .max_packets = 2,
    });
    _ = (try page_limited.next()).?;
    const page_limited_before = page_limited;
    try std.testing.expectError(
        error.OggPageLimitExceeded,
        page_limited.next(),
    );
    try std.testing.expectEqualDeep(page_limited_before, page_limited);
    try std.testing.expectError(
        error.OggPageLimitExceeded,
        requiredVorbisSeekPointsWithLimits(bytes, .{
            .max_stream_bytes = bytes.len,
            .max_pages = 1,
            .max_packets = 2,
        }),
    );

    var exact_pages = try PageIterator.initWithLimits(bytes, .{
        .max_stream_bytes = bytes.len,
        .max_pages = 2,
        .max_packets = 2,
    });
    _ = (try exact_pages.next()).?;
    _ = (try exact_pages.next()).?;
    try std.testing.expect((try exact_pages.next()) == null);

    var packet_storage: [16]u8 = undefined;
    var packet_limited = try PacketIterator.initWithLimits(
        bytes,
        &packet_storage,
        .{
            .max_stream_bytes = bytes.len,
            .max_pages = 2,
            .max_packets = 1,
        },
    );
    _ = (try packet_limited.next()).?;
    const packet_limited_before = packet_limited;
    const packet_storage_before = packet_storage;
    try std.testing.expectError(
        error.OggPacketLimitExceeded,
        packet_limited.next(),
    );
    try std.testing.expectEqualDeep(packet_limited_before, packet_limited);
    try std.testing.expectEqualSlices(
        u8,
        &packet_storage_before,
        &packet_storage,
    );

    var chained: [128]u8 = undefined;
    var first_writer = StreamWriter.init(&chained, 1);
    try first_writer.appendPacket("a", 1, true, true);
    const first_bytes = first_writer.bytes().len;
    var second_writer = StreamWriter.init(chained[first_bytes..], 2);
    try second_writer.appendPacket("b", 1, true, true);
    const chained_bytes = chained[0 .. first_bytes + second_writer.bytes().len];
    var stream_limited = try PageIterator.initChainedWithLimits(
        chained_bytes,
        .{
            .max_stream_bytes = chained_bytes.len,
            .max_pages = 2,
            .max_packets = 2,
            .max_logical_streams = 1,
        },
    );
    _ = (try stream_limited.next()).?;
    const stream_limited_before = stream_limited;
    try std.testing.expectError(
        error.OggLogicalStreamLimitExceeded,
        stream_limited.next(),
    );
    try std.testing.expectEqualDeep(stream_limited_before, stream_limited);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "bounded.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, bytes, 0);
    try file.setLength(std.testing.io, bytes.len);
    try std.testing.expectError(
        error.OggStreamLimitExceeded,
        FilePageReader.initWithLimits(std.testing.io, file, .{
            .max_stream_bytes = bytes.len - 1,
        }),
    );

    var file_page_limited = try FilePageReader.initWithLimits(
        std.testing.io,
        file,
        .{
            .max_stream_bytes = bytes.len,
            .max_pages = 1,
            .max_packets = 2,
        },
    );
    var page_storage: [maximum_page_bytes]u8 = undefined;
    _ = (try file_page_limited.next(&page_storage)).?;
    const file_page_before = file_page_limited;
    const page_storage_before = page_storage;
    try std.testing.expectError(
        error.OggPageLimitExceeded,
        file_page_limited.next(&page_storage),
    );
    try std.testing.expectEqualDeep(file_page_before, file_page_limited);
    try std.testing.expectEqualSlices(u8, &page_storage_before, &page_storage);
    try std.testing.expectError(
        error.OggPageLimitExceeded,
        requiredVorbisFileSeekPointsWithLimits(
            std.testing.io,
            file,
            &page_storage,
            .{
                .max_stream_bytes = bytes.len,
                .max_pages = 1,
                .max_packets = 2,
            },
        ),
    );

    var file_packet_limited = try FilePacketReader.initWithLimits(
        std.testing.io,
        file,
        .{
            .max_stream_bytes = bytes.len,
            .max_pages = 2,
            .max_packets = 1,
        },
    );
    _ = (try file_packet_limited.next(
        &page_storage,
        &packet_storage,
    )).?;
    const file_packet_before = file_packet_limited;
    const file_packet_storage_before = packet_storage;
    try std.testing.expectError(
        error.OggPacketLimitExceeded,
        file_packet_limited.next(&page_storage, &packet_storage),
    );
    try std.testing.expectEqualDeep(file_packet_before, file_packet_limited);
    try std.testing.expectEqualSlices(
        u8,
        &file_packet_storage_before,
        &packet_storage,
    );

    try file.writePositionalAll(std.testing.io, chained_bytes, 0);
    try file.setLength(std.testing.io, chained_bytes.len);
    var file_stream_limited = try FilePageReader.initChainedWithLimits(
        std.testing.io,
        file,
        .{
            .max_stream_bytes = chained_bytes.len,
            .max_pages = 2,
            .max_packets = 2,
            .max_logical_streams = 1,
        },
    );
    _ = (try file_stream_limited.next(&page_storage)).?;
    const file_stream_before = file_stream_limited;
    const file_stream_storage_before = page_storage;
    try std.testing.expectError(
        error.OggLogicalStreamLimitExceeded,
        file_stream_limited.next(&page_storage),
    );
    try std.testing.expectEqualDeep(file_stream_before, file_stream_limited);
    try std.testing.expectEqualSlices(
        u8,
        &file_stream_storage_before,
        &page_storage,
    );
}

test "Ogg packet iteration rolls back capacity and hostile state failures" {
    var encoded: [512]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 9);
    const source = [_]u8{0x5a} ** 300;
    try writer.appendPacket(&source, 300, true, true);

    var short_storage: [260]u8 = undefined;
    var packets = PacketIterator.init(writer.bytes(), &short_storage);
    try std.testing.expectError(
        error.OggPacketBufferTooSmall,
        packets.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), packets.pages.offset);
    try std.testing.expect(packets.page == null);
    try std.testing.expectEqual(@as(usize, 0), packets.packet_bytes);

    var complete_storage: [300]u8 = undefined;
    packets.storage = &complete_storage;
    const packet = (try packets.next()).?;
    try std.testing.expectEqualSlices(u8, &source, packet.bytes);
    try std.testing.expect(packet.beginning);
    try std.testing.expect(packet.end);

    var invalid = PacketIterator.init(writer.bytes(), &complete_storage);
    invalid.packet_bytes = complete_storage.len + 1;
    try std.testing.expect(!invalid.valid());
    try std.testing.expectError(
        error.InvalidOggPacketReaderState,
        invalid.next(),
    );
    invalid.packet_bytes = 0;
    invalid.segment_index = 1;
    try std.testing.expect(!invalid.valid());
    try std.testing.expectError(
        error.InvalidOggPacketReaderState,
        invalid.next(),
    );

    var detached_lacing = PacketIterator.init(
        writer.bytes(),
        &complete_storage,
    );
    detached_lacing.page = (try detached_lacing.pages.next()).?;
    var lacing_copy: [2]u8 = undefined;
    @memcpy(&lacing_copy, detached_lacing.page.?.lacing_values);
    detached_lacing.page.?.lacing_values = &lacing_copy;
    try std.testing.expect(!detached_lacing.valid());
    const detached_lacing_before = detached_lacing;
    try std.testing.expectError(
        error.InvalidOggPacketReaderState,
        detached_lacing.next(),
    );
    try std.testing.expectEqualDeep(
        detached_lacing_before,
        detached_lacing,
    );

    var detached_body = PacketIterator.init(
        writer.bytes(),
        &complete_storage,
    );
    detached_body.page = (try detached_body.pages.next()).?;
    var body_copy: [300]u8 = undefined;
    @memcpy(&body_copy, detached_body.page.?.body);
    detached_body.page.?.body = &body_copy;
    try std.testing.expect(!detached_body.valid());
    const detached_body_before = detached_body;
    try std.testing.expectError(
        error.InvalidOggPacketReaderState,
        detached_body.next(),
    );
    try std.testing.expectEqualDeep(detached_body_before, detached_body);

    var stale_page = PacketIterator.init(
        writer.bytes(),
        &complete_storage,
    );
    stale_page.page = (try stale_page.pages.next()).?;
    stale_page.page.?.granule_position +%= 1;
    try std.testing.expect(!stale_page.valid());
    const stale_page_before = stale_page;
    try std.testing.expectError(
        error.InvalidOggPacketReaderState,
        stale_page.next(),
    );
    try std.testing.expectEqualDeep(stale_page_before, stale_page);

    var stale_page_reader = PacketIterator.init(
        writer.bytes(),
        &complete_storage,
    );
    stale_page_reader.page = (try stale_page_reader.pages.next()).?;
    stale_page_reader.pages.offset -= 1;
    try std.testing.expect(!stale_page_reader.valid());
    const stale_page_reader_before = stale_page_reader;
    try std.testing.expectError(
        error.InvalidOggPacketReaderState,
        stale_page_reader.next(),
    );
    try std.testing.expectEqualDeep(
        stale_page_reader_before,
        stale_page_reader,
    );

    var overflow = PacketIterator.init(writer.bytes(), &complete_storage);
    overflow.pages.limits.max_packets = std.math.maxInt(u64);
    overflow.packet_index = std.math.maxInt(u64);
    try std.testing.expectError(
        error.OggPacketCountOverflow,
        overflow.next(),
    );
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        overflow.packet_index,
    );
    try std.testing.expectEqual(@as(usize, 0), overflow.pages.offset);

    var impossible_counts =
        PacketIterator.init(writer.bytes(), &complete_storage);
    impossible_counts.logical_stream_packet_index = 1;
    try std.testing.expect(!impossible_counts.valid());
    const impossible_counts_before = impossible_counts;
    try std.testing.expectError(
        error.InvalidOggPacketReaderState,
        impossible_counts.next(),
    );
    try std.testing.expectEqualDeep(
        impossible_counts_before,
        impossible_counts,
    );

    var invalid_pages = PageIterator.init(writer.bytes());
    invalid_pages.expected_sequence = 1;
    try std.testing.expect(!invalid_pages.valid());
    try std.testing.expectError(
        error.InvalidOggReaderState,
        invalid_pages.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), invalid_pages.offset);
}

test "transactional Ogg packet iteration preserves bound storage" {
    var encoded: [512]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 10);
    const source = [_]u8{0x6b} ** 300;
    try writer.appendPacket(&source, 300, true, true);

    var destination: [300]u8 = @splat(0xa5);
    const untouched = destination;
    var short_scratch: [260]u8 = undefined;
    var packets = PacketIterator.init(writer.bytes(), &destination);
    const before_short_scratch = packets;
    try std.testing.expectError(
        error.OggPacketBufferTooSmall,
        packets.nextTransactional(&short_scratch),
    );
    try std.testing.expectEqualDeep(before_short_scratch, packets);
    try std.testing.expectEqualSlices(u8, &untouched, &destination);

    try std.testing.expectError(
        error.OverlappingOggPacketStorage,
        packets.nextTransactional(destination[0..]),
    );
    try std.testing.expectEqualDeep(before_short_scratch, packets);
    try std.testing.expectEqualSlices(u8, &untouched, &destination);

    const before_encoded_scratch = packets;
    try std.testing.expectError(
        error.OverlappingOggPacketStorage,
        packets.nextTransactional(encoded[0..300]),
    );
    try std.testing.expectEqualDeep(before_encoded_scratch, packets);
    try std.testing.expectEqualSlices(u8, &untouched, &destination);

    var scratch: [300]u8 = undefined;
    const packet = (try packets.nextTransactional(&scratch)).?;
    try std.testing.expectEqualSlices(u8, &source, packet.bytes);
    try std.testing.expectEqual(
        @intFromPtr(destination[0..].ptr),
        @intFromPtr(packet.bytes.ptr),
    );
    try std.testing.expect((try packets.nextTransactional(&scratch)) == null);

    var short_destination: [260]u8 = @splat(0x5a);
    const short_untouched = short_destination;
    var capacity_limited = PacketIterator.init(
        writer.bytes(),
        &short_destination,
    );
    const before_capacity = capacity_limited;
    try std.testing.expectError(
        error.OggPacketBufferTooSmall,
        capacity_limited.nextTransactional(&scratch),
    );
    try std.testing.expectEqualDeep(before_capacity, capacity_limited);
    try std.testing.expectEqualSlices(
        u8,
        &short_untouched,
        &short_destination,
    );

    var aliased = PacketIterator.init(
        writer.bytes(),
        encoded[0..300],
    );
    try std.testing.expect(!aliased.valid());
    try std.testing.expectError(
        error.OverlappingOggPacketStorage,
        aliased.next(),
    );
}

test "file-backed Ogg writer streams continued packets" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "stream.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var page_storage: [maximum_page_bytes]u8 = undefined;
    var writer = try FileWriter.init(
        std.testing.io,
        file,
        &page_storage,
        0x12345678,
    );
    const first = [_]u8{0xaa} ** 65_100;
    try writer.appendPacket(&first, 100, true, false);
    try writer.appendPacket("tail", 104, false, true);
    try writer.finalize();
    try std.testing.expectEqual(
        writer.byte_count,
        try file.length(std.testing.io),
    );

    var reader = try FilePacketReader.init(std.testing.io, file);
    var reader_page_storage: [maximum_page_bytes]u8 = undefined;
    var packet_storage: [65_100]u8 = undefined;
    try std.testing.expectError(
        error.OggPacketBufferTooSmall,
        reader.next(
            &reader_page_storage,
            packet_storage[0..65_000],
        ),
    );
    try std.testing.expectEqual(@as(u64, 0), reader.pages.offset);
    try std.testing.expect(reader.page == null);
    try std.testing.expect(reader.page_storage_pointer == null);
    try std.testing.expect(reader.packet_storage_pointer == null);
    const decoded_first = (try reader.next(
        &reader_page_storage,
        &packet_storage,
    )).?;
    try std.testing.expect(decoded_first.beginning);
    try std.testing.expectEqual(@as(u64, 100), decoded_first.granule_position);
    try std.testing.expectEqualSlices(u8, &first, decoded_first.bytes);
    var detached_page = reader;
    const detached_lacing_length =
        detached_page.page.?.lacing_values.len;
    var detached_lacing: [maximum_page_segments]u8 = undefined;
    @memcpy(
        detached_lacing[0..detached_lacing_length],
        detached_page.page.?.lacing_values,
    );
    detached_page.page.?.lacing_values =
        detached_lacing[0..detached_lacing_length];
    try std.testing.expect(!detached_page.valid(
        &reader_page_storage,
        &packet_storage,
    ));
    const detached_page_before = detached_page;
    try std.testing.expectError(
        error.InvalidOggFilePacketReaderState,
        detached_page.next(&reader_page_storage, &packet_storage),
    );
    try std.testing.expectEqualDeep(detached_page_before, detached_page);
    const tail = (try reader.next(
        &reader_page_storage,
        &packet_storage,
    )).?;
    try std.testing.expect(tail.end);
    try std.testing.expectEqualStrings("tail", tail.bytes);
    try std.testing.expect(
        (try reader.next(
            &reader_page_storage,
            &packet_storage,
        )) == null,
    );

    var saturated = try FilePacketReader.init(std.testing.io, file);
    saturated.pages.limits.max_packets = std.math.maxInt(u64);
    saturated.packet_index = std.math.maxInt(u64) - 1;
    saturated.logical_stream_packet_index =
        std.math.maxInt(u64) - 1;
    _ = (try saturated.next(
        &reader_page_storage,
        &packet_storage,
    )).?;
    try std.testing.expect(saturated.valid(
        &reader_page_storage,
        &packet_storage,
    ));
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        saturated.packet_index,
    );
    const saturated_before = saturated;
    try std.testing.expectError(
        error.OggPacketCountOverflow,
        saturated.next(&reader_page_storage, &packet_storage),
    );
    try std.testing.expectEqualDeep(saturated_before, saturated);
}

test "transactional file packet reader preserves destination" {
    var encoded: [70_000]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 0x12345678);
    const source = [_]u8{0xaa} ** 65_100;
    try writer.appendPacket(&source, 65_100, true, true);
    const encoded_bytes = writer.bytes().len;

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "transactional-packet.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        writer.bytes(),
        0,
    );
    try file.setLength(std.testing.io, encoded_bytes);

    var page_scratch: [maximum_page_bytes]u8 = undefined;
    var packet_scratch: [65_100]u8 = undefined;
    const sentinel: [65_100]u8 = @splat(0xa5);
    var destination = sentinel;
    var reader = try FilePacketReader.init(std.testing.io, file);
    const packet = (try reader.nextTransactional(
        &destination,
        &page_scratch,
        &packet_scratch,
    )) orelse return error.TestExpectedOggPacket;
    try std.testing.expectEqualSlices(u8, &source, packet.bytes);
    try std.testing.expectEqual(
        @intFromPtr(destination[0..].ptr),
        @intFromPtr(packet.bytes.ptr),
    );
    try std.testing.expect(
        (try reader.nextTransactional(
            &destination,
            &page_scratch,
            &packet_scratch,
        )) == null,
    );

    reader = try FilePacketReader.init(std.testing.io, file);
    var short_destination: [65_000]u8 = @splat(0xa5);
    const short_destination_before = short_destination;
    const destination_reader_before = reader;
    try std.testing.expectError(
        error.OggPacketBufferTooSmall,
        reader.nextTransactional(
            &short_destination,
            &page_scratch,
            &packet_scratch,
        ),
    );
    try std.testing.expectEqualDeep(destination_reader_before, reader);
    try std.testing.expectEqualSlices(
        u8,
        &short_destination_before,
        &short_destination,
    );
    destination = sentinel;
    _ = (try reader.nextTransactional(
        &destination,
        &page_scratch,
        &packet_scratch,
    )).?;

    reader = try FilePacketReader.init(std.testing.io, file);
    destination = sentinel;
    try std.testing.expectError(
        error.OggPacketBufferTooSmall,
        reader.nextTransactional(
            &destination,
            &page_scratch,
            packet_scratch[0..65_000],
        ),
    );
    try std.testing.expect(reader.page == null);
    try std.testing.expect(reader.page_storage_pointer == null);
    try std.testing.expect(reader.packet_storage_pointer == null);
    try std.testing.expectEqualSlices(u8, &sentinel, &destination);
    _ = (try reader.nextTransactional(
        &destination,
        &page_scratch,
        &packet_scratch,
    )).?;

    reader = try FilePacketReader.init(std.testing.io, file);
    destination = sentinel;
    packet_scratch = @splat(0x3c);
    const packet_scratch_before = packet_scratch;
    const overlap_reader_before = reader;
    try std.testing.expectError(
        error.OverlappingOggPacketStorage,
        reader.nextTransactional(
            packet_scratch[0..],
            &page_scratch,
            &packet_scratch,
        ),
    );
    try std.testing.expectEqualDeep(overlap_reader_before, reader);
    try std.testing.expectEqualSlices(
        u8,
        &packet_scratch_before,
        &packet_scratch,
    );
    try std.testing.expectError(
        error.OverlappingOggPacketStorage,
        reader.nextTransactional(
            &destination,
            &page_scratch,
            page_scratch[0..65_100],
        ),
    );
    try std.testing.expectEqualDeep(overlap_reader_before, reader);
    try std.testing.expectEqualSlices(u8, &sentinel, &destination);

    encoded[encoded_bytes - 1] ^= 1;
    try file.writePositionalAll(
        std.testing.io,
        encoded[0..encoded_bytes],
        0,
    );
    reader = try FilePacketReader.init(std.testing.io, file);
    destination = sentinel;
    const damaged_reader_before = reader;
    try std.testing.expectError(
        error.OggPageChecksumMismatch,
        reader.nextTransactional(
            &destination,
            &page_scratch,
            &packet_scratch,
        ),
    );
    try std.testing.expectEqualDeep(damaged_reader_before, reader);
    try std.testing.expectEqualSlices(u8, &sentinel, &destination);
    encoded[encoded_bytes - 1] ^= 1;
    try file.writePositionalAll(
        std.testing.io,
        encoded[0..encoded_bytes],
        0,
    );

    reader = try FilePacketReader.init(std.testing.io, file);
    try file.setLength(std.testing.io, encoded_bytes - 1);
    destination = sentinel;
    const truncated_reader_before = reader;
    try std.testing.expectError(
        error.TruncatedOggPage,
        reader.nextTransactional(
            &destination,
            &page_scratch,
            &packet_scratch,
        ),
    );
    try std.testing.expectEqualDeep(truncated_reader_before, reader);
    try std.testing.expectEqualSlices(u8, &sentinel, &destination);
}

test "file-backed Ogg packet capacity rollback reloads chained packed BOS pages" {
    var encoded: [1024]u8 = undefined;
    var body: [301]u8 = @splat(0x5a);
    body[0] = 0x11;
    var encoded_bytes = try appendTestOggPage(
        &encoded,
        0,
        16,
        0,
        0x06,
        1,
        &.{1},
        &.{0x01},
    );
    encoded_bytes = try appendTestOggPage(
        &encoded,
        encoded_bytes,
        17,
        0,
        0x06,
        300,
        &.{ 1, 255, 45 },
        &body,
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "packed-capacity.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        encoded[0..encoded_bytes],
        0,
    );
    try file.setLength(std.testing.io, encoded_bytes);

    var reader = try FilePacketReader.initChained(std.testing.io, file);
    var page_storage: [maximum_page_bytes]u8 = undefined;
    var packet_storage: [300]u8 = undefined;
    const prelude = (try reader.next(
        &page_storage,
        packet_storage[0..260],
    )).?;
    try std.testing.expectEqualSlices(u8, &.{0x01}, prelude.bytes);
    try std.testing.expectEqual(
        @as(u32, 0),
        prelude.logical_stream_index,
    );
    const first = (try reader.next(
        &page_storage,
        packet_storage[0..260],
    )).?;
    try std.testing.expectEqualSlices(u8, &.{0x11}, first.bytes);
    try std.testing.expect(first.beginning);
    try std.testing.expectEqual(@as(u32, 1), first.logical_stream_index);

    try std.testing.expectError(
        error.OggPacketBufferTooSmall,
        reader.next(
            &page_storage,
            packet_storage[0..260],
        ),
    );
    try std.testing.expect(reader.page == null);
    try std.testing.expectEqual(@as(usize, 1), reader.reload_segment_index);
    try std.testing.expectEqual(@as(usize, 1), reader.reload_body_offset);
    try std.testing.expect(reader.preserve_logical_index_on_reload);
    try std.testing.expectEqual(@as(u64, 2), reader.packet_index);
    try std.testing.expectEqual(
        @as(u64, 1),
        reader.logical_stream_packet_index,
    );

    const second = (try reader.next(
        &page_storage,
        &packet_storage,
    )).?;
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0x5a} ** 300),
        second.bytes,
    );
    try std.testing.expect(!second.beginning);
    try std.testing.expect(second.end);
    try std.testing.expectEqual(@as(u64, 300), second.granule_position);
    try std.testing.expect(
        (try reader.next(
            &page_storage,
            &packet_storage,
        )) == null,
    );
}

test "Ogg page readers reject invalid cursors without trapping" {
    var encoded: [64]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 7);
    try writer.appendPacket("end", 3, true, true);

    var pages = PageIterator.initChained(writer.bytes());
    _ = try pages.next();
    pages.encoded = encoded[0 .. writer.bytes().len + 1];
    encoded[writer.bytes().len] = 0;
    const ended = pages.ended;
    const logical_stream_index = pages.logical_stream_index;
    try std.testing.expectError(
        error.TruncatedOggPage,
        pages.next(),
    );
    try std.testing.expectEqual(ended, pages.ended);
    try std.testing.expectEqual(
        logical_stream_index,
        pages.logical_stream_index,
    );

    pages.offset = pages.encoded.len + 1;
    try std.testing.expectError(
        error.InvalidOggReaderState,
        pages.next(),
    );

    var impossible_initial = PageIterator.init(writer.bytes());
    impossible_initial.ended = true;
    try std.testing.expect(!impossible_initial.valid());
    const impossible_initial_before = impossible_initial;
    try std.testing.expectError(
        error.InvalidOggReaderState,
        impossible_initial.next(),
    );
    try std.testing.expectEqual(
        impossible_initial_before,
        impossible_initial,
    );

    var impossible_chain = PageIterator.init(writer.bytes());
    impossible_chain.serial_number = 7;
    impossible_chain.expected_sequence = 1;
    impossible_chain.logical_stream_index = 1;
    try std.testing.expect(!impossible_chain.valid());
    try std.testing.expectError(
        error.InvalidOggReaderState,
        impossible_chain.next(),
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "invalid-cursor.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var file_pages = try FilePageReader.init(std.testing.io, file);
    try std.testing.expect(file_pages.valid());
    var storage: [27]u8 = undefined;
    file_pages.limits.max_stream_bytes = std.math.maxInt(u64);
    file_pages.file_size = std.math.maxInt(u64);
    file_pages.offset = std.math.maxInt(u64) - 10;
    try std.testing.expectError(
        error.TruncatedOggPage,
        file_pages.next(&storage),
    );
    try std.testing.expectEqual(
        std.math.maxInt(u64) - 10,
        file_pages.offset,
    );
    file_pages.file_size = 4;
    file_pages.offset = 5;
    try std.testing.expect(!file_pages.valid());
    try std.testing.expectError(
        error.InvalidOggFileReaderState,
        file_pages.next(&storage),
    );
    file_pages.offset = 0;
    file_pages.expected_sequence = 1;
    try std.testing.expect(!file_pages.valid());
    try std.testing.expectError(
        error.InvalidOggFileReaderState,
        file_pages.resynchronize(&storage, 1),
    );
    file_pages.expected_sequence = null;
    file_pages.ended = true;
    try std.testing.expect(!file_pages.valid());
    const impossible_file_before = file_pages;
    try std.testing.expectError(
        error.InvalidOggFileReaderState,
        file_pages.next(&storage),
    );
    try std.testing.expectEqual(impossible_file_before, file_pages);

    var file_packets = try FilePacketReader.init(std.testing.io, file);
    var packet_storage: [1]u8 = undefined;
    try std.testing.expect(file_packets.valid(&storage, &packet_storage));
    file_packets.page_storage_pointer = storage[0..].ptr;
    try std.testing.expect(!file_packets.valid(&storage, &packet_storage));
    try std.testing.expectError(
        error.InvalidOggFilePacketReaderState,
        file_packets.next(&storage, &packet_storage),
    );
    file_packets.page_storage_pointer = null;
    file_packets.packet_bytes = packet_storage.len + 1;
    try std.testing.expect(!file_packets.valid(&storage, &packet_storage));
    try std.testing.expectError(
        error.InvalidOggFilePacketReaderState,
        file_packets.next(&storage, &packet_storage),
    );
    file_packets.packet_bytes = 0;
    file_packets.pages.limits.max_packets = std.math.maxInt(u64);
    file_packets.packet_index = std.math.maxInt(u64);
    file_packets.logical_stream_packet_index =
        std.math.maxInt(u64);
    try std.testing.expect(file_packets.valid(
        &storage,
        &packet_storage,
    ));
    try std.testing.expect(
        (try file_packets.next(&storage, &packet_storage)) == null,
    );
    file_packets.packet_index = 0;
    file_packets.logical_stream_packet_index = 0;
    file_packets.reload_segment_index = std.math.maxInt(usize);
    try std.testing.expect(!file_packets.valid(&storage, &packet_storage));
    try std.testing.expectError(
        error.InvalidOggFilePacketReaderState,
        file_packets.next(&storage, &packet_storage),
    );
}

test "file-backed Ogg writer recovers positional failures" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "recovery.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var page_storage: [maximum_page_bytes]u8 = undefined;
    var faults = OggFileFaults{ .maximum_write_bytes = 3 };
    var writer = try FileWriter.initWithOperations(
        std.testing.io,
        file,
        &page_storage,
        77,
        faults.operations(),
    );
    try writer.appendPacket("one", 1, true, false);
    try std.testing.expect(faults.write_calls > 1);
    const committed_bytes = writer.byte_count;

    faults.maximum_write_bytes = 0;
    faults.fail_write_call = faults.write_calls + 1;
    faults.partial_write_bytes = 2;
    try std.testing.expectError(
        error.InjectedOggWriteFailure,
        writer.appendPacket("two", 2, false, true),
    );
    try std.testing.expect(writer.valid());
    try std.testing.expectEqual(committed_bytes, writer.byte_count);
    try std.testing.expectEqual(
        committed_bytes,
        try file.length(std.testing.io),
    );

    faults.fail_write_call = faults.write_calls + 1;
    faults.fail_set_length_call = faults.set_length_calls + 1;
    faults.partial_write_bytes = 2;
    try std.testing.expectError(
        error.InjectedOggWriteFailure,
        writer.appendPacket("two", 2, false, true),
    );
    try std.testing.expect(!writer.valid());
    try std.testing.expect(writer.recoverable());
    faults.clearFailures();
    try writer.recover();
    try std.testing.expect(writer.valid());
    try writer.appendPacket("two", 2, false, true);
    faults.fail_sync_call = faults.sync_calls + 1;
    try std.testing.expectError(
        error.InjectedOggSyncFailure,
        writer.finalize(),
    );
    try std.testing.expect(writer.recoverable());
    faults.clearFailures();
    try writer.finalize();

    var reader = try FilePacketReader.init(std.testing.io, file);
    var reader_page_storage: [maximum_page_bytes]u8 = undefined;
    var packet_storage: [3]u8 = undefined;
    try std.testing.expectEqualStrings(
        "one",
        (try reader.next(
            &reader_page_storage,
            &packet_storage,
        )).?.bytes,
    );
    try std.testing.expectEqualStrings(
        "two",
        (try reader.next(
            &reader_page_storage,
            &packet_storage,
        )).?.bytes,
    );
    try std.testing.expect(
        (try reader.next(
            &reader_page_storage,
            &packet_storage,
        )) == null,
    );
}

test "file-backed Ogg writer validates before file mutation" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "validation.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, "keep", 0);
    var small_storage: [maximum_page_bytes - 1]u8 = undefined;
    try std.testing.expectError(
        error.OggPageBufferTooSmall,
        FileWriter.init(
            std.testing.io,
            file,
            &small_storage,
            1,
        ),
    );
    try std.testing.expectEqual(
        @as(u64, 4),
        try file.length(std.testing.io),
    );

    var page_storage: [maximum_page_bytes]u8 = undefined;
    var writer = try FileWriter.init(
        std.testing.io,
        file,
        &page_storage,
        1,
    );
    writer.sequence_number = 1;
    const impossible_initial = writer;
    try std.testing.expect(!writer.recoverable());
    try std.testing.expect(!writer.valid());
    try std.testing.expectError(
        error.InvalidOggFileWriterState,
        writer.appendPacket("bad", 0, true, false),
    );
    try std.testing.expectEqualDeep(impossible_initial, writer);
    writer.sequence_number = 0;
    try std.testing.expectError(
        error.OggStreamNotEnded,
        writer.finalize(),
    );
    try std.testing.expectError(
        error.InvalidOggBeginningOfStream,
        writer.appendPacket("bad", 0, false, false),
    );
    try std.testing.expectEqual(@as(u64, 0), writer.byte_count);
    try std.testing.expectEqual(
        @as(u64, 0),
        try file.length(std.testing.io),
    );
    @memcpy(page_storage[100..103], "bad");
    try std.testing.expectError(
        error.OverlappingOggWriterStorage,
        writer.appendPacket(
            page_storage[100..103],
            0,
            true,
            false,
        ),
    );
    try std.testing.expectEqual(@as(u64, 0), writer.byte_count);
    try std.testing.expectError(
        error.OggSizeOverflow,
        packetLayout(std.math.maxInt(usize)),
    );
    writer.began = true;
    writer.byte_count = 1;
    try std.testing.expect(!writer.valid());
    try std.testing.expectError(
        error.InvalidOggFileWriterState,
        writer.recover(),
    );
    writer.byte_count = 28;
    try std.testing.expect(!writer.recoverable());
}

test "Ogg parser rejects corruption and sequence gaps" {
    var encoded: [256]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 7);
    try writer.appendPacket("one", 1, true, false);
    try writer.appendPacket("two", 2, false, true);
    const bytes = writer.bytes();
    var corrupt: [256]u8 = undefined;
    @memcpy(corrupt[0..bytes.len], bytes);
    corrupt[bytes.len - 1] ^= 1;
    var corrupt_pages = PageIterator.init(corrupt[0..bytes.len]);
    _ = try corrupt_pages.next();
    try std.testing.expectError(
        error.OggPageChecksumMismatch,
        corrupt_pages.next(),
    );

    @memcpy(corrupt[0..bytes.len], bytes);
    const second_page = 27 + 1 + 3;
    std.mem.writeInt(
        u32,
        corrupt[second_page + 18 ..][0..4],
        9,
        .little,
    );
    @memset(corrupt[second_page + 22 ..][0..4], 0);
    std.mem.writeInt(
        u32,
        corrupt[second_page + 22 ..][0..4],
        pageChecksum(corrupt[second_page..bytes.len]),
        .little,
    );
    var gap_pages = PageIterator.init(corrupt[0..bytes.len]);
    _ = try gap_pages.next();
    try std.testing.expectError(
        error.InvalidOggPageSequence,
        gap_pages.next(),
    );
}

test "Ogg readers reject single-bit page damage transactionally" {
    var clean: [128]u8 = undefined;
    const page_bytes = try appendTestOggPage(
        &clean,
        0,
        0x1020_3040,
        0,
        0x06,
        4,
        &.{4},
        "data",
    );

    for (0..page_bytes) |byte_index| {
        var damaged = clean;
        damaged[byte_index] ^= 1;
        const encoded = damaged[0..page_bytes];

        var pages = PageIterator.init(encoded);
        const pages_before = pages;
        const page_rejected = if (pages.next()) |_|
            false
        else |_|
            true;
        try std.testing.expect(page_rejected);
        try std.testing.expectEqualDeep(pages_before, pages);

        var packet_storage: [4]u8 = @splat(0xa5);
        var packets = PacketIterator.init(
            encoded,
            &packet_storage,
        );
        const packets_before = packets;
        const packet_rejected = if (packets.next()) |_|
            false
        else |_|
            true;
        try std.testing.expect(packet_rejected);
        try std.testing.expectEqualDeep(packets_before, packets);
        try std.testing.expectEqualSlices(
            u8,
            &@as([4]u8, @splat(0xa5)),
            &packet_storage,
        );
    }

    for (1..page_bytes) |truncated_bytes| {
        const encoded = clean[0..truncated_bytes];

        var pages = PageIterator.init(encoded);
        const pages_before = pages;
        try std.testing.expectError(
            error.TruncatedOggPage,
            pages.next(),
        );
        try std.testing.expectEqualDeep(pages_before, pages);

        var packet_storage: [4]u8 = @splat(0xa5);
        var packets = PacketIterator.init(
            encoded,
            &packet_storage,
        );
        const packets_before = packets;
        try std.testing.expectError(
            error.TruncatedOggPage,
            packets.next(),
        );
        try std.testing.expectEqualDeep(packets_before, packets);
        try std.testing.expectEqualSlices(
            u8,
            &@as([4]u8, @splat(0xa5)),
            &packet_storage,
        );
    }
}

test "Ogg page parsing is transactional across checksum-valid mutations" {
    var clean: [256]u8 = undefined;
    var stream_bytes = try appendTestOggPage(
        &clean,
        0,
        0x1020_3040,
        0,
        0x02,
        4,
        &.{4},
        "head",
    );
    const second_offset = stream_bytes;
    stream_bytes = try appendTestOggPage(
        &clean,
        stream_bytes,
        0x1020_3040,
        1,
        0x04,
        8,
        &.{ 3, 6 },
        "tail-data",
    );

    const mutation_masks = [_]u8{ 0x01, 0x80, 0xff };
    for (second_offset..stream_bytes) |byte_index| {
        for (mutation_masks) |mask| {
            var candidate = clean;
            candidate[byte_index] ^= mask;
            const second_page = candidate[second_offset..stream_bytes];
            std.mem.writeInt(
                u32,
                second_page[22..26],
                pageChecksum(second_page),
                .little,
            );

            var pages = PageIterator.init(candidate[0..stream_bytes]);
            _ = try pages.next();
            const pages_before = pages;
            if (pages.next()) |maybe_page| {
                const page = maybe_page orelse
                    return error.UnexpectedOggEndOfStream;
                try std.testing.expect(pages.offset > pages_before.offset);
                try std.testing.expect(pages.offset <= stream_bytes);
                try std.testing.expectEqual(
                    @as(u64, second_offset),
                    page.byte_offset,
                );
                try std.testing.expectEqual(
                    @as(u64, pages.offset - second_offset),
                    page.byte_length,
                );
                var body_bytes: usize = 0;
                for (page.lacing_values) |value| body_bytes += value;
                try std.testing.expectEqual(body_bytes, page.body.len);
            } else |_| {
                try std.testing.expectEqualDeep(pages_before, pages);
            }
        }
    }
}

test "file-backed Ogg readers reject single-bit page damage transactionally" {
    var clean: [128]u8 = undefined;
    const page_bytes = try appendTestOggPage(
        &clean,
        0,
        0x1020_3040,
        0,
        0x06,
        4,
        &.{4},
        "data",
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "damaged.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var page_storage: [maximum_page_bytes]u8 = undefined;
    const destination_sentinel: [128]u8 = @splat(0xa5);

    try file.writePositionalAll(
        std.testing.io,
        clean[0..page_bytes],
        0,
    );
    var transactional_pages = try FilePageReader.init(
        std.testing.io,
        file,
    );
    var transactional_storage = destination_sentinel;
    const transactional_page = (try transactional_pages.nextTransactional(
        &transactional_storage,
        &page_storage,
    )) orelse return error.TestExpectedOggPage;
    try std.testing.expectEqualSlices(u8, &.{4}, transactional_page.lacing_values);
    try std.testing.expectEqualStrings("data", transactional_page.body);
    try std.testing.expectEqual(
        @intFromPtr(transactional_storage[27..].ptr),
        @intFromPtr(transactional_page.lacing_values.ptr),
    );
    try std.testing.expect(
        (try transactional_pages.nextTransactional(
            &transactional_storage,
            &page_storage,
        )) == null,
    );

    for (0..page_bytes) |byte_index| {
        var damaged = clean;
        damaged[byte_index] ^= 1;
        try file.setLength(std.testing.io, page_bytes);
        try file.writePositionalAll(
            std.testing.io,
            damaged[0..page_bytes],
            0,
        );

        var pages = try FilePageReader.init(
            std.testing.io,
            file,
        );
        const pages_before = pages;
        const page_rejected =
            if (pages.next(&page_storage)) |_|
                false
            else |_|
                true;
        try std.testing.expect(page_rejected);
        try std.testing.expectEqualDeep(pages_before, pages);

        transactional_pages = try FilePageReader.init(
            std.testing.io,
            file,
        );
        transactional_storage = destination_sentinel;
        const transactional_before = transactional_pages;
        const transactional_rejected =
            if (transactional_pages.nextTransactional(
                &transactional_storage,
                &page_storage,
            )) |_|
                false
            else |_|
                true;
        try std.testing.expect(transactional_rejected);
        try std.testing.expectEqualDeep(
            transactional_before,
            transactional_pages,
        );
        try std.testing.expectEqualSlices(
            u8,
            &destination_sentinel,
            &transactional_storage,
        );

        var packet_storage: [4]u8 = @splat(0xa5);
        var packets = try FilePacketReader.init(
            std.testing.io,
            file,
        );
        const packets_before = packets;
        const packet_rejected =
            if (packets.next(
                &page_storage,
                &packet_storage,
            )) |_|
                false
            else |_|
                true;
        try std.testing.expect(packet_rejected);
        try std.testing.expectEqualDeep(
            packets_before,
            packets,
        );
        try std.testing.expectEqualSlices(
            u8,
            &@as([4]u8, @splat(0xa5)),
            &packet_storage,
        );
    }

    for (1..page_bytes) |truncated_bytes| {
        try file.setLength(std.testing.io, page_bytes);
        try file.writePositionalAll(
            std.testing.io,
            clean[0..page_bytes],
            0,
        );
        try file.setLength(std.testing.io, truncated_bytes);

        var pages = try FilePageReader.init(
            std.testing.io,
            file,
        );
        const pages_before = pages;
        try std.testing.expectError(
            error.TruncatedOggPage,
            pages.next(&page_storage),
        );
        try std.testing.expectEqualDeep(pages_before, pages);

        transactional_pages = try FilePageReader.init(
            std.testing.io,
            file,
        );
        transactional_storage = destination_sentinel;
        const transactional_before = transactional_pages;
        try std.testing.expectError(
            error.TruncatedOggPage,
            transactional_pages.nextTransactional(
                &transactional_storage,
                &page_storage,
            ),
        );
        try std.testing.expectEqualDeep(
            transactional_before,
            transactional_pages,
        );
        try std.testing.expectEqualSlices(
            u8,
            &destination_sentinel,
            &transactional_storage,
        );

        var packet_storage: [4]u8 = @splat(0xa5);
        var packets = try FilePacketReader.init(
            std.testing.io,
            file,
        );
        const packets_before = packets;
        try std.testing.expectError(
            error.TruncatedOggPage,
            packets.next(
                &page_storage,
                &packet_storage,
            ),
        );
        try std.testing.expectEqualDeep(
            packets_before,
            packets,
        );
        try std.testing.expectEqualSlices(
            u8,
            &@as([4]u8, @splat(0xa5)),
            &packet_storage,
        );
    }

    transactional_pages = try FilePageReader.init(
        std.testing.io,
        file,
    );
    transactional_storage = destination_sentinel;
    try std.testing.expectError(
        error.OverlappingOggPageStorage,
        transactional_pages.nextTransactional(
            transactional_storage[0..64],
            transactional_storage[32..96],
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &destination_sentinel,
        &transactional_storage,
    );
}

test "Ogg page readers resynchronize across bounded inserted junk" {
    var clean: [256]u8 = undefined;
    var clean_bytes = try appendTestOggPage(
        &clean,
        0,
        55,
        0,
        0x02,
        1,
        &.{3},
        "one",
    );
    const second_offset = clean_bytes;
    clean_bytes = try appendTestOggPage(
        &clean,
        clean_bytes,
        55,
        1,
        0,
        2,
        &.{3},
        "two",
    );
    const third_offset = clean_bytes;
    clean_bytes = try appendTestOggPage(
        &clean,
        clean_bytes,
        55,
        2,
        0x04,
        3,
        &.{5},
        "three",
    );
    const junk = [_]u8{ 'O', 'g', 'g', 'S', 0xff, 0x5a };
    var damaged: [clean.len + junk.len]u8 = undefined;
    @memcpy(damaged[0..second_offset], clean[0..second_offset]);
    @memcpy(
        damaged[second_offset..][0..junk.len],
        &junk,
    );
    @memcpy(
        damaged[second_offset + junk.len ..][0 .. clean_bytes - second_offset],
        clean[second_offset..clean_bytes],
    );
    const damaged_bytes =
        damaged[0 .. clean_bytes + junk.len];

    var pages = PageIterator.init(damaged_bytes);
    try std.testing.expectEqual(
        @as(u32, 0),
        (try pages.next()).?.sequence_number,
    );
    const retained_pages = pages;
    try std.testing.expectError(
        error.UnsupportedOggVersion,
        pages.next(),
    );
    try std.testing.expectEqual(retained_pages.offset, pages.offset);
    try std.testing.expectError(
        error.InvalidOggResynchronizationLimit,
        pages.resynchronize(0),
    );
    try std.testing.expectError(
        error.OggResynchronizationLimitReached,
        pages.resynchronize(junk.len - 1),
    );
    try std.testing.expectEqual(retained_pages.offset, pages.offset);
    try std.testing.expectEqual(
        junk.len,
        try pages.resynchronize(junk.len),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        (try pages.next()).?.sequence_number,
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        (try pages.next()).?.sequence_number,
    );
    try std.testing.expect((try pages.next()) == null);

    var packet_storage: [5]u8 = undefined;
    var packets = PacketIterator.init(
        damaged_bytes,
        &packet_storage,
    );
    try std.testing.expectEqualStrings(
        "one",
        (try packets.next()).?.bytes,
    );
    const retained_packets = packets;
    try std.testing.expectError(
        error.UnsupportedOggVersion,
        packets.next(),
    );
    try std.testing.expectEqual(
        retained_packets.packet_index,
        packets.packet_index,
    );
    try std.testing.expectEqual(
        junk.len,
        try packets.resynchronize(junk.len),
    );
    try std.testing.expectEqualStrings(
        "two",
        (try packets.next()).?.bytes,
    );
    try std.testing.expectEqualStrings(
        "three",
        (try packets.next()).?.bytes,
    );
    try std.testing.expect((try packets.next()) == null);
    try std.testing.expectEqual(
        @as(u64, 3),
        packets.packet_index,
    );

    var packed_encoded: [64]u8 = undefined;
    const packed_bytes = try appendTestOggPage(
        &packed_encoded,
        0,
        56,
        0,
        0x06,
        2,
        &.{ 3, 3 },
        "onetwo",
    );
    var packed_storage: [3]u8 = undefined;
    var packed_packets = PacketIterator.init(
        packed_encoded[0..packed_bytes],
        &packed_storage,
    );
    _ = try packed_packets.next();
    try std.testing.expectError(
        error.OggPacketResynchronizationRequiresPageBoundary,
        packed_packets.resynchronize(1),
    );
    try std.testing.expectEqualStrings(
        "two",
        (try packed_packets.next()).?.bytes,
    );

    var corrupt: [clean.len]u8 = undefined;
    @memcpy(corrupt[0..clean_bytes], clean[0..clean_bytes]);
    corrupt[third_offset - 1] ^= 1;
    var corrupt_pages = PageIterator.init(
        corrupt[0..clean_bytes],
    );
    _ = try corrupt_pages.next();
    try std.testing.expectError(
        error.OggPageChecksumMismatch,
        corrupt_pages.next(),
    );
    try std.testing.expectError(
        error.OggResynchronizationLimitReached,
        corrupt_pages.resynchronize(
            clean_bytes - second_offset,
        ),
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "resynchronize.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        damaged_bytes,
        0,
    );
    var file_pages = try FilePageReader.init(
        std.testing.io,
        file,
    );
    var page_storage: [maximum_page_bytes]u8 = undefined;
    _ = try file_pages.next(&page_storage);
    const retained_file_pages = file_pages;
    try std.testing.expectError(
        error.UnsupportedOggVersion,
        file_pages.next(&page_storage),
    );
    try std.testing.expectEqual(
        retained_file_pages.offset,
        file_pages.offset,
    );
    try std.testing.expectError(
        error.OggResynchronizationLimitReached,
        file_pages.resynchronize(
            &page_storage,
            junk.len - 1,
        ),
    );
    try std.testing.expectEqual(
        retained_file_pages.offset,
        file_pages.offset,
    );
    try std.testing.expectError(
        error.InvalidOggResynchronizationLimit,
        file_pages.resynchronize(&page_storage, 0),
    );
    var short_page_storage: [maximum_page_bytes - 1]u8 = undefined;
    try std.testing.expectError(
        error.OggPageBufferTooSmall,
        file_pages.resynchronize(
            &short_page_storage,
            junk.len,
        ),
    );
    try std.testing.expectEqual(
        junk.len,
        try file_pages.resynchronize(
            &page_storage,
            junk.len,
        ),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        (try file_pages.next(&page_storage)).?.sequence_number,
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        (try file_pages.next(&page_storage)).?.sequence_number,
    );
    try std.testing.expect(
        (try file_pages.next(&page_storage)) == null,
    );

    var file_packets = try FilePacketReader.init(
        std.testing.io,
        file,
    );
    var file_packet_storage: [5]u8 = undefined;
    try std.testing.expectEqualStrings(
        "one",
        (try file_packets.next(
            &page_storage,
            &file_packet_storage,
        )).?.bytes,
    );
    const retained_file_packets = file_packets;
    try std.testing.expectError(
        error.UnsupportedOggVersion,
        file_packets.next(
            &page_storage,
            &file_packet_storage,
        ),
    );
    try std.testing.expectEqual(
        retained_file_packets.packet_index,
        file_packets.packet_index,
    );
    var other_page_storage: [maximum_page_bytes]u8 = undefined;
    try std.testing.expectError(
        error.OggReaderStorageChanged,
        file_packets.resynchronize(
            &other_page_storage,
            &file_packet_storage,
            junk.len,
        ),
    );
    var reload_pending = file_packets;
    reload_pending.page = null;
    reload_pending.segment_index = 0;
    reload_pending.body_offset = 0;
    reload_pending.reload_segment_index = 1;
    reload_pending.reload_body_offset = 1;
    reload_pending.preserve_logical_index_on_reload = true;
    try std.testing.expectError(
        error.OggPacketResynchronizationRequiresPageBoundary,
        reload_pending.resynchronize(
            &page_storage,
            &file_packet_storage,
            junk.len,
        ),
    );
    try std.testing.expectEqual(
        junk.len,
        try file_packets.resynchronize(
            &page_storage,
            &file_packet_storage,
            junk.len,
        ),
    );
    try std.testing.expectEqualStrings(
        "two",
        (try file_packets.next(
            &page_storage,
            &file_packet_storage,
        )).?.bytes,
    );
    try std.testing.expectEqualStrings(
        "three",
        (try file_packets.next(
            &page_storage,
            &file_packet_storage,
        )).?.bytes,
    );
    try std.testing.expect(
        (try file_packets.next(
            &page_storage,
            &file_packet_storage,
        )) == null,
    );
    try std.testing.expectEqual(
        @as(u64, 3),
        file_packets.packet_index,
    );
}

test "Ogg writer preserves empty packets and fails transactionally" {
    var too_small: [27]u8 = undefined;
    var failed_writer = StreamWriter.init(&too_small, 1);
    try std.testing.expectError(
        error.OggOutputTooSmall,
        failed_writer.appendPacket("", 0, true, true),
    );
    try std.testing.expectEqual(@as(usize, 0), failed_writer.byte_count);
    try std.testing.expect(!failed_writer.began);

    var overlap_storage: [128]u8 = @splat(0x5a);
    const overlap_untouched = overlap_storage;
    var overlap_writer = StreamWriter.init(&overlap_storage, 2);
    try std.testing.expectError(
        error.OverlappingOggWriterStorage,
        overlap_writer.appendPacket(
            overlap_storage[64..68],
            0,
            true,
            true,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), overlap_writer.byte_count);
    try std.testing.expect(!overlap_writer.began);
    try std.testing.expectEqualSlices(
        u8,
        &overlap_untouched,
        &overlap_storage,
    );

    var encoded: [128]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 2);
    try writer.appendPacket("", 0, true, false);
    try writer.appendPacket("data", 4, false, true);
    var impossible_page_count = writer;
    impossible_page_count.sequence_number +%= 1;
    const impossible_page_count_before = impossible_page_count;
    try std.testing.expect(!impossible_page_count.valid());
    try std.testing.expectError(
        error.InvalidOggStreamWriterState,
        impossible_page_count.appendPacket("more", 5, false, true),
    );
    try std.testing.expectEqualDeep(
        impossible_page_count_before,
        impossible_page_count,
    );
    var impossible_end = StreamWriter.init(&encoded, 2);
    impossible_end.ended = true;
    try std.testing.expect(!impossible_end.valid());
    var storage: [4]u8 = undefined;
    var packets = PacketIterator.init(writer.bytes(), &storage);
    try std.testing.expectEqual(@as(usize, 0), (try packets.next()).?.bytes.len);
    try std.testing.expectEqualStrings("data", (try packets.next()).?.bytes);

    writer.byte_count = std.math.maxInt(usize);
    try std.testing.expect(!writer.valid());
    try std.testing.expectEqual(@as(usize, 0), writer.bytes().len);
    try std.testing.expectError(
        error.InvalidOggStreamWriterState,
        writer.appendPacket("more", 5, false, true),
    );
    try std.testing.expectEqual(std.math.maxInt(usize), writer.byte_count);
}

test "Ogg chained readers restart logical stream sequencing" {
    var first_encoded: [128]u8 = undefined;
    var first_writer = StreamWriter.init(&first_encoded, 11);
    try first_writer.appendPacket("first", 5, true, true);
    var second_encoded: [128]u8 = undefined;
    var second_writer = StreamWriter.init(&second_encoded, 22);
    try second_writer.appendPacket("second", 6, true, true);
    var chained_encoded: [256]u8 = undefined;
    const first_bytes = first_writer.bytes();
    const second_bytes = second_writer.bytes();
    @memcpy(chained_encoded[0..first_bytes.len], first_bytes);
    @memcpy(
        chained_encoded[first_bytes.len..][0..second_bytes.len],
        second_bytes,
    );
    const chained =
        chained_encoded[0 .. first_bytes.len + second_bytes.len];

    var strict_storage: [6]u8 = undefined;
    var strict = PacketIterator.init(chained, &strict_storage);
    try std.testing.expectEqualStrings(
        "first",
        (try strict.next()).?.bytes,
    );
    try std.testing.expectError(
        error.OggDataAfterEndOfStream,
        strict.next(),
    );

    var storage: [6]u8 = undefined;
    var packets = PacketIterator.initChained(chained, &storage);
    const first = (try packets.next()).?;
    try std.testing.expect(first.beginning);
    try std.testing.expect(first.end);
    try std.testing.expectEqual(@as(u32, 0), first.logical_stream_index);
    try std.testing.expectEqualStrings("first", first.bytes);
    const second = (try packets.next()).?;
    try std.testing.expect(second.beginning);
    try std.testing.expect(second.end);
    try std.testing.expectEqual(@as(u32, 1), second.logical_stream_index);
    try std.testing.expectEqualStrings("second", second.bytes);
    try std.testing.expect((try packets.next()) == null);

    var malformed = chained_encoded;
    malformed[first_bytes.len + 5] &= ~@as(u8, 0x02);
    @memset(malformed[first_bytes.len + 22 ..][0..4], 0);
    std.mem.writeInt(
        u32,
        malformed[first_bytes.len + 22 ..][0..4],
        pageChecksum(
            malformed[first_bytes.len .. first_bytes.len + second_bytes.len],
        ),
        .little,
    );
    var malformed_pages = PageIterator.initChained(
        malformed[0 .. first_bytes.len + second_bytes.len],
    );
    _ = try malformed_pages.next();
    try std.testing.expectError(
        error.MissingOggBeginningOfStream,
        malformed_pages.next(),
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "chained.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, chained, 0);
    try file.setLength(std.testing.io, chained.len);
    var file_reader = try FilePacketReader.initChained(
        std.testing.io,
        file,
    );
    var page_storage: [maximum_page_bytes]u8 = undefined;
    var file_packet_storage: [6]u8 = undefined;
    const file_first = (try file_reader.next(
        &page_storage,
        &file_packet_storage,
    )).?;
    try std.testing.expectEqual(@as(u32, 0), file_first.logical_stream_index);
    const file_second = (try file_reader.next(
        &page_storage,
        &file_packet_storage,
    )).?;
    try std.testing.expectEqual(@as(u32, 1), file_second.logical_stream_index);
    try std.testing.expectEqualStrings("second", file_second.bytes);
    try std.testing.expect(
        (try file_reader.next(
            &page_storage,
            &file_packet_storage,
        )) == null,
    );
}

test "Vorbis identification validates declared stream properties" {
    var packet: [30]u8 = @splat(0);
    packet[0] = 1;
    @memcpy(packet[1..7], "vorbis");
    packet[11] = 2;
    std.mem.writeInt(u32, packet[12..16], 48_000, .little);
    packet[28] = 0xb8;
    packet[29] = 1;
    const info = try VorbisIdentification.parse(&packet);
    try std.testing.expectEqual(@as(u16, 256), info.small_block_size);
    try std.testing.expectEqual(@as(u16, 2048), info.large_block_size);
    packet[29] = 0;
    try std.testing.expectError(
        error.InvalidVorbisIdentificationHeader,
        VorbisIdentification.parse(&packet),
    );
}

test "Vorbis identification encoding round trips transactionally" {
    const expected = VorbisIdentification{
        .channel_count = 6,
        .sample_rate = 96_000,
        .bitrate_maximum = 640_000,
        .bitrate_nominal = 384_000,
        .bitrate_minimum = -1,
        .small_block_size = 256,
        .large_block_size = 4_096,
    };
    var destination: [30]u8 = @splat(0xaa);
    const encoded = try encodeVorbisIdentificationPacket(
        &destination,
        expected,
    );
    try std.testing.expectEqualDeep(
        expected,
        try VorbisIdentification.parse(encoded),
    );

    const before = destination;
    var invalid = expected;
    invalid.small_block_size = 192;
    try std.testing.expectError(
        error.InvalidVorbisIdentification,
        encodeVorbisIdentificationPacket(&destination, invalid),
    );
    try std.testing.expectEqualSlices(u8, &before, &destination);
    try std.testing.expectError(
        error.VorbisIdentificationOutputTooSmall,
        encodeVorbisIdentificationPacket(
            destination[0..29],
            expected,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &destination);
    try std.testing.expectError(
        error.InvalidVorbisBlockSize,
        vorbisBlockExponent(0),
    );
    try std.testing.expectError(
        error.InvalidVorbisBlockSize,
        vorbisBlockExponent(63),
    );
    try std.testing.expectError(
        error.InvalidVorbisBlockSize,
        vorbisBlockExponent(16_384),
    );
}

test "Ogg Vorbis logical stream decodes to granule-trimmed PCM" {
    var identification_packet = [_]u8{0} ** 30;
    identification_packet[0] = 1;
    @memcpy(identification_packet[1..7], "vorbis");
    identification_packet[11] = 1;
    std.mem.writeInt(
        u32,
        identification_packet[12..16],
        48_000,
        .little,
    );
    identification_packet[28] = 0x66;
    identification_packet[29] = 1;
    var comment_packet = [_]u8{0} ** 16;
    comment_packet[0] = 3;
    @memcpy(comment_packet[1..7], "vorbis");
    comment_packet[15] = 1;
    var setup_packet_storage: [128]u8 = undefined;
    const setup_packet = makeTestVorbisSetup(
        &setup_packet_storage,
        .unordered,
        false,
        false,
    );

    var encoded: [1024]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 0x564F_5242);
    try writer.appendPacket(&identification_packet, 0, true, false);
    try writer.appendPacket(&comment_packet, 0, false, false);
    try writer.appendPacket(setup_packet.bytes, 0, false, false);
    try writer.appendPacket(&.{0}, 0, false, false);
    try writer.appendPacket(&.{0}, 32, false, true);
    try std.testing.expectEqual(
        @as(usize, 2),
        try requiredVorbisSeekPoints(writer.bytes()),
    );
    var seek_points: [2]VorbisSeekPoint = undefined;
    const seek_index = try buildVorbisSeekIndex(
        writer.bytes(),
        &seek_points,
    );
    try std.testing.expectEqual(@as(i64, 0), seek_index[0].pcm_end);
    try std.testing.expectEqual(@as(u64, 3), seek_index[0].packet.logical_packet_index);
    try std.testing.expectEqual(@as(i64, 32), seek_index[1].pcm_end);
    try std.testing.expectEqual(
        seek_index[0].packet.byte_offset,
        seek_index[1].decode.byte_offset,
    );
    try std.testing.expectEqualDeep(
        seek_index[0],
        try findVorbisSeekPoint(seek_index, 0, 16),
    );
    try std.testing.expectEqualDeep(
        seek_index[1],
        try findVorbisSeekPoint(seek_index, 0, 32),
    );
    try std.testing.expectError(
        error.VorbisSeekLogicalStreamNotFound,
        findVorbisSeekPoint(seek_index, 1, 0),
    );
    var short_seek_index = [_]VorbisSeekPoint{.{
        .pcm_end = 99,
        .decode = seek_index[0].decode,
        .packet = seek_index[0].packet,
    }};
    try std.testing.expectError(
        error.VorbisSeekIndexTooSmall,
        buildVorbisSeekIndex(writer.bytes(), &short_seek_index),
    );
    try std.testing.expectEqual(@as(i64, 99), short_seek_index[0].pcm_end);

    var packet_storage: [128]u8 = undefined;
    var packets = PacketIterator.init(writer.bytes(), &packet_storage);
    const encoded_identification = (try packets.next()).?;
    const identification =
        try VorbisIdentification.parse(encoded_identification.bytes);
    const encoded_comments = (try packets.next()).?;
    var comments = try VorbisCommentIterator.init(encoded_comments.bytes);
    try std.testing.expectEqual(@as(usize, 0), comments.vendor.len);
    try std.testing.expect((try comments.next()) == null);
    const encoded_setup = (try packets.next()).?;
    var codebooks: [1]VorbisCodebook = undefined;
    var entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var modes: [1]VorbisMode = undefined;
    const setup = try parseVorbisSetup(
        encoded_setup.bytes,
        identification.channel_count,
        .{
            .codebooks = &codebooks,
            .codebook_entries = &entries,
            .huffman_nodes = &nodes,
            .codebook_multiplicands = &multiplicands,
            .floors = &floors,
            .residues = &residues,
            .mappings = &mappings,
            .modes = &modes,
        },
    );

    var decoder = VorbisPcmStreamDecoder(f32, 1, 64, 64).init();
    var spectra: [32]f32 = undefined;
    var floor_curves: [32]f32 = undefined;
    var coupling: [32]f32 = undefined;
    var time: [64]f32 = undefined;
    var classifications: [1]u8 = undefined;
    var windowed: [64]f32 = undefined;
    const first_audio = (try packets.next()).?;
    var empty_output: [0]f32 = .{};
    const empty_outputs = [_][]f32{&empty_output};
    const first_result = try decoder.decode(
        first_audio,
        identification,
        setup,
        &empty_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &windowed,
        },
    );
    try std.testing.expectEqual(@as(usize, 0), first_result.sample_count);

    const final_audio = (try packets.next()).?;
    var output = [_]f32{99} ** 32;
    const outputs = [_][]f32{&output};
    const final_result = try decoder.decode(
        final_audio,
        identification,
        setup,
        &outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &windowed,
        },
    );
    try std.testing.expectEqual(@as(usize, 32), final_result.sample_count);
    try std.testing.expectEqual(@as(?i64, 0), final_result.pcm_start);
    try std.testing.expectEqual(@as(?i64, 32), final_result.pcm_end);
    try std.testing.expectEqualSlices(f32, &([_]f32{0} ** 32), &output);
    var pcm_seek = VorbisPcmSeekCursor.init(16);
    const selected = try pcm_seek.select(final_result);
    try std.testing.expectEqual(@as(usize, 16), selected.source_start);
    try std.testing.expectEqual(@as(usize, 16), selected.sample_count);
    try std.testing.expectEqual(@as(?i64, 16), selected.pcm_start);
    try std.testing.expectEqual(@as(?i64, 32), selected.pcm_end);
    var unavailable_result = final_result;
    unavailable_result.pcm_start = null;
    var unavailable_seek = VorbisPcmSeekCursor.init(16);
    try std.testing.expectError(
        error.VorbisPcmSeekPositionUnavailable,
        unavailable_seek.select(unavailable_result),
    );
    try std.testing.expect(!unavailable_seek.reached);
    var inconsistent_result = final_result;
    inconsistent_result.pcm_end = 31;
    var inconsistent_seek = VorbisPcmSeekCursor.init(16);
    try std.testing.expectError(
        error.InvalidVorbisPcmSeekRange,
        inconsistent_seek.select(inconsistent_result),
    );
    try std.testing.expect(!inconsistent_seek.reached);
    var boundary_seek = VorbisPcmSeekCursor.init(32);
    const boundary = try boundary_seek.select(final_result);
    try std.testing.expectEqual(@as(usize, 32), boundary.source_start);
    try std.testing.expectEqual(@as(usize, 0), boundary.sample_count);
    try std.testing.expect(boundary_seek.reached);
    try std.testing.expect((try packets.next()) == null);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "seek.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, writer.bytes(), 0);
    try file.setLength(std.testing.io, writer.bytes().len);
    var page_storage: [maximum_page_bytes]u8 = undefined;
    try std.testing.expectEqual(
        @as(usize, 2),
        try requiredVorbisFileSeekPoints(
            std.testing.io,
            file,
            &page_storage,
        ),
    );
    var file_seek_points: [2]VorbisSeekPoint = undefined;
    const file_index = try buildVorbisFileSeekIndex(
        std.testing.io,
        file,
        &page_storage,
        &file_seek_points,
    );
    try std.testing.expectEqualSlices(
        VorbisSeekPoint,
        seek_index,
        file_index,
    );

    var transactional_file_seek_points: [2]VorbisSeekPoint = undefined;
    var file_seek_scratch: [2]VorbisSeekPoint = undefined;
    const transactional_file_index =
        try buildVorbisFileSeekIndexTransactional(
            std.testing.io,
            file,
            &page_storage,
            &transactional_file_seek_points,
            &file_seek_scratch,
        );
    try std.testing.expectEqualSlices(
        VorbisSeekPoint,
        seek_index,
        transactional_file_index,
    );
    try std.testing.expectEqual(
        @intFromPtr(transactional_file_seek_points[0..].ptr),
        @intFromPtr(transactional_file_index.ptr),
    );

    const seek_sentinel = VorbisSeekPoint{
        .pcm_end = 99,
        .decode = seek_index[0].decode,
        .packet = seek_index[0].packet,
    };
    var short_file_seek_destination = [_]VorbisSeekPoint{seek_sentinel};
    const short_file_seek_before = short_file_seek_destination;
    try std.testing.expectError(
        error.VorbisSeekIndexTooSmall,
        buildVorbisFileSeekIndexTransactional(
            std.testing.io,
            file,
            &page_storage,
            &short_file_seek_destination,
            &file_seek_scratch,
        ),
    );
    try std.testing.expectEqual(
        short_file_seek_before,
        short_file_seek_destination,
    );

    transactional_file_seek_points = @splat(seek_sentinel);
    const transactional_file_seek_before =
        transactional_file_seek_points;
    var short_file_seek_scratch: [1]VorbisSeekPoint = undefined;
    try std.testing.expectError(
        error.VorbisSeekIndexTooSmall,
        buildVorbisFileSeekIndexTransactional(
            std.testing.io,
            file,
            &page_storage,
            &transactional_file_seek_points,
            &short_file_seek_scratch,
        ),
    );
    try std.testing.expectEqual(
        transactional_file_seek_before,
        transactional_file_seek_points,
    );

    var aliased_file_seek_points = [_]VorbisSeekPoint{seek_sentinel} ** 3;
    const aliased_file_seek_before = aliased_file_seek_points;
    try std.testing.expectError(
        error.OverlappingVorbisSeekStorage,
        buildVorbisFileSeekIndexTransactional(
            std.testing.io,
            file,
            &page_storage,
            aliased_file_seek_points[0..2],
            aliased_file_seek_points[1..3],
        ),
    );
    try std.testing.expectEqual(
        aliased_file_seek_before,
        aliased_file_seek_points,
    );

    var aliased_page_storage: [maximum_page_bytes]u8 align(@alignOf(VorbisSeekPoint)) = undefined;
    const page_aliased_seek_scratch = std.mem.bytesAsSlice(
        VorbisSeekPoint,
        aliased_page_storage[0 .. 2 * @sizeOf(VorbisSeekPoint)],
    );
    transactional_file_seek_points = @splat(seek_sentinel);
    const page_alias_destination_before =
        transactional_file_seek_points;
    try std.testing.expectError(
        error.OverlappingVorbisSeekStorage,
        buildVorbisFileSeekIndexTransactional(
            std.testing.io,
            file,
            &aliased_page_storage,
            &transactional_file_seek_points,
            page_aliased_seek_scratch,
        ),
    );
    try std.testing.expectEqual(
        page_alias_destination_before,
        transactional_file_seek_points,
    );

    transactional_file_seek_points = @splat(seek_sentinel);
    const truncated_file_seek_before = transactional_file_seek_points;
    try file.setLength(std.testing.io, writer.bytes().len - 1);
    try std.testing.expectError(
        error.TruncatedOggPage,
        buildVorbisFileSeekIndexTransactional(
            std.testing.io,
            file,
            &page_storage,
            &transactional_file_seek_points,
            &file_seek_scratch,
        ),
    );
    try std.testing.expectEqual(
        truncated_file_seek_before,
        transactional_file_seek_points,
    );
    try file.setLength(std.testing.io, writer.bytes().len);
    try file.writePositionalAll(std.testing.io, writer.bytes(), 0);

    var file_packets = try FilePacketReader.init(
        std.testing.io,
        file,
    );
    var invalid_point = file_index[1];
    invalid_point.decode.sequence_number += 1;
    try std.testing.expectError(
        error.InvalidVorbisSeekPoint,
        file_packets.seek(invalid_point),
    );
    try std.testing.expectEqual(@as(u64, 0), file_packets.pages.offset);
    try file_packets.seek(file_index[1]);
    var file_packet_storage: [128]u8 = undefined;
    const seek_prime = (try file_packets.next(
        &page_storage,
        &file_packet_storage,
    )).?;
    try std.testing.expectEqual(
        @as(u64, 3),
        file_packets.logical_stream_packet_index - 1,
    );
    try std.testing.expectEqual(@as(u64, 0), seek_prime.granule_position);
    decoder.reset();
    const seek_prime_result = try decoder.decode(
        seek_prime,
        identification,
        setup,
        &empty_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &windowed,
        },
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        seek_prime_result.sample_count,
    );
    const seek_target = (try file_packets.next(
        &page_storage,
        &file_packet_storage,
    )).?;
    try std.testing.expectEqual(@as(u64, 32), seek_target.granule_position);
    try std.testing.expect(seek_target.end);
    output = [_]f32{99} ** 32;
    const seek_result = try decoder.decode(
        seek_target,
        identification,
        setup,
        &outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &windowed,
        },
    );
    var file_pcm_seek = VorbisPcmSeekCursor.init(16);
    const file_selected = try file_pcm_seek.select(seek_result);
    try std.testing.expectEqualDeep(selected, file_selected);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 16),
        output[file_selected.source_start..][0..file_selected.sample_count],
    );
}

test "Vorbis PCM concealment advances overlap and granules explicitly" {
    const identification = VorbisIdentification{
        .channel_count = 1,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 64_000,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    var decoder = VorbisPcmStreamDecoder(f32, 1, 64, 64).init();
    try std.testing.expect(decoder.valid());
    var windowed: [64]f32 = undefined;
    var empty: [0]f32 = .{};
    const empty_outputs = [_][]f32{&empty};
    const primed = try decoder.concealMissingPacket(
        false,
        unknown_granule,
        false,
        identification,
        &empty_outputs,
        &windowed,
    );
    try std.testing.expectEqual(@as(usize, 0), primed.sample_count);
    try std.testing.expectEqual(@as(u64, 1), primed.concealed_packet_count);
    try std.testing.expectEqual(@as(u64, 1), decoder.audio_packet_count);
    try std.testing.expect(decoder.valid());

    var impossible_packet_timeline = decoder;
    impossible_packet_timeline.audio_packet_count = 2;
    const impossible_packet_timeline_before = impossible_packet_timeline;
    try std.testing.expect(!impossible_packet_timeline.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmStreamState,
        impossible_packet_timeline.concealMissingPacket(
            false,
            unknown_granule,
            false,
            identification,
            &empty_outputs,
            &windowed,
        ),
    );
    try std.testing.expectEqualDeep(
        impossible_packet_timeline_before,
        impossible_packet_timeline,
    );

    var corrupt_decoder = decoder;
    corrupt_decoder.granules.decoded_samples = std.math.maxInt(u64);
    const corrupt_decoder_before = corrupt_decoder;
    try std.testing.expect(!corrupt_decoder.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmStreamState,
        corrupt_decoder.concealMissingPacket(
            false,
            unknown_granule,
            false,
            identification,
            &empty_outputs,
            &windowed,
        ),
    );
    try std.testing.expectEqualDeep(
        corrupt_decoder_before,
        corrupt_decoder,
    );

    var output = [_]f32{99} ** 32;
    const outputs = [_][]f32{&output};
    const middle = try decoder.concealMissingPacket(
        false,
        32,
        false,
        identification,
        &outputs,
        &windowed,
    );
    try std.testing.expectEqual(@as(u16, 64), middle.block_size);
    try std.testing.expectEqual(@as(usize, 32), middle.sample_count);
    try std.testing.expectEqual(@as(?i64, 0), middle.pcm_start);
    try std.testing.expectEqual(@as(?i64, 32), middle.pcm_end);
    try std.testing.expectEqual(@as(u64, 2), middle.concealed_packet_count);
    try std.testing.expectEqualSlices(f32, &([_]f32{0} ** 32), &output);

    var short_packet_timeline = decoder;
    short_packet_timeline.granules.decoded_samples = 31;
    try std.testing.expect(!short_packet_timeline.valid());

    output = [_]f32{99} ** 32;
    const ended = try decoder.concealMissingPacket(
        false,
        60,
        true,
        identification,
        &outputs,
        &windowed,
    );
    try std.testing.expectEqual(@as(usize, 28), ended.sample_count);
    try std.testing.expectEqual(@as(?i64, 32), ended.pcm_start);
    try std.testing.expectEqual(@as(?i64, 60), ended.pcm_end);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 28),
        output[0..28],
    );
    try std.testing.expect(decoder.ended);
    try std.testing.expect(decoder.valid());
    try std.testing.expectError(
        error.VorbisPcmStreamAlreadyEnded,
        decoder.concealMissingPacket(
            false,
            92,
            true,
            identification,
            &outputs,
            &windowed,
        ),
    );

    decoder.reset();
    try std.testing.expect(decoder.valid());
    const before_empty_end = decoder;
    try std.testing.expectError(
        error.VorbisStreamEndedBeforePcm,
        decoder.concealMissingPacket(
            false,
            0,
            true,
            identification,
            &empty_outputs,
            &windowed,
        ),
    );
    try std.testing.expectEqualDeep(before_empty_end, decoder);
    _ = try decoder.concealMissingPacket(
        false,
        unknown_granule,
        false,
        identification,
        &empty_outputs,
        &windowed,
    );
    var aliased = [_]f32{7} ** 64;
    const aliased_outputs = [_][]f32{aliased[0..32]};
    const before_alias = decoder;
    try std.testing.expectError(
        error.OverlappingVorbisPcmStreamScratch,
        decoder.concealMissingPacket(
            false,
            32,
            false,
            identification,
            &aliased_outputs,
            &aliased,
        ),
    );
    try std.testing.expectEqualDeep(before_alias, decoder);
    try std.testing.expectEqualSlices(f32, &([_]f32{7} ** 64), &aliased);

    var hostile = decoder;
    hostile.concealed_packet_count = hostile.audio_packet_count + 1;
    const hostile_before = hostile;
    try std.testing.expectError(
        error.InvalidVorbisPcmStreamState,
        hostile.concealMissingPacket(
            false,
            32,
            false,
            identification,
            &outputs,
            &windowed,
        ),
    );
    try std.testing.expectEqualDeep(hostile_before, hostile);

    var fading = VorbisPcmStreamDecoder(f32, 1, 64, 64).init();
    const retained = [_]f32{1} ** 64;
    _ = try fading.overlap.push(
        &[_][]const f32{&retained},
        &empty_outputs,
    );
    fading.audio_packet_count = 1;
    var faded_output: [32]f32 = undefined;
    const faded_outputs = [_][]f32{&faded_output};
    _ = try fading.concealMissingPacket(
        false,
        32,
        false,
        identification,
        &faded_outputs,
        &windowed,
    );
    var faded_energy: f64 = 0;
    for (faded_output) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        faded_energy += @as(f64, sample) * sample;
    }
    try std.testing.expect(faded_energy > 0);

    const mixed_identification = VorbisIdentification{
        .channel_count = 1,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 64_000,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 256,
    };
    var mixed = VorbisPcmStreamDecoder(f32, 1, 64, 256).init();
    var mixed_windowed: [256]f32 = undefined;
    _ = try mixed.concealMissingPacket(
        false,
        unknown_granule,
        false,
        mixed_identification,
        &empty_outputs,
        &mixed_windowed,
    );
    var mixed_output: [80]f32 = undefined;
    const mixed_outputs = [_][]f32{&mixed_output};
    const mixed_large = try mixed.concealMissingPacket(
        true,
        80,
        false,
        mixed_identification,
        &mixed_outputs,
        &mixed_windowed,
    );
    try std.testing.expectEqual(@as(u16, 256), mixed_large.block_size);
    try std.testing.expectEqual(@as(usize, 80), mixed_large.sample_count);
    const mixed_small = try mixed.concealMissingPacket(
        false,
        160,
        true,
        mixed_identification,
        &mixed_outputs,
        &mixed_windowed,
    );
    try std.testing.expectEqual(@as(u16, 64), mixed_small.block_size);
    try std.testing.expectEqual(@as(usize, 80), mixed_small.sample_count);

    var predicted = VorbisPcmStreamDecoder(f32, 1, 64, 256).init();
    const predicted_before = predicted;
    try std.testing.expectError(
        error.VorbisPreviousBlockSizeUnavailable,
        predicted.concealMissingPacketUsingPreviousBlockSize(
            unknown_granule,
            false,
            mixed_identification,
            &empty_outputs,
            &mixed_windowed,
        ),
    );
    try std.testing.expectEqualDeep(predicted_before, predicted);
    _ = try predicted.concealMissingPacket(
        true,
        unknown_granule,
        false,
        mixed_identification,
        &empty_outputs,
        &mixed_windowed,
    );
    var predicted_output: [128]f32 = undefined;
    const predicted_outputs = [_][]f32{&predicted_output};
    const predicted_loss =
        try predicted.concealMissingPacketUsingPreviousBlockSize(
            128,
            false,
            mixed_identification,
            &predicted_outputs,
            &mixed_windowed,
        );
    try std.testing.expectEqual(@as(u16, 256), predicted_loss.block_size);
    try std.testing.expectEqual(@as(usize, 128), predicted_loss.sample_count);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 128),
        &predicted_output,
    );

    predicted.reset();
    _ = try predicted.concealMissingPacket(
        false,
        unknown_granule,
        false,
        mixed_identification,
        &empty_outputs,
        &mixed_windowed,
    );
    predicted_output = [_]f32{99} ** 128;
    const predicted_small =
        try predicted.concealMissingPacketUsingPreviousBlockSize(
            32,
            false,
            mixed_identification,
            &predicted_outputs,
            &mixed_windowed,
        );
    try std.testing.expectEqual(@as(u16, 64), predicted_small.block_size);
    try std.testing.expectEqual(@as(usize, 32), predicted_small.sample_count);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 32),
        predicted_output[0..32],
    );

    const following_large = VorbisAudioPacketHeader{
        .mode_number = 1,
        .large_block = true,
        .previous_window_flag = false,
        .next_window_flag = true,
        .block_size = 256,
        .payload_bit_offset = 4,
    };
    try std.testing.expect(
        !try inferVorbisMissingPacketLargeBlock(
            mixed_identification,
            following_large,
        ),
    );
    var following_previous_large = following_large;
    following_previous_large.previous_window_flag = true;
    try std.testing.expect(
        try inferVorbisMissingPacketLargeBlock(
            mixed_identification,
            following_previous_large,
        ),
    );
    const following_small = VorbisAudioPacketHeader{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = 64,
        .payload_bit_offset = 2,
    };
    try std.testing.expectError(
        error.VorbisFollowingPacketBlockSizeUnavailable,
        inferVorbisMissingPacketLargeBlock(
            mixed_identification,
            following_small,
        ),
    );
    var malformed_following = following_large;
    malformed_following.previous_window_flag = null;
    try std.testing.expectError(
        error.InvalidVorbisAudioPacketHeader,
        inferVorbisMissingPacketLargeBlock(
            mixed_identification,
            malformed_following,
        ),
    );

    var following_decoder =
        VorbisPcmStreamDecoder(f32, 1, 64, 256).init();
    const following_before = following_decoder;
    try std.testing.expectError(
        error.VorbisFollowingPacketBlockSizeUnavailable,
        following_decoder.concealMissingPacketUsingFollowingHeader(
            following_small,
            unknown_granule,
            false,
            mixed_identification,
            &empty_outputs,
            &mixed_windowed,
        ),
    );
    try std.testing.expectEqualDeep(following_before, following_decoder);
    try std.testing.expectError(
        error.InvalidVorbisAudioPacketHeader,
        following_decoder.concealMissingPacketUsingFollowingHeader(
            malformed_following,
            unknown_granule,
            false,
            mixed_identification,
            &empty_outputs,
            &mixed_windowed,
        ),
    );
    try std.testing.expectEqualDeep(following_before, following_decoder);
    const following_loss =
        try following_decoder.concealMissingPacketUsingFollowingHeader(
            following_large,
            unknown_granule,
            false,
            mixed_identification,
            &empty_outputs,
            &mixed_windowed,
        );
    try std.testing.expectEqual(@as(u16, 64), following_loss.block_size);
    try std.testing.expectEqual(@as(usize, 0), following_loss.sample_count);

    const known_granules = VorbisGranuleTracker{
        .decoded_samples = 32,
        .position_offset = 0,
    };
    try std.testing.expect(
        !try inferVorbisMissingPacketLargeBlockFromFollowingGranule(
            mixed_identification,
            64,
            following_small,
            known_granules,
            96,
            false,
        ),
    );
    try std.testing.expect(
        try inferVorbisMissingPacketLargeBlockFromFollowingGranule(
            mixed_identification,
            64,
            following_small,
            known_granules,
            192,
            false,
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisGranulePosition,
        inferVorbisMissingPacketLargeBlockFromFollowingGranule(
            mixed_identification,
            64,
            following_small,
            known_granules,
            100,
            false,
        ),
    );
    try std.testing.expectError(
        error.VorbisFollowingGranuleUnavailable,
        inferVorbisMissingPacketLargeBlockFromFollowingGranule(
            mixed_identification,
            64,
            following_small,
            known_granules,
            unknown_granule,
            false,
        ),
    );
    try std.testing.expectError(
        error.VorbisFollowingGranuleUnavailable,
        inferVorbisMissingPacketLargeBlockFromFollowingGranule(
            mixed_identification,
            64,
            following_small,
            .{ .decoded_samples = 32 },
            96,
            false,
        ),
    );
    try std.testing.expectError(
        error.VorbisFollowingGranuleUnavailable,
        inferVorbisMissingPacketLargeBlockFromFollowingGranule(
            mixed_identification,
            64,
            following_small,
            known_granules,
            96,
            true,
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisPreviousBlockSize,
        inferVorbisMissingPacketLargeBlockFromFollowingGranule(
            mixed_identification,
            128,
            following_small,
            known_granules,
            96,
            false,
        ),
    );
    try std.testing.expectError(
        error.VorbisGranulePositionOverflow,
        inferVorbisMissingPacketLargeBlockFromFollowingGranule(
            mixed_identification,
            64,
            following_small,
            .{
                .decoded_samples = std.math.maxInt(i64),
                .position_offset = 0,
            },
            96,
            false,
        ),
    );

    var granule_decoder =
        VorbisPcmStreamDecoder(f32, 1, 64, 256).init();
    _ = try granule_decoder.concealMissingPacket(
        false,
        unknown_granule,
        false,
        mixed_identification,
        &empty_outputs,
        &mixed_windowed,
    );
    var granule_output = [_]f32{99} ** 32;
    const granule_outputs = [_][]f32{&granule_output};
    _ = try granule_decoder.concealMissingPacket(
        false,
        32,
        false,
        mixed_identification,
        &granule_outputs,
        &mixed_windowed,
    );
    granule_output = [_]f32{99} ** 32;
    const granule_before = granule_decoder;
    try std.testing.expectError(
        error.InvalidVorbisGranulePosition,
        granule_decoder.concealMissingPacketUsingFollowingGranule(
            following_small,
            100,
            false,
            mixed_identification,
            &granule_outputs,
            &mixed_windowed,
        ),
    );
    try std.testing.expectEqualDeep(granule_before, granule_decoder);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{99} ** 32),
        &granule_output,
    );
    const granule_loss =
        try granule_decoder.concealMissingPacketUsingFollowingGranule(
            following_small,
            96,
            false,
            mixed_identification,
            &granule_outputs,
            &mixed_windowed,
        );
    try std.testing.expectEqual(@as(u16, 64), granule_loss.block_size);
    try std.testing.expectEqual(@as(usize, 32), granule_loss.sample_count);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 32),
        &granule_output,
    );

    var granule_chained =
        VorbisChainedPcmStreamDecoder(f32, 1, 64, 256).init();
    try granule_chained.beginLogicalStream(mixed_identification);
    _ = try granule_chained.concealMissingPacket(
        false,
        unknown_granule,
        false,
        mixed_identification,
        &empty_outputs,
        &mixed_windowed,
    );
    _ = try granule_chained.concealMissingPacket(
        false,
        32,
        false,
        mixed_identification,
        &granule_outputs,
        &mixed_windowed,
    );
    const chained_granule_loss =
        try granule_chained.concealMissingPacketUsingFollowingGranule(
            following_small,
            96,
            false,
            mixed_identification,
            &granule_outputs,
            &mixed_windowed,
        );
    try std.testing.expectEqual(
        @as(u16, 64),
        chained_granule_loss.stream.block_size,
    );
    try std.testing.expectEqual(
        @as(u64, 64),
        chained_granule_loss.global_pcm_end,
    );
}

test "Vorbis signal concealment repeats and decays retained windows" {
    const identification = VorbisIdentification{
        .channel_count = 1,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 64_000,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 256,
    };
    const retained = [_]f32{1} ** 64;
    var empty: [0]f32 = .{};
    const empty_outputs = [_][]f32{&empty};
    const Decoder = VorbisPcmStreamDecoder(f32, 1, 64, 256);
    var decoder = Decoder.init();
    _ = try decoder.overlap.push(
        &[_][]const f32{&retained},
        &empty_outputs,
    );
    decoder.audio_packet_count = 1;

    var scratch = [_]f32{99} ** 256;
    var output = [_]f32{99} ** 80;
    const outputs = [_][]f32{&output};
    const first = try decoder.concealMissingPacketWithPreviousSignal(
        false,
        .{},
        32,
        false,
        identification,
        &outputs,
        &scratch,
    );
    try std.testing.expectEqual(@as(u16, 64), first.block_size);
    try std.testing.expectEqual(@as(usize, 32), first.sample_count);
    try std.testing.expectEqual(@as(?i64, 0), first.pcm_start);
    try std.testing.expectEqual(@as(?i64, 32), first.pcm_end);
    for (0..64) |index| {
        const progress = @as(f32, @floatFromInt(index)) / 63;
        const expected = 1 - 0.5 * progress;
        try std.testing.expectApproxEqAbs(
            expected,
            scratch[index],
            1.0e-6,
        );
        if (index < 32) {
            try std.testing.expectApproxEqAbs(
                1 + expected,
                output[index],
                1.0e-6,
            );
        }
    }

    const first_replacement = scratch[0..64].*;
    const second = try decoder.concealMissingPacketUsingPreviousBlockSignal(
        .{},
        64,
        false,
        identification,
        &outputs,
        &scratch,
    );
    try std.testing.expectEqual(@as(u64, 2), second.concealed_packet_count);
    for (0..64) |index| {
        const progress = @as(f32, @floatFromInt(index)) / 63;
        const expected = first_replacement[index] *
            (1 - 0.5 * progress);
        try std.testing.expectApproxEqAbs(
            expected,
            scratch[index],
            1.0e-6,
        );
    }

    decoder.reset();
    _ = try decoder.overlap.push(
        &[_][]const f32{&retained},
        &empty_outputs,
    );
    decoder.audio_packet_count = 1;
    scratch = [_]f32{99} ** 256;
    const mixed = try decoder.concealMissingPacketWithPreviousSignal(
        true,
        .{ .final_gain = 0 },
        80,
        false,
        identification,
        &outputs,
        &scratch,
    );
    try std.testing.expectEqual(@as(u16, 256), mixed.block_size);
    try std.testing.expectEqual(@as(usize, 80), mixed.sample_count);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 96),
        scratch[0..96],
    );
    try std.testing.expect(scratch[96] > scratch[159]);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 96),
        scratch[160..256],
    );

    var unavailable = Decoder.init();
    const unavailable_scratch = scratch;
    try std.testing.expectError(
        error.VorbisPreviousSignalUnavailable,
        unavailable.concealMissingPacketWithPreviousSignal(
            false,
            .{},
            unknown_granule,
            false,
            identification,
            &empty_outputs,
            &scratch,
        ),
    );
    try std.testing.expectEqual(unavailable_scratch, scratch);
    try std.testing.expectEqual(@as(u64, 0), unavailable.audio_packet_count);

    decoder.reset();
    _ = try decoder.overlap.push(
        &[_][]const f32{&retained},
        &empty_outputs,
    );
    decoder.audio_packet_count = 1;
    scratch = [_]f32{77} ** 256;
    output = [_]f32{66} ** 80;
    try std.testing.expectError(
        error.InvalidVorbisPcmSignalConcealmentConfig,
        decoder.concealMissingPacketWithPreviousSignal(
            false,
            .{ .initial_gain = 0.5, .final_gain = 0.75 },
            32,
            false,
            identification,
            &outputs,
            &scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{77} ** 256),
        &scratch,
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{66} ** 80),
        &output,
    );
    try std.testing.expectEqual(@as(u64, 1), decoder.audio_packet_count);

    decoder.overlap.channels[0].previous[7] = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidVorbisPcmStreamState,
        decoder.concealMissingPacketWithPreviousSignal(
            false,
            .{},
            32,
            false,
            identification,
            &outputs,
            &scratch,
        ),
    );
    try std.testing.expectEqual(@as(u64, 1), decoder.audio_packet_count);

    const StereoDecoder = VorbisPcmStreamDecoder(f64, 2, 64, 64);
    var stereo = StereoDecoder.init();
    const retained_left = [_]f64{1} ** 64;
    const retained_right = [_]f64{-1} ** 64;
    var empty_left: [0]f64 = .{};
    var empty_right: [0]f64 = .{};
    const stereo_empty_outputs =
        [_][]f64{ &empty_left, &empty_right };
    _ = try stereo.overlap.push(
        &[_][]const f64{ &retained_left, &retained_right },
        &stereo_empty_outputs,
    );
    stereo.audio_packet_count = 1;
    var stereo_left: [32]f64 = undefined;
    var stereo_right: [32]f64 = undefined;
    const stereo_outputs = [_][]f64{ &stereo_left, &stereo_right };
    var stereo_scratch: [128]f64 = undefined;
    const stereo_result =
        try stereo.concealMissingPacketUsingPreviousBlockSignal(
            .{},
            32,
            false,
            .{
                .channel_count = 2,
                .sample_rate = 48_000,
                .bitrate_maximum = 0,
                .bitrate_nominal = 128_000,
                .bitrate_minimum = 0,
                .small_block_size = 64,
                .large_block_size = 64,
            },
            &stereo_outputs,
            &stereo_scratch,
        );
    try std.testing.expectEqual(@as(usize, 32), stereo_result.sample_count);
    for (stereo_left, stereo_right) |left, right| {
        try std.testing.expect(left > 0);
        try std.testing.expectApproxEqAbs(-left, right, 1.0e-12);
    }

    const Chained = VorbisChainedPcmStreamDecoder(f32, 1, 64, 256);
    var chained = Chained.init();
    try chained.beginLogicalStream(identification);
    _ = try chained.stream.overlap.push(
        &[_][]const f32{&retained},
        &empty_outputs,
    );
    chained.stream.audio_packet_count = 1;
    scratch = undefined;
    const chained_result =
        try chained.concealMissingPacketUsingPreviousBlockSignal(
            .{},
            32,
            false,
            identification,
            &outputs,
            &scratch,
        );
    try std.testing.expectEqual(@as(u64, 0), chained_result.global_pcm_start);
    try std.testing.expectEqual(@as(u64, 32), chained_result.global_pcm_end);
    try std.testing.expectEqual(
        @as(u64, 1),
        chained_result.stream.concealed_packet_count,
    );
}

test "Vorbis signal concealment improves periodic loss calibration" {
    try testVorbisSignalConcealmentQuality(f32);
    try testVorbisSignalConcealmentQuality(f64);
}

fn testVorbisSignalConcealmentQuality(comptime Float: type) !void {
    const identification = VorbisIdentification{
        .channel_count = 1,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 64_000,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    var window: [64]Float = undefined;
    try synthesizeVorbisWindow(
        Float,
        identification,
        .{
            .mode_number = 0,
            .large_block = false,
            .previous_window_flag = null,
            .next_window_flag = null,
            .block_size = 64,
            .payload_bit_offset = 1,
        },
        &window,
    );
    var retained: [64]Float = undefined;
    for (&retained, window, 0..) |*sample, window_gain, index| {
        const phase = @as(Float, @floatFromInt(index)) *
            @as(Float, 2.0 * std.math.pi / 16.0);
        sample.* = @sin(phase) * window_gain * 0.75;
    }

    const Decoder = VorbisPcmStreamDecoder(Float, 1, 64, 64);
    var clean = Decoder.init();
    var silent = Decoder.init();
    var signal = Decoder.init();
    var empty: [0]Float = .{};
    const empty_outputs = [_][]Float{&empty};
    _ = try clean.overlap.push(
        &[_][]const Float{&retained},
        &empty_outputs,
    );
    _ = try silent.overlap.push(
        &[_][]const Float{&retained},
        &empty_outputs,
    );
    _ = try signal.overlap.push(
        &[_][]const Float{&retained},
        &empty_outputs,
    );
    silent.audio_packet_count = 1;
    signal.audio_packet_count = 1;

    var clean_output: [32]Float = undefined;
    var silent_output: [32]Float = undefined;
    var signal_output: [32]Float = undefined;
    const clean_count = try clean.overlap.push(
        &[_][]const Float{&retained},
        &[_][]Float{&clean_output},
    );
    var silent_scratch: [64]Float = undefined;
    const silent_result = try silent.concealMissingPacket(
        false,
        32,
        false,
        identification,
        &[_][]Float{&silent_output},
        &silent_scratch,
    );
    var signal_scratch: [64]Float = undefined;
    const signal_result = try signal.concealMissingPacketWithPreviousSignal(
        false,
        .{ .initial_gain = 1, .final_gain = 1 },
        32,
        false,
        identification,
        &[_][]Float{&signal_output},
        &signal_scratch,
    );
    try std.testing.expectEqual(@as(usize, 32), clean_count);
    try std.testing.expectEqual(clean_count, silent_result.sample_count);
    try std.testing.expectEqual(clean_count, signal_result.sample_count);

    var silent_meter = VorbisPcmQualityMeter{};
    try silent_meter.update(
        Float,
        &.{&clean_output},
        &.{&silent_output},
    );
    var signal_meter = VorbisPcmQualityMeter{};
    try signal_meter.update(
        Float,
        &.{&clean_output},
        &.{&signal_output},
    );
    const silent_quality = try silent_meter.measurement();
    const signal_quality = try signal_meter.measurement();
    try std.testing.expect(silent_quality.normalized_rms_error > 0.4);
    try std.testing.expectEqual(
        @as(f64, 0),
        signal_quality.normalized_rms_error,
    );
    try std.testing.expect(
        signal_quality.normalized_rms_error <
            silent_quality.normalized_rms_error,
    );
    try std.testing.expectEqual(
        std.math.inf(f64),
        signal_quality.signal_to_noise_db,
    );
}

test "Vorbis granule loss inference covers every block geometry" {
    const decoded_positions = [_]u64{ 512, 10_000, 1_000_000 };
    const position_offsets = [_]i64{ -200, 0, 300 };

    for (6..14) |small_exponent| {
        const small_block_size: u16 =
            @as(u16, 1) << @intCast(small_exponent);
        for (small_exponent + 1..14) |large_exponent| {
            const large_block_size: u16 =
                @as(u16, 1) << @intCast(large_exponent);
            const identification = VorbisIdentification{
                .channel_count = 2,
                .sample_rate = 48_000,
                .bitrate_maximum = 0,
                .bitrate_nominal = 128_000,
                .bitrate_minimum = 0,
                .small_block_size = small_block_size,
                .large_block_size = large_block_size,
            };
            const following = VorbisAudioPacketHeader{
                .mode_number = 0,
                .large_block = false,
                .previous_window_flag = null,
                .next_window_flag = null,
                .block_size = small_block_size,
                .payload_bit_offset = 2,
            };
            const previous_sizes = [_]u16{
                small_block_size,
                large_block_size,
            };
            for (previous_sizes) |previous_block_size| {
                for ([_]bool{ false, true }) |missing_large| {
                    const missing_block_size = if (missing_large)
                        large_block_size
                    else
                        small_block_size;
                    const emitted_samples =
                        previous_block_size / 4 +
                        missing_block_size / 2 +
                        following.block_size / 4;
                    for (decoded_positions) |decoded_samples| {
                        for (position_offsets) |position_offset| {
                            const expected_end = position_offset +
                                @as(i64, @intCast(
                                    decoded_samples + emitted_samples,
                                ));
                            try std.testing.expectEqual(
                                missing_large,
                                try inferVorbisMissingPacketLargeBlockFromFollowingGranule(
                                    identification,
                                    previous_block_size,
                                    following,
                                    .{
                                        .decoded_samples = decoded_samples,
                                        .position_offset = position_offset,
                                    },
                                    @bitCast(expected_end),
                                    false,
                                ),
                            );
                            try std.testing.expectError(
                                error.InvalidVorbisGranulePosition,
                                inferVorbisMissingPacketLargeBlockFromFollowingGranule(
                                    identification,
                                    previous_block_size,
                                    following,
                                    .{
                                        .decoded_samples = decoded_samples,
                                        .position_offset = position_offset,
                                    },
                                    @bitCast(expected_end + 1),
                                    false,
                                ),
                            );
                        }
                    }
                }
            }
        }
    }
}

test "Vorbis seeking handles packed packets and chained streams" {
    var packed_encoded: [512]u8 = undefined;
    var packed_writer = StreamWriter.init(&packed_encoded, 0x1020_3040);
    try packed_writer.appendPacket("header 1", 0, true, false);
    try packed_writer.appendPacket("header 2", 0, false, false);
    try packed_writer.appendPacket("header 3", 0, false, false);
    packed_writer.byte_count = try appendTestOggPage(
        &packed_encoded,
        packed_writer.byte_count,
        packed_writer.serial_number,
        packed_writer.sequence_number,
        0x04,
        32,
        &.{ 1, 1, 1 },
        &.{ 0x11, 0x22, 0x33 },
    );
    var packed_points: [1]VorbisSeekPoint = undefined;
    const packed_index = try buildVorbisSeekIndex(
        packed_writer.bytes(),
        &packed_points,
    );
    try std.testing.expectEqual(@as(usize, 1), packed_index.len);
    try std.testing.expectEqual(
        @as(u64, 3),
        packed_index[0].decode.logical_packet_index,
    );
    try std.testing.expectEqual(
        @as(u16, 0),
        packed_index[0].decode.completed_packets_before,
    );
    try std.testing.expectEqual(
        @as(u64, 5),
        packed_index[0].packet.logical_packet_index,
    );
    try std.testing.expectEqual(
        @as(u16, 2),
        packed_index[0].packet.completed_packets_before,
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "packed-seek.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        packed_writer.bytes(),
        0,
    );
    try file.setLength(std.testing.io, packed_writer.bytes().len);
    var packets = try FilePacketReader.init(std.testing.io, file);
    try packets.seek(packed_index[0]);
    var page_storage: [maximum_page_bytes]u8 = undefined;
    var packet_storage: [8]u8 = undefined;
    const prime = (try packets.next(
        &page_storage,
        &packet_storage,
    )).?;
    try std.testing.expectEqualSlices(u8, &.{0x11}, prime.bytes);
    try std.testing.expectEqual(
        unknown_granule,
        prime.granule_position,
    );
    const middle = (try packets.next(
        &page_storage,
        &packet_storage,
    )).?;
    try std.testing.expectEqualSlices(u8, &.{0x22}, middle.bytes);
    try std.testing.expectEqual(
        unknown_granule,
        middle.granule_position,
    );
    const target = (try packets.next(
        &page_storage,
        &packet_storage,
    )).?;
    try std.testing.expectEqualSlices(u8, &.{0x33}, target.bytes);
    try std.testing.expectEqual(@as(u64, 32), target.granule_position);
    try std.testing.expect(target.end);

    var chained_encoded: [1024]u8 = undefined;
    var first_writer = StreamWriter.init(&chained_encoded, 0x1111_1111);
    try first_writer.appendPacket("header 1", 0, true, false);
    try first_writer.appendPacket("header 2", 0, false, false);
    try first_writer.appendPacket("header 3", 0, false, false);
    try first_writer.appendPacket("audio", 8, false, true);
    var second_writer = StreamWriter.init(
        chained_encoded[first_writer.byte_count..],
        0x2222_2222,
    );
    try second_writer.appendPacket("header 1", 0, true, false);
    try second_writer.appendPacket("header 2", 0, false, false);
    try second_writer.appendPacket("header 3", 0, false, false);
    try second_writer.appendPacket("audio", 16, false, true);
    const chained_bytes = chained_encoded[0 .. first_writer.byte_count + second_writer.byte_count];
    var chained_points: [2]VorbisSeekPoint = undefined;
    const chained_index = try buildVorbisSeekIndex(
        chained_bytes,
        &chained_points,
    );
    try std.testing.expectEqual(@as(usize, 2), chained_index.len);
    try std.testing.expectEqual(
        @as(u32, 1),
        chained_index[1].packet.logical_stream_index,
    );
    try std.testing.expectEqualDeep(
        chained_index[1],
        try findVorbisSeekPoint(chained_index, 1, 4),
    );
}

test "Vorbis comments validate UTF-8 fields and framing" {
    var packet: [64]u8 = @splat(0);
    packet[0] = 3;
    @memcpy(packet[1..7], "vorbis");
    std.mem.writeInt(u32, packet[7..11], 6, .little);
    @memcpy(packet[11..17], "vendor");
    std.mem.writeInt(u32, packet[17..21], 1, .little);
    std.mem.writeInt(u32, packet[21..25], 10, .little);
    @memcpy(packet[25..35], "TITLE=Song");
    packet[35] = 1;
    var comments = try VorbisCommentIterator.init(packet[0..36]);
    try std.testing.expect(comments.valid());
    try std.testing.expectEqualStrings("vendor", comments.vendor);
    comments.validated_packet = null;
    const title = (try comments.next()).?;
    try std.testing.expectEqualStrings("TITLE", title.name);
    try std.testing.expectEqualStrings("Song", title.value);
    try std.testing.expect((try comments.next()) == null);
    try std.testing.expect(comments.valid());
    packet[35] = 0;
    try std.testing.expectError(
        error.InvalidVorbisCommentHeader,
        VorbisCommentIterator.init(packet[0..36]),
    );

    packet[35] = 1;
    var hostile = try VorbisCommentIterator.init(packet[0..36]);
    hostile.offset = packet.len;
    try std.testing.expect(!hostile.valid());
    const hostile_offset = hostile.offset;
    try std.testing.expectError(
        error.InvalidVorbisCommentIteratorState,
        hostile.next(),
    );
    try std.testing.expectEqual(hostile_offset, hostile.offset);

    var interior = try VorbisCommentIterator.init(packet[0..36]);
    interior.offset = 26;
    try std.testing.expect(!interior.valid());
    const interior_before = interior;
    try std.testing.expectError(
        error.InvalidVorbisCommentIteratorState,
        interior.next(),
    );
    try std.testing.expectEqual(interior_before.offset, interior.offset);
    try std.testing.expectEqual(
        interior_before.remaining,
        interior.remaining,
    );

    var stale_count = try VorbisCommentIterator.init(packet[0..36]);
    stale_count.remaining = 0;
    try std.testing.expect(!stale_count.valid());
    const stale_count_offset = stale_count.offset;
    try std.testing.expectError(
        error.InvalidVorbisCommentIteratorState,
        stale_count.next(),
    );
    try std.testing.expectEqual(stale_count_offset, stale_count.offset);
    try std.testing.expectEqual(@as(u32, 0), stale_count.remaining);

    var stale_vendor = try VorbisCommentIterator.init(packet[0..36]);
    stale_vendor.vendor = packet[12..18];
    try std.testing.expect(!stale_vendor.valid());
    const stale_vendor_offset = stale_vendor.offset;
    try std.testing.expectError(
        error.InvalidVorbisCommentIteratorState,
        stale_vendor.next(),
    );
    try std.testing.expectEqual(stale_vendor_offset, stale_vendor.offset);
    try std.testing.expectEqual(@intFromPtr(packet[12..18].ptr), @intFromPtr(stale_vendor.vendor.ptr));
}

test "Vorbis comment encoding preserves fields and caller storage" {
    const comments = [_]VorbisComment{
        .{ .name = "TITLE", .value = "Night Drive" },
        .{ .name = "ARTIST", .value = "Miyuki \xe7\xbe\x8e\xe9\x9b\xaa" },
        .{ .name = "DESCRIPTION", .value = "" },
    };
    const required = try requiredVorbisCommentPacketBytes(
        "zig-vst3",
        &comments,
    );
    var destination: [128]u8 = @splat(0xaa);
    const encoded = try encodeVorbisCommentPacket(
        &destination,
        "zig-vst3",
        &comments,
    );
    try std.testing.expectEqual(required, encoded.len);
    var iterator = try VorbisCommentIterator.init(encoded);
    try std.testing.expectEqualStrings("zig-vst3", iterator.vendor);
    for (comments) |expected| {
        const actual = (try iterator.next()).?;
        try std.testing.expectEqualStrings(expected.name, actual.name);
        try std.testing.expectEqualStrings(expected.value, actual.value);
    }
    try std.testing.expect((try iterator.next()) == null);

    const before = destination;
    try std.testing.expectError(
        error.VorbisCommentOutputTooSmall,
        encodeVorbisCommentPacket(
            destination[0 .. required - 1],
            "zig-vst3",
            &comments,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &destination);
    const invalid = [_]VorbisComment{
        .{ .name = "BAD=NAME", .value = "value" },
    };
    try std.testing.expectError(
        error.InvalidVorbisCommentField,
        encodeVorbisCommentPacket(
            &destination,
            "zig-vst3",
            &invalid,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &destination);
}

test "Vorbis comment encoding rejects overlapping borrowed input" {
    var destination: [64]u8 = @splat(0xaa);
    @memcpy(destination[20..26], "vendor");
    const before = destination;
    try std.testing.expectError(
        error.OverlappingVorbisCommentStorage,
        encodeVorbisCommentPacket(
            &destination,
            destination[20..26],
            &.{},
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &destination);

    var descriptor_storage: [64]u8 align(@alignOf(VorbisComment)) =
        @splat(0xaa);
    const descriptors = std.mem.bytesAsSlice(
        VorbisComment,
        descriptor_storage[0..@sizeOf(VorbisComment)],
    );
    descriptors[0] = .{ .name = "TITLE", .value = "value" };
    const descriptors_before = descriptor_storage;
    try std.testing.expectError(
        error.OverlappingVorbisCommentStorage,
        encodeVorbisCommentPacket(
            &descriptor_storage,
            "",
            descriptors,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &descriptors_before,
        &descriptor_storage,
    );
}

test "encoded Vorbis headers traverse Ogg and parse together" {
    const expected_identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = -1,
        .bitrate_nominal = 192_000,
        .bitrate_minimum = -1,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    var identification_storage: [30]u8 = undefined;
    const identification = try encodeVorbisIdentificationPacket(
        &identification_storage,
        expected_identification,
    );
    const expected_comments = [_]VorbisComment{
        .{ .name = "TITLE", .value = "Header integration" },
    };
    var comment_storage: [64]u8 = undefined;
    const comments = try encodeVorbisCommentPacket(
        &comment_storage,
        "zig-vst3",
        &expected_comments,
    );
    var setup_storage: [128]u8 = undefined;
    const setup = makeTestVorbisSetup(
        &setup_storage,
        .unordered,
        false,
        false,
    );

    var ogg_storage: [512]u8 = undefined;
    var writer = StreamWriter.init(&ogg_storage, 0x564f_5242);
    try writer.appendPacket(identification, 0, true, false);
    try writer.appendPacket(comments, 0, false, false);
    try writer.appendPacket(setup.bytes, 0, false, true);

    var packet_storage: [128]u8 = undefined;
    var packets = PacketIterator.init(
        writer.bytes(),
        &packet_storage,
    );
    const decoded_identification = (try packets.next()).?;
    var decoded_identification_storage: [30]u8 = undefined;
    @memcpy(
        &decoded_identification_storage,
        decoded_identification.bytes,
    );
    try std.testing.expectEqualDeep(
        expected_identification,
        try VorbisIdentification.parse(
            &decoded_identification_storage,
        ),
    );
    const decoded_comments = (try packets.next()).?;
    var decoded_comment_storage: [64]u8 = undefined;
    @memcpy(
        decoded_comment_storage[0..decoded_comments.bytes.len],
        decoded_comments.bytes,
    );
    const decoded_comment_bytes =
        decoded_comment_storage[0..decoded_comments.bytes.len];
    var decoded_comment_iterator =
        try VorbisCommentIterator.init(decoded_comment_bytes);
    try std.testing.expectEqualStrings(
        "zig-vst3",
        decoded_comment_iterator.vendor,
    );
    const decoded_title = (try decoded_comment_iterator.next()).?;
    try std.testing.expectEqualStrings(
        "Header integration",
        decoded_title.value,
    );
    const decoded_setup = (try packets.next()).?;
    var decoded_setup_storage: [128]u8 = undefined;
    @memcpy(
        decoded_setup_storage[0..decoded_setup.bytes.len],
        decoded_setup.bytes,
    );
    const decoded_setup_bytes =
        decoded_setup_storage[0..decoded_setup.bytes.len];
    const parsed = try VorbisHeaders.parse(
        &decoded_identification_storage,
        decoded_comment_bytes,
        decoded_setup_bytes,
    );
    try std.testing.expectEqualDeep(
        expected_identification,
        parsed.identification,
    );
    try std.testing.expect((try packets.next()) == null);
}

test "Vorbis setup validates codebook encodings and codec configuration" {
    for (std.enums.values(TestVorbisCodebookEncoding)) |encoding| {
        var packet_storage: [128]u8 = undefined;
        const packet = makeTestVorbisSetup(
            &packet_storage,
            encoding,
            true,
            false,
        );
        var codebook_storage: [1]VorbisCodebook = undefined;
        var entry_storage: [4]VorbisCodebookEntry = undefined;
        var node_storage: [3]VorbisHuffmanNode = undefined;
        var multiplicand_storage: [4]u32 = undefined;
        var floor_storage: [1]VorbisFloor = undefined;
        var residue_storage: [1]VorbisResidue = undefined;
        var mapping_storage: [1]VorbisMapping = undefined;
        var mode_storage: [1]VorbisMode = undefined;
        const setup = try parseVorbisSetup(packet.bytes, 2, .{
            .codebooks = &codebook_storage,
            .codebook_entries = &entry_storage,
            .huffman_nodes = &node_storage,
            .codebook_multiplicands = &multiplicand_storage,
            .floors = &floor_storage,
            .residues = &residue_storage,
            .mappings = &mapping_storage,
            .modes = &mode_storage,
        });
        try std.testing.expectEqual(@as(u16, 1), setup.summary.codebook_count);
        try std.testing.expectEqual(@as(u8, 1), setup.summary.floor_count);
        try std.testing.expectEqual(@as(u8, 1), setup.summary.residue_count);
        try std.testing.expectEqual(@as(u8, 1), setup.summary.mapping_count);
        try std.testing.expectEqual(@as(u8, 1), setup.summary.mode_count);
        try std.testing.expectEqual(@as(u16, 1), setup.codebooks[0].dimensions);
        try std.testing.expectEqual(@as(u2, 1), setup.codebooks[0].lookup_type);
        try std.testing.expect(setup.modes[0].large_block);
        try std.testing.expectEqual(
            VorbisResidueKind.zero,
            setup.residues[0].kind,
        );
        try std.testing.expectEqual(@as(u25, 1), setup.residues[0].partition_size);
        try std.testing.expectEqual(@as(u7, 1), setup.residues[0].classification_count);
        try std.testing.expectEqual(@as(u8, 1), setup.residues[0].cascades[0]);
        try std.testing.expectEqual(@as(i16, 0), setup.residues[0].books[0][0]);
        try std.testing.expectEqual(@as(u5, 2), setup.mappings[0].submap_count);
        try std.testing.expectEqual(@as(u9, 1), setup.mappings[0].coupling_step_count);
        try std.testing.expectEqual(
            VorbisCouplingStep{ .magnitude = 0, .angle = 1 },
            setup.mappings[0].coupling_steps[0],
        );
        try std.testing.expectEqual(@as(u4, 0), setup.mappings[0].channel_mux[0]);
        try std.testing.expectEqual(@as(u4, 1), setup.mappings[0].channel_mux[1]);
        try std.testing.expectEqual(
            VorbisSubmap{ .floor = 0, .residue = 0 },
            setup.mappings[0].submaps[1],
        );
        const deep = encoding == .unordered_deep or encoding == .ordered_gap;
        try std.testing.expectEqual(
            @as(u64, if (deep) 4 else 2),
            setup.summary.codebook_entry_count,
        );
        var scalar_reader = try VorbisPacketReader.init(
            if (encoding == .sparse)
                &.{1}
            else if (deep)
                &.{0b11011000}
            else
                &.{0b00000010},
            0,
        );
        const decoded_count: usize = if (encoding == .sparse)
            1
        else if (deep)
            4
        else
            2;
        try std.testing.expectEqual(
            @as(u64, if (encoding == .sparse) 0 else decoded_count - 1),
            setup.summary.huffman_node_count,
        );
        for (0..decoded_count) |expected| {
            try std.testing.expectEqual(
                @as(u32, @intCast(expected)),
                try scalar_reader.decodeScalar(setup, 0),
            );
        }
        var vector_reader = try VorbisPacketReader.init(
            if (encoding == .sparse)
                &.{1}
            else if (deep)
                &.{0b11011000}
            else
                &.{0b00000010},
            0,
        );
        for (0..decoded_count) |expected| {
            var vector: [1]f64 = undefined;
            try vector_reader.decodeVector(f64, setup, 0, &vector);
            try std.testing.expectEqual(
                @as(f64, @floatFromInt(expected)),
                vector[0],
            );
        }
        try std.testing.expectEqual(
            @as(u32, @intCast(decoded_count)),
            setup.codebooks[0].active_entry_count,
        );
        switch (setup.floors[0]) {
            .one => |floor| {
                try std.testing.expectEqual(
                    @as(u5, 1),
                    floor.partition_count,
                );
                try std.testing.expectEqual(
                    @as(u7, 3),
                    floor.point_count,
                );
            },
            .zero => return error.TestExpectedFloorOne,
        }
    }

    var floor_zero_storage: [128]u8 = undefined;
    const floor_zero_packet = makeTestVorbisSetup(
        &floor_zero_storage,
        .unordered,
        false,
        true,
    );
    var floor_zero_codebooks: [1]VorbisCodebook = undefined;
    var floor_zero_entries: [2]VorbisCodebookEntry = undefined;
    var floor_zero_nodes: [1]VorbisHuffmanNode = undefined;
    var floor_zero_multiplicands: [2]u32 = undefined;
    var floor_zero_floors: [1]VorbisFloor = undefined;
    var floor_zero_residues: [1]VorbisResidue = undefined;
    var floor_zero_mappings: [1]VorbisMapping = undefined;
    var floor_zero_modes: [1]VorbisMode = undefined;
    const floor_zero_setup = try parseVorbisSetup(
        floor_zero_packet.bytes,
        1,
        .{
            .codebooks = &floor_zero_codebooks,
            .codebook_entries = &floor_zero_entries,
            .huffman_nodes = &floor_zero_nodes,
            .codebook_multiplicands = &floor_zero_multiplicands,
            .floors = &floor_zero_floors,
            .residues = &floor_zero_residues,
            .mappings = &floor_zero_mappings,
            .modes = &floor_zero_modes,
        },
    );
    switch (floor_zero_setup.floors[0]) {
        .zero => |floor| {
            try std.testing.expectEqual(@as(u8, 1), floor.order);
            try std.testing.expectEqual(@as(u16, 48_000), floor.rate);
            try std.testing.expectEqual(@as(u16, 64), floor.bark_map_size);
            try std.testing.expectEqual(@as(u6, 8), floor.amplitude_bits);
            try std.testing.expectEqual(@as(u8, 60), floor.amplitude_offset);
            try std.testing.expectEqual(@as(u5, 1), floor.book_count);
            try std.testing.expectEqual(@as(u8, 0), floor.books[0]);
        },
        .one => return error.TestExpectedFloorZero,
    }
}

test "Vorbis setup encoding canonicalizes and round trips retained setup" {
    for (std.enums.values(TestVorbisCodebookEncoding)) |encoding| {
        var packet_storage: [128]u8 = undefined;
        const packet = makeTestVorbisSetup(
            &packet_storage,
            encoding,
            true,
            false,
        );
        var codebooks: [1]VorbisCodebook = undefined;
        var entries: [4]VorbisCodebookEntry = undefined;
        var nodes: [3]VorbisHuffmanNode = undefined;
        var multiplicands: [4]u32 = undefined;
        var floors: [1]VorbisFloor = undefined;
        var residues: [1]VorbisResidue = undefined;
        var mappings: [1]VorbisMapping = undefined;
        var modes: [1]VorbisMode = undefined;
        const setup = try parseVorbisSetup(packet.bytes, 2, .{
            .codebooks = &codebooks,
            .codebook_entries = &entries,
            .huffman_nodes = &nodes,
            .codebook_multiplicands = &multiplicands,
            .floors = &floors,
            .residues = &residues,
            .mappings = &mappings,
            .modes = &modes,
        });
        if (encoding == .ordered) {
            codebooks[0].lookup_type = 2;
            codebooks[0].minimum_value = -1;
            codebooks[0].delta_value = 0.5;
            multiplicands[0] = 65535;
        }

        var encoded_storage: [256]u8 = undefined;
        @memset(&encoded_storage, 0xa5);
        const required = try requiredVorbisSetupPacketBytes(setup, 2);
        const encoded = try encodeVorbisSetupPacket(
            &encoded_storage,
            setup,
            2,
        );
        try std.testing.expectEqual(required, encoded.len);

        var decoded_codebooks: [1]VorbisCodebook = undefined;
        var decoded_entries: [4]VorbisCodebookEntry = undefined;
        var decoded_nodes: [3]VorbisHuffmanNode = undefined;
        var decoded_multiplicands: [4]u32 = undefined;
        var decoded_floors: [1]VorbisFloor = undefined;
        var decoded_residues: [1]VorbisResidue = undefined;
        var decoded_mappings: [1]VorbisMapping = undefined;
        var decoded_modes: [1]VorbisMode = undefined;
        const decoded = try parseVorbisSetup(encoded, 2, .{
            .codebooks = &decoded_codebooks,
            .codebook_entries = &decoded_entries,
            .huffman_nodes = &decoded_nodes,
            .codebook_multiplicands = &decoded_multiplicands,
            .floors = &decoded_floors,
            .residues = &decoded_residues,
            .mappings = &decoded_mappings,
            .modes = &decoded_modes,
        });
        try std.testing.expectEqualDeep(setup.summary, decoded.summary);
        try std.testing.expectEqualDeep(
            setup.codebooks,
            decoded.codebooks,
        );
        try std.testing.expectEqualDeep(
            setup.codebook_entries,
            decoded.codebook_entries,
        );
        try std.testing.expectEqualDeep(
            setup.codebook_multiplicands,
            decoded.codebook_multiplicands,
        );
        try std.testing.expectEqualDeep(setup.floors, decoded.floors);
        try std.testing.expectEqualDeep(setup.residues, decoded.residues);
        try std.testing.expectEqualDeep(setup.mappings, decoded.mappings);
        try std.testing.expectEqualDeep(setup.modes, decoded.modes);
    }

    var packet_storage: [128]u8 = undefined;
    const packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        false,
        true,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var modes: [1]VorbisMode = undefined;
    const setup = try parseVorbisSetup(packet.bytes, 1, .{
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &multiplicands,
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    });
    var encoded_storage: [256]u8 = undefined;
    const encoded = try encodeVorbisSetupPacket(
        &encoded_storage,
        setup,
        1,
    );
    const summary = try validateVorbisSetup(encoded, 1);
    try std.testing.expectEqualDeep(setup.summary, summary);
}

test "Vorbis setup encoding validates before destination mutation" {
    var packet_storage: [128]u8 = undefined;
    const packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        true,
        false,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var modes: [1]VorbisMode = undefined;
    const setup = try parseVorbisSetup(packet.bytes, 2, .{
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &multiplicands,
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    });
    const required = try requiredVorbisSetupPacketBytes(setup, 2);

    var destination: [256]u8 = undefined;
    @memset(&destination, 0xa5);
    try std.testing.expectError(
        error.VorbisSetupOutputTooSmall,
        encodeVorbisSetupPacket(
            destination[0 .. required - 1],
            setup,
            2,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** 256),
        &destination,
    );

    var invalid = setup;
    invalid.summary.mode_count = 2;
    try std.testing.expectError(
        error.InconsistentVorbisSetupSummary,
        encodeVorbisSetupPacket(&destination, invalid, 2),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** 256),
        &destination,
    );

    codebooks[0].minimum_value = 0.1;
    try std.testing.expectError(
        error.UnrepresentableVorbisCodebookFloat,
        encodeVorbisSetupPacket(&destination, setup, 2),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** 256),
        &destination,
    );
    codebooks[0].minimum_value = 0;
    multiplicands[0] = 65536;
    try std.testing.expectError(
        error.VorbisCodebookMultiplicandTooLarge,
        encodeVorbisSetupPacket(&destination, setup, 2),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** 256),
        &destination,
    );
    multiplicands[0] = 0;

    var overlapping: [256]u8 align(@alignOf(VorbisCodebook)) =
        [_]u8{0xa5} ** 256;
    const overlapping_codebooks = std.mem.bytesAsSlice(
        VorbisCodebook,
        overlapping[0..@sizeOf(VorbisCodebook)],
    );
    overlapping_codebooks[0] = setup.codebooks[0];
    var overlapping_setup = setup;
    overlapping_setup.codebooks = overlapping_codebooks;
    const before = overlapping;
    try std.testing.expectError(
        error.OverlappingVorbisSetupStorage,
        encodeVorbisSetupPacket(
            &overlapping,
            overlapping_setup,
            2,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &overlapping);

    var node_overlap: [256]u8 align(@alignOf(VorbisHuffmanNode)) =
        [_]u8{0xa5} ** 256;
    const overlapping_nodes = std.mem.bytesAsSlice(
        VorbisHuffmanNode,
        node_overlap[0 .. setup.huffman_nodes.len * @sizeOf(VorbisHuffmanNode)],
    );
    @memcpy(overlapping_nodes, setup.huffman_nodes);
    overlapping_setup = setup;
    overlapping_setup.huffman_nodes = overlapping_nodes;
    const node_before = node_overlap;
    try std.testing.expectError(
        error.OverlappingVorbisSetupStorage,
        encodeVorbisSetupPacket(
            &node_overlap,
            overlapping_setup,
            2,
        ),
    );
    try std.testing.expectEqualSlices(u8, &node_before, &node_overlap);
}

test "Vorbis setup rejects malformed structure transactionally" {
    var packet_storage: [128]u8 = undefined;
    const packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        false,
        false,
    );
    var codebook_sentinel = [_]VorbisCodebook{.{
        .dimensions = 99,
        .entries = 99,
        .entry_offset = 99,
        .active_entry_count = 99,
        .lookup_type = 2,
    }};
    var entry_sentinel = [_]VorbisCodebookEntry{.{
        .codeword = 99,
        .length = 99,
    }};
    var multiplicand_sentinel = [_]u32{99};
    var node_sentinel = [_]VorbisHuffmanNode{.{
        .branches = .{ 99, 99 },
    }};
    var floor_sentinel = [_]VorbisFloor{.{
        .zero = .{
            .order = 99,
            .rate = 99,
            .bark_map_size = 99,
            .amplitude_bits = 1,
            .amplitude_offset = 99,
            .book_count = 1,
            .books = [_]u8{99} ** 16,
        },
    }};
    var residue_sentinel = [_]VorbisResidue{.{
        .kind = .two,
        .begin = 99,
        .end = 99,
        .partition_size = 99,
        .classification_count = 1,
        .classbook = 99,
        .cascades = [_]u8{99} ** 64,
        .books = [_][8]i16{[_]i16{99} ** 8} ** 64,
    }};
    var mapping_sentinel: [1]VorbisMapping = undefined;
    var mode_sentinel = [_]VorbisMode{.{
        .large_block = true,
        .mapping = 99,
    }};
    try std.testing.expectError(
        error.VorbisSetupStorageTooSmall,
        parseVorbisSetup(packet.bytes, 1, .{
            .codebooks = codebook_sentinel[0..0],
            .codebook_entries = &entry_sentinel,
            .huffman_nodes = &node_sentinel,
            .codebook_multiplicands = &multiplicand_sentinel,
            .floors = &floor_sentinel,
            .residues = &residue_sentinel,
            .mappings = &mapping_sentinel,
            .modes = &mode_sentinel,
        }),
    );
    try std.testing.expectEqual(
        @as(u16, 99),
        codebook_sentinel[0].dimensions,
    );
    try std.testing.expectEqual(@as(u8, 99), mode_sentinel[0].mapping);
    try std.testing.expectEqual(@as(u8, 99), entry_sentinel[0].length);
    try std.testing.expectEqual(@as(u32, 99), multiplicand_sentinel[0]);
    try std.testing.expectEqual(@as(u32, 99), node_sentinel[0].branches[0]);
    switch (floor_sentinel[0]) {
        .zero => |floor| try std.testing.expectEqual(@as(u8, 99), floor.order),
        .one => return error.TestExpectedFloorZero,
    }

    var malformed = packet_storage;
    malformed[8] = 0;
    try std.testing.expectError(
        error.InvalidVorbisCodebookSync,
        validateVorbisSetup(malformed[0..packet.bytes.len], 1),
    );
    try std.testing.expectError(
        error.TruncatedVorbisSetup,
        validateVorbisSetup(packet.bytes[0 .. packet.bytes.len - 1], 1),
    );

    var bad_framing = packet_storage;
    flipTestBit(&bad_framing, packet.framing_bit);
    try std.testing.expectError(
        error.InvalidVorbisSetupFraming,
        validateVorbisSetup(bad_framing[0..packet.bytes.len], 1),
    );

    var bad_tree = packet_storage;
    flipTestBit(&bad_tree, 130);
    try std.testing.expectError(
        error.InvalidVorbisCodebookLengths,
        validateVorbisSetup(bad_tree[0..packet.bytes.len], 1),
    );

    var bad_mapping = packet_storage;
    flipTestBit(&bad_mapping, packet.mapping_reserved_bit);
    try std.testing.expectError(
        error.InvalidVorbisMappingReservedBits,
        validateVorbisSetup(bad_mapping[0..packet.bytes.len], 1),
    );

    var rich_storage: [128]u8 = undefined;
    const rich_packet = makeTestVorbisSetup(
        &rich_storage,
        .unordered,
        true,
        false,
    );
    flipTestBit(&rich_storage, rich_packet.floor_point_bit.?);
    try std.testing.expectError(
        error.DuplicateVorbisFloorPoint,
        validateVorbisSetup(
            rich_storage[0..rich_packet.bytes.len],
            2,
        ),
    );
}

test "Vorbis codewords follow entry order across mixed lengths" {
    var entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 2 },
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 0, .length = 2 },
    };

    assignVorbisCodewords(&entries);

    try std.testing.expectEqual(@as(u32, 0b00), entries[0].codeword);
    try std.testing.expectEqual(@as(u32, 0b1), entries[1].codeword);
    try std.testing.expectEqual(@as(u32, 0b01), entries[2].codeword);
}

test "Vorbis packet writer round trips headers and canonical codewords" {
    for (std.enums.values(TestVorbisCodebookEncoding)) |encoding| {
        var packet_storage: [128]u8 = undefined;
        const packet = makeTestVorbisSetup(
            &packet_storage,
            encoding,
            true,
            false,
        );
        var codebooks: [1]VorbisCodebook = undefined;
        var entries: [4]VorbisCodebookEntry = undefined;
        var nodes: [3]VorbisHuffmanNode = undefined;
        var multiplicands: [4]u32 = undefined;
        var floors: [1]VorbisFloor = undefined;
        var residues: [1]VorbisResidue = undefined;
        var mappings: [1]VorbisMapping = undefined;
        var modes: [1]VorbisMode = undefined;
        const setup = try parseVorbisSetup(packet.bytes, 2, .{
            .codebooks = &codebooks,
            .codebook_entries = &entries,
            .huffman_nodes = &nodes,
            .codebook_multiplicands = &multiplicands,
            .floors = &floors,
            .residues = &residues,
            .mappings = &mappings,
            .modes = &modes,
        });
        const identification = VorbisIdentification{
            .channel_count = 2,
            .sample_rate = 48_000,
            .bitrate_maximum = 0,
            .bitrate_nominal = 0,
            .bitrate_minimum = 0,
            .small_block_size = 64,
            .large_block_size = 128,
        };

        var output: [32]u8 = undefined;
        var writer = VorbisPacketWriter.init(&output);
        const header = try writer.writeAudioHeader(
            identification,
            setup,
            0,
            false,
            true,
        );
        const decoded_count: usize = if (encoding == .sparse)
            1
        else if (encoding == .unordered_deep or
            encoding == .ordered_gap)
            4
        else
            2;
        for (0..decoded_count) |entry|
            try writer.writeVectorEntry(setup, 0, @intCast(entry));

        const parsed_header = try parseVorbisAudioPacketHeader(
            writer.bytes(),
            identification,
            setup,
        );
        try std.testing.expectEqualDeep(header, parsed_header);
        var reader = try VorbisPacketReader.init(
            writer.bytes(),
            parsed_header.payload_bit_offset,
        );
        for (0..decoded_count) |entry| {
            try std.testing.expectEqual(
                @as(u32, @intCast(entry)),
                try reader.decodeScalar(setup, 0),
            );
        }
        try std.testing.expectEqual(writer.bit_offset, reader.bit_offset);

        const before = output;
        const before_offset = writer.bit_offset;
        try std.testing.expectError(
            error.VorbisPacketValueDoesNotFit,
            writer.writeBits(2, 1),
        );
        try std.testing.expectEqual(before_offset, writer.bit_offset);
        try std.testing.expectEqualSlices(
            u8,
            before[0..writer.bytes().len],
            writer.bytes(),
        );
        if (encoding == .sparse) {
            try std.testing.expectError(
                error.InvalidVorbisCodebookEntry,
                writer.writeScalar(setup, 0, 1),
            );
            try std.testing.expectEqual(before_offset, writer.bit_offset);
        }
    }

    var no_storage: [0]u8 = .{};
    var full = VorbisPacketWriter.init(&no_storage);
    try std.testing.expectError(
        error.VorbisAudioPacketOutputTooSmall,
        full.writeBits(1, 1),
    );
    try std.testing.expectEqual(@as(usize, 0), full.bit_offset);

    var malformed_storage: [1]u8 = .{0};
    var malformed = VorbisPacketWriter.init(&malformed_storage);
    malformed.bit_offset = std.math.maxInt(usize);
    try std.testing.expect(!malformed.valid());
    try std.testing.expectEqual(@as(usize, 0), malformed.bytes().len);
    try std.testing.expectError(
        error.InvalidVorbisPacketWriterState,
        malformed.writeBits(1, 1),
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        malformed.bit_offset,
    );
}

test "Vorbis packet writer round trips both floor packet formats" {
    var floor_one_storage: [128]u8 = undefined;
    const floor_one_packet = makeTestVorbisSetup(
        &floor_one_storage,
        .unordered,
        true,
        false,
    );
    var floor_one_codebooks: [1]VorbisCodebook = undefined;
    var floor_one_entries: [2]VorbisCodebookEntry = undefined;
    var floor_one_nodes: [1]VorbisHuffmanNode = undefined;
    var floor_one_multiplicands: [2]u32 = undefined;
    var floor_one_floors: [1]VorbisFloor = undefined;
    var floor_one_residues: [1]VorbisResidue = undefined;
    var floor_one_mappings: [1]VorbisMapping = undefined;
    var floor_one_modes: [1]VorbisMode = undefined;
    const floor_one_setup = try parseVorbisSetup(
        floor_one_packet.bytes,
        2,
        .{
            .codebooks = &floor_one_codebooks,
            .codebook_entries = &floor_one_entries,
            .huffman_nodes = &floor_one_nodes,
            .codebook_multiplicands = &floor_one_multiplicands,
            .floors = &floor_one_floors,
            .residues = &floor_one_residues,
            .mappings = &floor_one_mappings,
            .modes = &floor_one_modes,
        },
    );
    var encoded_floor_one: [16]u8 = undefined;
    var floor_one_writer =
        VorbisPacketWriter.init(&encoded_floor_one);
    try floor_one_writer.writeFloorOne(
        floor_one_setup,
        0,
        .{
            .used = true,
            .y_values = &.{ 12, 34, 1 },
        },
    );
    var floor_one_reader = try VorbisPacketReader.init(
        floor_one_writer.bytes(),
        0,
    );
    var y_values: [65]u32 = undefined;
    const floor_one_decoded = try floor_one_reader.decodeFloorOne(
        floor_one_setup,
        0,
        &y_values,
    );
    try std.testing.expect(floor_one_decoded.used);
    try std.testing.expectEqualSlices(
        u32,
        &.{ 12, 34, 1 },
        y_values[0..floor_one_decoded.value_count],
    );
    try std.testing.expectEqual(
        floor_one_writer.bit_offset,
        floor_one_reader.bit_offset,
    );

    var unused_floor_one: [1]u8 = undefined;
    var unused_writer =
        VorbisPacketWriter.init(&unused_floor_one);
    try unused_writer.writeFloorOne(
        floor_one_setup,
        0,
        .{},
    );
    var unused_reader = try VorbisPacketReader.init(
        unused_writer.bytes(),
        0,
    );
    const unused = try unused_reader.decodeFloorOne(
        floor_one_setup,
        0,
        &y_values,
    );
    try std.testing.expect(!unused.used);

    var too_small: [1]u8 = undefined;
    var small_writer = VorbisPacketWriter.init(&too_small);
    try std.testing.expectError(
        error.VorbisAudioPacketOutputTooSmall,
        small_writer.writeFloorOne(
            floor_one_setup,
            0,
            .{
                .used = true,
                .y_values = &.{ 12, 34, 1 },
            },
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), small_writer.bit_offset);
    try std.testing.expectEqual(@as(u8, 0), too_small[0]);

    var floor_zero_storage: [128]u8 = undefined;
    const floor_zero_packet = makeTestVorbisSetup(
        &floor_zero_storage,
        .unordered,
        false,
        true,
    );
    var floor_zero_codebooks: [1]VorbisCodebook = undefined;
    var floor_zero_entries: [2]VorbisCodebookEntry = undefined;
    var floor_zero_nodes: [1]VorbisHuffmanNode = undefined;
    var floor_zero_multiplicands: [2]u32 = undefined;
    var floor_zero_floors: [1]VorbisFloor = undefined;
    var floor_zero_residues: [1]VorbisResidue = undefined;
    var floor_zero_mappings: [1]VorbisMapping = undefined;
    var floor_zero_modes: [1]VorbisMode = undefined;
    const floor_zero_setup = try parseVorbisSetup(
        floor_zero_packet.bytes,
        1,
        .{
            .codebooks = &floor_zero_codebooks,
            .codebook_entries = &floor_zero_entries,
            .huffman_nodes = &floor_zero_nodes,
            .codebook_multiplicands = &floor_zero_multiplicands,
            .floors = &floor_zero_floors,
            .residues = &floor_zero_residues,
            .mappings = &floor_zero_mappings,
            .modes = &floor_zero_modes,
        },
    );
    var encoded_floor_zero: [16]u8 = undefined;
    var floor_zero_writer =
        VorbisPacketWriter.init(&encoded_floor_zero);
    try floor_zero_writer.writeFloorZero(
        floor_zero_setup,
        0,
        .{
            .amplitude = 5,
            .entries = &.{1},
        },
    );
    var floor_zero_reader = try VorbisPacketReader.init(
        floor_zero_writer.bytes(),
        0,
    );
    var coefficients: [1]f64 = undefined;
    const floor_zero_decoded = try floor_zero_reader.decodeFloorZero(
        floor_zero_setup,
        0,
        &coefficients,
    );
    try std.testing.expect(floor_zero_decoded.used);
    try std.testing.expectEqual(
        @as(u64, 5),
        floor_zero_decoded.amplitude,
    );
    try std.testing.expectEqual(@as(f64, 1), coefficients[0]);
    try std.testing.expectEqual(
        floor_zero_writer.bit_offset,
        floor_zero_reader.bit_offset,
    );
}

test "Vorbis Floor 1 fitting round trips packet values and residue" {
    try testVorbisFloorOneFitting(f32);
    try testVorbisFloorOneFitting(f64);
}

fn testVorbisFloorOneFitting(comptime Float: type) !void {
    var packet_storage: [128]u8 = undefined;
    const packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        true,
        false,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var modes: [1]VorbisMode = undefined;
    const setup = try parseVorbisSetup(packet.bytes, 2, .{
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &multiplicands,
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    });
    const floor = switch (setup.floors[0]) {
        .one => |value| value,
        .zero => return error.TestExpectedFloorOne,
    };

    var target =
        [_]Float{vorbisFloorOneInverseDb(Float, 100)} ** 4;
    target[floor.x_list[2]] =
        vorbisFloorOneInverseDb(Float, 99);
    var fitted_y = [_]u32{ 91, 92, 93, 94 };
    const fitted = try fitVorbisFloorOne(
        Float,
        setup,
        0,
        &target,
        &fitted_y,
    );
    try std.testing.expect(fitted.encoding.used);
    try std.testing.expectEqualSlices(
        u32,
        &.{ 100, 100, 1 },
        fitted.encoding.y_values,
    );
    try std.testing.expectEqual(
        @as(f64, 0),
        fitted.squared_control_point_error,
    );
    try std.testing.expectEqual(@as(u32, 94), fitted_y[3]);

    var encoded: [16]u8 = undefined;
    var writer = VorbisPacketWriter.init(&encoded);
    try writer.writeFloorOne(setup, 0, fitted.encoding);
    var reader = try VorbisPacketReader.init(writer.bytes(), 0);
    var decoded_y: [65]u32 = undefined;
    const decoded = try reader.decodeFloorOne(
        setup,
        0,
        &decoded_y,
    );
    try std.testing.expect(decoded.used);
    try std.testing.expectEqualSlices(
        u32,
        fitted.encoding.y_values,
        decoded_y[0..decoded.value_count],
    );

    var floor_curve: [4]Float = undefined;
    try synthesizeVorbisFloorOne(
        Float,
        floor,
        decoded,
        &decoded_y,
        &floor_curve,
    );
    const residue_values = [_]Float{ 1, -2, 3, -4 };
    var spectrum: [4]Float = undefined;
    for (&spectrum, floor_curve, residue_values) |
        *destination,
        floor_value,
        residue_value,
    | {
        destination.* = floor_value * residue_value;
    }
    var normalized = [_]Float{ 99, 99, 99, 99 };
    try normalizeVorbisResidue(
        Float,
        &spectrum,
        &floor_curve,
        &normalized,
    );
    for (normalized, residue_values) |actual, expected| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            @as(Float, 16) * std.math.floatEps(Float),
        );
    }
    try applyVorbisFloor(Float, &normalized, &floor_curve);
    for (normalized, spectrum) |actual, expected| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            @as(Float, 16) * std.math.floatEps(Float),
        );
    }

    var silent_destination = [_]u32{ 81, 82, 83 };
    const silent = try fitVorbisFloorOne(
        Float,
        setup,
        0,
        &([_]Float{0} ** 4),
        &silent_destination,
    );
    try std.testing.expect(!silent.encoding.used);
    try std.testing.expectEqual(@as(usize, 0), silent.encoding.y_values.len);
    try std.testing.expectEqualSlices(
        u32,
        &.{ 81, 82, 83 },
        &silent_destination,
    );

    var preserved = [_]u32{ 71, 72, 73 };
    try std.testing.expectError(
        error.VorbisFloorOutputTooSmall,
        fitVorbisFloorOne(
            Float,
            setup,
            0,
            &target,
            preserved[0..2],
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 71, 72, 73 },
        &preserved,
    );
    var invalid_target = target;
    invalid_target[1] = std.math.nan(Float);
    try std.testing.expectError(
        error.InvalidVorbisSpectrumValue,
        fitVorbisFloorOne(
            Float,
            setup,
            0,
            &invalid_target,
            &preserved,
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 71, 72, 73 },
        &preserved,
    );
    try std.testing.expectError(
        error.InvalidVorbisSpectrumShape,
        fitVorbisFloorOne(
            Float,
            setup,
            0,
            target[0..3],
            &preserved,
        ),
    );

    var unwritable_entries = entries;
    @memset(&unwritable_entries, .{
        .codeword = 0,
        .length = 0,
    });
    var unwritable_setup = setup;
    unwritable_setup.codebook_entries = &unwritable_entries;
    try std.testing.expectError(
        error.UnencodableVorbisFloorValue,
        fitVorbisFloorOne(
            Float,
            unwritable_setup,
            0,
            &target,
            &preserved,
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 71, 72, 73 },
        &preserved,
    );

    var wrong_floors = floors;
    wrong_floors[0] = .{ .zero = .{
        .order = 1,
        .rate = 48_000,
        .bark_map_size = 1,
        .amplitude_bits = 1,
        .amplitude_offset = 1,
        .book_count = 1,
        .books = [_]u8{0} ** 16,
    } };
    var wrong_setup = setup;
    wrong_setup.floors = &wrong_floors;
    try std.testing.expectError(
        error.InvalidVorbisFloorType,
        fitVorbisFloorOne(
            Float,
            wrong_setup,
            0,
            &target,
            &preserved,
        ),
    );
}

test "Vorbis multichannel Floor 1 analysis publishes atomically" {
    try testVorbisAudioFloorOne(f32);
    try testVorbisAudioFloorOne(f64);
}

fn testVorbisAudioFloorOne(comptime Float: type) !void {
    var x_list = [_]u16{0} ** 65;
    x_list[1] = 32;
    const floor_one = VorbisFloorOne{
        .partition_count = 0,
        .partition_classes = [_]u4{0} ** 31,
        .class_count = 0,
        .classes = [_]VorbisFloorOneClass{.{
            .dimensions = 0,
            .subclass_bits = 0,
            .masterbook = -1,
            .subclass_books = [_]i16{-1} ** 8,
        }} ** 16,
        .multiplier = 1,
        .range_bits = 5,
        .point_count = 2,
        .x_list = x_list,
    };
    const floors = [_]VorbisFloor{.{ .one = floor_one }};
    const residues = [_]VorbisResidue{.{
        .kind = .one,
        .begin = 0,
        .end = 32,
        .partition_size = 1,
        .classification_count = 1,
        .classbook = 0,
        .cascades = [_]u8{0} ** 64,
        .books = [_][8]i16{[_]i16{-1} ** 8} ** 64,
    }};
    const mappings = [_]VorbisMapping{.{
        .submap_count = 1,
        .coupling_step_count = 0,
        .coupling_steps = [_]VorbisCouplingStep{.{
            .magnitude = 0,
            .angle = 0,
        }} ** 256,
        .channel_mux = [_]u4{0} ** 255,
        .submaps = [_]VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    }};
    const modes = [_]VorbisMode{.{
        .large_block = false,
        .mapping = 0,
    }};
    const setup = VorbisSetup{
        .summary = .{
            .codebook_count = 0,
            .codebook_entry_count = 0,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 0,
            .maximum_codebook_entries = 0,
        },
        .codebooks = &.{},
        .codebook_entries = &.{},
        .huffman_nodes = &.{},
        .codebook_multiplicands = &.{},
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    };
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    const header = VorbisAudioPacketHeader{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = 64,
        .payload_bit_offset = 1,
    };
    try std.testing.expectEqual(
        VorbisAudioFloorOneStorageRequirements{
            .encodings = 2,
            .y_values = 4,
            .curve_values = 64,
        },
        try requiredVorbisAudioFloorOneStorage(
            identification,
            setup,
            header,
        ),
    );

    const active_target =
        [_]Float{vorbisFloorOneInverseDb(Float, 100)} ** 32;
    const silent_target = [_]Float{0} ** 32;
    var trial_y: [4]u32 = undefined;
    var trial_curves: [64]Float = undefined;
    var encodings = [_]VorbisFloorPacketEncoding{
        .{ .one = .{} },
        .{ .one = .{} },
        .{ .one = .{
            .used = true,
            .y_values = &.{99},
        } },
    };
    var y_values = [_]u32{ 91, 92, 93, 94, 95 };
    var curves = [_]Float{9} ** 65;
    const plan = try fitVorbisAudioFloorOne(
        Float,
        identification,
        setup,
        header,
        &.{ &active_target, &silent_target },
        .{
            .y_values = &trial_y,
            .curves = &trial_curves,
        },
        .{
            .encodings = &encodings,
            .y_values = &y_values,
            .curves = &curves,
        },
    );
    try std.testing.expectEqual(@as(usize, 32), plan.coefficient_count);
    try std.testing.expectEqual(@as(f64, 0), plan.squared_control_point_error);
    try std.testing.expect(plan.encodings[0].one.used);
    try std.testing.expectEqualSlices(
        u32,
        &.{ 100, 100 },
        plan.encodings[0].one.y_values,
    );
    try std.testing.expect(!plan.encodings[1].one.used);
    try std.testing.expectEqual(@as(usize, 0), plan.encodings[1].one.y_values.len);
    for (plan.curves[0..32]) |value| {
        try std.testing.expect(std.math.isFinite(value));
        try std.testing.expect(value > 0);
    }
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 32),
        plan.curves[32..64],
    );
    try std.testing.expectEqual(@as(u32, 95), y_values[4]);
    try std.testing.expectEqual(@as(Float, 9), curves[64]);
    try std.testing.expect(encodings[2].one.used);
    try std.testing.expectEqualSlices(
        u32,
        &.{99},
        encodings[2].one.y_values,
    );

    var skips = [_]bool{false} ** 2;
    const fixed = try measureVorbisAudioPacketFixedCost(
        identification,
        setup,
        .{
            .mode_number = 0,
            .floors = plan.encodings,
        },
        &skips,
    );
    try std.testing.expectEqualSlices(
        bool,
        &.{ false, true },
        fixed.do_not_encode,
    );

    const encodings_before = encodings;
    const y_before = y_values;
    const curves_before = curves;
    var invalid_target = silent_target;
    invalid_target[31] = std.math.nan(Float);
    try std.testing.expectError(
        error.InvalidVorbisSpectrumValue,
        fitVorbisAudioFloorOne(
            Float,
            identification,
            setup,
            header,
            &.{ &active_target, &invalid_target },
            .{
                .y_values = &trial_y,
                .curves = &trial_curves,
            },
            .{
                .encodings = &encodings,
                .y_values = &y_values,
                .curves = &curves,
            },
        ),
    );
    try std.testing.expectEqualDeep(encodings_before, encodings);
    try std.testing.expectEqualSlices(u32, &y_before, &y_values);
    try std.testing.expectEqualSlices(Float, &curves_before, &curves);
    try std.testing.expectError(
        error.VorbisAudioFloorScratchTooSmall,
        fitVorbisAudioFloorOne(
            Float,
            identification,
            setup,
            header,
            &.{ &active_target, &silent_target },
            .{
                .y_values = trial_y[0..3],
                .curves = &trial_curves,
            },
            .{
                .encodings = &encodings,
                .y_values = &y_values,
                .curves = &curves,
            },
        ),
    );
    try std.testing.expectError(
        error.VorbisAudioFloorStorageTooSmall,
        fitVorbisAudioFloorOne(
            Float,
            identification,
            setup,
            header,
            &.{ &active_target, &silent_target },
            .{
                .y_values = &trial_y,
                .curves = &trial_curves,
            },
            .{
                .encodings = encodings[0..1],
                .y_values = &y_values,
                .curves = &curves,
            },
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisAudioFloorStorage,
        fitVorbisAudioFloorOne(
            Float,
            identification,
            setup,
            header,
            &.{ &active_target, &silent_target },
            .{
                .y_values = &trial_y,
                .curves = &trial_curves,
            },
            .{
                .encodings = &encodings,
                .y_values = &trial_y,
                .curves = &curves,
            },
        ),
    );

    const floor_zero = [_]VorbisFloor{.{ .zero = .{
        .order = 1,
        .rate = 48_000,
        .bark_map_size = 32,
        .amplitude_bits = 1,
        .amplitude_offset = 1,
        .book_count = 1,
        .books = [_]u8{0} ** 16,
    } }};
    var floor_zero_setup = setup;
    floor_zero_setup.floors = &floor_zero;
    try std.testing.expectError(
        error.UnsupportedVorbisFloorZeroAnalysis,
        requiredVorbisAudioFloorOneStorage(
            identification,
            floor_zero_setup,
            header,
        ),
    );
    var invalid_header = header;
    invalid_header.block_size = 128;
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockShape,
        requiredVorbisAudioFloorOneStorage(
            identification,
            setup,
            invalid_header,
        ),
    );
}

test "Vorbis residue preparation fits normalizes and couples atomically" {
    try testVorbisAudioResiduePreparation(f32);
    try testVorbisAudioResiduePreparation(f64);
}

fn testVorbisAudioResiduePreparation(comptime Float: type) !void {
    var x_list = [_]u16{0} ** 65;
    x_list[1] = 32;
    const floor_one = VorbisFloorOne{
        .partition_count = 0,
        .partition_classes = [_]u4{0} ** 31,
        .class_count = 0,
        .classes = [_]VorbisFloorOneClass{.{
            .dimensions = 0,
            .subclass_bits = 0,
            .masterbook = -1,
            .subclass_books = [_]i16{-1} ** 8,
        }} ** 16,
        .multiplier = 1,
        .range_bits = 5,
        .point_count = 2,
        .x_list = x_list,
    };
    const floors = [_]VorbisFloor{.{ .one = floor_one }};
    const residues = [_]VorbisResidue{.{
        .kind = .one,
        .begin = 0,
        .end = 32,
        .partition_size = 1,
        .classification_count = 1,
        .classbook = 0,
        .cascades = [_]u8{0} ** 64,
        .books = [_][8]i16{[_]i16{-1} ** 8} ** 64,
    }};
    var coupling_steps = [_]VorbisCouplingStep{.{
        .magnitude = 0,
        .angle = 0,
    }} ** 256;
    coupling_steps[0] = .{ .magnitude = 0, .angle = 1 };
    const mappings = [_]VorbisMapping{.{
        .submap_count = 1,
        .coupling_step_count = 1,
        .coupling_steps = coupling_steps,
        .channel_mux = [_]u4{0} ** 255,
        .submaps = [_]VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    }};
    const modes = [_]VorbisMode{.{
        .large_block = false,
        .mapping = 0,
    }};
    const setup = VorbisSetup{
        .summary = .{
            .codebook_count = 0,
            .codebook_entry_count = 0,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 0,
            .maximum_codebook_entries = 0,
        },
        .codebooks = &.{},
        .codebook_entries = &.{},
        .huffman_nodes = &.{},
        .codebook_multiplicands = &.{},
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    };
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    const header = VorbisAudioPacketHeader{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = 64,
        .payload_bit_offset = 1,
    };
    try std.testing.expectEqual(
        VorbisAudioResiduePreparationStorageRequirements{
            .floor_encodings = 2,
            .floor_y_values = 4,
            .floor_curve_values = 64,
            .residue_values = 64,
            .threshold_values = 64,
            .coupling_values = 64,
            .do_not_encode = 2,
        },
        try requiredVorbisAudioResiduePreparationStorage(
            identification,
            setup,
            header,
        ),
    );

    const floor_value =
        vorbisFloorOneInverseDb(Float, 100);
    const active_spectrum = [_]Float{floor_value * 2} ** 32;
    const silent_spectrum = [_]Float{0} ** 32;
    const active_floor = [_]Float{floor_value} ** 32;
    const silent_floor = [_]Float{0} ** 32;
    const active_threshold =
        [_]Float{floor_value * 0.1} ** 32;
    const silent_threshold = [_]Float{0} ** 32;
    var fit_y: [4]u32 = undefined;
    var fit_curves: [64]Float = undefined;
    var trial_encodings: [2]VorbisFloorPacketEncoding = undefined;
    var trial_y: [4]u32 = undefined;
    var trial_curves: [64]Float = undefined;
    var trial_residue: [64]Float = undefined;
    var trial_thresholds: [64]Float = undefined;
    var coupling_values: [64]Float = undefined;
    var coupling_thresholds: [64]Float = undefined;
    var trial_skips: [2]bool = undefined;
    const sentinel_encoding = VorbisFloorPacketEncoding{
        .one = .{
            .used = true,
            .y_values = &.{99},
        },
    };
    var retained_encodings =
        [_]VorbisFloorPacketEncoding{sentinel_encoding} ** 3;
    var retained_y = [_]u32{91} ** 5;
    var retained_curves = [_]Float{92} ** 65;
    var retained_residue = [_]Float{93} ** 65;
    var retained_thresholds = [_]Float{94} ** 65;
    var retained_skips = [_]bool{true} ** 3;
    const plan = try prepareVorbisAudioResidue(
        Float,
        identification,
        setup,
        header,
        &.{ &active_spectrum, &silent_spectrum },
        &.{ &active_floor, &silent_floor },
        &.{ &active_threshold, &silent_threshold },
        .{
            .floor_fit_y_values = &fit_y,
            .floor_fit_curves = &fit_curves,
            .floor_encodings = &trial_encodings,
            .floor_y_values = &trial_y,
            .floor_curves = &trial_curves,
            .residue_values = &trial_residue,
            .noise_thresholds = &trial_thresholds,
            .coupling_values = &coupling_values,
            .coupling_thresholds = &coupling_thresholds,
            .do_not_encode = &trial_skips,
        },
        .{
            .floor_encodings = &retained_encodings,
            .floor_y_values = &retained_y,
            .floor_curves = &retained_curves,
            .residue_values = &retained_residue,
            .noise_thresholds = &retained_thresholds,
            .do_not_encode = &retained_skips,
        },
    );
    try std.testing.expectEqual(@as(usize, 32), plan.coefficient_count);
    try std.testing.expect(plan.fixed_packet_bits > 0);
    try std.testing.expectEqual(
        @as(f64, 0),
        plan.squared_control_point_error,
    );
    try std.testing.expect(plan.floor_encodings[0].one.used);
    try std.testing.expect(!plan.floor_encodings[1].one.used);
    try std.testing.expectEqualSlices(
        bool,
        &.{ false, false },
        plan.do_not_encode,
    );
    const tolerance =
        @as(Float, 64) * std.math.floatEps(Float);
    for (plan.residue_values, plan.noise_thresholds) |
        residue_value,
        threshold,
    | {
        try std.testing.expectApproxEqAbs(
            @as(Float, 2),
            residue_value,
            tolerance,
        );
        try std.testing.expectApproxEqAbs(
            @as(Float, 0.05),
            threshold,
            tolerance,
        );
    }
    var decoded_left: [32]Float = undefined;
    var decoded_right: [32]Float = undefined;
    @memcpy(&decoded_left, plan.residue_values[0..32]);
    @memcpy(&decoded_right, plan.residue_values[32..64]);
    var inverse_scratch: [64]Float = undefined;
    try inverseCoupleVorbisChannels(
        Float,
        mappings[0],
        &.{ &decoded_left, &decoded_right },
        &inverse_scratch,
    );
    try applyVorbisFloor(
        Float,
        &decoded_left,
        plan.floor_curves[0..32],
    );
    try applyVorbisFloor(
        Float,
        &decoded_right,
        plan.floor_curves[32..64],
    );
    try std.testing.expectEqualSlices(
        Float,
        &active_spectrum,
        &decoded_left,
    );
    try std.testing.expectEqualSlices(
        Float,
        &silent_spectrum,
        &decoded_right,
    );
    try std.testing.expectEqual(@as(u32, 91), retained_y[4]);
    try std.testing.expectEqual(@as(Float, 92), retained_curves[64]);
    try std.testing.expectEqual(@as(Float, 93), retained_residue[64]);
    try std.testing.expectEqual(
        @as(Float, 94),
        retained_thresholds[64],
    );
    try std.testing.expect(retained_skips[2]);
    try std.testing.expectEqual(
        sentinel_encoding,
        retained_encodings[2],
    );

    const encodings_before = retained_encodings;
    const y_before = retained_y;
    const curves_before = retained_curves;
    const residue_before = retained_residue;
    const thresholds_before = retained_thresholds;
    const skips_before = retained_skips;
    var invalid_threshold = active_threshold;
    invalid_threshold[31] = 0;
    try std.testing.expectError(
        error.InvalidVorbisNoiseThreshold,
        prepareVorbisAudioResidue(
            Float,
            identification,
            setup,
            header,
            &.{ &active_spectrum, &silent_spectrum },
            &.{ &active_floor, &silent_floor },
            &.{ &invalid_threshold, &silent_threshold },
            .{
                .floor_fit_y_values = &fit_y,
                .floor_fit_curves = &fit_curves,
                .floor_encodings = &trial_encodings,
                .floor_y_values = &trial_y,
                .floor_curves = &trial_curves,
                .residue_values = &trial_residue,
                .noise_thresholds = &trial_thresholds,
                .coupling_values = &coupling_values,
                .coupling_thresholds = &coupling_thresholds,
                .do_not_encode = &trial_skips,
            },
            .{
                .floor_encodings = &retained_encodings,
                .floor_y_values = &retained_y,
                .floor_curves = &retained_curves,
                .residue_values = &retained_residue,
                .noise_thresholds = &retained_thresholds,
                .do_not_encode = &retained_skips,
            },
        ),
    );
    try std.testing.expectEqualDeep(
        encodings_before,
        retained_encodings,
    );
    try std.testing.expectEqualSlices(u32, &y_before, &retained_y);
    try std.testing.expectEqualSlices(
        Float,
        &curves_before,
        &retained_curves,
    );
    try std.testing.expectEqualSlices(
        Float,
        &residue_before,
        &retained_residue,
    );
    try std.testing.expectEqualSlices(
        Float,
        &thresholds_before,
        &retained_thresholds,
    );
    try std.testing.expectEqualSlices(
        bool,
        &skips_before,
        &retained_skips,
    );

    try std.testing.expectError(
        error.VorbisAudioResiduePreparationScratchTooSmall,
        prepareVorbisAudioResidue(
            Float,
            identification,
            setup,
            header,
            &.{ &active_spectrum, &silent_spectrum },
            &.{ &active_floor, &silent_floor },
            &.{ &active_threshold, &silent_threshold },
            .{
                .floor_fit_y_values = fit_y[0..3],
                .floor_fit_curves = &fit_curves,
                .floor_encodings = &trial_encodings,
                .floor_y_values = &trial_y,
                .floor_curves = &trial_curves,
                .residue_values = &trial_residue,
                .noise_thresholds = &trial_thresholds,
                .coupling_values = &coupling_values,
                .coupling_thresholds = &coupling_thresholds,
                .do_not_encode = &trial_skips,
            },
            .{
                .floor_encodings = &retained_encodings,
                .floor_y_values = &retained_y,
                .floor_curves = &retained_curves,
                .residue_values = &retained_residue,
                .noise_thresholds = &retained_thresholds,
                .do_not_encode = &retained_skips,
            },
        ),
    );
    try std.testing.expectError(
        error.VorbisAudioResiduePreparationStorageTooSmall,
        prepareVorbisAudioResidue(
            Float,
            identification,
            setup,
            header,
            &.{ &active_spectrum, &silent_spectrum },
            &.{ &active_floor, &silent_floor },
            &.{ &active_threshold, &silent_threshold },
            .{
                .floor_fit_y_values = &fit_y,
                .floor_fit_curves = &fit_curves,
                .floor_encodings = &trial_encodings,
                .floor_y_values = &trial_y,
                .floor_curves = &trial_curves,
                .residue_values = &trial_residue,
                .noise_thresholds = &trial_thresholds,
                .coupling_values = &coupling_values,
                .coupling_thresholds = &coupling_thresholds,
                .do_not_encode = &trial_skips,
            },
            .{
                .floor_encodings = retained_encodings[0..1],
                .floor_y_values = &retained_y,
                .floor_curves = &retained_curves,
                .residue_values = &retained_residue,
                .noise_thresholds = &retained_thresholds,
                .do_not_encode = &retained_skips,
            },
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisAudioResiduePreparationStorage,
        prepareVorbisAudioResidue(
            Float,
            identification,
            setup,
            header,
            &.{ &active_spectrum, &silent_spectrum },
            &.{ &active_floor, &silent_floor },
            &.{ &active_threshold, &silent_threshold },
            .{
                .floor_fit_y_values = &fit_y,
                .floor_fit_curves = &fit_curves,
                .floor_encodings = &trial_encodings,
                .floor_y_values = &trial_y,
                .floor_curves = &trial_curves,
                .residue_values = &trial_residue,
                .noise_thresholds = &trial_thresholds,
                .coupling_values = &trial_residue,
                .coupling_thresholds = &coupling_thresholds,
                .do_not_encode = &trial_skips,
            },
            .{
                .floor_encodings = &retained_encodings,
                .floor_y_values = &retained_y,
                .floor_curves = &retained_curves,
                .residue_values = &retained_residue,
                .noise_thresholds = &retained_thresholds,
                .do_not_encode = &retained_skips,
            },
        ),
    );
    var invalid_header = header;
    invalid_header.payload_bit_offset = 2;
    try std.testing.expectError(
        error.InvalidVorbisPacketBitOffset,
        prepareVorbisAudioResidue(
            Float,
            identification,
            setup,
            invalid_header,
            &.{ &active_spectrum, &silent_spectrum },
            &.{ &active_floor, &silent_floor },
            &.{ &active_threshold, &silent_threshold },
            .{
                .floor_fit_y_values = &fit_y,
                .floor_fit_curves = &fit_curves,
                .floor_encodings = &trial_encodings,
                .floor_y_values = &trial_y,
                .floor_curves = &trial_curves,
                .residue_values = &trial_residue,
                .noise_thresholds = &trial_thresholds,
                .coupling_values = &coupling_values,
                .coupling_thresholds = &coupling_thresholds,
                .do_not_encode = &trial_skips,
            },
            .{
                .floor_encodings = &retained_encodings,
                .floor_y_values = &retained_y,
                .floor_curves = &retained_curves,
                .residue_values = &retained_residue,
                .noise_thresholds = &retained_thresholds,
                .do_not_encode = &retained_skips,
            },
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &residue_before,
        &retained_residue,
    );
}

test "Vorbis Floor 1 fitting and normalization reject aliases" {
    var packet_storage: [128]u8 = undefined;
    const packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        true,
        false,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var modes: [1]VorbisMode = undefined;
    const setup = try parseVorbisSetup(packet.bytes, 2, .{
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &multiplicands,
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    });

    var aliased_storage align(@alignOf(u32)) =
        [_]u8{0} ** (4 * @sizeOf(u32));
    const aliased_target = std.mem.bytesAsSlice(
        f32,
        &aliased_storage,
    );
    @memset(aliased_target, 1);
    const aliased_output = std.mem.bytesAsSlice(
        u32,
        &aliased_storage,
    );
    try std.testing.expectError(
        error.OverlappingVorbisFloorFit,
        fitVorbisFloorOne(
            f32,
            setup,
            0,
            aliased_target,
            aliased_output,
        ),
    );

    const setup_output = std.mem.bytesAsSlice(
        u32,
        std.mem.sliceAsBytes(entries[0..]),
    );
    try std.testing.expectError(
        error.OverlappingVorbisFloorFit,
        fitVorbisFloorOne(
            f32,
            setup,
            0,
            &.{ 1, 1, 1, 1 },
            setup_output,
        ),
    );

    var in_place = [_]f64{ 2, -4, 6, -8 };
    try normalizeVorbisResidue(
        f64,
        &in_place,
        &.{ 2, 2, 2, 2 },
        &in_place,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1, -2, 3, -4 },
        &in_place,
    );

    var overlapping = [_]f64{ 1, 2, 3, 4, 5 };
    try std.testing.expectError(
        error.OverlappingVorbisResidueNormalization,
        normalizeVorbisResidue(
            f64,
            overlapping[0..4],
            &.{ 1, 1, 1, 1 },
            overlapping[1..5],
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1, 2, 3, 4, 5 },
        &overlapping,
    );

    var floor_alias = [_]f64{ 1, 2, 3, 4 };
    try std.testing.expectError(
        error.OverlappingVorbisResidueNormalization,
        normalizeVorbisResidue(
            f64,
            &.{ 1, 2, 3, 4 },
            &floor_alias,
            &floor_alias,
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1, 2, 3, 4 },
        &floor_alias,
    );

    var preserved = [_]f64{ 9, 9, 9, 9 };
    try std.testing.expectError(
        error.InvalidVorbisSpectrumValue,
        normalizeVorbisResidue(
            f64,
            &.{ 1, 2, 3, 4 },
            &.{ 1, 0, 1, 1 },
            &preserved,
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 9, 9, 9, 9 },
        &preserved,
    );
    try std.testing.expectError(
        error.InvalidVorbisSpectrumShape,
        normalizeVorbisResidue(
            f64,
            &.{ 1, 2, 3 },
            &.{ 1, 1, 1 },
            &preserved,
        ),
    );
}

test "Vorbis packet writer round trips every residue layout" {
    var packet_storage: [128]u8 = undefined;
    const packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        true,
        false,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var codebook_entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var modes: [1]VorbisMode = undefined;
    const setup = try parseVorbisSetup(packet.bytes, 2, .{
        .codebooks = &codebooks,
        .codebook_entries = &codebook_entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &multiplicands,
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    });
    residues[0].end = 4;

    inline for (std.enums.values(VorbisResidueKind)) |kind| {
        residues[0].kind = kind;
        const classification_count: usize =
            if (kind == .two) 4 else 8;
        const classifications = [_]u8{0} ** 8;
        const entries = [_]u32{
            0, 1, 1, 0,
            1, 0, 0, 1,
        };
        var encoded: [32]u8 = undefined;
        var writer = VorbisPacketWriter.init(&encoded);
        try writer.writeResidue(
            setup,
            0,
            4,
            .{
                .do_not_encode = &.{ false, false },
                .classifications = classifications[0..classification_count],
                .entries = entries[0..classification_count],
            },
        );

        var first = [_]f64{99} ** 4;
        var second = [_]f64{99} ** 4;
        const outputs = [_][]f64{ &first, &second };
        var classification_scratch: [8]u8 = undefined;
        var reader = try VorbisPacketReader.init(
            writer.bytes(),
            0,
        );
        const decoded = try reader.decodeResidue(
            f64,
            setup,
            0,
            &.{ false, false },
            &outputs,
            &classification_scratch,
        );
        try std.testing.expect(!decoded.truncated);
        try std.testing.expectEqual(writer.bit_offset, reader.bit_offset);
        if (kind == .two) {
            try std.testing.expectEqualSlices(
                f64,
                &.{ 0, 1, 0, 0 },
                &first,
            );
            try std.testing.expectEqualSlices(
                f64,
                &.{ 1, 0, 0, 0 },
                &second,
            );
        } else {
            try std.testing.expectEqualSlices(
                f64,
                &.{ 0, 1, 1, 0 },
                &first,
            );
            try std.testing.expectEqualSlices(
                f64,
                &.{ 1, 0, 0, 1 },
                &second,
            );
        }
    }

    residues[0].kind = .two;
    var skipped_output: [1]u8 = undefined;
    var skipped_writer = VorbisPacketWriter.init(&skipped_output);
    try skipped_writer.writeResidue(
        setup,
        0,
        4,
        .{
            .do_not_encode = &.{ true, true },
            .classifications = &.{},
            .entries = &.{},
        },
    );
    try std.testing.expectEqual(@as(usize, 0), skipped_writer.bit_offset);

    var no_output: [0]u8 = .{};
    var small_writer = VorbisPacketWriter.init(&no_output);
    try std.testing.expectError(
        error.VorbisAudioPacketOutputTooSmall,
        small_writer.writeResidue(
            setup,
            0,
            4,
            .{
                .do_not_encode = &.{ false, false },
                .classifications = &.{ 0, 0, 0, 0 },
                .entries = &.{ 0, 1, 1, 0 },
            },
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), small_writer.bit_offset);
}

test "Vorbis audio packet encoding composes floors residues and coupling" {
    var setup_storage: [128]u8 = undefined;
    const setup_packet = makeTestVorbisSetup(
        &setup_storage,
        .unordered,
        true,
        false,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var codebook_entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var modes: [1]VorbisMode = undefined;
    const setup = try parseVorbisSetup(
        setup_packet.bytes,
        2,
        .{
            .codebooks = &codebooks,
            .codebook_entries = &codebook_entries,
            .huffman_nodes = &nodes,
            .codebook_multiplicands = &multiplicands,
            .floors = &floors,
            .residues = &residues,
            .mappings = &mappings,
            .modes = &modes,
        },
    );
    residues[0].end = 4;
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 128,
    };
    const floor_encodings = [_]VorbisFloorPacketEncoding{
        .{ .one = .{
            .used = true,
            .y_values = &.{ 12, 34, 1 },
        } },
        .{ .one = .{
            .used = true,
            .y_values = &.{ 20, 40, 0 },
        } },
    };
    const residue_encodings = [_]VorbisResidueEncoding{
        .{
            .do_not_encode = &.{false},
            .classifications = &.{ 0, 0, 0, 0 },
            .entries = &.{ 0, 1, 1, 0 },
        },
        .{
            .do_not_encode = &.{false},
            .classifications = &.{ 0, 0, 0, 0 },
            .entries = &.{ 1, 0, 0, 1 },
        },
    };
    const encoding = VorbisAudioPacketEncoding{
        .mode_number = 0,
        .previous_window_flag = false,
        .next_window_flag = true,
        .floors = &floor_encodings,
        .residues = &residue_encodings,
    };

    var packet: [128]u8 = undefined;
    @memset(&packet, 0xa5);
    const required = try requiredVorbisAudioPacketBytes(
        identification,
        setup,
        encoding,
    );
    const encoded = try encodeVorbisAudioPacket(
        &packet,
        identification,
        setup,
        encoding,
    );
    var measured_skips = [_]bool{ true, true, true };
    const fixed = try measureVorbisAudioPacketFixedCost(
        identification,
        setup,
        .{
            .mode_number = encoding.mode_number,
            .previous_window_flag = encoding.previous_window_flag,
            .next_window_flag = encoding.next_window_flag,
            .floors = encoding.floors,
        },
        &measured_skips,
    );
    try std.testing.expectEqualSlices(
        bool,
        &.{ false, false },
        fixed.do_not_encode,
    );
    try std.testing.expect(measured_skips[2]);
    var residue_bit_count: usize = 0;
    for (residue_encodings, 0..) |residue_encoding, submap| {
        var residue_counter = VorbisPacketWriter.counting();
        try residue_counter.writeResidue(
            setup,
            mappings[0].submaps[submap].residue,
            encoded.header.block_size / 2,
            residue_encoding,
        );
        residue_bit_count += residue_counter.bit_offset;
    }
    try std.testing.expectEqual(
        encoded.bit_count,
        fixed.bit_count + residue_bit_count,
    );
    try std.testing.expectEqualDeep(encoded.header, fixed.header);
    try std.testing.expectEqual(required, encoded.bytes.len);
    try std.testing.expectEqualDeep(
        encoded.header,
        try parseVorbisAudioPacketHeader(
            encoded.bytes,
            identification,
            setup,
        ),
    );

    var first_output: [128]f64 = undefined;
    var second_output: [128]f64 = undefined;
    const outputs = [_][]f64{ &first_output, &second_output };
    var spectra: [128]f64 = undefined;
    var floor_curves: [128]f64 = undefined;
    var coupling: [128]f64 = undefined;
    var time: [256]f64 = undefined;
    var classifications: [8]u8 = undefined;
    var decoder = VorbisAudioPacketDecoder(
        f64,
        2,
        64,
        128,
    ).init();
    const decoded = try decoder.decode(
        encoded.bytes,
        identification,
        setup,
        &outputs,
        .{
            .spectra = &spectra,
            .floor_curves = &floor_curves,
            .coupling = &coupling,
            .time = &time,
            .classifications = &classifications,
        },
    );
    try std.testing.expect(!decoded.truncated);
    try std.testing.expectEqual(encoded.bit_count, decoded.decoded_bit_count);
    var nonzero = false;
    for (first_output) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        nonzero = nonzero or sample != 0;
    }
    for (second_output) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        nonzero = nonzero or sample != 0;
    }
    try std.testing.expect(nonzero);

    const partly_silent_floors = [_]VorbisFloorPacketEncoding{
        .{ .one = .{} },
        floor_encodings[1],
    };
    const partly_silent = try measureVorbisAudioPacketFixedCost(
        identification,
        setup,
        .{
            .mode_number = encoding.mode_number,
            .previous_window_flag = encoding.previous_window_flag,
            .next_window_flag = encoding.next_window_flag,
            .floors = &partly_silent_floors,
        },
        &measured_skips,
    );
    try std.testing.expectEqualSlices(
        bool,
        &.{ false, false },
        partly_silent.do_not_encode,
    );
    const silent_floors = [_]VorbisFloorPacketEncoding{
        .{ .one = .{} },
        .{ .one = .{} },
    };
    const silent = try measureVorbisAudioPacketFixedCost(
        identification,
        setup,
        .{
            .mode_number = encoding.mode_number,
            .previous_window_flag = encoding.previous_window_flag,
            .next_window_flag = encoding.next_window_flag,
            .floors = &silent_floors,
        },
        &measured_skips,
    );
    try std.testing.expectEqualSlices(
        bool,
        &.{ true, true },
        silent.do_not_encode,
    );
    const preserved_skips = measured_skips;
    try std.testing.expectError(
        error.VorbisAudioPacketSkipOutputTooSmall,
        measureVorbisAudioPacketFixedCost(
            identification,
            setup,
            .{
                .mode_number = encoding.mode_number,
                .previous_window_flag = encoding.previous_window_flag,
                .next_window_flag = encoding.next_window_flag,
                .floors = encoding.floors,
            },
            measured_skips[0..1],
        ),
    );
    try std.testing.expectEqualSlices(
        bool,
        &preserved_skips,
        &measured_skips,
    );
    var invalid_floors = floor_encodings;
    invalid_floors[1] = .{ .zero = .{} };
    try std.testing.expectError(
        error.InvalidVorbisAudioFloorEncoding,
        measureVorbisAudioPacketFixedCost(
            identification,
            setup,
            .{
                .mode_number = encoding.mode_number,
                .previous_window_flag = encoding.previous_window_flag,
                .next_window_flag = encoding.next_window_flag,
                .floors = &invalid_floors,
            },
            &measured_skips,
        ),
    );
    try std.testing.expectEqualSlices(
        bool,
        &preserved_skips,
        &measured_skips,
    );
    var aliased_y = [_]u32{ 12, 34, 1 };
    const aliased_floor = [_]VorbisFloorPacketEncoding{
        .{ .one = .{
            .used = true,
            .y_values = &aliased_y,
        } },
        floor_encodings[1],
    };
    const aliased_skips = std.mem.bytesAsSlice(
        bool,
        std.mem.sliceAsBytes(&aliased_y),
    )[0..2];
    try std.testing.expectError(
        error.OverlappingVorbisPacketEncoding,
        measureVorbisAudioPacketFixedCost(
            identification,
            setup,
            .{
                .mode_number = encoding.mode_number,
                .previous_window_flag = encoding.previous_window_flag,
                .next_window_flag = encoding.next_window_flag,
                .floors = &aliased_floor,
            },
            aliased_skips,
        ),
    );

    @memset(&packet, 0xa5);
    try std.testing.expectError(
        error.VorbisAudioPacketOutputTooSmall,
        encodeVorbisAudioPacket(
            packet[0 .. required - 1],
            identification,
            setup,
            encoding,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** 128),
        &packet,
    );
    var invalid_residues = residue_encodings;
    invalid_residues[0].do_not_encode = &.{true};
    var invalid_encoding = encoding;
    invalid_encoding.residues = &invalid_residues;
    try std.testing.expectError(
        error.InvalidVorbisAudioResidueEncoding,
        encodeVorbisAudioPacket(
            &packet,
            identification,
            setup,
            invalid_encoding,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** 128),
        &packet,
    );

    var overlapping: [128]u8 align(@alignOf(u32)) =
        [_]u8{0xa5} ** 128;
    const overlapping_entries = std.mem.bytesAsSlice(
        u32,
        overlapping[0 .. 4 * @sizeOf(u32)],
    );
    @memcpy(
        overlapping_entries,
        residue_encodings[0].entries,
    );
    var overlapping_residues = residue_encodings;
    overlapping_residues[0].entries = overlapping_entries;
    var overlapping_encoding = encoding;
    overlapping_encoding.residues = &overlapping_residues;
    const overlapping_before = overlapping;
    try std.testing.expectError(
        error.OverlappingVorbisPacketEncoding,
        encodeVorbisAudioPacket(
            &overlapping,
            identification,
            setup,
            overlapping_encoding,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &overlapping_before,
        &overlapping,
    );
}

test "Vorbis scalar codebook decoding preserves cursor on failure" {
    const entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
    };
    const codebooks = [_]VorbisCodebook{.{
        .dimensions = 1,
        .entries = 2,
        .entry_offset = 0,
        .active_entry_count = 2,
        .tree_node_count = 1,
        .lookup_type = 0,
    }};
    const nodes = [_]VorbisHuffmanNode{.{
        .branches = .{
            huffman_leaf_flag,
            invalid_huffman_branch,
        },
    }};
    const setup = VorbisSetup{
        .summary = .{
            .codebook_count = 1,
            .codebook_entry_count = 2,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 1,
            .maximum_codebook_entries = 2,
        },
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &.{},
        .floors = &.{},
        .residues = &.{},
        .mappings = &.{},
        .modes = &.{.{ .large_block = false, .mapping = 0 }},
    };
    try std.testing.expectError(
        error.InvalidVorbisPacketBitOffset,
        VorbisPacketReader.init(&.{0}, 9),
    );
    var hostile = try VorbisPacketReader.init(&.{0}, 0);
    try std.testing.expect(hostile.valid());
    hostile.bit_offset = std.math.maxInt(usize);
    try std.testing.expect(!hostile.valid());
    try std.testing.expectError(
        error.InvalidVorbisPacketBitOffset,
        hostile.decodeScalar(setup, 0),
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        hostile.bit_offset,
    );

    var truncated = try VorbisPacketReader.init(&.{}, 0);
    try std.testing.expectError(
        error.TruncatedVorbisAudioPacket,
        truncated.decodeScalar(setup, 0),
    );
    try std.testing.expectEqual(@as(usize, 0), truncated.bit_offset);

    const invalid_packet = [_]u8{0xff} ** 4;
    var invalid = try VorbisPacketReader.init(&invalid_packet, 0);
    try std.testing.expectError(
        error.InvalidVorbisCodeword,
        invalid.decodeScalar(setup, 0),
    );
    try std.testing.expectEqual(@as(usize, 0), invalid.bit_offset);
    try std.testing.expectError(
        error.InvalidVorbisCodebookNumber,
        invalid.decodeScalar(setup, 1),
    );

    var invalid_node_reference = nodes;
    invalid_node_reference[0].branches[0] = 1;
    var invalid_node_setup = setup;
    invalid_node_setup.huffman_nodes = &invalid_node_reference;
    var invalid_node_reader = try VorbisPacketReader.init(&.{0}, 0);
    try std.testing.expectError(
        error.InvalidVorbisSetupState,
        invalid_node_reader.decodeScalar(invalid_node_setup, 0),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        invalid_node_reader.bit_offset,
    );

    var invalid_leaf = nodes;
    invalid_leaf[0].branches[0] = huffman_leaf_flag | 2;
    var invalid_leaf_setup = setup;
    invalid_leaf_setup.huffman_nodes = &invalid_leaf;
    var invalid_leaf_reader = try VorbisPacketReader.init(&.{0}, 0);
    try std.testing.expectError(
        error.InvalidVorbisSetupState,
        invalid_leaf_reader.decodeScalar(invalid_leaf_setup, 0),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        invalid_leaf_reader.bit_offset,
    );

    var empty_codebooks = codebooks;
    empty_codebooks[0].entries = 0;
    var empty_setup = setup;
    empty_setup.codebooks = &empty_codebooks;
    var empty_reader = try VorbisPacketReader.init(&.{0}, 0);
    try std.testing.expectError(
        error.InvalidVorbisSetupState,
        empty_reader.decodeScalar(empty_setup, 0),
    );
    try std.testing.expectEqual(@as(usize, 0), empty_reader.bit_offset);
}

test "Vorbis vector codebooks reconstruct both lookup forms" {
    const type_one_entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 2 },
        .{ .codeword = 1, .length = 2 },
        .{ .codeword = 2, .length = 2 },
        .{ .codeword = 3, .length = 2 },
    };
    const type_one_books = [_]VorbisCodebook{.{
        .dimensions = 2,
        .entries = 4,
        .entry_offset = 0,
        .active_entry_count = 4,
        .tree_node_count = 3,
        .lookup_type = 1,
        .delta_value = 1,
        .multiplicand_count = 2,
    }};
    const type_one_nodes = [_]VorbisHuffmanNode{
        .{ .branches = .{ 1, 2 } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
        .{ .branches = .{
            huffman_leaf_flag | 2,
            huffman_leaf_flag | 3,
        } },
    };
    const type_one_setup = VorbisSetup{
        .summary = .{
            .codebook_count = 1,
            .codebook_entry_count = 4,
            .codebook_multiplicand_count = 2,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 2,
            .maximum_codebook_entries = 4,
        },
        .codebooks = &type_one_books,
        .codebook_entries = &type_one_entries,
        .huffman_nodes = &type_one_nodes,
        .codebook_multiplicands = &.{ 1, 2 },
        .floors = &.{},
        .residues = &.{},
        .mappings = &.{},
        .modes = &.{.{ .large_block = false, .mapping = 0 }},
    };
    var hostile_reader = try VorbisPacketReader.init(&.{0b11}, 0);
    hostile_reader.bit_offset = std.math.maxInt(usize);
    var hostile_output = [_]f32{ 99, 99 };
    try std.testing.expectError(
        error.InvalidVorbisPacketBitOffset,
        hostile_reader.decodeVector(
            f32,
            type_one_setup,
            0,
            &hostile_output,
        ),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 99, 99 },
        &hostile_output,
    );

    var type_one_reader = try VorbisPacketReader.init(&.{0b11}, 0);
    var type_one_output: [2]f32 = undefined;
    try type_one_reader.decodeVector(
        f32,
        type_one_setup,
        0,
        &type_one_output,
    );
    try std.testing.expectEqualSlices(f32, &.{ 2, 2 }, &type_one_output);

    const type_two_entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
    };
    const type_two_books = [_]VorbisCodebook{.{
        .dimensions = 2,
        .entries = 2,
        .entry_offset = 0,
        .active_entry_count = 2,
        .tree_node_count = 1,
        .lookup_type = 2,
        .minimum_value = 1,
        .delta_value = 0.5,
        .sequence = true,
        .multiplicand_count = 4,
    }};
    const type_two_nodes = [_]VorbisHuffmanNode{.{
        .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        },
    }};
    const type_two_setup = VorbisSetup{
        .summary = .{
            .codebook_count = 1,
            .codebook_entry_count = 2,
            .codebook_multiplicand_count = 4,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 2,
            .maximum_codebook_entries = 2,
        },
        .codebooks = &type_two_books,
        .codebook_entries = &type_two_entries,
        .huffman_nodes = &type_two_nodes,
        .codebook_multiplicands = &.{ 0, 2, 4, 6 },
        .floors = &.{},
        .residues = &.{},
        .mappings = &.{},
        .modes = &.{.{ .large_block = false, .mapping = 0 }},
    };
    var type_two_reader = try VorbisPacketReader.init(&.{1}, 0);
    var type_two_output: [2]f64 = undefined;
    try type_two_reader.decodeVector(
        f64,
        type_two_setup,
        0,
        &type_two_output,
    );
    try std.testing.expectEqualSlices(f64, &.{ 3, 7 }, &type_two_output);

    var bounded_reader = try VorbisPacketReader.init(&.{1}, 0);
    var short_output: [1]f64 = .{99};
    try std.testing.expectError(
        error.VorbisVectorOutputTooSmall,
        bounded_reader.decodeVector(
            f64,
            type_two_setup,
            0,
            &short_output,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), bounded_reader.bit_offset);
    try std.testing.expectEqual(@as(f64, 99), short_output[0]);

    var invalid_lookup_books = type_two_books;
    invalid_lookup_books[0].lookup_type = 3;
    var invalid_lookup_setup = type_two_setup;
    invalid_lookup_setup.codebooks = &invalid_lookup_books;
    var invalid_lookup_reader = try VorbisPacketReader.init(&.{1}, 0);
    var preserved_output = [_]f64{ 99, 99 };
    try std.testing.expectError(
        error.InvalidVorbisSetupState,
        invalid_lookup_reader.decodeVector(
            f64,
            invalid_lookup_setup,
            0,
            &preserved_output,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        invalid_lookup_reader.bit_offset,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 99, 99 },
        &preserved_output,
    );
}

test "Vorbis vector quantization selects nearest active entries" {
    const type_one_entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 2 },
        .{ .codeword = 1, .length = 2 },
        .{ .codeword = 2, .length = 2 },
        .{ .codeword = 3, .length = 2 },
    };
    const type_one_books = [_]VorbisCodebook{.{
        .dimensions = 2,
        .entries = 4,
        .entry_offset = 0,
        .active_entry_count = 4,
        .tree_node_count = 3,
        .lookup_type = 1,
        .delta_value = 1,
        .multiplicand_count = 2,
    }};
    const quantizer_type_one_nodes = [_]VorbisHuffmanNode{
        .{ .branches = .{ 1, 2 } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
        .{ .branches = .{
            huffman_leaf_flag | 2,
            huffman_leaf_flag | 3,
        } },
    };
    const type_one_setup = VorbisSetup{
        .summary = .{
            .codebook_count = 1,
            .codebook_entry_count = 4,
            .codebook_multiplicand_count = 2,
            .time_count = 0,
            .floor_count = 0,
            .residue_count = 0,
            .mapping_count = 0,
            .mode_count = 0,
            .maximum_codebook_dimensions = 2,
            .maximum_codebook_entries = 4,
        },
        .codebooks = &type_one_books,
        .codebook_entries = &type_one_entries,
        .huffman_nodes = &quantizer_type_one_nodes,
        .codebook_multiplicands = &.{ 1, 2 },
        .floors = &.{},
        .residues = &.{},
        .mappings = &.{},
        .modes = &.{},
    };
    try std.testing.expectEqualDeep(
        VorbisVectorQuantization{
            .entry = 3,
            .squared_error = 0,
        },
        try quantizeVorbisVector(
            f32,
            type_one_setup,
            0,
            &.{ 2, 2 },
        ),
    );
    try std.testing.expectEqualDeep(
        VorbisVectorQuantization{
            .entry = 0,
            .squared_error = 0.5,
        },
        try quantizeVorbisVector(
            f64,
            type_one_setup,
            0,
            &.{ 1.5, 1.5 },
        ),
    );

    const type_two_entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
    };
    const type_two_books = [_]VorbisCodebook{.{
        .dimensions = 2,
        .entries = 2,
        .entry_offset = 0,
        .active_entry_count = 2,
        .tree_node_count = 1,
        .lookup_type = 2,
        .minimum_value = 1,
        .delta_value = 0.5,
        .sequence = true,
        .multiplicand_count = 4,
    }};
    const type_two_nodes = [_]VorbisHuffmanNode{.{
        .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        },
    }};
    const type_two_setup = VorbisSetup{
        .summary = .{
            .codebook_count = 1,
            .codebook_entry_count = 2,
            .codebook_multiplicand_count = 4,
            .time_count = 0,
            .floor_count = 0,
            .residue_count = 0,
            .mapping_count = 0,
            .mode_count = 0,
            .maximum_codebook_dimensions = 2,
            .maximum_codebook_entries = 2,
        },
        .codebooks = &type_two_books,
        .codebook_entries = &type_two_entries,
        .huffman_nodes = &type_two_nodes,
        .codebook_multiplicands = &.{ 0, 2, 4, 6 },
        .floors = &.{},
        .residues = &.{},
        .mappings = &.{},
        .modes = &.{},
    };
    try std.testing.expectEqualDeep(
        VorbisVectorQuantization{
            .entry = 1,
            .squared_error = 0,
        },
        try quantizeVorbisVector(
            f64,
            type_two_setup,
            0,
            &.{ 3, 7 },
        ),
    );
    var batch_entries = [_]u32{ 99, 99, 99 };
    const batch = try quantizeVorbisVectors(
        f64,
        type_one_setup,
        0,
        &.{ 1.9, 2.1, 1.5, 1.5 },
        &batch_entries,
    );
    try std.testing.expectEqualSlices(u32, &.{ 3, 0 }, batch.entries);
    try std.testing.expectEqual(@as(u32, 99), batch_entries[2]);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.52),
        batch.squared_error,
        1e-12,
    );

    var preserved_batch = [_]u32{ 99, 99 };
    try std.testing.expectError(
        error.VorbisQuantizationOutputTooSmall,
        quantizeVorbisVectors(
            f64,
            type_one_setup,
            0,
            &.{ 2, 2, 1, 1 },
            preserved_batch[0..1],
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 99, 99 },
        &preserved_batch,
    );
    try std.testing.expectError(
        error.InvalidVorbisQuantizationTarget,
        quantizeVorbisVectors(
            f64,
            type_one_setup,
            0,
            &.{ 2, 2, std.math.inf(f64), 1 },
            &preserved_batch,
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 99, 99 },
        &preserved_batch,
    );
    try std.testing.expectError(
        error.InvalidVorbisQuantizationShape,
        quantizeVorbisVectors(
            f64,
            type_one_setup,
            0,
            &.{ 2, 2, 1 },
            &preserved_batch,
        ),
    );

    var aliased_storage: [16]u8 align(@alignOf(u32)) = [_]u8{0} ** 16;
    const aliased_targets = std.mem.bytesAsSlice(
        f32,
        aliased_storage[0 .. 4 * @sizeOf(f32)],
    );
    const aliased_entries = std.mem.bytesAsSlice(
        u32,
        aliased_storage[0 .. 2 * @sizeOf(u32)],
    );
    try std.testing.expectError(
        error.OverlappingVorbisQuantization,
        quantizeVorbisVectors(
            f32,
            type_one_setup,
            0,
            aliased_targets,
            aliased_entries,
        ),
    );

    var sparse_entries = type_two_entries;
    sparse_entries[1].length = 0;
    var sparse_books = type_two_books;
    sparse_books[0].active_entry_count = 1;
    sparse_books[0].tree_node_count = 0;
    var sparse_setup = type_two_setup;
    sparse_setup.codebooks = &sparse_books;
    sparse_setup.codebook_entries = &sparse_entries;
    try std.testing.expectEqualDeep(
        VorbisVectorQuantization{
            .entry = 0,
            .squared_error = 20,
        },
        try quantizeVorbisVector(
            f64,
            sparse_setup,
            0,
            &.{ 3, 7 },
        ),
    );

    try std.testing.expectError(
        error.InvalidVorbisCodebookNumber,
        quantizeVorbisVector(f64, type_two_setup, 1, &.{ 3, 7 }),
    );
    try std.testing.expectError(
        error.InvalidVorbisQuantizationShape,
        quantizeVorbisVector(f64, type_two_setup, 0, &.{3}),
    );
    try std.testing.expectError(
        error.InvalidVorbisQuantizationTarget,
        quantizeVorbisVector(
            f64,
            type_two_setup,
            0,
            &.{ std.math.nan(f64), 7 },
        ),
    );

    var invalid_books = type_two_books;
    invalid_books[0].minimum_value = std.math.inf(f64);
    var invalid_setup = type_two_setup;
    invalid_setup.codebooks = &invalid_books;
    try std.testing.expectError(
        error.InvalidVorbisSetupState,
        quantizeVorbisVector(f64, invalid_setup, 0, &.{ 3, 7 }),
    );
}

test "Vorbis residue quantization plans classifications and entries" {
    const codebook_entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 2 },
        .{ .codeword = 1, .length = 2 },
        .{ .codeword = 2, .length = 2 },
        .{ .codeword = 3, .length = 2 },
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
    };
    const codebooks = [_]VorbisCodebook{
        .{
            .dimensions = 2,
            .entries = 4,
            .entry_offset = 0,
            .active_entry_count = 4,
            .tree_node_offset = 0,
            .tree_node_count = 3,
            .lookup_type = 0,
        },
        .{
            .dimensions = 2,
            .entries = 2,
            .entry_offset = 4,
            .active_entry_count = 2,
            .tree_node_offset = 3,
            .tree_node_count = 1,
            .lookup_type = 2,
            .delta_value = 1,
            .multiplicand_offset = 0,
            .multiplicand_count = 4,
        },
        .{
            .dimensions = 2,
            .entries = 2,
            .entry_offset = 6,
            .active_entry_count = 2,
            .tree_node_offset = 4,
            .tree_node_count = 1,
            .lookup_type = 2,
            .delta_value = 1,
            .multiplicand_offset = 4,
            .multiplicand_count = 4,
        },
    };
    const nodes = [_]VorbisHuffmanNode{
        .{ .branches = .{ 1, 2 } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
        .{ .branches = .{
            huffman_leaf_flag | 2,
            huffman_leaf_flag | 3,
        } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
    };
    var cascades = [_]u8{0} ** 64;
    cascades[0] = 1;
    cascades[1] = 1;
    var books = [_][8]i16{[_]i16{-1} ** 8} ** 64;
    books[0][0] = 1;
    books[1][0] = 2;
    const base_residue = VorbisResidue{
        .kind = .one,
        .begin = 0,
        .end = 8,
        .partition_size = 4,
        .classification_count = 2,
        .classbook = 0,
        .cascades = cascades,
        .books = books,
    };
    var residues = [_]VorbisResidue{base_residue};
    const setup = VorbisSetup{
        .summary = .{
            .codebook_count = 3,
            .codebook_entry_count = codebook_entries.len,
            .huffman_node_count = nodes.len,
            .codebook_multiplicand_count = 8,
            .time_count = 0,
            .floor_count = 0,
            .residue_count = 1,
            .mapping_count = 0,
            .mode_count = 0,
            .maximum_codebook_dimensions = 2,
            .maximum_codebook_entries = 4,
        },
        .codebooks = &codebooks,
        .codebook_entries = &codebook_entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &.{
            0, 0, 1, 1,
            0, 0, 2, 2,
        },
        .floors = &.{},
        .residues = &residues,
        .mappings = &.{},
        .modes = &.{},
    };
    const requirements =
        try requiredVorbisResidueQuantizationScratch(
            setup,
            0,
            8,
            1,
        );
    try std.testing.expectEqualDeep(
        VorbisResidueQuantizationScratchRequirements{
            .partition_values = 4,
            .vector_values = 2,
            .classifications = 2,
        },
        requirements,
    );
    try std.testing.expectEqual(
        @as(usize, 4),
        try requiredVorbisResidueQuantizationEntries(
            setup,
            0,
            8,
            1,
        ),
    );

    const mono = [_]f64{ 1, 1, 1, 1, 2, 2, 2, 2 };
    var partition_scratch: [4]f64 = undefined;
    var vector_scratch: [2]f64 = undefined;
    var classification_scratch: [2]u8 = undefined;
    var classifications = [_]u8{ 99, 99, 99 };
    var entries = [_]u32{ 99, 99, 99, 99, 99 };
    const quantized = try quantizeVorbisResidue(
        f64,
        setup,
        0,
        &.{false},
        &.{&mono},
        .{
            .partition = &partition_scratch,
            .vector = &vector_scratch,
            .classifications = &classification_scratch,
        },
        &classifications,
        &entries,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 1 },
        quantized.encoding.classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 1, 1, 1, 1 },
        quantized.encoding.entries,
    );
    try std.testing.expectEqual(@as(u8, 99), classifications[2]);
    try std.testing.expectEqual(@as(u32, 99), entries[4]);
    try std.testing.expectEqual(@as(f64, 0), quantized.squared_error);

    residues[0].cascades[0] = 0;
    residues[0].books[0][0] = -1;
    const adaptive_mono = [_]f64{2} ** mono.len;
    const thresholds = [_]f64{0.1} ** mono.len;
    var adaptive_trial: [2]u8 = undefined;
    var adaptive_best: [2]u8 = undefined;
    var adaptive_classifications = [_]u8{ 77, 77, 77 };
    var adaptive_entries = [_]u32{ 77, 77, 77, 77, 77 };
    const adaptive_quality = try quantizeVorbisResidueAdaptive(
        f64,
        setup,
        0,
        &.{false},
        &.{&adaptive_mono},
        &.{&thresholds},
        .{ .target_bits = 6 },
        .{
            .partition = &partition_scratch,
            .vector = &vector_scratch,
            .classifications = &adaptive_trial,
            .best_classifications = &adaptive_best,
        },
        &adaptive_classifications,
        &adaptive_entries,
    );
    try std.testing.expect(adaptive_quality.budget_met);
    try std.testing.expectEqual(@as(u32, 6), adaptive_quality.encoded_bits);
    try std.testing.expectEqual(@as(f64, 0), adaptive_quality.squared_error);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 1 },
        adaptive_quality.encoding.classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 1, 1, 1, 1 },
        adaptive_quality.encoding.entries,
    );
    try std.testing.expectEqual(@as(u8, 77), adaptive_classifications[2]);
    try std.testing.expectEqual(@as(u32, 77), adaptive_entries[4]);

    const adaptive_rate = try quantizeVorbisResidueAdaptive(
        f64,
        setup,
        0,
        &.{false},
        &.{&adaptive_mono},
        &.{&thresholds},
        .{ .target_bits = 2 },
        .{
            .partition = &partition_scratch,
            .vector = &vector_scratch,
            .classifications = &adaptive_trial,
            .best_classifications = &adaptive_best,
        },
        &adaptive_classifications,
        &adaptive_entries,
    );
    try std.testing.expect(adaptive_rate.budget_met);
    try std.testing.expectEqual(@as(u32, 2), adaptive_rate.encoded_bits);
    try std.testing.expect(adaptive_rate.squared_error > 0);
    try std.testing.expect(adaptive_rate.weighted_squared_error > 0);
    try std.testing.expect(adaptive_rate.audible_excess_power > 0);
    try std.testing.expect(adaptive_rate.lambda > 0);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0 },
        adaptive_rate.encoding.classifications,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        adaptive_rate.encoding.entries.len,
    );

    const impossible_budget = try quantizeVorbisResidueAdaptive(
        f64,
        setup,
        0,
        &.{false},
        &.{&adaptive_mono},
        &.{&thresholds},
        .{ .target_bits = 1 },
        .{
            .partition = &partition_scratch,
            .vector = &vector_scratch,
            .classifications = &adaptive_trial,
            .best_classifications = &adaptive_best,
        },
        &adaptive_classifications,
        &adaptive_entries,
    );
    try std.testing.expect(!impossible_budget.budget_met);
    try std.testing.expectEqual(@as(u32, 2), impossible_budget.encoded_bits);

    const mono_f32 = [_]f32{2} ** mono.len;
    const thresholds_f32 = [_]f32{0.1} ** mono.len;
    var adaptive_partition_f32: [4]f32 = undefined;
    var adaptive_vector_f32: [2]f32 = undefined;
    const adaptive_f32 = try quantizeVorbisResidueAdaptive(
        f32,
        setup,
        0,
        &.{false},
        &.{&mono_f32},
        &.{&thresholds_f32},
        .{ .target_bits = 6 },
        .{
            .partition = &adaptive_partition_f32,
            .vector = &adaptive_vector_f32,
            .classifications = &adaptive_trial,
            .best_classifications = &adaptive_best,
        },
        &adaptive_classifications,
        &adaptive_entries,
    );
    try std.testing.expectEqual(@as(f64, 0), adaptive_f32.squared_error);

    const preserved_adaptive_classifications =
        adaptive_classifications;
    const preserved_adaptive_entries = adaptive_entries;
    var invalid_thresholds = thresholds;
    invalid_thresholds[3] = 0;
    try std.testing.expectError(
        error.InvalidVorbisNoiseThreshold,
        quantizeVorbisResidueAdaptive(
            f64,
            setup,
            0,
            &.{false},
            &.{&adaptive_mono},
            &.{&invalid_thresholds},
            .{ .target_bits = 6 },
            .{
                .partition = &partition_scratch,
                .vector = &vector_scratch,
                .classifications = &adaptive_trial,
                .best_classifications = &adaptive_best,
            },
            &adaptive_classifications,
            &adaptive_entries,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &preserved_adaptive_classifications,
        &adaptive_classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &preserved_adaptive_entries,
        &adaptive_entries,
    );
    try std.testing.expectError(
        error.VorbisResidueQuantizationScratchTooSmall,
        quantizeVorbisResidueAdaptive(
            f64,
            setup,
            0,
            &.{false},
            &.{&adaptive_mono},
            &.{&thresholds},
            .{ .target_bits = 6 },
            .{
                .partition = &partition_scratch,
                .vector = &vector_scratch,
                .classifications = &adaptive_trial,
                .best_classifications = adaptive_best[0..1],
            },
            &adaptive_classifications,
            &adaptive_entries,
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisResidueQuantization,
        quantizeVorbisResidueAdaptive(
            f64,
            setup,
            0,
            &.{false},
            &.{&adaptive_mono},
            &.{&thresholds},
            .{ .target_bits = 6 },
            .{
                .partition = &partition_scratch,
                .vector = &vector_scratch,
                .classifications = &adaptive_trial,
                .best_classifications = &adaptive_trial,
            },
            &adaptive_classifications,
            &adaptive_entries,
        ),
    );
    try std.testing.expectError(
        error.VorbisResidueEntryOutputTooSmall,
        quantizeVorbisResidueAdaptive(
            f64,
            setup,
            0,
            &.{false},
            &.{&adaptive_mono},
            &.{&thresholds},
            .{ .target_bits = 6 },
            .{
                .partition = &partition_scratch,
                .vector = &vector_scratch,
                .classifications = &adaptive_trial,
                .best_classifications = &adaptive_best,
            },
            &adaptive_classifications,
            adaptive_entries[0..3],
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &preserved_adaptive_classifications,
        &adaptive_classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &preserved_adaptive_entries,
        &adaptive_entries,
    );
    try std.testing.expectError(
        error.InvalidVorbisAdaptiveResidueConfig,
        quantizeVorbisResidueAdaptive(
            f64,
            setup,
            0,
            &.{false},
            &.{&adaptive_mono},
            &.{&thresholds},
            .{
                .target_bits = 6,
                .maximum_iterations = 0,
            },
            .{
                .partition = &partition_scratch,
                .vector = &vector_scratch,
                .classifications = &adaptive_trial,
                .best_classifications = &adaptive_best,
            },
            &adaptive_classifications,
            &adaptive_entries,
        ),
    );
    residues[0].cascades[0] = 1;
    residues[0].books[0][0] = 1;

    var packet: [16]u8 = undefined;
    var writer = VorbisPacketWriter.init(&packet);
    try writer.writeResidue(
        setup,
        0,
        mono.len,
        quantized.encoding,
    );
    var decoded = [_]f64{0} ** mono.len;
    var decode_classifications: [2]u8 = undefined;
    var reader = try VorbisPacketReader.init(writer.bytes(), 0);
    _ = try reader.decodeResidue(
        f64,
        setup,
        0,
        &.{false},
        &.{&decoded},
        &decode_classifications,
    );
    try std.testing.expectEqualSlices(f64, &mono, &decoded);

    residues[0].kind = .zero;
    const type_zero = try quantizeVorbisResidue(
        f64,
        setup,
        0,
        &.{false},
        &.{&mono},
        .{
            .partition = &partition_scratch,
            .vector = &vector_scratch,
            .classifications = &classification_scratch,
        },
        classifications[0..2],
        entries[0..4],
    );
    try std.testing.expectEqual(@as(f64, 0), type_zero.squared_error);

    residues[0].kind = .one;
    var skipped_classification_scratch: [4]u8 = undefined;
    var skipped_classifications: [4]u8 = undefined;
    var skipped_entries: [4]u32 = undefined;
    const one_channel_skipped = try quantizeVorbisResidue(
        f64,
        setup,
        0,
        &.{ false, true },
        &.{ &mono, &mono },
        .{
            .partition = &partition_scratch,
            .vector = &vector_scratch,
            .classifications = &skipped_classification_scratch,
        },
        &skipped_classifications,
        &skipped_entries,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 1, 0, 0 },
        one_channel_skipped.encoding.classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 1, 1, 1, 1 },
        one_channel_skipped.encoding.entries,
    );
    try std.testing.expectEqual(
        @as(f64, 0),
        one_channel_skipped.squared_error,
    );

    residues[0].kind = .two;
    const stereo_left = [_]f32{ 1, 1, 2, 2 };
    const stereo_right = [_]f32{ 1, 1, 2, 2 };
    var stereo_partition_scratch: [4]f32 = undefined;
    var stereo_vector_scratch: [2]f32 = undefined;
    const type_two = try quantizeVorbisResidue(
        f32,
        setup,
        0,
        &.{ false, false },
        &.{ &stereo_left, &stereo_right },
        .{
            .partition = &stereo_partition_scratch,
            .vector = &stereo_vector_scratch,
            .classifications = &classification_scratch,
        },
        classifications[0..2],
        entries[0..4],
    );
    try std.testing.expectEqual(@as(f64, 0), type_two.squared_error);

    const preserved_classifications = classifications;
    const preserved_entries = entries;
    try std.testing.expectError(
        error.VorbisResidueClassificationOutputTooSmall,
        quantizeVorbisResidue(
            f32,
            setup,
            0,
            &.{ false, false },
            &.{ &stereo_left, &stereo_right },
            .{
                .partition = &stereo_partition_scratch,
                .vector = &stereo_vector_scratch,
                .classifications = &classification_scratch,
            },
            classifications[0..1],
            &entries,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &preserved_classifications,
        &classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &preserved_entries,
        &entries,
    );
    try std.testing.expectError(
        error.VorbisResidueEntryOutputTooSmall,
        quantizeVorbisResidue(
            f32,
            setup,
            0,
            &.{ false, false },
            &.{ &stereo_left, &stereo_right },
            .{
                .partition = &stereo_partition_scratch,
                .vector = &stereo_vector_scratch,
                .classifications = &classification_scratch,
            },
            &classifications,
            entries[0..3],
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &preserved_classifications,
        &classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &preserved_entries,
        &entries,
    );
    try std.testing.expectError(
        error.OverlappingVorbisResidueQuantization,
        quantizeVorbisResidue(
            f32,
            setup,
            0,
            &.{ false, false },
            &.{ &stereo_left, &stereo_right },
            .{
                .partition = &stereo_partition_scratch,
                .vector = &stereo_vector_scratch,
                .classifications = &classification_scratch,
            },
            &classification_scratch,
            &entries,
        ),
    );

    residues[0].kind = .one;
    residues[0].classification_count = 1;
    residues[0].cascades[0] = 3;
    residues[0].books[0][0] = 1;
    residues[0].books[0][1] = 1;
    var wide_codebooks = codebooks;
    wide_codebooks[0].dimensions = 40;
    wide_codebooks[0].entries = 1;
    wide_codebooks[0].active_entry_count = 1;
    wide_codebooks[0].tree_node_count = 0;
    var wide_entries = codebook_entries;
    wide_entries[0].length = 1;
    var wide_setup = setup;
    wide_setup.codebooks = &wide_codebooks;
    wide_setup.codebook_entries = &wide_entries;
    const two_pass_input = [_]f64{2} ** 8;
    var two_pass_classifications: [2]u8 = undefined;
    var two_pass_entries: [8]u32 = undefined;
    const two_pass = try quantizeVorbisResidue(
        f64,
        wide_setup,
        0,
        &.{false},
        &.{&two_pass_input},
        .{
            .partition = &partition_scratch,
            .vector = &vector_scratch,
            .classifications = &classification_scratch,
        },
        &two_pass_classifications,
        &two_pass_entries,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0 },
        two_pass.encoding.classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 1, 1, 1, 1, 1, 1, 1, 1 },
        two_pass.encoding.entries,
    );
    try std.testing.expectEqual(@as(f64, 0), two_pass.squared_error);
    var two_pass_packet: [16]u8 = undefined;
    var two_pass_writer = VorbisPacketWriter.init(&two_pass_packet);
    try two_pass_writer.writeResidue(
        wide_setup,
        0,
        two_pass_input.len,
        two_pass.encoding,
    );
    var two_pass_decoded = [_]f64{0} ** two_pass_input.len;
    var two_pass_decode_classifications: [2]u8 = undefined;
    var two_pass_reader =
        try VorbisPacketReader.init(two_pass_writer.bytes(), 0);
    _ = try two_pass_reader.decodeResidue(
        f64,
        wide_setup,
        0,
        &.{false},
        &.{&two_pass_decoded},
        &two_pass_decode_classifications,
    );
    try std.testing.expectEqualSlices(
        f64,
        &two_pass_input,
        &two_pass_decoded,
    );

    residues[0].kind = .two;
    const skipped = try quantizeVorbisResidue(
        f32,
        setup,
        0,
        &.{ true, true },
        &.{ &stereo_left, &stereo_right },
        .{
            .partition = &.{},
            .vector = &.{},
            .classifications = &.{},
        },
        &.{},
        &.{},
    );
    try std.testing.expectEqual(@as(usize, 0), skipped.encoding.entries.len);
    try std.testing.expectEqual(
        @as(usize, 0),
        skipped.encoding.classifications.len,
    );
}

test "Vorbis audio residues group and quantize submaps atomically" {
    try testVorbisAudioResidueQuantization(f32);
    try testVorbisAudioResidueQuantization(f64);
}

fn testVorbisAudioResidueQuantization(comptime Float: type) !void {
    const codebook_entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 2 },
        .{ .codeword = 1, .length = 2 },
        .{ .codeword = 2, .length = 2 },
        .{ .codeword = 3, .length = 2 },
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
    };
    const codebooks = [_]VorbisCodebook{
        .{
            .dimensions = 2,
            .entries = 4,
            .entry_offset = 0,
            .active_entry_count = 4,
            .tree_node_offset = 0,
            .tree_node_count = 3,
            .lookup_type = 0,
        },
        .{
            .dimensions = 2,
            .entries = 2,
            .entry_offset = 4,
            .active_entry_count = 2,
            .tree_node_offset = 3,
            .tree_node_count = 1,
            .lookup_type = 2,
            .delta_value = 1,
            .multiplicand_offset = 0,
            .multiplicand_count = 4,
        },
        .{
            .dimensions = 2,
            .entries = 2,
            .entry_offset = 6,
            .active_entry_count = 2,
            .tree_node_offset = 4,
            .tree_node_count = 1,
            .lookup_type = 2,
            .delta_value = 1,
            .multiplicand_offset = 4,
            .multiplicand_count = 4,
        },
    };
    const nodes = [_]VorbisHuffmanNode{
        .{ .branches = .{ 1, 2 } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
        .{ .branches = .{
            huffman_leaf_flag | 2,
            huffman_leaf_flag | 3,
        } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
    };
    var cascades = [_]u8{0} ** 64;
    cascades[1] = 1;
    var books = [_][8]i16{[_]i16{-1} ** 8} ** 64;
    books[1][0] = 2;
    const residues = [_]VorbisResidue{.{
        .kind = .one,
        .begin = 0,
        .end = 8,
        .partition_size = 4,
        .classification_count = 2,
        .classbook = 0,
        .cascades = cascades,
        .books = books,
    }};
    var x_list = [_]u16{0} ** 65;
    x_list[1] = 32;
    const floors = [_]VorbisFloor{.{ .one = .{
        .partition_count = 0,
        .partition_classes = [_]u4{0} ** 31,
        .class_count = 0,
        .classes = [_]VorbisFloorOneClass{.{
            .dimensions = 0,
            .subclass_bits = 0,
            .masterbook = -1,
            .subclass_books = [_]i16{-1} ** 8,
        }} ** 16,
        .multiplier = 1,
        .range_bits = 5,
        .point_count = 2,
        .x_list = x_list,
    } }};
    var channel_mux = [_]u4{0} ** 255;
    channel_mux[1] = 1;
    const mappings = [_]VorbisMapping{.{
        .submap_count = 2,
        .coupling_step_count = 0,
        .coupling_steps = [_]VorbisCouplingStep{.{
            .magnitude = 0,
            .angle = 0,
        }} ** 256,
        .channel_mux = channel_mux,
        .submaps = [_]VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    }};
    const modes = [_]VorbisMode{.{
        .large_block = false,
        .mapping = 0,
    }};
    const setup = VorbisSetup{
        .summary = .{
            .codebook_count = codebooks.len,
            .codebook_entry_count = codebook_entries.len,
            .huffman_node_count = nodes.len,
            .codebook_multiplicand_count = 8,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 2,
            .maximum_codebook_entries = 4,
        },
        .codebooks = &codebooks,
        .codebook_entries = &codebook_entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &.{
            0, 0, 1, 1,
            0, 0, 2, 2,
        },
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    };
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    const header = VorbisAudioPacketHeader{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = 64,
        .payload_bit_offset = 1,
    };
    try std.testing.expectEqual(
        VorbisAudioResidueQuantizationStorageRequirements{
            .encodings = 2,
            .submap_results = 2,
            .do_not_encode = 2,
            .classifications = 4,
            .entries = 8,
            .partition_values = 4,
            .vector_values = 2,
            .classification_scratch = 2,
        },
        try requiredVorbisAudioResidueQuantizationStorage(
            identification,
            setup,
            header,
        ),
    );

    var residue_values = [_]Float{0} ** 64;
    @memset(residue_values[0..8], 2);
    @memset(residue_values[32..40], 2);
    const thresholds = [_]Float{0.1} ** 64;
    var partition: [4]Float = undefined;
    var vector: [2]Float = undefined;
    var classification_scratch: [2]u8 = undefined;
    var best_classifications: [2]u8 = undefined;
    var trial_classifications: [4]u8 = undefined;
    var trial_entries: [8]u32 = undefined;
    var trial_skips: [2]bool = undefined;
    const sentinel_encoding = VorbisResidueEncoding{
        .do_not_encode = &.{true},
        .classifications = &.{99},
        .entries = &.{99},
    };
    const sentinel_result = VorbisAudioResidueSubmapResult{
        .target_bits = 91,
        .encoded_bits = 92,
        .budget_met = false,
        .squared_error = 93,
        .weighted_squared_error = 94,
        .audible_excess_power = 95,
        .lambda = 96,
        .iterations = 97,
    };
    var retained_encodings =
        [_]VorbisResidueEncoding{sentinel_encoding} ** 3;
    var retained_results =
        [_]VorbisAudioResidueSubmapResult{sentinel_result} ** 3;
    var retained_skips = [_]bool{true} ** 3;
    var retained_classifications = [_]u8{98} ** 5;
    var retained_entries = [_]u32{99} ** 9;
    const budget = VorbisPacketBitBudget{
        .packet_index = 0,
        .nominal_bits = 12,
        .target_bits = 12,
        .reservoir_balance_before = 0,
    };
    const plan = try quantizeVorbisAudioResiduesAdaptive(
        Float,
        identification,
        setup,
        header,
        &residue_values,
        &thresholds,
        &.{ false, false },
        budget,
        0,
        &.{ 1, 1 },
        .{},
        .{
            .partition = &partition,
            .vector = &vector,
            .classifications = &classification_scratch,
            .best_classifications = &best_classifications,
            .output_classifications = &trial_classifications,
            .entries = &trial_entries,
            .do_not_encode = &trial_skips,
        },
        .{
            .encodings = &retained_encodings,
            .submap_results = &retained_results,
            .do_not_encode = &retained_skips,
            .classifications = &retained_classifications,
            .entries = &retained_entries,
        },
    );
    try std.testing.expectEqual(
        VorbisResidueBitAllocation{
            .packet_target_bits = 12,
            .fixed_packet_bits = 0,
            .residue_bits = 12,
        },
        plan.allocation,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 1, 1, 1 },
        plan.classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 1, 1, 1, 1, 1, 1, 1, 1 },
        plan.entries,
    );
    for (plan.submap_results) |result| {
        try std.testing.expectEqual(@as(u32, 6), result.target_bits);
        try std.testing.expectEqual(@as(u32, 6), result.encoded_bits);
        try std.testing.expect(result.budget_met);
        try std.testing.expectEqual(@as(f64, 0), result.squared_error);
    }
    for (plan.encodings) |encoding| {
        try std.testing.expectEqualSlices(
            bool,
            &.{false},
            encoding.do_not_encode,
        );
        try std.testing.expectEqualSlices(
            u8,
            &.{ 1, 1 },
            encoding.classifications,
        );
        try std.testing.expectEqualSlices(
            u32,
            &.{ 1, 1, 1, 1 },
            encoding.entries,
        );
    }
    try std.testing.expectEqual(
        sentinel_encoding,
        retained_encodings[2],
    );
    try std.testing.expectEqual(
        sentinel_result,
        retained_results[2],
    );
    try std.testing.expect(retained_skips[2]);
    try std.testing.expectEqual(@as(u8, 98), retained_classifications[4]);
    try std.testing.expectEqual(@as(u32, 99), retained_entries[8]);

    const floor_y = [_]u32{ 100, 100 };
    const floor_encodings = [_]VorbisFloorPacketEncoding{
        .{ .one = .{
            .used = true,
            .y_values = &floor_y,
        } },
        .{ .one = .{
            .used = true,
            .y_values = &floor_y,
        } },
    };
    try std.testing.expect(
        try requiredVorbisAudioPacketBytes(
            identification,
            setup,
            .{
                .mode_number = 0,
                .floors = &floor_encodings,
                .residues = plan.encodings,
            },
        ) > 0,
    );

    const encodings_before = retained_encodings;
    const results_before = retained_results;
    const skips_before = retained_skips;
    const classifications_before = retained_classifications;
    const entries_before = retained_entries;
    var invalid_thresholds = thresholds;
    invalid_thresholds[63] = 0;
    try std.testing.expectError(
        error.InvalidVorbisNoiseThreshold,
        quantizeVorbisAudioResiduesAdaptive(
            Float,
            identification,
            setup,
            header,
            &residue_values,
            &invalid_thresholds,
            &.{ false, false },
            budget,
            0,
            &.{ 1, 1 },
            .{},
            .{
                .partition = &partition,
                .vector = &vector,
                .classifications = &classification_scratch,
                .best_classifications = &best_classifications,
                .output_classifications = &trial_classifications,
                .entries = &trial_entries,
                .do_not_encode = &trial_skips,
            },
            .{
                .encodings = &retained_encodings,
                .submap_results = &retained_results,
                .do_not_encode = &retained_skips,
                .classifications = &retained_classifications,
                .entries = &retained_entries,
            },
        ),
    );
    try std.testing.expectEqualDeep(
        encodings_before,
        retained_encodings,
    );
    try std.testing.expectEqualSlices(
        VorbisAudioResidueSubmapResult,
        &results_before,
        &retained_results,
    );
    try std.testing.expectEqualSlices(
        bool,
        &skips_before,
        &retained_skips,
    );
    try std.testing.expectEqualSlices(
        u8,
        &classifications_before,
        &retained_classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &entries_before,
        &retained_entries,
    );
    try std.testing.expectError(
        error.VorbisAudioResidueQuantizationScratchTooSmall,
        quantizeVorbisAudioResiduesAdaptive(
            Float,
            identification,
            setup,
            header,
            &residue_values,
            &thresholds,
            &.{ false, false },
            budget,
            0,
            &.{ 1, 1 },
            .{},
            .{
                .partition = partition[0..3],
                .vector = &vector,
                .classifications = &classification_scratch,
                .best_classifications = &best_classifications,
                .output_classifications = &trial_classifications,
                .entries = &trial_entries,
                .do_not_encode = &trial_skips,
            },
            .{
                .encodings = &retained_encodings,
                .submap_results = &retained_results,
                .do_not_encode = &retained_skips,
                .classifications = &retained_classifications,
                .entries = &retained_entries,
            },
        ),
    );
    try std.testing.expectError(
        error.VorbisAudioResidueQuantizationStorageTooSmall,
        quantizeVorbisAudioResiduesAdaptive(
            Float,
            identification,
            setup,
            header,
            &residue_values,
            &thresholds,
            &.{ false, false },
            budget,
            0,
            &.{ 1, 1 },
            .{},
            .{
                .partition = &partition,
                .vector = &vector,
                .classifications = &classification_scratch,
                .best_classifications = &best_classifications,
                .output_classifications = &trial_classifications,
                .entries = &trial_entries,
                .do_not_encode = &trial_skips,
            },
            .{
                .encodings = retained_encodings[0..1],
                .submap_results = &retained_results,
                .do_not_encode = &retained_skips,
                .classifications = &retained_classifications,
                .entries = &retained_entries,
            },
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisAudioResidueQuantizationStorage,
        quantizeVorbisAudioResiduesAdaptive(
            Float,
            identification,
            setup,
            header,
            &residue_values,
            &thresholds,
            &.{ false, false },
            budget,
            0,
            &.{ 1, 1 },
            .{},
            .{
                .partition = &partition,
                .vector = &vector,
                .classifications = &classification_scratch,
                .best_classifications = &classification_scratch,
                .output_classifications = &trial_classifications,
                .entries = &trial_entries,
                .do_not_encode = &trial_skips,
            },
            .{
                .encodings = &retained_encodings,
                .submap_results = &retained_results,
                .do_not_encode = &retained_skips,
                .classifications = &retained_classifications,
                .entries = &retained_entries,
            },
        ),
    );
}

test "Vorbis residues decode layouts transactionally with caller scratch" {
    const entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
    };
    const codebooks = [_]VorbisCodebook{
        .{
            .dimensions = 1,
            .entries = 2,
            .entry_offset = 0,
            .active_entry_count = 2,
            .tree_node_offset = 0,
            .tree_node_count = 1,
            .lookup_type = 0,
        },
        .{
            .dimensions = 2,
            .entries = 2,
            .entry_offset = 2,
            .active_entry_count = 2,
            .tree_node_offset = 1,
            .tree_node_count = 1,
            .lookup_type = 2,
            .delta_value = 1,
            .multiplicand_count = 4,
        },
    };
    const nodes = [_]VorbisHuffmanNode{
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
    };
    var cascades = [_]u8{0} ** 64;
    cascades[0] = 1;
    cascades[1] = 1;
    var books = [_][8]i16{[_]i16{-1} ** 8} ** 64;
    books[0][0] = 1;
    books[1][0] = 1;
    var residues = [_]VorbisResidue{.{
        .kind = .zero,
        .begin = 0,
        .end = 8,
        .partition_size = 4,
        .classification_count = 2,
        .classbook = 0,
        .cascades = cascades,
        .books = books,
    }};
    var setup = VorbisSetup{
        .summary = .{
            .codebook_count = 2,
            .codebook_entry_count = 4,
            .huffman_node_count = 2,
            .codebook_multiplicand_count = 4,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 2,
            .maximum_codebook_entries = 2,
        },
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &.{ 1, 2, 3, 4 },
        .floors = &.{},
        .residues = &residues,
        .mappings = &.{},
        .modes = &.{.{ .large_block = false, .mapping = 0 }},
    };
    try std.testing.expectEqual(
        @as(usize, 4),
        try requiredVorbisResidueClassifications(residues[0], 8, 2),
    );

    var zero_left = [_]f32{99} ** 8;
    var zero_right = [_]f32{99} ** 8;
    const zero_outputs = [_][]f32{ &zero_left, &zero_right };
    var zero_scratch: [4]u8 = undefined;
    var hostile_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    hostile_reader.bit_offset = std.math.maxInt(usize);
    try std.testing.expectError(
        error.InvalidVorbisPacketBitOffset,
        hostile_reader.decodeResidue(
            f32,
            setup,
            0,
            &.{ false, true },
            &zero_outputs,
            &zero_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 99, 99, 99, 99, 99, 99, 99, 99 },
        &zero_left,
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        hostile_reader.bit_offset,
    );

    var zero_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    const zero_result = try zero_reader.decodeResidue(
        f32,
        setup,
        0,
        &.{ false, true },
        &zero_outputs,
        &zero_scratch,
    );
    try std.testing.expect(!zero_result.truncated);
    try std.testing.expectEqual(@as(usize, 6), zero_reader.bit_offset);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1, 3, 2, 4, 3, 1, 4, 2 },
        &zero_left,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, 0, 0, 0, 0, 0, 0, 0 },
        &zero_right,
    );

    residues[0].kind = .one;
    var one_left = [_]f64{99} ** 8;
    var one_right = [_]f64{99} ** 8;
    const one_outputs = [_][]f64{ &one_left, &one_right };
    var one_scratch: [4]u8 = undefined;
    var one_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    _ = try one_reader.decodeResidue(
        f64,
        setup,
        0,
        &.{ false, true },
        &one_outputs,
        &one_scratch,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1, 2, 3, 4, 3, 4, 1, 2 },
        &one_left,
    );

    residues[0].kind = .two;
    try std.testing.expectEqual(
        @as(usize, 2),
        try requiredVorbisResidueClassifications(residues[0], 4, 2),
    );
    var two_left = [_]f32{99} ** 4;
    var two_right = [_]f32{99} ** 4;
    const two_outputs = [_][]f32{ &two_left, &two_right };
    var two_scratch: [2]u8 = undefined;
    var two_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    _ = try two_reader.decodeResidue(
        f32,
        setup,
        0,
        &.{ false, true },
        &two_outputs,
        &two_scratch,
    );
    try std.testing.expectEqualSlices(f32, &.{ 1, 3, 3, 1 }, &two_left);
    try std.testing.expectEqualSlices(f32, &.{ 2, 4, 4, 2 }, &two_right);

    @memset(&two_left, 99);
    @memset(&two_right, 99);
    var all_skipped_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    _ = try all_skipped_reader.decodeResidue(
        f32,
        setup,
        0,
        &.{ true, true },
        &two_outputs,
        &two_scratch,
    );
    try std.testing.expectEqual(@as(usize, 0), all_skipped_reader.bit_offset);
    try std.testing.expectEqualSlices(f32, &.{ 0, 0, 0, 0 }, &two_left);
    try std.testing.expectEqualSlices(f32, &.{ 0, 0, 0, 0 }, &two_right);

    residues[0].kind = .one;
    residues[0].end = 12;
    var partial_left = [_]f32{99} ** 12;
    var partial_right = [_]f32{99} ** 12;
    const partial_outputs = [_][]f32{ &partial_left, &partial_right };
    var partial_scratch: [6]u8 = undefined;
    var partial_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    const partial = try partial_reader.decodeResidue(
        f32,
        setup,
        0,
        &.{ false, true },
        &partial_outputs,
        &partial_scratch,
    );
    try std.testing.expect(partial.truncated);
    try std.testing.expectEqual(@as(usize, 8), partial_reader.bit_offset);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1, 2, 3, 4, 3, 4, 1, 2, 1, 2, 0, 0 },
        &partial_left,
    );

    var preserved = [_]f32{99} ** 12;
    const overlapping_outputs = [_][]f32{ &preserved, &preserved };
    var overlap_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    try std.testing.expectError(
        error.OverlappingVorbisResidueOutput,
        overlap_reader.decodeResidue(
            f32,
            setup,
            0,
            &.{ false, false },
            &overlapping_outputs,
            &partial_scratch,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), overlap_reader.bit_offset);
    try std.testing.expectEqual(@as(f32, 99), preserved[0]);

    var alias_output = [_]f32{99} ** 12;
    var other_output = [_]f32{99} ** 12;
    const alias_outputs = [_][]f32{ &alias_output, &other_output };
    var alias_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    try std.testing.expectError(
        error.OverlappingVorbisResidueScratch,
        alias_reader.decodeResidue(
            f32,
            setup,
            0,
            &.{ false, false },
            &alias_outputs,
            std.mem.sliceAsBytes(alias_output[0..]),
        ),
    );
    try std.testing.expectEqual(@as(f32, 99), alias_output[0]);

    @memset(&partial_left, 99);
    @memset(&partial_right, 99);
    var short_scratch: [5]u8 = undefined;
    var short_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    try std.testing.expectError(
        error.VorbisResidueScratchTooSmall,
        short_reader.decodeResidue(
            f32,
            setup,
            0,
            &.{ false, true },
            &partial_outputs,
            &short_scratch,
        ),
    );
    try std.testing.expectEqual(@as(f32, 99), partial_right[11]);

    var invalid_residues = residues;
    invalid_residues[0].books[0][0] = -1;
    setup.residues = &invalid_residues;
    var invalid_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    try std.testing.expectError(
        error.InvalidVorbisSetupState,
        invalid_reader.decodeResidue(
            f32,
            setup,
            0,
            &.{ false, true },
            &partial_outputs,
            &partial_scratch,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), invalid_reader.bit_offset);
}

test "Vorbis channel coupling inverts through transactional scratch" {
    var coupling_steps = [_]VorbisCouplingStep{.{
        .magnitude = 0,
        .angle = 0,
    }} ** 256;
    coupling_steps[0] = .{ .magnitude = 0, .angle = 1 };
    const mapping = VorbisMapping{
        .submap_count = 1,
        .coupling_step_count = 1,
        .coupling_steps = coupling_steps,
        .channel_mux = [_]u4{0} ** 255,
        .submaps = [_]VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    };
    try std.testing.expectEqual(
        @as(usize, 8),
        try requiredVorbisCouplingScratch(2, 4),
    );
    const original_first = [_]f64{
        4, 3, -4, -3, 1, -1, 2, -2,
    };
    const original_second = [_]f64{
        3, 4, -3, -4, -1, 1, -2, 2,
    };
    var forward_first = original_first;
    var forward_second = original_second;
    const forward_channels =
        [_][]f64{ &forward_first, &forward_second };
    var forward_scratch: [16]f64 = undefined;
    try forwardCoupleVorbisChannels(
        f64,
        mapping,
        &forward_channels,
        &forward_scratch,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 4, 4, -4, -4, -1, 1, -2, 2 },
        &forward_first,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1, -1, 1, -1, -2, -2, -4, -4 },
        &forward_second,
    );
    try inverseCoupleVorbisChannels(
        f64,
        mapping,
        &forward_channels,
        &forward_scratch,
    );
    try std.testing.expectEqualSlices(
        f64,
        &original_first,
        &forward_first,
    );
    try std.testing.expectEqualSlices(
        f64,
        &original_second,
        &forward_second,
    );
    var short_forward_scratch: [15]f64 = undefined;
    try std.testing.expectError(
        error.VorbisCouplingScratchTooSmall,
        forwardCoupleVorbisChannels(
            f64,
            mapping,
            &forward_channels,
            &short_forward_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &original_first,
        &forward_first,
    );
    var invalid_forward_mapping = mapping;
    invalid_forward_mapping.coupling_steps[0].angle = 0;
    try std.testing.expectError(
        error.InvalidVorbisMappingState,
        forwardCoupleVorbisChannels(
            f64,
            invalid_forward_mapping,
            &forward_channels,
            &forward_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &original_second,
        &forward_second,
    );

    var magnitude = [_]f64{ 4, 4, -4, -4 };
    var angle = [_]f64{ 1, -1, 1, -1 };
    const channels = [_][]f64{ &magnitude, &angle };
    var scratch: [8]f64 = undefined;
    try inverseCoupleVorbisChannels(
        f64,
        mapping,
        &channels,
        &scratch,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 4, 3, -4, -3 },
        &magnitude,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 3, 4, -3, -4 },
        &angle,
    );

    magnitude = [_]f64{ 4, 4, -4, -4 };
    angle = [_]f64{ 1, -1, 1, -1 };
    var short_scratch: [7]f64 = undefined;
    try std.testing.expectError(
        error.VorbisCouplingScratchTooSmall,
        inverseCoupleVorbisChannels(
            f64,
            mapping,
            &channels,
            &short_scratch,
        ),
    );
    try std.testing.expectEqual(@as(f64, 4), magnitude[0]);

    var alias_backing = [_]f64{ 4, 4, -4, -4, 0, 0, 0, 0 };
    const alias_channels = [_][]f64{ alias_backing[0..4], &angle };
    try std.testing.expectError(
        error.OverlappingVorbisCouplingScratch,
        inverseCoupleVorbisChannels(
            f64,
            mapping,
            &alias_channels,
            &alias_backing,
        ),
    );
    try std.testing.expectEqual(@as(f64, 4), alias_backing[0]);

    var invalid_mapping = mapping;
    invalid_mapping.coupling_steps[0].angle = 0;
    try std.testing.expectError(
        error.InvalidVorbisMappingState,
        inverseCoupleVorbisChannels(
            f64,
            invalid_mapping,
            &channels,
            &scratch,
        ),
    );
    try std.testing.expectEqual(@as(f64, 4), magnitude[0]);

    var chained_mapping = mapping;
    chained_mapping.coupling_step_count = 2;
    chained_mapping.coupling_steps[1] = .{
        .magnitude = 1,
        .angle = 2,
    };
    const chained_original = [3][3]f32{
        .{ 4, -2, 1 },
        .{ 1, 3, -4 },
        .{ -2, 1, 2 },
    };
    var chained_values = chained_original;
    const chained_channels = [_][]f32{
        &chained_values[0],
        &chained_values[1],
        &chained_values[2],
    };
    var chained_scratch: [9]f32 = undefined;
    try forwardCoupleVorbisChannels(
        f32,
        chained_mapping,
        &chained_channels,
        &chained_scratch,
    );
    try inverseCoupleVorbisChannels(
        f32,
        chained_mapping,
        &chained_channels,
        &chained_scratch,
    );
    try std.testing.expectEqualDeep(
        chained_original,
        chained_values,
    );

    angle[0] = std.math.inf(f64);
    try std.testing.expectError(
        error.InvalidVorbisChannelValue,
        inverseCoupleVorbisChannels(
            f64,
            mapping,
            &channels,
            &scratch,
        ),
    );
    try std.testing.expectEqual(@as(f64, 4), magnitude[0]);

    var shared = [_]f32{ 1, 2 };
    const overlapping = [_][]f32{ &shared, &shared };
    var overlap_scratch: [4]f32 = undefined;
    try std.testing.expectError(
        error.OverlappingVorbisChannelOutput,
        inverseCoupleVorbisChannels(
            f32,
            mapping,
            &overlapping,
            &overlap_scratch,
        ),
    );
}

test "Vorbis masking thresholds survive floor normalization and coupling" {
    try testVorbisNoiseThresholdCoupling(f32);
    try testVorbisNoiseThresholdCoupling(f64);
}

fn testVorbisNoiseThresholdCoupling(comptime Float: type) !void {
    const thresholds = [_]Float{ 0.1, 0.2, 0.4, 0.8 };
    const floor_curve = [_]Float{ 0.5, 2, 4, 0.25 };
    var normalized: [4]Float = undefined;
    try normalizeVorbisNoiseThresholds(
        Float,
        &thresholds,
        &floor_curve,
        &normalized,
    );
    const expected = [_]Float{ 0.2, 0.1, 0.1, 3.2 };
    for (normalized, expected) |actual, wanted| {
        try std.testing.expectApproxEqAbs(
            wanted,
            actual,
            16 * std.math.floatEps(Float),
        );
    }
    var in_place = thresholds;
    try normalizeVorbisNoiseThresholds(
        Float,
        &in_place,
        &floor_curve,
        &in_place,
    );
    try std.testing.expectEqualSlices(Float, &normalized, &in_place);

    var coupling_steps = [_]VorbisCouplingStep{.{
        .magnitude = 0,
        .angle = 0,
    }} ** 256;
    coupling_steps[0] = .{ .magnitude = 0, .angle = 1 };
    const mapping = VorbisMapping{
        .submap_count = 1,
        .coupling_step_count = 1,
        .coupling_steps = coupling_steps,
        .channel_mux = [_]u4{0} ** 255,
        .submaps = [_]VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    };
    var first_threshold = [_]Float{0.4};
    var second_threshold = [_]Float{0.4};
    const first_source_value = [_]Float{0.4};
    const second_source_value = [_]Float{0.2};
    const source_channels = [_][]const Float{
        &first_source_value,
        &second_source_value,
    };
    const threshold_channels = [_][]Float{
        &first_threshold,
        &second_threshold,
    };
    var value_scratch: [2]Float = undefined;
    var threshold_scratch: [2]Float = undefined;
    try forwardCoupleVorbisNoiseThresholds(
        Float,
        mapping,
        &source_channels,
        &threshold_channels,
        &value_scratch,
        &threshold_scratch,
    );
    try std.testing.expectApproxEqAbs(
        @as(Float, 0.2),
        first_threshold[0],
        4 * std.math.floatEps(Float),
    );
    try std.testing.expectApproxEqAbs(
        @as(Float, 0.2),
        second_threshold[0],
        4 * std.math.floatEps(Float),
    );

    const source_values = [_]Float{ -0.2, 0, 0.2 };
    const perturbation_signs = [_]Float{ -1, 1 };
    for (source_values) |first_source| {
        for (source_values) |second_source| {
            var bounded_first_threshold = [_]Float{0.4};
            var bounded_second_threshold = [_]Float{0.4};
            const bounded_source_channels = [_][]const Float{
                &[_]Float{first_source},
                &[_]Float{second_source},
            };
            const bounded_threshold_channels = [_][]Float{
                &bounded_first_threshold,
                &bounded_second_threshold,
            };
            try forwardCoupleVorbisNoiseThresholds(
                Float,
                mapping,
                &bounded_source_channels,
                &bounded_threshold_channels,
                &value_scratch,
                &threshold_scratch,
            );
            for (perturbation_signs) |first_sign| {
                for (perturbation_signs) |second_sign| {
                    var first = [_]Float{first_source};
                    var second = [_]Float{second_source};
                    const channels = [_][]Float{ &first, &second };
                    var scratch: [2]Float = undefined;
                    try forwardCoupleVorbisChannels(
                        Float,
                        mapping,
                        &channels,
                        &scratch,
                    );
                    first[0] +=
                        first_sign * bounded_first_threshold[0];
                    second[0] +=
                        second_sign * bounded_second_threshold[0];
                    try inverseCoupleVorbisChannels(
                        Float,
                        mapping,
                        &channels,
                        &scratch,
                    );
                    const tolerance =
                        @as(Float, 0.4) +
                        32 * std.math.floatEps(Float);
                    try std.testing.expect(
                        @abs(first[0] - first_source) <= tolerance,
                    );
                    try std.testing.expect(
                        @abs(second[0] - second_source) <= tolerance,
                    );
                }
            }
        }
    }

    var chained_mapping = mapping;
    chained_mapping.coupling_step_count = 2;
    chained_mapping.coupling_steps[1] = .{
        .magnitude = 0,
        .angle = 2,
    };
    var chained_first = [_]Float{0.8};
    var chained_second = [_]Float{0.4};
    var chained_third = [_]Float{0.2};
    const chained_source_first = [_]Float{10};
    const chained_source_second = [_]Float{5};
    const chained_source_third = [_]Float{2};
    const chained_sources = [_][]const Float{
        &chained_source_first,
        &chained_source_second,
        &chained_source_third,
    };
    const chained_thresholds = [_][]Float{
        &chained_first,
        &chained_second,
        &chained_third,
    };
    var chained_value_scratch: [3]Float = undefined;
    var chained_scratch: [3]Float = undefined;
    try forwardCoupleVorbisNoiseThresholds(
        Float,
        chained_mapping,
        &chained_sources,
        &chained_thresholds,
        &chained_value_scratch,
        &chained_scratch,
    );
    try std.testing.expectApproxEqAbs(
        @as(Float, 0.1),
        chained_first[0],
        4 * std.math.floatEps(Float),
    );
    try std.testing.expectApproxEqAbs(
        @as(Float, 0.2),
        chained_second[0],
        4 * std.math.floatEps(Float),
    );
    try std.testing.expectApproxEqAbs(
        @as(Float, 0.1),
        chained_third[0],
        4 * std.math.floatEps(Float),
    );

    var preserved = [_]Float{9} ** 4;
    var invalid_thresholds = thresholds;
    invalid_thresholds[3] = 0;
    try std.testing.expectError(
        error.InvalidVorbisNoiseThreshold,
        normalizeVorbisNoiseThresholds(
            Float,
            &invalid_thresholds,
            &floor_curve,
            &preserved,
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{9} ** 4),
        &preserved,
    );
    var overlap = [_]Float{ 0.1, 0.2, 0.3, 0.4, 0.5 };
    try std.testing.expectError(
        error.OverlappingVorbisNoiseThresholdNormalization,
        normalizeVorbisNoiseThresholds(
            Float,
            overlap[0..4],
            &floor_curve,
            overlap[1..5],
        ),
    );

    first_threshold[0] = 0;
    second_threshold[0] = 0.4;
    const preserved_first = first_threshold;
    const preserved_second = second_threshold;
    try std.testing.expectError(
        error.InvalidVorbisNoiseThreshold,
        forwardCoupleVorbisNoiseThresholds(
            Float,
            mapping,
            &source_channels,
            &threshold_channels,
            &value_scratch,
            &threshold_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_first,
        &first_threshold,
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_second,
        &second_threshold,
    );
    first_threshold[0] = 0.4;
    var short_scratch: [1]Float = undefined;
    try std.testing.expectError(
        error.VorbisCouplingScratchTooSmall,
        forwardCoupleVorbisNoiseThresholds(
            Float,
            mapping,
            &source_channels,
            &threshold_channels,
            &short_scratch,
            &threshold_scratch,
        ),
    );
    const overlapping_channels = [_][]Float{
        &first_threshold,
        &first_threshold,
    };
    try std.testing.expectError(
        error.OverlappingVorbisChannelOutput,
        forwardCoupleVorbisNoiseThresholds(
            Float,
            mapping,
            &source_channels,
            &overlapping_channels,
            &value_scratch,
            &threshold_scratch,
        ),
    );
    var invalid_source_value = first_source_value;
    invalid_source_value[0] = std.math.nan(Float);
    const invalid_sources = [_][]const Float{
        &invalid_source_value,
        &second_source_value,
    };
    const before_invalid_first = first_threshold;
    const before_invalid_second = second_threshold;
    try std.testing.expectError(
        error.InvalidVorbisChannelValue,
        forwardCoupleVorbisNoiseThresholds(
            Float,
            mapping,
            &invalid_sources,
            &threshold_channels,
            &value_scratch,
            &threshold_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &before_invalid_first,
        &first_threshold,
    );
    try std.testing.expectEqualSlices(
        Float,
        &before_invalid_second,
        &second_threshold,
    );
    var invalid_mapping = mapping;
    invalid_mapping.coupling_steps[0].angle = 0;
    try std.testing.expectError(
        error.InvalidVorbisMappingState,
        forwardCoupleVorbisNoiseThresholds(
            Float,
            invalid_mapping,
            &source_channels,
            &threshold_channels,
            &value_scratch,
            &threshold_scratch,
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisCouplingScratch,
        forwardCoupleVorbisNoiseThresholds(
            Float,
            mapping,
            &source_channels,
            &threshold_channels,
            &value_scratch,
            &value_scratch,
        ),
    );
    var alias_backing = [_]Float{ 0.4, 0.4 };
    const alias_channels = [_][]Float{
        alias_backing[0..1],
        alias_backing[1..2],
    };
    try std.testing.expectError(
        error.OverlappingVorbisCouplingScratch,
        forwardCoupleVorbisNoiseThresholds(
            Float,
            mapping,
            &source_channels,
            &alias_channels,
            &alias_backing,
            &threshold_scratch,
        ),
    );
}

test "Vorbis floor packets decode retained type zero and type one setup" {
    var floor_zero_packet_storage: [128]u8 = undefined;
    const floor_zero_packet = makeTestVorbisSetup(
        &floor_zero_packet_storage,
        .unordered,
        false,
        true,
    );
    var floor_zero_codebooks: [1]VorbisCodebook = undefined;
    var floor_zero_entries: [2]VorbisCodebookEntry = undefined;
    var floor_zero_nodes: [1]VorbisHuffmanNode = undefined;
    var floor_zero_multiplicands: [2]u32 = undefined;
    var floor_zero_floors: [1]VorbisFloor = undefined;
    var floor_zero_residues: [1]VorbisResidue = undefined;
    var floor_zero_mappings: [1]VorbisMapping = undefined;
    var floor_zero_modes: [1]VorbisMode = undefined;
    const floor_zero_setup = try parseVorbisSetup(
        floor_zero_packet.bytes,
        1,
        .{
            .codebooks = &floor_zero_codebooks,
            .codebook_entries = &floor_zero_entries,
            .huffman_nodes = &floor_zero_nodes,
            .codebook_multiplicands = &floor_zero_multiplicands,
            .floors = &floor_zero_floors,
            .residues = &floor_zero_residues,
            .mappings = &floor_zero_mappings,
            .modes = &floor_zero_modes,
        },
    );
    var hostile_floor_zero = try VorbisPacketReader.init(&.{0}, 0);
    hostile_floor_zero.bit_offset = std.math.maxInt(usize);
    var hostile_coefficients = [_]f64{99};
    try std.testing.expectError(
        error.InvalidVorbisPacketBitOffset,
        hostile_floor_zero.decodeFloorZero(
            floor_zero_setup,
            0,
            &hostile_coefficients,
        ),
    );
    try std.testing.expectEqual(@as(f64, 99), hostile_coefficients[0]);

    var floor_zero_audio_storage: [4]u8 = undefined;
    var floor_zero_writer =
        TestVorbisBitWriter.init(&floor_zero_audio_storage);
    floor_zero_writer.write(5, 8);
    floor_zero_writer.write(0, 1);
    floor_zero_writer.write(1, 1);
    var floor_zero_reader = try VorbisPacketReader.init(
        floor_zero_audio_storage[0..2],
        0,
    );
    var coefficients = [_]f64{99};
    const floor_zero_result = try floor_zero_reader.decodeFloorZero(
        floor_zero_setup,
        0,
        &coefficients,
    );
    try std.testing.expect(floor_zero_result.used);
    try std.testing.expectEqual(@as(u64, 5), floor_zero_result.amplitude);
    try std.testing.expectEqual(@as(u8, 1), floor_zero_result.coefficient_count);
    try std.testing.expectEqual(@as(f64, 1), coefficients[0]);
    try std.testing.expectEqual(@as(usize, 10), floor_zero_reader.bit_offset);
    const retained_floor_zero = switch (floor_zero_setup.floors[0]) {
        .zero => |floor| floor,
        .one => return error.TestExpectedFloorZero,
    };
    var floor_zero_curve: [4]f64 = undefined;
    try synthesizeVorbisFloorZero(
        f64,
        retained_floor_zero,
        floor_zero_result,
        &coefficients,
        &floor_zero_curve,
    );
    const expected_floor_zero_curve = [_]f64{
        0.0013426457711833558,
        0.001098155656368672,
        0.0010932223306766293,
        0.0010921548064638331,
    };
    for (floor_zero_curve, expected_floor_zero_curve) |actual, expected| {
        try std.testing.expectApproxEqAbs(expected, actual, 1e-14);
    }

    var maximum_order_floor = retained_floor_zero;
    maximum_order_floor.order = 255;
    var maximum_order_coefficients: [255]f64 = undefined;
    for (&maximum_order_coefficients, 0..) |*coefficient, index| {
        coefficient.* =
            std.math.pi * @as(f64, @floatFromInt(index + 1)) / 256.0;
    }
    var maximum_order_curve: [16]f64 = undefined;
    try synthesizeVorbisFloorZero(
        f64,
        maximum_order_floor,
        .{
            .used = true,
            .amplitude = floor_zero_result.amplitude,
            .coefficient_count = 255,
        },
        &maximum_order_coefficients,
        &maximum_order_curve,
    );
    for (maximum_order_curve) |value| {
        try std.testing.expect(std.math.isFinite(value));
        try std.testing.expect(value > 0);
    }

    var invalid_coefficients = [_]f64{std.math.nan(f64)};
    var preserved_floor_zero_curve = [_]f64{99} ** 4;
    try std.testing.expectError(
        error.InvalidVorbisFloorPacketState,
        synthesizeVorbisFloorZero(
            f64,
            retained_floor_zero,
            floor_zero_result,
            &invalid_coefficients,
            &preserved_floor_zero_curve,
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 99, 99, 99, 99 },
        &preserved_floor_zero_curve,
    );

    var truncated_zero = try VorbisPacketReader.init(&.{5}, 0);
    var preserved_coefficient = [_]f64{99};
    const truncated_zero_result = try truncated_zero.decodeFloorZero(
        floor_zero_setup,
        0,
        &preserved_coefficient,
    );
    try std.testing.expect(!truncated_zero_result.used);
    try std.testing.expectEqual(@as(usize, 8), truncated_zero.bit_offset);
    try std.testing.expectEqual(@as(f64, 99), preserved_coefficient[0]);

    var wide_amplitude_floors = floor_zero_floors;
    wide_amplitude_floors[0].zero.amplitude_bits = 63;
    var wide_amplitude_setup = floor_zero_setup;
    wide_amplitude_setup.floors = &wide_amplitude_floors;
    var wide_amplitude_packet = [_]u8{0} ** 9;
    wide_amplitude_packet[0] = 1;
    wide_amplitude_packet[8] = 1;
    var wide_amplitude_reader = try VorbisPacketReader.init(
        &wide_amplitude_packet,
        0,
    );
    const wide_amplitude_result = try wide_amplitude_reader.decodeFloorZero(
        wide_amplitude_setup,
        0,
        &coefficients,
    );
    try std.testing.expect(wide_amplitude_result.used);
    try std.testing.expectEqual(@as(u64, 1), wide_amplitude_result.amplitude);
    try std.testing.expectEqual(@as(usize, 65), wide_amplitude_reader.bit_offset);

    var reserved_book_storage: [2]u8 = undefined;
    var reserved_book_writer =
        TestVorbisBitWriter.init(&reserved_book_storage);
    reserved_book_writer.write(5, 8);
    reserved_book_writer.write(1, 1);
    var reserved_book_reader = try VorbisPacketReader.init(
        &reserved_book_storage,
        0,
    );
    try std.testing.expectError(
        error.InvalidVorbisFloorBookNumber,
        reserved_book_reader.decodeFloorZero(
            floor_zero_setup,
            0,
            &preserved_coefficient,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), reserved_book_reader.bit_offset);
    try std.testing.expectEqual(@as(f64, 99), preserved_coefficient[0]);

    var floor_one_packet_storage: [128]u8 = undefined;
    const floor_one_packet = makeTestVorbisSetup(
        &floor_one_packet_storage,
        .unordered,
        true,
        false,
    );
    var floor_one_codebooks: [1]VorbisCodebook = undefined;
    var floor_one_entries: [2]VorbisCodebookEntry = undefined;
    var floor_one_nodes: [1]VorbisHuffmanNode = undefined;
    var floor_one_multiplicands: [2]u32 = undefined;
    var floor_one_floors: [1]VorbisFloor = undefined;
    var floor_one_residues: [1]VorbisResidue = undefined;
    var floor_one_mappings: [1]VorbisMapping = undefined;
    var floor_one_modes: [1]VorbisMode = undefined;
    const floor_one_setup = try parseVorbisSetup(
        floor_one_packet.bytes,
        2,
        .{
            .codebooks = &floor_one_codebooks,
            .codebook_entries = &floor_one_entries,
            .huffman_nodes = &floor_one_nodes,
            .codebook_multiplicands = &floor_one_multiplicands,
            .floors = &floor_one_floors,
            .residues = &floor_one_residues,
            .mappings = &floor_one_mappings,
            .modes = &floor_one_modes,
        },
    );
    var hostile_floor_one = try VorbisPacketReader.init(&.{0}, 0);
    hostile_floor_one.bit_offset = std.math.maxInt(usize);
    var hostile_y_values = [_]u32{ 99, 99, 99 };
    try std.testing.expectError(
        error.InvalidVorbisPacketBitOffset,
        hostile_floor_one.decodeFloorOne(
            floor_one_setup,
            0,
            &hostile_y_values,
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 99, 99, 99 },
        &hostile_y_values,
    );

    var floor_one_audio_storage: [4]u8 = undefined;
    var floor_one_writer =
        TestVorbisBitWriter.init(&floor_one_audio_storage);
    floor_one_writer.write(1, 1);
    floor_one_writer.write(23, 8);
    floor_one_writer.write(47, 8);
    floor_one_writer.write(1, 1);
    floor_one_writer.write(1, 1);
    var floor_one_reader = try VorbisPacketReader.init(
        floor_one_audio_storage[0..3],
        0,
    );
    var y_values = [_]u32{ 99, 99, 99 };
    const floor_one_result = try floor_one_reader.decodeFloorOne(
        floor_one_setup,
        0,
        &y_values,
    );
    try std.testing.expect(floor_one_result.used);
    try std.testing.expectEqual(@as(u7, 3), floor_one_result.value_count);
    try std.testing.expectEqualSlices(u32, &.{ 23, 47, 1 }, &y_values);
    try std.testing.expectEqual(@as(usize, 19), floor_one_reader.bit_offset);
    const retained_floor_one = switch (floor_one_setup.floors[0]) {
        .one => |floor| floor,
        .zero => return error.TestExpectedFloorOne,
    };
    var floor_curve: [4]f64 = undefined;
    try synthesizeVorbisFloorOne(
        f64,
        retained_floor_one,
        floor_one_result,
        &y_values,
        &floor_curve,
    );
    const expected_curve = [_]f64{
        4.5315863e-7,
        6.2082472e-7,
        9.0579828e-7,
        1.3215816e-6,
    };
    for (floor_curve, expected_curve) |actual, expected| {
        try std.testing.expectApproxEqAbs(expected, actual, 1e-13);
    }

    var unused_one = try VorbisPacketReader.init(&.{0}, 0);
    var preserved_y = [_]u32{ 99, 99, 99 };
    const unused_one_result = try unused_one.decodeFloorOne(
        floor_one_setup,
        0,
        &preserved_y,
    );
    try std.testing.expect(!unused_one_result.used);
    try std.testing.expectEqual(@as(usize, 1), unused_one.bit_offset);
    try std.testing.expectEqualSlices(u32, &.{ 99, 99, 99 }, &preserved_y);
    var silent_curve = [_]f32{99} ** 4;
    try synthesizeVorbisFloorOne(
        f32,
        retained_floor_one,
        unused_one_result,
        &preserved_y,
        &silent_curve,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, 0, 0, 0 },
        &silent_curve,
    );

    var truncated_one = try VorbisPacketReader.init(&.{1}, 0);
    const truncated_one_result = try truncated_one.decodeFloorOne(
        floor_one_setup,
        0,
        &preserved_y,
    );
    try std.testing.expect(!truncated_one_result.used);
    try std.testing.expectEqual(@as(usize, 8), truncated_one.bit_offset);
    try std.testing.expectEqualSlices(u32, &.{ 99, 99, 99 }, &preserved_y);

    var preserved_curve = [_]f64{99} ** 4;
    try std.testing.expectError(
        error.InvalidVorbisFloorPacketState,
        synthesizeVorbisFloorOne(
            f64,
            retained_floor_one,
            .{ .used = true, .value_count = 2 },
            y_values[0..2],
            &preserved_curve,
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 99, 99, 99, 99 },
        &preserved_curve,
    );

    var short_floor_output = [_]u32{99};
    var bounded_floor_reader = try VorbisPacketReader.init(&.{0}, 0);
    try std.testing.expectError(
        error.VorbisFloorOutputTooSmall,
        bounded_floor_reader.decodeFloorOne(
            floor_one_setup,
            0,
            &short_floor_output,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), bounded_floor_reader.bit_offset);
    try std.testing.expectEqual(@as(u32, 99), short_floor_output[0]);

    var invalid_floors = floor_one_floors;
    invalid_floors[0].one.x_list[2] = 0;
    var invalid_floor_setup = floor_one_setup;
    invalid_floor_setup.floors = &invalid_floors;
    var invalid_floor_reader = try VorbisPacketReader.init(
        floor_one_audio_storage[0..3],
        0,
    );
    try std.testing.expectError(
        error.InvalidVorbisSetupState,
        invalid_floor_reader.decodeFloorOne(
            invalid_floor_setup,
            0,
            &preserved_y,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), invalid_floor_reader.bit_offset);
    try std.testing.expectEqualSlices(u32, &.{ 99, 99, 99 }, &preserved_y);

    var wrong_type_reader = try VorbisPacketReader.init(&.{0}, 0);
    try std.testing.expectError(
        error.InvalidVorbisFloorType,
        wrong_type_reader.decodeFloorOne(
            floor_zero_setup,
            0,
            &preserved_y,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), wrong_type_reader.bit_offset);
}

test "Vorbis psychoacoustics distinguish tonal and noise-like spectra" {
    try testVorbisPsychoacoustics(f32);
    try testVorbisPsychoacoustics(f64);
}

test "Vorbis quality presets map q0 through q10 without changing policy" {
    const presets = [_]VorbisQualityPreset{
        .q0,
        .q1,
        .q2,
        .q3,
        .q4,
        .q5,
        .q6,
        .q7,
        .q8,
        .q9,
        .q10,
    };
    const base = VorbisPsychoacousticConfig{
        .band_count = 31,
        .absolute_threshold = 0.000_002,
        .tonal_masking_offset_db = 16,
        .noise_masking_offset_db = 6,
        .lower_spread_db_per_bark = 28,
        .upper_spread_db_per_bark = 13,
        .quality = 0.375,
        .maximum_masking_relaxation_db = 20,
    };
    for (presets, 0..) |preset, level| {
        const expected = @as(f64, @floatFromInt(level)) / 10;
        try std.testing.expectApproxEqAbs(
            expected,
            preset.quality(),
            1.0e-15,
        );
        const configured = preset.applyTo(base);
        try std.testing.expectApproxEqAbs(
            expected,
            configured.quality,
            1.0e-15,
        );
        var retained = configured;
        retained.quality = base.quality;
        try std.testing.expectEqualDeep(base, retained);
    }

    var spectrum = [_]f64{0} ** 32;
    spectrum[5] = 1;
    var floor_target: [32]f64 = undefined;
    var noise_threshold: [32]f64 = undefined;
    const q0 = try analyzeVorbisPsychoacoustics(
        f64,
        &spectrum,
        48_000,
        VorbisQualityPreset.q0.applyTo(.{}),
        &floor_target,
        &noise_threshold,
    );
    const q10 = try analyzeVorbisPsychoacoustics(
        f64,
        &spectrum,
        48_000,
        VorbisQualityPreset.q10.applyTo(.{}),
        &floor_target,
        &noise_threshold,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 18),
        q0.masking_relaxation_db,
        1.0e-15,
    );
    try std.testing.expectEqual(
        @as(f64, 0),
        q10.masking_relaxation_db,
    );
}

test "Vorbis PCM quality meter measures decoded signal independently" {
    try testVorbisPcmQualityMeter(f32);
    try testVorbisPcmQualityMeter(f64);
}

fn testVorbisPcmQualityMeter(comptime Float: type) !void {
    const reference = [_]Float{ 1, -1, 0.5, -0.5 };
    const exact = reference;
    var exact_meter = VorbisPcmQualityMeter{};
    try exact_meter.update(
        Float,
        &.{&reference},
        &.{&exact},
    );
    const exact_measurement = try exact_meter.measurement();
    try std.testing.expectEqual(@as(u64, 4), exact_measurement.sample_count);
    try std.testing.expectEqual(
        @as(f64, 0),
        exact_measurement.normalized_rms_error,
    );
    try std.testing.expectEqual(
        std.math.inf(f64),
        exact_measurement.signal_to_noise_db,
    );
    var hostile_exact_peak = exact_meter;
    hostile_exact_peak.peak_sample_index = 1;
    const hostile_exact_peak_before = hostile_exact_peak;
    try std.testing.expect(!hostile_exact_peak.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmQualityMeter,
        hostile_exact_peak.measurement(),
    );
    try std.testing.expectEqualDeep(
        hostile_exact_peak_before,
        hostile_exact_peak,
    );
    var hostile_exact_energy = exact_meter;
    hostile_exact_energy.candidate_energy += 1;
    const hostile_exact_energy_before = hostile_exact_energy;
    try std.testing.expect(!hostile_exact_energy.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmQualityMeter,
        hostile_exact_energy.measurement(),
    );
    try std.testing.expectEqualDeep(
        hostile_exact_energy_before,
        hostile_exact_energy,
    );

    const candidate = [_]Float{ 0.5, -0.5, 0.25, -0.25 };
    var meter = VorbisPcmQualityMeter{};
    try meter.update(
        Float,
        &.{reference[0..2]},
        &.{candidate[0..2]},
    );
    try meter.update(
        Float,
        &.{reference[2..4]},
        &.{candidate[2..4]},
    );
    const measurement = try meter.measurement();
    try std.testing.expectEqual(@as(u64, 4), measurement.sample_count);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        measurement.normalized_rms_error,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 2),
        measurement.optimal_candidate_gain,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0),
        measurement.gain_aligned_normalized_rms_error,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 6.020599913279624),
        measurement.signal_to_noise_db,
        1.0e-12,
    );
    try std.testing.expectEqual(@as(f64, 0.5), measurement.peak_absolute_error);
    try std.testing.expectEqual(@as(u64, 0), measurement.peak_sample_index);

    var hostile_missing_peak = meter;
    hostile_missing_peak.peak_absolute_error = 0;
    const hostile_missing_peak_before = hostile_missing_peak;
    try std.testing.expect(!hostile_missing_peak.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmQualityMeter,
        hostile_missing_peak.measurement(),
    );
    try std.testing.expectEqualDeep(
        hostile_missing_peak_before,
        hostile_missing_peak,
    );

    const silence = [_]Float{ 0, 0 };
    const nonzero = [_]Float{ 0.25, -0.5 };
    var silent_reference_meter = VorbisPcmQualityMeter{};
    try silent_reference_meter.update(
        Float,
        &.{&silence},
        &.{&nonzero},
    );
    var hostile_silent_reference = silent_reference_meter;
    hostile_silent_reference.cross_energy = 1;
    const hostile_silent_reference_before = hostile_silent_reference;
    try std.testing.expect(!hostile_silent_reference.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmQualityMeter,
        hostile_silent_reference.measurement(),
    );
    try std.testing.expectEqualDeep(
        hostile_silent_reference_before,
        hostile_silent_reference,
    );
    hostile_silent_reference = silent_reference_meter;
    hostile_silent_reference.error_energy += 1;
    try std.testing.expect(!hostile_silent_reference.valid());

    var silent_candidate_meter = VorbisPcmQualityMeter{};
    try silent_candidate_meter.update(
        Float,
        &.{&nonzero},
        &.{&silence},
    );
    var hostile_silent_candidate = silent_candidate_meter;
    hostile_silent_candidate.cross_energy = -1;
    const hostile_silent_candidate_before = hostile_silent_candidate;
    try std.testing.expect(!hostile_silent_candidate.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmQualityMeter,
        hostile_silent_candidate.measurement(),
    );
    try std.testing.expectEqualDeep(
        hostile_silent_candidate_before,
        hostile_silent_candidate,
    );
    hostile_silent_candidate = silent_candidate_meter;
    hostile_silent_candidate.error_energy += 1;
    try std.testing.expect(!hostile_silent_candidate.valid());

    const retained = meter;
    const non_finite = [_]Float{std.math.nan(Float)};
    try std.testing.expectError(
        error.NonFiniteVorbisPcmQualitySample,
        meter.update(Float, &.{reference[0..1]}, &.{&non_finite}),
    );
    try std.testing.expectEqualDeep(retained, meter);
    try std.testing.expectError(
        error.InvalidVorbisPcmQualityShape,
        meter.update(Float, &.{reference[0..1]}, &.{candidate[0..2]}),
    );
    try std.testing.expectEqualDeep(retained, meter);

    meter.sample_count = std.math.maxInt(u64);
    try std.testing.expect(meter.valid());
    const saturated = meter;
    try std.testing.expectError(
        error.VorbisPcmQualitySampleCountOverflow,
        meter.update(Float, &.{reference[0..1]}, &.{candidate[0..1]}),
    );
    try std.testing.expectEqualDeep(saturated, meter);

    meter = retained;
    meter.reference_energy = std.math.nan(f128);
    try std.testing.expect(!meter.valid());
    const corrupted = meter;
    try std.testing.expectError(
        error.InvalidVorbisPcmQualityMeter,
        meter.update(Float, &.{reference[0..1]}, &.{candidate[0..1]}),
    );
    try std.testing.expectEqualSlices(
        u8,
        std.mem.asBytes(&corrupted),
        std.mem.asBytes(&meter),
    );
    meter.reset();
    try std.testing.expect(meter.valid());
    try std.testing.expectError(
        error.EmptyVorbisPcmQualityMeasurement,
        meter.measurement(),
    );
    try meter.update(Float, &.{&silence}, &.{&silence});
    try std.testing.expectError(
        error.SilentVorbisPcmQualityReference,
        meter.measurement(),
    );
}

test "Vorbis multichannel psychoacoustics publish atomically" {
    try testVorbisAudioPsychoacoustics(f32);
    try testVorbisAudioPsychoacoustics(f64);
}

fn testVorbisAudioPsychoacoustics(comptime Float: type) !void {
    const requirements =
        try requiredVorbisAudioPsychoacousticStorage(2, 64);
    try std.testing.expectEqual(@as(usize, 2), requirements.analyses);
    try std.testing.expectEqual(
        @as(usize, 128),
        requirements.floor_values,
    );
    try std.testing.expectEqual(
        @as(usize, 128),
        requirements.threshold_values,
    );
    try std.testing.expectError(
        error.InvalidVorbisChannelCount,
        requiredVorbisAudioPsychoacousticStorage(0, 64),
    );
    try std.testing.expectError(
        error.InvalidVorbisChannelCount,
        requiredVorbisAudioPsychoacousticStorage(256, 64),
    );
    try std.testing.expectError(
        error.InvalidVorbisSpectrumShape,
        requiredVorbisAudioPsychoacousticStorage(2, 63),
    );

    var tone = [_]Float{0} ** 64;
    tone[7] = 1;
    const silence = [_]Float{0} ** 64;
    const spectra = [_][]const Float{ &tone, &silence };
    var scratch_floor: [128]Float = undefined;
    var scratch_thresholds: [128]Float = undefined;
    const sentinel_analysis = VorbisPsychoacousticAnalysis{
        .silent = false,
        .active_band_count = 71,
        .peak = 72,
        .rms = 73,
        .spectral_flatness = 74,
        .tonality = 75,
        .masking_relaxation_db = 76,
    };
    var retained_analyses =
        [_]VorbisPsychoacousticAnalysis{sentinel_analysis} ** 3;
    var retained_floor = [_]Float{91} ** 129;
    var retained_thresholds = [_]Float{92} ** 129;
    const plan = try analyzeVorbisAudioPsychoacoustics(
        Float,
        &spectra,
        48_000,
        .{ .absolute_threshold = 0.000_000_001 },
        .{
            .floor_targets = &scratch_floor,
            .noise_thresholds = &scratch_thresholds,
        },
        .{
            .analyses = &retained_analyses,
            .floor_targets = &retained_floor,
            .noise_thresholds = &retained_thresholds,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), plan.analyses.len);
    try std.testing.expectEqual(
        @as(usize, 128),
        plan.floor_targets.len,
    );
    try std.testing.expectEqual(
        @as(usize, 128),
        plan.noise_thresholds.len,
    );
    try std.testing.expectEqual(@as(usize, 64), plan.coefficient_count);
    try std.testing.expectEqual(
        @intFromPtr(retained_analyses[0..2].ptr),
        @intFromPtr(plan.analyses.ptr),
    );
    try std.testing.expectEqual(
        @intFromPtr(retained_floor[0..128].ptr),
        @intFromPtr(plan.floor_targets.ptr),
    );
    try std.testing.expectEqual(
        @intFromPtr(retained_thresholds[0..128].ptr),
        @intFromPtr(plan.noise_thresholds.ptr),
    );
    try std.testing.expect(!plan.analyses[0].silent);
    try std.testing.expect(plan.analyses[1].silent);
    for (
        plan.floor_targets[64..],
        plan.noise_thresholds[64..],
    ) |floor_value, threshold| {
        try std.testing.expectEqual(@as(Float, 0), floor_value);
        try std.testing.expectEqual(@as(Float, 0), threshold);
    }
    try std.testing.expectEqual(sentinel_analysis, retained_analyses[2]);
    try std.testing.expectEqual(@as(Float, 91), retained_floor[128]);
    try std.testing.expectEqual(
        @as(Float, 92),
        retained_thresholds[128],
    );

    const preserved_analyses = retained_analyses;
    const preserved_floor = retained_floor;
    const preserved_thresholds = retained_thresholds;
    var invalid = silence;
    invalid[63] = std.math.nan(Float);
    const invalid_spectra =
        [_][]const Float{ &tone, &invalid };
    try std.testing.expectError(
        error.InvalidVorbisSpectrumValue,
        analyzeVorbisAudioPsychoacoustics(
            Float,
            &invalid_spectra,
            48_000,
            .{},
            .{
                .floor_targets = &scratch_floor,
                .noise_thresholds = &scratch_thresholds,
            },
            .{
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectEqualSlices(
        VorbisPsychoacousticAnalysis,
        &preserved_analyses,
        &retained_analyses,
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_floor,
        &retained_floor,
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_thresholds,
        &retained_thresholds,
    );

    const short_spectra =
        [_][]const Float{ &tone, silence[0..32] };
    try std.testing.expectError(
        error.InvalidVorbisSpectrumBundle,
        analyzeVorbisAudioPsychoacoustics(
            Float,
            &short_spectra,
            48_000,
            .{},
            .{
                .floor_targets = &scratch_floor,
                .noise_thresholds = &scratch_thresholds,
            },
            .{
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectError(
        error.VorbisAudioPsychoacousticScratchTooSmall,
        analyzeVorbisAudioPsychoacoustics(
            Float,
            &spectra,
            48_000,
            .{},
            .{
                .floor_targets = scratch_floor[0..127],
                .noise_thresholds = &scratch_thresholds,
            },
            .{
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectError(
        error.VorbisAudioPsychoacousticStorageTooSmall,
        analyzeVorbisAudioPsychoacoustics(
            Float,
            &spectra,
            48_000,
            .{},
            .{
                .floor_targets = &scratch_floor,
                .noise_thresholds = &scratch_thresholds,
            },
            .{
                .analyses = retained_analyses[0..1],
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisAudioPsychoacousticStorage,
        analyzeVorbisAudioPsychoacoustics(
            Float,
            &spectra,
            48_000,
            .{},
            .{
                .floor_targets = &scratch_floor,
                .noise_thresholds = &scratch_floor,
            },
            .{
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );

    var aliased_floor = [_]Float{0} ** 128;
    aliased_floor[7] = 1;
    const aliased_spectra = [_][]const Float{
        aliased_floor[0..64],
        &silence,
    };
    try std.testing.expectError(
        error.OverlappingVorbisAudioPsychoacousticStorage,
        analyzeVorbisAudioPsychoacoustics(
            Float,
            &aliased_spectra,
            48_000,
            .{},
            .{
                .floor_targets = &scratch_floor,
                .noise_thresholds = &scratch_thresholds,
            },
            .{
                .analyses = &retained_analyses,
                .floor_targets = &aliased_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisSampleRate,
        analyzeVorbisAudioPsychoacoustics(
            Float,
            &spectra,
            0,
            .{},
            .{
                .floor_targets = &scratch_floor,
                .noise_thresholds = &scratch_thresholds,
            },
            .{
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
}

fn testVorbisPsychoacoustics(comptime Float: type) !void {
    var tone = [_]Float{0} ** 64;
    tone[7] = 1;
    var tone_floor: [64]Float = undefined;
    var tone_threshold: [64]Float = undefined;
    const tone_analysis = try analyzeVorbisPsychoacoustics(
        Float,
        &tone,
        48_000,
        .{ .absolute_threshold = 0.000_000_001 },
        &tone_floor,
        &tone_threshold,
    );
    try std.testing.expect(!tone_analysis.silent);
    try std.testing.expectEqual(@as(f64, 1), tone_analysis.peak);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.125),
        tone_analysis.rms,
        16 * std.math.floatEps(f64),
    );
    try std.testing.expect(tone_analysis.spectral_flatness < 0.001);
    try std.testing.expect(tone_analysis.tonality > 0.999);
    try std.testing.expect(tone_analysis.active_band_count > 0);
    for (tone_floor, tone_threshold) |floor_value, threshold| {
        try std.testing.expect(std.math.isFinite(floor_value));
        try std.testing.expect(std.math.isFinite(threshold));
        try std.testing.expect(floor_value >= threshold);
        try std.testing.expect(threshold > 0);
    }

    const noise_like = [_]Float{1} ** 64;
    var noise_floor: [64]Float = undefined;
    var high_quality_threshold: [64]Float = undefined;
    const noise_analysis = try analyzeVorbisPsychoacoustics(
        Float,
        &noise_like,
        48_000,
        .{
            .absolute_threshold = 0.000_000_001,
            .quality = 1,
        },
        &noise_floor,
        &high_quality_threshold,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1),
        noise_analysis.spectral_flatness,
        16 * std.math.floatEps(f64),
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0),
        noise_analysis.tonality,
        16 * std.math.floatEps(f64),
    );
    var relaxed_floor: [64]Float = undefined;
    var relaxed_threshold: [64]Float = undefined;
    const relaxed = try analyzeVorbisPsychoacoustics(
        Float,
        &noise_like,
        48_000,
        .{
            .absolute_threshold = 0.000_000_001,
            .quality = 0,
        },
        &relaxed_floor,
        &relaxed_threshold,
    );
    try std.testing.expectEqual(
        @as(f64, 18),
        relaxed.masking_relaxation_db,
    );
    for (relaxed_threshold, high_quality_threshold) |
        relaxed_value,
        high_quality_value,
    | {
        try std.testing.expect(relaxed_value >= high_quality_value);
    }

    const within_mask = try evaluateVorbisRateDistortion(
        Float,
        &.{ 0, 0, 0, 0 },
        &.{ 0.5, -0.5, 0.5, -0.5 },
        &.{ 1, 1, 1, 1 },
    );
    try std.testing.expect(within_mask.within_mask);
    try std.testing.expectEqual(
        @as(f64, 0.5),
        within_mask.maximum_noise_ratio,
    );
    try std.testing.expectEqual(
        @as(f64, 1),
        within_mask.weighted_squared_error,
    );
    try std.testing.expectEqual(
        @as(f64, 0),
        within_mask.audible_excess_power,
    );
    const outside_mask = try evaluateVorbisRateDistortion(
        Float,
        &.{ 0, 0 },
        &.{ 2, 0 },
        &.{ 1, 1 },
    );
    try std.testing.expect(!outside_mask.within_mask);
    try std.testing.expectEqual(
        @as(f64, 2),
        outside_mask.maximum_noise_ratio,
    );
    try std.testing.expectEqual(
        @as(f64, 3),
        outside_mask.audible_excess_power,
    );
    const zero_threshold = try evaluateVorbisRateDistortion(
        Float,
        &.{0},
        &.{1},
        &.{0},
    );
    try std.testing.expect(!zero_threshold.within_mask);
    try std.testing.expect(std.math.isInf(
        zero_threshold.maximum_noise_ratio,
    ));
    try std.testing.expectError(
        error.InvalidVorbisSpectrumValue,
        evaluateVorbisRateDistortion(
            Float,
            &.{0},
            &.{0},
            &.{-1},
        ),
    );

    var silent_floor = [_]Float{9} ** 64;
    var silent_threshold = [_]Float{8} ** 64;
    const silence = try analyzeVorbisPsychoacoustics(
        Float,
        &([_]Float{0} ** 64),
        48_000,
        .{},
        &silent_floor,
        &silent_threshold,
    );
    try std.testing.expect(silence.silent);
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 64),
        &silent_floor,
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 64),
        &silent_threshold,
    );

    var in_place = tone;
    var in_place_threshold: [64]Float = undefined;
    _ = try analyzeVorbisPsychoacoustics(
        Float,
        &in_place,
        48_000,
        .{},
        &in_place,
        &in_place_threshold,
    );
    try std.testing.expect(in_place[7] > 0);

    var preserved_floor = [_]Float{7} ** 64;
    var preserved_threshold = [_]Float{8} ** 64;
    var invalid = tone;
    invalid[63] = std.math.nan(Float);
    try std.testing.expectError(
        error.InvalidVorbisSpectrumValue,
        analyzeVorbisPsychoacoustics(
            Float,
            &invalid,
            48_000,
            .{},
            &preserved_floor,
            &preserved_threshold,
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{7} ** 64),
        &preserved_floor,
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{8} ** 64),
        &preserved_threshold,
    );
    try std.testing.expectError(
        error.OverlappingVorbisPsychoacousticOutput,
        analyzeVorbisPsychoacoustics(
            Float,
            &tone,
            48_000,
            .{},
            &preserved_floor,
            &preserved_floor,
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisPsychoacousticConfig,
        analyzeVorbisPsychoacoustics(
            Float,
            &tone,
            48_000,
            .{ .quality = 1.1 },
            &preserved_floor,
            &preserved_threshold,
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisSpectrumShape,
        analyzeVorbisPsychoacoustics(
            Float,
            tone[0..63],
            48_000,
            .{},
            preserved_floor[0..63],
            preserved_threshold[0..63],
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisSampleRate,
        analyzeVorbisPsychoacoustics(
            Float,
            &tone,
            0,
            .{},
            &preserved_floor,
            &preserved_threshold,
        ),
    );
}

test "Vorbis bit reservoir budgets and commits packet rates" {
    var reservoir = try VorbisBitReservoir.init(.{
        .target_bitrate = 48_000,
        .reservoir_capacity_bits = 256,
        .minimum_packet_bits = 32,
        .maximum_packet_bits = 256,
        .correction_window_packets = 4,
    });
    try std.testing.expect(reservoir.valid());
    const first = try reservoir.plan(48_000, 128);
    try std.testing.expect(reservoir.valid());
    try std.testing.expectEqual(
        VorbisPacketBitBudget{
            .packet_index = 0,
            .nominal_bits = 128,
            .target_bits = 128,
            .reservoir_balance_before = 0,
        },
        first,
    );
    var residue_budgets = [_]u32{ 99, 99, 99, 99 };
    try std.testing.expectEqual(
        VorbisResidueBitAllocation{
            .packet_target_bits = 128,
            .fixed_packet_bits = 28,
            .residue_bits = 100,
        },
        try allocateVorbisResidueBitBudgets(
            first,
            28,
            &.{ 1, 2, 1 },
            &residue_budgets,
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 25, 50, 25, 99 },
        &residue_budgets,
    );
    _ = try allocateVorbisResidueBitBudgets(
        .{
            .packet_index = 0,
            .nominal_bits = 5,
            .target_bits = 5,
            .reservoir_balance_before = 0,
        },
        0,
        &.{ 0, 0, 0 },
        &residue_budgets,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 2, 2, 1, 99 },
        &residue_budgets,
    );
    const preserved_residue_budgets = residue_budgets;
    try std.testing.expectError(
        error.InvalidVorbisResidueBitWeights,
        allocateVorbisResidueBitBudgets(
            first,
            28,
            &.{ 1, -1, 1 },
            &residue_budgets,
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &preserved_residue_budgets,
        &residue_budgets,
    );
    try std.testing.expectError(
        error.VorbisResidueBitBudgetOutputTooSmall,
        allocateVorbisResidueBitBudgets(
            first,
            28,
            &.{ 1, 1, 1 },
            residue_budgets[0..2],
        ),
    );
    try std.testing.expectError(
        error.VorbisPacketBudgetBelowFixedCost,
        allocateVorbisResidueBitBudgets(
            first,
            129,
            &.{1},
            &residue_budgets,
        ),
    );
    var aliased_weights = [_]f64{ 1, 1, 1 };
    const aliased_destination = std.mem.bytesAsSlice(
        u32,
        std.mem.sliceAsBytes(&aliased_weights),
    );
    try std.testing.expectError(
        error.OverlappingVorbisResidueBitBudgets,
        allocateVorbisResidueBitBudgets(
            first,
            28,
            &aliased_weights,
            aliased_destination,
        ),
    );
    try std.testing.expectError(
        error.VorbisRateBudgetAlreadyPending,
        reservoir.plan(48_000, 128),
    );
    const first_commit = try reservoir.commit(64);
    try std.testing.expect(reservoir.valid());
    try std.testing.expectEqual(
        VorbisRateCommit{
            .packet_index = 0,
            .actual_bits = 64,
            .reservoir_balance_after = 64,
        },
        first_commit,
    );

    const second = try reservoir.plan(48_000, 128);
    try std.testing.expectEqual(@as(u32, 144), second.target_bits);
    _ = try reservoir.commit(160);
    try std.testing.expectEqual(@as(i64, 32), reservoir.balance_bits);
    const third = try reservoir.plan(48_000, 128);
    try std.testing.expectEqual(@as(u32, 136), third.target_bits);
    const before_excess = reservoir;
    try std.testing.expectError(
        error.VorbisBitReservoirExceeded,
        reservoir.commit(1_000),
    );
    try std.testing.expectEqualDeep(before_excess, reservoir);
    try reservoir.cancel();
    try std.testing.expectEqual(@as(?VorbisPacketBitBudget, null), reservoir.pending);
    try std.testing.expectError(
        error.VorbisRateBudgetNotPending,
        reservoir.commit(128),
    );
    try std.testing.expectError(
        error.VorbisRateBudgetNotPending,
        reservoir.cancel(),
    );
    var corrupt = reservoir;
    corrupt.pending = .{
        .packet_index = corrupt.packet_index + 1,
        .nominal_bits = 128,
        .target_bits = 128,
        .reservoir_balance_before = corrupt.balance_bits,
    };
    const corrupt_before = corrupt;
    try std.testing.expect(!corrupt.valid());
    try std.testing.expectError(
        error.InvalidVorbisBitReservoirState,
        corrupt.commit(128),
    );
    try std.testing.expectEqualDeep(corrupt_before, corrupt);
    try std.testing.expectError(
        error.InvalidVorbisBitReservoirState,
        corrupt.cancel(),
    );
    try std.testing.expectEqualDeep(corrupt_before, corrupt);

    var invalid_balance = reservoir;
    invalid_balance.balance_bits = 257;
    const invalid_balance_before = invalid_balance;
    try std.testing.expect(!invalid_balance.valid());
    try std.testing.expectError(
        error.InvalidVorbisBitReservoirState,
        invalid_balance.plan(48_000, 128),
    );
    try std.testing.expectEqualDeep(invalid_balance_before, invalid_balance);

    var invalid_config = reservoir;
    invalid_config.config.target_bitrate = 0;
    try std.testing.expect(!invalid_config.valid());
    try std.testing.expectError(
        error.InvalidVorbisRateControlConfig,
        invalid_config.cancel(),
    );

    const clamped = try VorbisBitReservoir.init(.{
        .target_bitrate = 48_000,
        .reservoir_capacity_bits = 128,
        .minimum_packet_bits = 140,
        .maximum_packet_bits = 150,
    });
    var mutable_clamped = clamped;
    try std.testing.expectEqual(
        @as(u32, 140),
        (try mutable_clamped.plan(48_000, 128)).target_bits,
    );
    mutable_clamped.reset();
    try std.testing.expectEqual(@as(u64, 0), mutable_clamped.packet_index);
    try std.testing.expectEqual(@as(i64, 0), mutable_clamped.balance_bits);

    try std.testing.expectError(
        error.InvalidVorbisRateControlConfig,
        VorbisBitReservoir.init(.{
            .target_bitrate = 0,
            .reservoir_capacity_bits = 0,
        }),
    );
    try std.testing.expectError(
        error.InvalidVorbisRateInterval,
        reservoir.plan(0, 128),
    );
    reservoir.packet_index = std.math.maxInt(u64);
    try std.testing.expect(reservoir.valid());
    try std.testing.expectError(
        error.VorbisAudioPacketCountOverflow,
        reservoir.plan(48_000, 128),
    );
}

test "Vorbis adaptive rate policy shifts bounded packet targets" {
    const rate_control = VorbisRateControlConfig{
        .target_bitrate = 96_000,
        .reservoir_capacity_bits = 500,
        .minimum_packet_bits = 100,
        .maximum_packet_bits = 2_000,
    };
    const budget = VorbisPacketBitBudget{
        .packet_index = 7,
        .nominal_bits = 1_000,
        .target_bits = 1_000,
        .reservoir_balance_before = 0,
    };
    const quiet = try adaptVorbisPacketBitBudget(
        budget,
        .{
            .analysis = .{
                .recommended_large_block = true,
                .peak = 0,
                .rms = 0,
                .maximum_energy_ratio = 1,
                .transient_segment = null,
            },
            .recommended_large_block = true,
            .cross_block_energy_ratio = 1,
            .short_blocks_remaining = 0,
        },
        rate_control,
        .{},
    );
    try std.testing.expectEqual(@as(u32, 600), quiet.budget.target_bits);
    try std.testing.expectEqual(@as(f64, 0), quiet.complexity);
    try std.testing.expectEqual(@as(f64, 0.6), quiet.target_scale);

    const complex = try adaptVorbisPacketBitBudget(
        budget,
        .{
            .analysis = .{
                .recommended_large_block = false,
                .peak = 1.5,
                .rms = 0.25,
                .maximum_energy_ratio = 8,
                .transient_segment = 1,
            },
            .recommended_large_block = false,
            .cross_block_energy_ratio = 8,
            .short_blocks_remaining = 2,
        },
        rate_control,
        .{},
    );
    try std.testing.expectEqual(@as(u32, 1_400), complex.budget.target_bits);
    try std.testing.expectEqual(@as(f64, 1), complex.activity);
    try std.testing.expectEqual(@as(f64, 1), complex.transient);
    try std.testing.expectEqual(@as(f64, 1), complex.crest);
    try std.testing.expectEqual(@as(f64, 1), complex.complexity);
    try std.testing.expectEqual(@as(f64, 1.4), complex.target_scale);

    const constrained = try adaptVorbisPacketBitBudget(
        .{
            .packet_index = 8,
            .nominal_bits = 100,
            .target_bits = 100,
            .reservoir_balance_before = -90,
        },
        complexAnalysisForVorbisRateTest(),
        .{
            .target_bitrate = 48_000,
            .reservoir_capacity_bits = 100,
            .maximum_packet_bits = 1_000,
        },
        .{},
    );
    try std.testing.expectEqual(@as(u32, 110), constrained.budget.target_bits);

    try std.testing.expectError(
        error.InvalidVorbisAdaptiveRatePolicyConfig,
        adaptVorbisPacketBitBudget(
            budget,
            complexAnalysisForVorbisRateTest(),
            rate_control,
            .{ .transient_weight = 0.8, .crest_weight = 0.3 },
        ),
    );
    var invalid_classification = complexAnalysisForVorbisRateTest();
    invalid_classification.analysis.rms = 2;
    try std.testing.expectError(
        error.InvalidVorbisBlockAnalysis,
        adaptVorbisPacketBitBudget(
            budget,
            invalid_classification,
            rate_control,
            .{},
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisPacketBitBudget,
        adaptVorbisPacketBitBudget(
            .{
                .packet_index = 9,
                .nominal_bits = 1_000,
                .target_bits = 99,
                .reservoir_balance_before = 0,
            },
            complexAnalysisForVorbisRateTest(),
            rate_control,
            .{},
        ),
    );
    try std.testing.expectError(
        error.VorbisAdaptiveRateRangeUnavailable,
        adaptVorbisPacketBitBudget(
            .{
                .packet_index = 10,
                .nominal_bits = 100,
                .target_bits = 1_000,
                .reservoir_balance_before = -90,
            },
            complexAnalysisForVorbisRateTest(),
            .{
                .target_bitrate = 48_000,
                .reservoir_capacity_bits = 100,
                .minimum_packet_bits = 1_000,
                .maximum_packet_bits = 2_000,
            },
            .{},
        ),
    );
}

test "Vorbis adaptive rate targets are monotonic across activity and transients" {
    const rate_control = VorbisRateControlConfig{
        .target_bitrate = 128_000,
        .reservoir_capacity_bits = 2_000,
        .minimum_packet_bits = 100,
        .maximum_packet_bits = 4_000,
    };
    const budget = VorbisPacketBitBudget{
        .packet_index = 11,
        .nominal_bits = 2_000,
        .target_bits = 2_000,
        .reservoir_balance_before = 0,
    };
    var prior_activity_target: u32 = 0;
    for (0..17) |activity_index| {
        const activity =
            @as(f64, @floatFromInt(activity_index)) / 16;
        const rms = 0.000_1 + activity * (0.25 - 0.000_1);
        var prior_transient_target: u32 = 0;
        for (0..17) |transient_index| {
            const transient =
                @as(f64, @floatFromInt(transient_index)) / 16;
            const ratio = std.math.pow(f64, 8, transient);
            const decision = try adaptVorbisPacketBitBudget(
                budget,
                .{
                    .analysis = .{
                        .recommended_large_block = transient == 0,
                        .peak = rms,
                        .rms = rms,
                        .maximum_energy_ratio = ratio,
                        .transient_segment = if (transient == 0)
                            null
                        else
                            1,
                    },
                    .recommended_large_block = transient == 0,
                    .cross_block_energy_ratio = ratio,
                    .short_blocks_remaining = 0,
                },
                rate_control,
                .{},
            );
            try std.testing.expect(
                decision.budget.target_bits >= prior_transient_target,
            );
            try std.testing.expect(
                decision.budget.target_bits >=
                    rate_control.minimum_packet_bits,
            );
            try std.testing.expect(
                decision.budget.target_bits <=
                    rate_control.maximum_packet_bits,
            );
            prior_transient_target = decision.budget.target_bits;
            if (transient_index == 0) {
                try std.testing.expect(
                    decision.budget.target_bits >=
                        prior_activity_target,
                );
                prior_activity_target = decision.budget.target_bits;
            }
        }
    }
}

test "Vorbis quality rate controller follows committed packet evidence" {
    const config = VorbisQualityRateControllerConfig{
        .minimum_quality = 0.5,
        .maximum_quality = 0.9,
        .initial_quality = 0.75,
        .adjustment_per_packet = 0.1,
        .headroom_ratio = 0.1,
    };
    var controller = try VorbisQualityRateController.init(config);

    const over_target = try controller.observeCommit(
        .{
            .packet_index = 4,
            .nominal_bits = 1_000,
            .target_bits = 1_000,
            .reservoir_balance_before = 0,
        },
        .{
            .packet_index = 4,
            .actual_bits = 1_100,
            .reservoir_balance_after = -100,
        },
        true,
    );
    try std.testing.expectEqual(
        VorbisQualityRateAction.decrease_quality,
        over_target.action,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.65),
        over_target.quality,
        1.0e-15,
    );
    const missed_budget = try controller.observe(1_000, 900, false);
    try std.testing.expectEqual(
        VorbisQualityRateAction.decrease_quality,
        missed_budget.action,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.55),
        missed_budget.quality,
        1.0e-15,
    );
    const spare_rate = try controller.observe(1_000, 800, true);
    try std.testing.expectEqual(
        VorbisQualityRateAction.increase_quality,
        spare_rate.action,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.65),
        spare_rate.quality,
        1.0e-15,
    );
    const deadband = try controller.observe(1_000, 950, true);
    try std.testing.expectEqual(
        VorbisQualityRateAction.hold,
        deadband.action,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.65),
        deadband.quality,
        1.0e-15,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.95),
        deadband.actual_to_target_ratio,
        1.0e-15,
    );

    const psychoacoustics = try controller.applyTo(.{});
    try std.testing.expectApproxEqAbs(
        try controller.quality(),
        psychoacoustics.quality,
        1.0e-15,
    );
    try controller.reset();
    try std.testing.expectApproxEqAbs(
        config.initial_quality,
        try controller.quality(),
        1.0e-15,
    );
}

test "Vorbis quality rate controller clamps and contains invalid state" {
    const config = VorbisQualityRateControllerConfig{
        .minimum_quality = 0.4,
        .maximum_quality = 0.8,
        .initial_quality = 0.6,
        .adjustment_per_packet = 0.25,
        .headroom_ratio = 0.2,
    };
    var controller = try VorbisQualityRateController.init(config);
    const lower_clamp = try controller.observe(1_000, 2_000, true);
    try std.testing.expectApproxEqAbs(
        config.minimum_quality,
        try controller.quality(),
        1.0e-15,
    );
    try std.testing.expectEqual(
        VorbisQualityRateAction.decrease_quality,
        lower_clamp.action,
    );
    const at_lower_limit = try controller.observe(1_000, 2_000, true);
    try std.testing.expectApproxEqAbs(
        config.minimum_quality,
        try controller.quality(),
        1.0e-15,
    );
    try std.testing.expectEqual(
        VorbisQualityRateAction.hold,
        at_lower_limit.action,
    );
    _ = try controller.observe(1_000, 100, true);
    _ = try controller.observe(1_000, 100, true);
    try std.testing.expectApproxEqAbs(
        config.maximum_quality,
        try controller.quality(),
        1.0e-15,
    );

    const retained = try controller.quality();
    try std.testing.expectError(
        error.InvalidVorbisQualityRateObservation,
        controller.observe(0, 100, true),
    );
    try std.testing.expectError(
        error.InvalidVorbisQualityRateObservation,
        controller.observe(100, 0, true),
    );
    try std.testing.expectEqual(retained, try controller.quality());
    try std.testing.expectError(
        error.MismatchedVorbisQualityRateObservation,
        controller.observeCommit(
            .{
                .packet_index = 1,
                .nominal_bits = 100,
                .target_bits = 100,
                .reservoir_balance_before = 0,
            },
            .{
                .packet_index = 2,
                .actual_bits = 100,
                .reservoir_balance_after = 0,
            },
            true,
        ),
    );
    try std.testing.expectEqual(retained, try controller.quality());

    inline for (.{
        VorbisQualityRateControllerConfig{
            .minimum_quality = -0.1,
            .maximum_quality = 0.8,
            .initial_quality = 0.6,
            .adjustment_per_packet = 0.1,
            .headroom_ratio = 0.1,
        },
        VorbisQualityRateControllerConfig{
            .minimum_quality = 0.5,
            .maximum_quality = 0.4,
            .initial_quality = 0.45,
            .adjustment_per_packet = 0.1,
            .headroom_ratio = 0.1,
        },
        VorbisQualityRateControllerConfig{
            .minimum_quality = 0.4,
            .maximum_quality = 0.8,
            .initial_quality = 0.6,
            .adjustment_per_packet = 0,
            .headroom_ratio = 0.1,
        },
        VorbisQualityRateControllerConfig{
            .minimum_quality = 0.4,
            .maximum_quality = 0.8,
            .initial_quality = 0.6,
            .adjustment_per_packet = 0.1,
            .headroom_ratio = 1.1,
        },
    }) |invalid| {
        try std.testing.expectError(
            error.InvalidVorbisQualityRateControllerConfig,
            VorbisQualityRateController.init(invalid),
        );
    }

    controller.current_quality = std.math.nan(f64);
    try std.testing.expectError(
        error.InvalidVorbisQualityRateController,
        controller.observe(1_000, 900, true),
    );
    try std.testing.expectError(
        error.InvalidVorbisQualityRateController,
        controller.applyTo(.{}),
    );
    try controller.reset();
    try std.testing.expectApproxEqAbs(
        config.initial_quality,
        try controller.quality(),
        1.0e-15,
    );
}

test "Vorbis quality controller combines signal distortion and rate evidence" {
    const config = VorbisQualityRateControllerConfig{
        .minimum_quality = 0.3,
        .maximum_quality = 0.9,
        .initial_quality = 0.6,
        .adjustment_per_packet = 0.1,
        .headroom_ratio = 0.2,
    };
    var controller = try VorbisQualityRateController.init(config);
    const budget = VorbisPacketBitBudget{
        .packet_index = 7,
        .nominal_bits = 1_000,
        .target_bits = 1_000,
        .reservoir_balance_before = 0,
    };
    const clean = VorbisAudioResidueSubmapResult{
        .target_bits = 400,
        .encoded_bits = 300,
        .budget_met = true,
        .squared_error = 0.25,
        .weighted_squared_error = 0.5,
        .audible_excess_power = 0,
        .lambda = 0.01,
        .iterations = 3,
    };
    const audible = VorbisAudioResidueSubmapResult{
        .target_bits = 400,
        .encoded_bits = 300,
        .budget_met = true,
        .squared_error = 0.5,
        .weighted_squared_error = 1.5,
        .audible_excess_power = 0.25,
        .lambda = 0.02,
        .iterations = 4,
    };

    const clean_headroom = try controller.observeSignal(
        budget,
        .{
            .packet_index = 7,
            .actual_bits = 700,
            .reservoir_balance_after = 300,
        },
        &.{clean},
    );
    try std.testing.expect(clean_headroom.within_mask);
    try std.testing.expect(clean_headroom.has_rate_headroom);
    try std.testing.expectEqual(
        VorbisQualityRateAction.hold,
        clean_headroom.rate.action,
    );
    try std.testing.expectEqual(
        config.initial_quality,
        clean_headroom.rate.quality,
    );

    const audible_headroom = try controller.observeSignal(
        budget,
        .{
            .packet_index = 7,
            .actual_bits = 700,
            .reservoir_balance_after = 300,
        },
        &.{ audible, audible },
    );
    try std.testing.expect(!audible_headroom.within_mask);
    try std.testing.expect(audible_headroom.has_rate_headroom);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        audible_headroom.audible_excess_power,
        1.0e-15,
    );
    try std.testing.expectEqual(
        VorbisQualityRateAction.increase_quality,
        audible_headroom.rate.action,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.7),
        audible_headroom.rate.quality,
        1.0e-15,
    );

    const no_headroom = try controller.observeSignal(
        budget,
        .{
            .packet_index = 7,
            .actual_bits = 900,
            .reservoir_balance_after = 100,
        },
        &.{audible},
    );
    try std.testing.expect(!no_headroom.within_mask);
    try std.testing.expect(!no_headroom.has_rate_headroom);
    try std.testing.expectEqual(
        VorbisQualityRateAction.hold,
        no_headroom.rate.action,
    );

    const over_rate = try controller.observeSignal(
        budget,
        .{
            .packet_index = 7,
            .actual_bits = 1_100,
            .reservoir_balance_after = -100,
        },
        &.{clean},
    );
    try std.testing.expectEqual(
        VorbisQualityRateAction.decrease_quality,
        over_rate.rate.action,
    );
    const missed = VorbisAudioResidueSubmapResult{
        .target_bits = 100,
        .encoded_bits = 101,
        .budget_met = false,
        .squared_error = 1,
        .weighted_squared_error = 2,
        .audible_excess_power = 1,
        .lambda = 0.1,
        .iterations = 8,
    };
    const missed_budget = try controller.observeSignal(
        budget,
        .{
            .packet_index = 7,
            .actual_bits = 700,
            .reservoir_balance_after = 300,
        },
        &.{missed},
    );
    try std.testing.expectEqual(
        VorbisQualityRateAction.decrease_quality,
        missed_budget.rate.action,
    );
}

test "Vorbis signal quality feedback rejects hostile evidence transactionally" {
    var controller = try VorbisQualityRateController.init(.{
        .minimum_quality = 0.3,
        .maximum_quality = 0.9,
        .initial_quality = 0.6,
        .adjustment_per_packet = 0.1,
        .headroom_ratio = 0.2,
    });
    const budget = VorbisPacketBitBudget{
        .packet_index = 3,
        .nominal_bits = 1_000,
        .target_bits = 1_000,
        .reservoir_balance_before = 0,
    };
    const commit = VorbisRateCommit{
        .packet_index = 3,
        .actual_bits = 700,
        .reservoir_balance_after = 300,
    };
    const valid = VorbisAudioResidueSubmapResult{
        .target_bits = 400,
        .encoded_bits = 300,
        .budget_met = true,
        .squared_error = 0.25,
        .weighted_squared_error = 0.5,
        .audible_excess_power = 0.1,
        .lambda = 0.01,
        .iterations = 3,
    };
    const retained = try controller.quality();

    try std.testing.expectError(
        error.InvalidVorbisQualitySignalObservation,
        controller.observeSignal(budget, commit, &.{}),
    );
    var inconsistent = valid;
    inconsistent.budget_met = false;
    try std.testing.expectError(
        error.InvalidVorbisQualitySignalObservation,
        controller.observeSignal(budget, commit, &.{inconsistent}),
    );
    var non_finite = valid;
    non_finite.audible_excess_power = std.math.nan(f64);
    try std.testing.expectError(
        error.InvalidVorbisQualitySignalObservation,
        controller.observeSignal(budget, commit, &.{ valid, non_finite }),
    );
    var oversized_target = valid;
    oversized_target.target_bits = budget.target_bits + 1;
    try std.testing.expectError(
        error.InvalidVorbisQualitySignalObservation,
        controller.observeSignal(budget, commit, &.{oversized_target}),
    );
    var oversized_encoding = valid;
    oversized_encoding.target_bits = commit.actual_bits + 1;
    oversized_encoding.encoded_bits = commit.actual_bits + 1;
    try std.testing.expectError(
        error.InvalidVorbisQualitySignalObservation,
        controller.observeSignal(budget, commit, &.{oversized_encoding}),
    );
    const too_many = [_]VorbisAudioResidueSubmapResult{valid} ** 17;
    try std.testing.expectError(
        error.InvalidVorbisQualitySignalObservation,
        controller.observeSignal(budget, commit, &too_many),
    );
    var mismatched_commit = commit;
    mismatched_commit.packet_index += 1;
    try std.testing.expectError(
        error.MismatchedVorbisQualityRateObservation,
        controller.observeSignal(budget, mismatched_commit, &.{valid}),
    );
    try std.testing.expectEqual(retained, try controller.quality());
}

fn complexAnalysisForVorbisRateTest() VorbisPcmBlockClassification {
    return .{
        .analysis = .{
            .recommended_large_block = false,
            .peak = 1.5,
            .rms = 0.25,
            .maximum_energy_ratio = 8,
            .transient_segment = 1,
        },
        .recommended_large_block = false,
        .cross_block_energy_ratio = 8,
        .short_blocks_remaining = 2,
    };
}

test "Vorbis PCM block analysis selects steady and transient blocks" {
    try testVorbisPcmBlockAnalysis(f32);
    try testVorbisPcmBlockAnalysis(f64);
}

test "Vorbis PCM block classifier stabilizes cross-block decisions" {
    try testVorbisPcmBlockClassifier(f32);
    try testVorbisPcmBlockClassifier(f64);
}

fn testVorbisPcmBlockClassifier(comptime Float: type) !void {
    const quiet = [_]Float{0.1} ** 256;
    const loud = [_]Float{1} ** 256;
    const config = VorbisPcmBlockClassifierConfig{
        .cross_block_energy_ratio = 3,
        .stable_energy_ratio = 1.25,
        .energy_smoothing = 1,
        .minimum_short_blocks = 2,
    };
    var classifier = VorbisPcmBlockClassifier{};
    try std.testing.expect(classifier.valid());
    const first = try classifier.classify(
        Float,
        &.{&quiet},
        64,
        256,
        config,
    );
    try std.testing.expect(classifier.valid());
    try std.testing.expect(first.recommended_large_block);
    try std.testing.expectEqual(@as(f64, 1), first.cross_block_energy_ratio);

    const change = try classifier.classify(
        Float,
        &.{&loud},
        64,
        256,
        config,
    );
    try std.testing.expect(!change.recommended_large_block);
    try std.testing.expect(change.cross_block_energy_ratio > 99);
    try std.testing.expectEqual(
        @as(u8, 2),
        change.short_blocks_remaining,
    );
    const held_one = try classifier.classify(
        Float,
        &.{&loud},
        64,
        256,
        config,
    );
    try std.testing.expect(!held_one.recommended_large_block);
    try std.testing.expectEqual(
        @as(u8, 1),
        held_one.short_blocks_remaining,
    );
    const held_two = try classifier.classify(
        Float,
        &.{&loud},
        64,
        256,
        config,
    );
    try std.testing.expect(!held_two.recommended_large_block);
    try std.testing.expectEqual(
        @as(u8, 0),
        held_two.short_blocks_remaining,
    );
    const released = try classifier.classify(
        Float,
        &.{&loud},
        64,
        256,
        config,
    );
    try std.testing.expect(released.recommended_large_block);

    var within_block = [_]Float{0} ** 256;
    @memset(within_block[128..], 1);
    const attacked = try classifier.classify(
        Float,
        &.{&within_block},
        64,
        256,
        config,
    );
    try std.testing.expect(!attacked.recommended_large_block);
    try std.testing.expectEqual(@as(u8, 2), attacked.short_blocks_remaining);

    var hostile_hold = classifier;
    hostile_hold.large_block = true;
    const hostile_hold_before = hostile_hold;
    try std.testing.expect(!hostile_hold.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockClassifierState,
        hostile_hold.classify(
            Float,
            &.{&loud},
            64,
            256,
            config,
        ),
    );
    try std.testing.expectEqualDeep(hostile_hold_before, hostile_hold);

    const before_invalid = classifier;
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockClassifierConfig,
        classifier.classify(
            Float,
            &.{&loud},
            64,
            256,
            .{ .stable_energy_ratio = 3 },
        ),
    );
    try std.testing.expectEqualDeep(before_invalid, classifier);
    var non_finite = loud;
    non_finite[255] = std.math.nan(Float);
    try std.testing.expectError(
        error.InvalidVorbisPcmSample,
        classifier.classify(
            Float,
            &.{&non_finite},
            64,
            256,
            config,
        ),
    );
    try std.testing.expectEqualDeep(before_invalid, classifier);

    classifier.smoothed_mean_square = -1;
    const corrupt = classifier;
    try std.testing.expect(!classifier.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockClassifierState,
        classifier.classify(
            Float,
            &.{&loud},
            64,
            256,
            config,
        ),
    );
    try std.testing.expectEqualDeep(corrupt, classifier);
    classifier.reset();
    try std.testing.expect(classifier.valid());
    try std.testing.expectEqualDeep(
        VorbisPcmBlockClassifier{},
        classifier,
    );

    var malformed_initial = VorbisPcmBlockClassifier{};
    malformed_initial.large_block = false;
    const malformed_initial_before = malformed_initial;
    try std.testing.expect(!malformed_initial.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockClassifierState,
        malformed_initial.classify(
            Float,
            &.{&loud},
            64,
            256,
            config,
        ),
    );
    try std.testing.expectEqualDeep(
        malformed_initial_before,
        malformed_initial,
    );

    const silence = [_]Float{0} ** 256;
    _ = try classifier.classify(
        Float,
        &.{&silence},
        64,
        256,
        .{
            .analysis = .{ .minimum_rms = 0 },
            .energy_smoothing = 1,
        },
    );
    const from_silence = try classifier.classify(
        Float,
        &.{&loud},
        64,
        256,
        .{
            .analysis = .{ .minimum_rms = 0 },
            .energy_smoothing = 1,
        },
    );
    try std.testing.expectEqual(
        std.math.floatMax(f64),
        from_silence.cross_block_energy_ratio,
    );
    try std.testing.expect(!from_silence.recommended_large_block);
}

fn testVorbisPcmBlockAnalysis(comptime Float: type) !void {
    const steady = [_]Float{0.25} ** 256;
    const steady_analysis = try analyzeVorbisPcmBlock(
        Float,
        &.{&steady},
        64,
        256,
        .{},
    );
    try std.testing.expect(steady_analysis.recommended_large_block);
    try std.testing.expectEqual(@as(f64, 0.25), steady_analysis.peak);
    try std.testing.expectEqual(@as(f64, 0.25), steady_analysis.rms);
    try std.testing.expectEqual(
        @as(f64, 1),
        steady_analysis.maximum_energy_ratio,
    );
    try std.testing.expectEqual(
        @as(?u16, null),
        steady_analysis.transient_segment,
    );

    var attack = [_]Float{0} ** 256;
    @memset(attack[128..], 1);
    const silent_channel = [_]Float{0} ** 256;
    const attack_analysis = try analyzeVorbisPcmBlock(
        Float,
        &.{ &attack, &silent_channel },
        64,
        256,
        .{},
    );
    try std.testing.expect(!attack_analysis.recommended_large_block);
    try std.testing.expectEqual(@as(f64, 1), attack_analysis.peak);
    try std.testing.expectApproxEqAbs(
        @sqrt(@as(f64, 0.25)),
        attack_analysis.rms,
        8 * std.math.floatEps(f64),
    );
    try std.testing.expectEqual(
        @as(?u16, 4),
        attack_analysis.transient_segment,
    );
    try std.testing.expect(
        attack_analysis.maximum_energy_ratio >= 1_000_000,
    );

    const no_switch = try analyzeVorbisPcmBlock(
        Float,
        &.{steady[0..64]},
        64,
        64,
        .{},
    );
    try std.testing.expect(!no_switch.recommended_large_block);
    const zero_floor = try analyzeVorbisPcmBlock(
        Float,
        &.{&([_]Float{0} ** 256)},
        64,
        256,
        .{ .minimum_rms = 0 },
    );
    try std.testing.expect(zero_floor.recommended_large_block);
    try std.testing.expectEqual(
        @as(f64, 1),
        zero_floor.maximum_energy_ratio,
    );

    try std.testing.expectError(
        error.InvalidVorbisBlockAnalysisConfig,
        analyzeVorbisPcmBlock(
            Float,
            &.{&steady},
            64,
            256,
            .{ .transient_energy_ratio = 1 },
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisBlockSizes,
        analyzeVorbisPcmBlock(
            Float,
            &.{&steady},
            63,
            256,
            .{},
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockShape,
        analyzeVorbisPcmBlock(
            Float,
            &.{steady[0..255]},
            64,
            256,
            .{},
        ),
    );
    var non_finite = steady;
    non_finite[255] = std.math.inf(Float);
    try std.testing.expectError(
        error.InvalidVorbisPcmSample,
        analyzeVorbisPcmBlock(
            Float,
            &.{&non_finite},
            64,
            256,
            .{},
        ),
    );
}

test "Vorbis encoding block plans select retained modes" {
    var packet_storage: [128]u8 = undefined;
    const packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        true,
        false,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var parsed_modes: [1]VorbisMode = undefined;
    var setup = try parseVorbisSetup(packet.bytes, 2, .{
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &multiplicands,
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &parsed_modes,
    });
    const modes = [_]VorbisMode{
        .{ .large_block = false, .mapping = 0 },
        .{ .large_block = true, .mapping = 0 },
    };
    setup.modes = &modes;
    setup.summary.mode_count = modes.len;
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 256,
    };

    try std.testing.expectEqual(
        @as(u8, 0),
        try selectVorbisEncodingMode(setup, 0, false),
    );
    try std.testing.expectEqual(
        @as(u8, 1),
        try selectVorbisEncodingMode(setup, 0, true),
    );
    const small = try planVorbisEncodingBlock(
        identification,
        setup,
        0,
        true,
        false,
        true,
    );
    try std.testing.expectEqual(@as(u8, 0), small.mode_number);
    try std.testing.expect(!small.large_block);
    try std.testing.expectEqual(@as(?bool, null), small.previous_window_flag);
    try std.testing.expectEqual(@as(?bool, null), small.next_window_flag);
    try std.testing.expectEqual(@as(u16, 64), small.block_size);
    try std.testing.expectEqual(@as(usize, 2), small.payload_bit_offset);

    const large = try planVorbisEncodingBlock(
        identification,
        setup,
        0,
        false,
        true,
        true,
    );
    try std.testing.expectEqual(@as(u8, 1), large.mode_number);
    try std.testing.expect(large.large_block);
    try std.testing.expectEqual(
        @as(?bool, false),
        large.previous_window_flag,
    );
    try std.testing.expectEqual(
        @as(?bool, true),
        large.next_window_flag,
    );
    try std.testing.expectEqual(@as(u16, 256), large.block_size);
    try std.testing.expectEqual(@as(usize, 4), large.payload_bit_offset);

    var small_only = setup;
    small_only.modes = modes[0..1];
    small_only.summary.mode_count = 1;
    try std.testing.expectError(
        error.VorbisEncodingModeUnavailable,
        selectVorbisEncodingMode(small_only, 0, true),
    );
    try std.testing.expectError(
        error.InvalidVorbisMappingNumber,
        selectVorbisEncodingMode(setup, 1, false),
    );
    var invalid_identification = identification;
    invalid_identification.small_block_size = 63;
    try std.testing.expectError(
        error.InvalidVorbisIdentificationState,
        planVorbisEncodingBlock(
            invalid_identification,
            setup,
            0,
            false,
            true,
            true,
        ),
    );

    var frames = VorbisPcmFramePlanner.init(true);
    try std.testing.expect(frames.valid());
    const large_to_small = try frames.plan(
        identification,
        setup,
        0,
        true,
        false,
    );
    try std.testing.expect(frames.valid());
    try std.testing.expectEqual(
        @as(u64, 0),
        large_to_small.packet_index,
    );
    try std.testing.expectEqual(
        @as(i64, -128),
        large_to_small.source_start,
    );
    try std.testing.expectEqual(
        @as(u16, 80),
        large_to_small.pcm_advance,
    );
    try std.testing.expectEqual(
        @as(i64, 80),
        large_to_small.next_center,
    );
    try std.testing.expectEqual(
        @as(?bool, true),
        large_to_small.header.previous_window_flag,
    );
    try std.testing.expectEqual(
        @as(?bool, false),
        large_to_small.header.next_window_flag,
    );
    const short = try frames.plan(
        identification,
        setup,
        0,
        false,
        false,
    );
    try std.testing.expectEqual(@as(i64, 48), short.source_start);
    try std.testing.expectEqual(@as(u16, 32), short.pcm_advance);
    try std.testing.expectEqual(@as(i64, 112), short.next_center);
    const small_to_large = try frames.plan(
        identification,
        setup,
        0,
        false,
        true,
    );
    try std.testing.expectEqual(
        @as(i64, 80),
        small_to_large.source_start,
    );
    try std.testing.expectEqual(
        @as(u16, 80),
        small_to_large.pcm_advance,
    );
    const sequenced_large = try frames.plan(
        identification,
        setup,
        0,
        true,
        true,
    );
    try std.testing.expectEqual(
        @as(i64, 64),
        sequenced_large.source_start,
    );
    try std.testing.expectEqual(
        @as(u16, 128),
        sequenced_large.pcm_advance,
    );
    try std.testing.expectEqual(
        @as(?bool, false),
        sequenced_large.header.previous_window_flag,
    );
    try std.testing.expectEqual(
        @as(?bool, true),
        sequenced_large.header.next_window_flag,
    );

    const preserved_frames = frames;
    try std.testing.expectError(
        error.InvalidVorbisMappingNumber,
        frames.plan(
            identification,
            setup,
            1,
            true,
            true,
        ),
    );
    try std.testing.expectEqualDeep(preserved_frames, frames);
    frames.packet_index = @intCast(
        @divFloor(std.math.maxInt(i64), 4096) + 1,
    );
    frames.center = std.math.maxInt(i64) - 15;
    try std.testing.expect(frames.valid());
    const overflow_state = frames;
    try std.testing.expectError(
        error.VorbisPcmFramePositionOverflow,
        frames.plan(
            identification,
            setup,
            0,
            true,
            false,
        ),
    );
    try std.testing.expectEqualDeep(overflow_state, frames);
    frames.reset(false);
    try std.testing.expect(frames.valid());
    try std.testing.expectEqual(
        VorbisPcmFramePlanner.init(false),
        frames,
    );
    frames.packet_index = std.math.maxInt(u64);
    const exhausted_state = frames;
    try std.testing.expect(!frames.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmFramePlannerState,
        frames.plan(
            identification,
            setup,
            0,
            false,
            false,
        ),
    );
    try std.testing.expectEqualDeep(exhausted_state, frames);

    frames = VorbisPcmFramePlanner.init(false);
    frames.packet_index = 1;
    frames.center = 31;
    try std.testing.expect(!frames.valid());
    frames.center = 4097;
    try std.testing.expect(!frames.valid());
    frames.center = 32;
    try std.testing.expect(frames.valid());
    frames.center = 33;
    try std.testing.expect(!frames.valid());
    frames.center = 4096;
    try std.testing.expect(frames.valid());

    var invalid_frames = VorbisPcmFramePlanner.init(false);
    invalid_frames.center = -1;
    const invalid_frames_before = invalid_frames;
    try std.testing.expect(!invalid_frames.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmFramePlannerState,
        invalid_frames.plan(
            identification,
            setup,
            0,
            false,
            false,
        ),
    );
    try std.testing.expectEqualDeep(
        invalid_frames_before,
        invalid_frames,
    );

    const stationary = VorbisPcmBlockAnalysis{
        .recommended_large_block = true,
        .peak = 1,
        .rms = 0.5,
        .maximum_energy_ratio = 1,
        .transient_segment = null,
    };
    const transient = VorbisPcmBlockAnalysis{
        .recommended_large_block = false,
        .peak = 1,
        .rms = 0.5,
        .maximum_energy_ratio = 8,
        .transient_segment = 2,
    };
    var lookahead = VorbisPcmBlockLookahead.init(true);
    try std.testing.expect(lookahead.valid());
    var invalid_lookahead = lookahead;
    invalid_lookahead.frames.center = -1;
    const invalid_lookahead_before = invalid_lookahead;
    try std.testing.expect(!invalid_lookahead.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockLookaheadState,
        invalid_lookahead.prime(stationary),
    );
    try std.testing.expectEqualDeep(
        invalid_lookahead_before,
        invalid_lookahead,
    );
    try std.testing.expectError(
        error.VorbisBlockLookaheadNotPrimed,
        lookahead.push(
            identification,
            setup,
            0,
            stationary,
        ),
    );
    try lookahead.prime(stationary);
    try std.testing.expect(lookahead.valid());
    try std.testing.expectError(
        error.VorbisBlockLookaheadAlreadyPrimed,
        lookahead.prime(transient),
    );
    const lookahead_before_failure = lookahead;
    try std.testing.expectError(
        error.InvalidVorbisMappingNumber,
        lookahead.push(
            identification,
            setup,
            1,
            transient,
        ),
    );
    try std.testing.expectEqualDeep(
        lookahead_before_failure,
        lookahead,
    );
    const scheduled_large = try lookahead.push(
        identification,
        setup,
        0,
        transient,
    );
    try std.testing.expect(scheduled_large.header.large_block);
    try std.testing.expectEqual(
        @as(?bool, false),
        scheduled_large.header.next_window_flag,
    );
    const scheduled_small = try lookahead.push(
        identification,
        setup,
        0,
        stationary,
    );
    try std.testing.expect(!scheduled_small.header.large_block);
    const terminal = try lookahead.finish(
        identification,
        setup,
        0,
    );
    try std.testing.expect(lookahead.valid());
    try std.testing.expect(terminal.header.large_block);
    try std.testing.expectEqual(
        @as(?bool, false),
        terminal.header.previous_window_flag,
    );
    try std.testing.expectEqual(
        @as(?bool, true),
        terminal.header.next_window_flag,
    );
    try std.testing.expectEqual(
        @as(?bool, null),
        lookahead.pending_large_block,
    );
    try std.testing.expectError(
        error.VorbisBlockLookaheadNotPrimed,
        lookahead.finish(
            identification,
            setup,
            0,
        ),
    );
    lookahead.reset(false);
    try std.testing.expect(lookahead.valid());
    try std.testing.expectEqual(
        VorbisPcmBlockLookahead.init(false),
        lookahead,
    );
}

test "Vorbis PCM packet sequence commits only after Ogg append" {
    try testVorbisPcmPacketSequence(f32);
    try testVorbisPcmPacketSequence(f64);
}

fn testVorbisPcmPacketSequence(comptime Float: type) !void {
    var packet_storage: [128]u8 = undefined;
    const setup_packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        true,
        false,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var parsed_modes: [1]VorbisMode = undefined;
    var setup = try parseVorbisSetup(setup_packet.bytes, 2, .{
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &multiplicands,
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &parsed_modes,
    });
    const modes = [_]VorbisMode{
        .{ .large_block = false, .mapping = 0 },
        .{ .large_block = true, .mapping = 0 },
    };
    setup.modes = &modes;
    setup.summary.mode_count = modes.len;
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 48_000,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 256,
    };
    const config = VorbisPcmPacketSequenceConfig{
        .classifier = .{
            .cross_block_energy_ratio = 3,
            .stable_energy_ratio = 1.25,
            .energy_smoothing = 1,
            .minimum_short_blocks = 1,
        },
        .rate_control = .{
            .target_bitrate = 48_000,
            .reservoir_capacity_bits = 2_048,
            .maximum_packet_bits = 2_048,
        },
        .adaptive_rate = .{},
    };
    var invalid_config = config;
    invalid_config.adaptive_rate.?.full_activity_rms =
        invalid_config.adaptive_rate.?.quiet_rms;
    try std.testing.expectError(
        error.InvalidVorbisAdaptiveRatePolicyConfig,
        VorbisPcmPacketSequence.init(invalid_config, true),
    );
    var sequence = try VorbisPcmPacketSequence.init(config, true);
    try std.testing.expect(sequence.valid());
    const steady = [_]Float{0.1} ** 256;
    var corrupt_sequence = sequence;
    corrupt_sequence.reservoir.balance_bits = 2_049;
    const corrupt_sequence_before = corrupt_sequence;
    try std.testing.expect(!corrupt_sequence.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketSequenceState,
        corrupt_sequence.prime(
            Float,
            &.{ &steady, &steady },
            identification,
        ),
    );
    try std.testing.expectEqualDeep(
        corrupt_sequence_before,
        corrupt_sequence,
    );

    const primed = try sequence.prime(
        Float,
        &.{ &steady, &steady },
        identification,
    );
    try std.testing.expect(sequence.valid());
    try std.testing.expect(primed.recommended_large_block);
    try std.testing.expectEqual(@as(u64, 1), sequence.revision);

    var hostile_classifier_schedule = sequence;
    hostile_classifier_schedule.classifier.large_block = false;
    try std.testing.expect(hostile_classifier_schedule.classifier.valid());
    const hostile_classifier_schedule_before =
        hostile_classifier_schedule;
    try std.testing.expect(!hostile_classifier_schedule.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketSequenceState,
        hostile_classifier_schedule.planNext(
            Float,
            &.{ &steady, &steady },
            identification,
            setup,
        ),
    );
    try std.testing.expectEqualDeep(
        hostile_classifier_schedule_before,
        hostile_classifier_schedule,
    );

    const before_plan = sequence;
    const loud = [_]Float{1} ** 256;
    const plan = try sequence.planNext(
        Float,
        &.{ &loud, &loud },
        identification,
        setup,
    );
    try std.testing.expectEqualDeep(before_plan, sequence);
    try std.testing.expect(plan.frame.header.large_block);
    try std.testing.expectEqual(
        @as(?bool, false),
        plan.frame.header.next_window_flag,
    );
    try std.testing.expectEqual(@as(u64, 0), plan.granule_position);
    try std.testing.expect(!plan.end);
    try std.testing.expectEqual(@as(u64, 0), plan.budget.packet_index);
    try std.testing.expectEqual(@as(u32, 99), plan.budget.target_bits);
    try std.testing.expectEqualDeep(
        plan.budget,
        plan.reservoir_pending.pending.?,
    );
    try std.testing.expect(
        !plan.classification.?.recommended_large_block,
    );
    var hostile_plan = plan;
    hostile_plan.reservoir_pending.balance_bits = 1;
    hostile_plan.reservoir_pending.pending.?.reservoir_balance_before = 1;
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketPlan,
        sequence.commit(hostile_plan, 1),
    );
    try std.testing.expectEqualDeep(before_plan, sequence);

    var hostile_frame = plan;
    hostile_frame.frame.source_start += 1;
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketPlan,
        sequence.commit(hostile_frame, 1),
    );
    try std.testing.expectEqualDeep(before_plan, sequence);

    var hostile_header = plan;
    hostile_header.frame.header.previous_window_flag = false;
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketPlan,
        sequence.commit(hostile_header, 1),
    );
    try std.testing.expectEqualDeep(before_plan, sequence);

    var hostile_classifier = plan;
    hostile_classifier.classifier_after.smoothed_mean_square =
        std.math.nan(f64);
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketPlan,
        sequence.commit(hostile_classifier, 1),
    );
    try std.testing.expectEqualDeep(before_plan, sequence);

    var hostile_classification = plan;
    hostile_classification.classification.?.cross_block_energy_ratio =
        std.math.nan(f64);
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketPlan,
        sequence.commit(hostile_classification, 1),
    );
    try std.testing.expectEqualDeep(before_plan, sequence);

    try std.testing.expectError(
        error.InvalidVorbisAudioPacketBitCount,
        sequence.commit(plan, 0),
    );
    try std.testing.expectEqualDeep(before_plan, sequence);

    var ogg_storage: [96]u8 = undefined;
    var writer = StreamWriter.init(&ogg_storage, 0x70636d);
    try writer.appendPacket(&.{1}, 0, true, false);
    const before_failed_append = sequence;
    const writer_before_failed_append = writer;
    const oversized_packet = [_]u8{0} ** 80;
    try std.testing.expectError(
        error.OggOutputTooSmall,
        sequence.appendMemory(
            &writer,
            plan,
            &oversized_packet,
            oversized_packet.len * 8,
        ),
    );
    try std.testing.expectEqualDeep(
        before_failed_append,
        sequence,
    );
    try std.testing.expectEqualDeep(
        writer_before_failed_append,
        writer,
    );

    const first_commit = try sequence.appendMemory(
        &writer,
        plan,
        &.{0},
        1,
    );
    try std.testing.expectEqual(@as(u64, 0), first_commit.rate.packet_index);
    try std.testing.expectEqual(@as(u32, 1), first_commit.rate.actual_bits);
    try std.testing.expectEqual(@as(u64, 2), sequence.revision);
    try std.testing.expectEqual(@as(u64, 1), sequence.reservoir.packet_index);
    try std.testing.expectEqual(@as(u64, 0), sequence.granule_position);
    try std.testing.expect(sequence.valid());

    var hostile_hold_sequence = sequence;
    try std.testing.expect(
        hostile_hold_sequence.classifier.short_blocks_remaining != 0,
    );
    hostile_hold_sequence.classifier.large_block = true;
    const hostile_hold_sequence_before = hostile_hold_sequence;
    try std.testing.expect(!hostile_hold_sequence.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketSequenceState,
        hostile_hold_sequence.planFinish(
            identification,
            setup,
            80,
        ),
    );
    try std.testing.expectEqualDeep(
        hostile_hold_sequence_before,
        hostile_hold_sequence,
    );

    var impossible_granule = sequence;
    impossible_granule.granule_position =
        @intCast(impossible_granule.lookahead.frames.center);
    const impossible_granule_before = impossible_granule;
    try std.testing.expect(!impossible_granule.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketSequenceState,
        impossible_granule.planFinish(
            identification,
            setup,
            80,
        ),
    );
    try std.testing.expectEqualDeep(
        impossible_granule_before,
        impossible_granule,
    );

    const after_first_commit = sequence;
    try std.testing.expectError(
        error.StaleVorbisPcmPacketPlan,
        sequence.commit(plan, 1),
    );
    try std.testing.expectEqualDeep(after_first_commit, sequence);

    try std.testing.expectError(
        error.InvalidVorbisEncoderGranulePosition,
        sequence.planFinish(
            identification,
            setup,
            81,
        ),
    );
    try std.testing.expectEqualDeep(after_first_commit, sequence);
    const finish = try sequence.planFinish(
        identification,
        setup,
        80,
    );
    try std.testing.expect(finish.end);
    try std.testing.expectEqual(
        @as(?VorbisPcmBlockClassification, null),
        finish.classification,
    );
    try std.testing.expectEqual(@as(u64, 80), finish.granule_position);
    try std.testing.expectEqualDeep(after_first_commit, sequence);

    var hostile_finish_granule = finish;
    hostile_finish_granule.granule_position += 1;
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketPlan,
        sequence.commit(hostile_finish_granule, 1),
    );
    try std.testing.expectEqualDeep(after_first_commit, sequence);

    var hostile_finish_classifier = finish;
    hostile_finish_classifier.classifier_after.large_block =
        !hostile_finish_classifier.classifier_after.large_block;
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketPlan,
        sequence.commit(hostile_finish_classifier, 1),
    );
    try std.testing.expectEqualDeep(after_first_commit, sequence);

    try std.testing.expectError(
        error.InvalidVorbisAudioPacketBitCount,
        sequence.appendMemory(&writer, finish, &.{0}, 9),
    );
    try std.testing.expectEqualDeep(after_first_commit, sequence);
    var invalid_file_writer: FileWriter = undefined;
    invalid_file_writer.failed = true;
    try std.testing.expectError(
        error.InvalidOggFileWriterState,
        sequence.appendFile(
            &invalid_file_writer,
            finish,
            &.{0},
            1,
        ),
    );
    try std.testing.expectEqualDeep(after_first_commit, sequence);

    const terminal_commit = try sequence.appendMemory(
        &writer,
        finish,
        &.{0},
        1,
    );
    try std.testing.expect(terminal_commit.end);
    try std.testing.expect(sequence.ended);
    try std.testing.expect(sequence.valid());
    try std.testing.expect(writer.ended);
    try std.testing.expectEqual(@as(u64, 80), sequence.granule_position);

    var pages = PageIterator.init(writer.bytes());
    var final_page: ?Page = null;
    while (try pages.next()) |page| final_page = page;
    try std.testing.expect(final_page.?.end);
    try std.testing.expectEqual(
        @as(u64, 80),
        final_page.?.granule_position,
    );
    try std.testing.expectError(
        error.VorbisPcmPacketSequenceAlreadyEnded,
        sequence.planFinish(
            identification,
            setup,
            80,
        ),
    );
}

test "Vorbis PCM packet trials encode without advancing sequence state" {
    try testVorbisPcmPacketEncodingTrial(f32);
    try testVorbisPcmPacketEncodingTrial(f64);
}

fn testVorbisPcmPacketEncodingTrial(comptime Float: type) !void {
    const codebook_entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 1 },
    };
    const codebooks = [_]VorbisCodebook{.{
        .dimensions = 1,
        .entries = 1,
        .entry_offset = 0,
        .active_entry_count = 1,
        .tree_node_offset = 0,
        .tree_node_count = 0,
        .lookup_type = 0,
    }};
    var x_list = [_]u16{0} ** 65;
    x_list[1] = 32;
    const floors = [_]VorbisFloor{.{ .one = .{
        .partition_count = 0,
        .partition_classes = [_]u4{0} ** 31,
        .class_count = 0,
        .classes = [_]VorbisFloorOneClass{.{
            .dimensions = 0,
            .subclass_bits = 0,
            .masterbook = -1,
            .subclass_books = [_]i16{-1} ** 8,
        }} ** 16,
        .multiplier = 1,
        .range_bits = 5,
        .point_count = 2,
        .x_list = x_list,
    } }};
    const residues = [_]VorbisResidue{.{
        .kind = .one,
        .begin = 0,
        .end = 32,
        .partition_size = 1,
        .classification_count = 1,
        .classbook = 0,
        .cascades = [_]u8{0} ** 64,
        .books = [_][8]i16{[_]i16{-1} ** 8} ** 64,
    }};
    const mappings = [_]VorbisMapping{.{
        .submap_count = 1,
        .coupling_step_count = 0,
        .coupling_steps = [_]VorbisCouplingStep{.{
            .magnitude = 0,
            .angle = 0,
        }} ** 256,
        .channel_mux = [_]u4{0} ** 255,
        .submaps = [_]VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    }};
    const modes = [_]VorbisMode{.{
        .large_block = false,
        .mapping = 0,
    }};
    const setup = VorbisSetup{
        .summary = .{
            .codebook_count = 1,
            .codebook_entry_count = 1,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 1,
            .maximum_codebook_entries = 1,
        },
        .codebooks = &codebooks,
        .codebook_entries = &codebook_entries,
        .huffman_nodes = &.{},
        .codebook_multiplicands = &.{},
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    };
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 192_000,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    var sequence = try VorbisPcmPacketSequence.init(
        .{
            .classifier = .{
                .cross_block_energy_ratio = 3,
                .stable_energy_ratio = 1.25,
                .energy_smoothing = 1,
                .minimum_short_blocks = 1,
            },
            .rate_control = .{
                .target_bitrate = 192_000,
                .reservoir_capacity_bits = 2_048,
                .maximum_packet_bits = 2_048,
            },
        },
        true,
    );
    const steady = [_]Float{0.1} ** 64;
    _ = try sequence.prime(
        Float,
        &.{ &steady, &steady },
        identification,
    );
    const plan = try sequence.planNext(
        Float,
        &.{ &steady, &steady },
        identification,
        setup,
    );
    const sequence_before = sequence;
    const coefficient_count: usize =
        plan.frame.header.block_size / 2;
    try std.testing.expectEqual(@as(usize, 32), coefficient_count);

    const floor_value =
        vorbisFloorOneInverseDb(Float, 100);
    var spectra: [64]Float = undefined;
    var floor_targets: [64]Float = undefined;
    var thresholds: [64]Float = undefined;
    @memset(&spectra, floor_value * 2);
    @memset(&floor_targets, floor_value);
    @memset(&thresholds, floor_value * 0.1);
    const analysis_value = VorbisPsychoacousticAnalysis{
        .silent = false,
        .active_band_count = 1,
        .peak = 1,
        .rms = 1,
        .spectral_flatness = 0,
        .tonality = 1,
        .masking_relaxation_db = 0,
    };
    const analyses =
        [_]VorbisPsychoacousticAnalysis{analysis_value} ** 2;
    const analysis = VorbisPcmFrameAnalysisPlan(Float){
        .frame = plan.frame,
        .spectra = &spectra,
        .analyses = &analyses,
        .floor_targets = &floor_targets,
        .noise_thresholds = &thresholds,
        .coefficient_count = coefficient_count,
    };
    const requirements =
        try requiredVorbisPcmPacketEncodingStorage(
            identification,
            setup,
            plan.frame,
        );
    try std.testing.expectEqual(
        @as(usize, identification.channel_count),
        requirements.preparation.floor_encodings,
    );
    try std.testing.expectEqual(
        @as(usize, identification.channel_count),
        requirements.quantization.do_not_encode,
    );
    try std.testing.expectEqual(
        @as(usize, mappings[0].submap_count),
        requirements.quantization.encodings,
    );

    var floor_fit_y: [130]u32 = undefined;
    var floor_fit_curves: [256]Float = undefined;
    var preparation_floor_encodings: [2]VorbisFloorPacketEncoding = undefined;
    var preparation_y: [130]u32 = undefined;
    var preparation_curves: [256]Float = undefined;
    var preparation_residue: [256]Float = undefined;
    var preparation_thresholds: [256]Float = undefined;
    var coupling_values: [256]Float = undefined;
    var coupling_thresholds: [256]Float = undefined;
    var preparation_skips: [2]bool = undefined;

    var trial_floor_encodings: [2]VorbisFloorPacketEncoding = undefined;
    var trial_floor_y: [130]u32 = undefined;
    var trial_floor_curves: [256]Float = undefined;
    var trial_residue: [256]Float = undefined;
    var trial_thresholds: [256]Float = undefined;
    var trial_preparation_skips: [2]bool = undefined;

    var partition: [256]Float = undefined;
    var vector: [256]Float = undefined;
    var classifications: [512]u8 = undefined;
    var best_classifications: [512]u8 = undefined;
    var output_classifications: [512]u8 = undefined;
    var quantization_entries: [2_048]u32 = undefined;
    var quantization_skips: [2]bool = undefined;

    var trial_residue_encodings: [16]VorbisResidueEncoding = undefined;
    var trial_submap_results: [16]VorbisAudioResidueSubmapResult = undefined;
    var trial_quantization_skips: [2]bool = undefined;
    var trial_classifications: [512]u8 = undefined;
    var trial_entries: [2_048]u32 = undefined;

    const sentinel_floor = VorbisFloorPacketEncoding{
        .one = .{
            .used = true,
            .y_values = &.{99},
        },
    };
    var retained_floor_encodings =
        [_]VorbisFloorPacketEncoding{sentinel_floor} ** 2;
    var retained_floor_y = [_]u32{91} ** 130;
    var retained_floor_curves = [_]Float{92} ** 256;
    var retained_residue = [_]Float{93} ** 256;
    var retained_thresholds = [_]Float{94} ** 256;
    var retained_preparation_skips = [_]bool{true} ** 2;

    var retained_residue_encodings: [16]VorbisResidueEncoding = undefined;
    var retained_submap_results: [16]VorbisAudioResidueSubmapResult = undefined;
    var retained_quantization_skips = [_]bool{true} ** 2;
    var retained_classifications = [_]u8{95} ** 512;
    var retained_entries = [_]u32{96} ** 2_048;

    const scratch = VorbisPcmPacketEncodingScratch(Float){
        .preparation = .{
            .floor_fit_y_values = &floor_fit_y,
            .floor_fit_curves = &floor_fit_curves,
            .floor_encodings = &preparation_floor_encodings,
            .floor_y_values = &preparation_y,
            .floor_curves = &preparation_curves,
            .residue_values = &preparation_residue,
            .noise_thresholds = &preparation_thresholds,
            .coupling_values = &coupling_values,
            .coupling_thresholds = &coupling_thresholds,
            .do_not_encode = &preparation_skips,
        },
        .preparation_storage = .{
            .floor_encodings = &trial_floor_encodings,
            .floor_y_values = &trial_floor_y,
            .floor_curves = &trial_floor_curves,
            .residue_values = &trial_residue,
            .noise_thresholds = &trial_thresholds,
            .do_not_encode = &trial_preparation_skips,
        },
        .quantization = .{
            .partition = &partition,
            .vector = &vector,
            .classifications = &classifications,
            .best_classifications = &best_classifications,
            .output_classifications = &output_classifications,
            .entries = &quantization_entries,
            .do_not_encode = &quantization_skips,
        },
        .quantization_storage = .{
            .encodings = &trial_residue_encodings,
            .submap_results = &trial_submap_results,
            .do_not_encode = &trial_quantization_skips,
            .classifications = &trial_classifications,
            .entries = &trial_entries,
        },
    };
    const storage = VorbisPcmPacketEncodingStorage(Float){
        .preparation = .{
            .floor_encodings = &retained_floor_encodings,
            .floor_y_values = &retained_floor_y,
            .floor_curves = &retained_floor_curves,
            .residue_values = &retained_residue,
            .noise_thresholds = &retained_thresholds,
            .do_not_encode = &retained_preparation_skips,
        },
        .quantization = .{
            .encodings = &retained_residue_encodings,
            .submap_results = &retained_submap_results,
            .do_not_encode = &retained_quantization_skips,
            .classifications = &retained_classifications,
            .entries = &retained_entries,
        },
    };
    var packet = [_]u8{97} ** 256;
    const floor_before = retained_floor_encodings;
    const y_before = retained_floor_y;
    const residue_before = retained_residue;
    const classifications_before = retained_classifications;
    var invalid_analysis = analysis;
    invalid_analysis.coefficient_count -= 1;
    try std.testing.expectError(
        error.InvalidVorbisPcmFrameAnalysisPlan,
        encodeVorbisPcmPacketTrial(
            Float,
            &sequence,
            identification,
            setup,
            plan,
            invalid_analysis,
            &.{1},
            .{},
            &packet,
            scratch,
            storage,
        ),
    );
    var short_scratch = scratch;
    short_scratch.preparation_storage.floor_y_values =
        trial_floor_y[0 .. requirements.preparation.floor_y_values - 1];
    try std.testing.expectError(
        error.VorbisPcmPacketEncodingScratchTooSmall,
        encodeVorbisPcmPacketTrial(
            Float,
            &sequence,
            identification,
            setup,
            plan,
            analysis,
            &.{1},
            .{},
            &packet,
            short_scratch,
            storage,
        ),
    );
    var short_storage = storage;
    short_storage.quantization.classifications =
        retained_classifications[0 .. requirements.quantization.classifications - 1];
    try std.testing.expectError(
        error.VorbisPcmPacketEncodingStorageTooSmall,
        encodeVorbisPcmPacketTrial(
            Float,
            &sequence,
            identification,
            setup,
            plan,
            analysis,
            &.{1},
            .{},
            &packet,
            scratch,
            short_storage,
        ),
    );
    var aliased_storage = storage;
    aliased_storage.preparation.residue_values = &trial_residue;
    try std.testing.expectError(
        error.OverlappingVorbisPcmPacketEncodingStorage,
        encodeVorbisPcmPacketTrial(
            Float,
            &sequence,
            identification,
            setup,
            plan,
            analysis,
            &.{1},
            .{},
            &packet,
            scratch,
            aliased_storage,
        ),
    );
    try std.testing.expectError(
        error.VorbisAudioPacketOutputTooSmall,
        encodeVorbisPcmPacketTrial(
            Float,
            &sequence,
            identification,
            setup,
            plan,
            analysis,
            &.{1},
            .{},
            packet[0..0],
            scratch,
            storage,
        ),
    );
    try std.testing.expectEqualDeep(floor_before, retained_floor_encodings);
    try std.testing.expectEqualSlices(u32, &y_before, &retained_floor_y);
    try std.testing.expectEqualSlices(
        Float,
        &residue_before,
        &retained_residue,
    );
    try std.testing.expectEqualSlices(
        u8,
        &classifications_before,
        &retained_classifications,
    );
    try std.testing.expectEqualDeep(sequence_before, sequence);
    try std.testing.expectEqual(@as(u8, 97), packet[0]);

    var constrained_sequence = try VorbisPcmPacketSequence.init(
        .{
            .classifier = .{
                .cross_block_energy_ratio = 3,
                .stable_energy_ratio = 1.25,
                .energy_smoothing = 1,
                .minimum_short_blocks = 1,
            },
            .rate_control = .{
                .target_bitrate = 54_000,
                .reservoir_capacity_bits = 32,
                .maximum_packet_bits = 2_048,
            },
        },
        true,
    );
    _ = try constrained_sequence.prime(
        Float,
        &.{ &steady, &steady },
        identification,
    );
    const constrained_plan = try constrained_sequence.planNext(
        Float,
        &.{ &steady, &steady },
        identification,
        setup,
    );
    var constrained_analysis = analysis;
    constrained_analysis.frame = constrained_plan.frame;
    const constrained_before = constrained_sequence;
    try std.testing.expectError(
        error.VorbisBitReservoirExceeded,
        encodeVorbisPcmPacketTrial(
            Float,
            &constrained_sequence,
            identification,
            setup,
            constrained_plan,
            constrained_analysis,
            &.{1},
            .{},
            &packet,
            scratch,
            storage,
        ),
    );
    try std.testing.expectEqualDeep(
        constrained_before,
        constrained_sequence,
    );
    try std.testing.expectEqual(@as(u8, 97), packet[0]);
    try std.testing.expectEqualDeep(floor_before, retained_floor_encodings);
    try std.testing.expectEqualSlices(u32, &y_before, &retained_floor_y);

    const Analyzer = VorbisPcmFrameAnalyzer(Float, 2, 64, 64);
    var analyzer = Analyzer.init();
    var analysis_pcm: [128]Float = undefined;
    var analysis_transform: [64]Float = undefined;
    var analysis_spectrum_scratch: [64]Float = undefined;
    var analysis_floor_scratch: [64]Float = undefined;
    var analysis_threshold_scratch: [64]Float = undefined;
    var analysis_spectra: [64]Float = undefined;
    var analysis_values: [2]VorbisPsychoacousticAnalysis = undefined;
    var analysis_floor: [64]Float = undefined;
    var analysis_thresholds: [64]Float = undefined;
    const orchestration_scratch =
        VorbisPcmPacketOrchestrationScratch(Float){
            .analysis = .{
                .pcm = &analysis_pcm,
                .transform = &analysis_transform,
                .spectra = &analysis_spectrum_scratch,
                .floor_targets = &analysis_floor_scratch,
                .noise_thresholds = &analysis_threshold_scratch,
            },
            .analysis_storage = .{
                .spectra = &analysis_spectra,
                .analyses = &analysis_values,
                .floor_targets = &analysis_floor,
                .noise_thresholds = &analysis_thresholds,
            },
            .encoding = scratch,
        };
    var invalid_identification = identification;
    invalid_identification.channel_count = 1;
    try std.testing.expectError(
        error.InvalidVorbisPcmEncoderConfiguration,
        encodeVorbisPcmPacket(
            Float,
            2,
            64,
            64,
            &analyzer,
            &sequence,
            invalid_identification,
            setup,
            plan,
            &.{ &steady, &steady },
            .{},
            &.{1},
            .{},
            &packet,
            orchestration_scratch,
            storage,
        ),
    );
    var short_orchestration_scratch = orchestration_scratch;
    short_orchestration_scratch.analysis_storage.analyses =
        analysis_values[0..1];
    try std.testing.expectError(
        error.VorbisPcmFrameAnalysisStorageTooSmall,
        encodeVorbisPcmPacket(
            Float,
            2,
            64,
            64,
            &analyzer,
            &sequence,
            identification,
            setup,
            plan,
            &.{ &steady, &steady },
            .{},
            &.{1},
            .{},
            &packet,
            short_orchestration_scratch,
            storage,
        ),
    );
    try std.testing.expectEqualDeep(sequence_before, sequence);
    try std.testing.expectEqual(@as(u8, 97), packet[0]);
    const orchestrated = try encodeVorbisPcmPacket(
        Float,
        2,
        64,
        64,
        &analyzer,
        &sequence,
        identification,
        setup,
        plan,
        &.{ &steady, &steady },
        .{},
        &.{1},
        .{},
        &packet,
        orchestration_scratch,
        storage,
    );
    try std.testing.expectEqualDeep(sequence_before, sequence);
    try std.testing.expectEqual(
        orchestrated.packet.bit_count,
        orchestrated.commit.rate.actual_bits,
    );

    const trial = try encodeVorbisPcmPacketTrial(
        Float,
        &sequence,
        identification,
        setup,
        plan,
        analysis,
        &.{1},
        .{},
        &packet,
        scratch,
        storage,
    );
    try std.testing.expectEqualDeep(sequence_before, sequence);
    try std.testing.expectEqual(
        trial.packet.bit_count,
        trial.commit.rate.actual_bits,
    );
    var residue_bits: u32 = 0;
    for (trial.quantization.submap_results) |result|
        residue_bits += result.encoded_bits;
    try std.testing.expectEqual(
        trial.packet.bit_count,
        trial.preparation.fixed_packet_bits + residue_bits,
    );
    try std.testing.expectEqual(
        @intFromPtr(retained_floor_encodings[0..].ptr),
        @intFromPtr(trial.preparation.floor_encodings.ptr),
    );
    try std.testing.expectEqual(
        @intFromPtr(retained_residue_encodings[0..].ptr),
        @intFromPtr(trial.quantization.encodings.ptr),
    );
    try std.testing.expectEqualSlices(
        u8,
        trial.packet.bytes,
        packet[0..trial.packet.bytes.len],
    );
    var quality_controller = try VorbisQualityRateController.init(.{
        .minimum_quality = 0.4,
        .maximum_quality = 0.9,
        .initial_quality = 0.7,
        .adjustment_per_packet = 0.05,
        .headroom_ratio = 0.1,
    });
    const signal_decision = try quality_controller.observePcmPacketTrial(
        Float,
        plan,
        trial,
    );
    var audible_excess_power: f64 = 0;
    for (trial.quantization.submap_results) |result|
        audible_excess_power += result.audible_excess_power;
    try std.testing.expectApproxEqAbs(
        audible_excess_power,
        signal_decision.audible_excess_power,
        1.0e-15,
    );
    const retained_quality = try quality_controller.quality();
    var malformed_trial = trial;
    malformed_trial.quantization.allocation.residue_bits += 1;
    try std.testing.expectError(
        error.InvalidVorbisQualityPcmPacketTrial,
        quality_controller.observePcmPacketTrial(
            Float,
            plan,
            malformed_trial,
        ),
    );
    var malformed_packet = trial;
    malformed_packet.packet.bit_count += 1;
    try std.testing.expectError(
        error.InvalidVorbisQualityPcmPacketTrial,
        quality_controller.observePcmPacketTrial(
            Float,
            plan,
            malformed_packet,
        ),
    );
    try std.testing.expectEqual(
        retained_quality,
        try quality_controller.quality(),
    );

    var ogg_storage: [2_048]u8 = undefined;
    var writer = StreamWriter.init(&ogg_storage, 0x74726961);
    try writer.appendPacket(&.{1}, 0, true, false);
    const committed = try sequence.appendMemory(
        &writer,
        plan,
        trial.packet.bytes,
        trial.packet.bit_count,
    );
    try std.testing.expectEqualDeep(trial.commit, committed);
    try std.testing.expectEqual(@as(u64, 2), sequence.revision);
    const packet_after = packet;
    const retained_after = retained_floor_y;
    try std.testing.expectError(
        error.StaleVorbisPcmPacketPlan,
        encodeVorbisPcmPacketTrial(
            Float,
            &sequence,
            identification,
            setup,
            plan,
            analysis,
            &.{1},
            .{},
            &packet,
            scratch,
            storage,
        ),
    );
    try std.testing.expectEqualSlices(u8, &packet_after, &packet);
    try std.testing.expectEqualSlices(
        u32,
        &retained_after,
        &retained_floor_y,
    );
}

test "Vorbis PCM frame extraction pads boundaries transactionally" {
    try testVorbisPcmFrameExtraction(f32);
    try testVorbisPcmFrameExtraction(f64);
}

fn testVorbisPcmFrameExtraction(comptime Float: type) !void {
    var left: [100]Float = undefined;
    var right: [100]Float = undefined;
    for (&left, &right, 0..) |*left_value, *right_value, index| {
        const value: Float = @floatFromInt(index + 1);
        left_value.* = value;
        right_value.* = -value;
    }
    var left_output: [64]Float = undefined;
    var right_output: [64]Float = undefined;
    try extractVorbisPcmBlock(
        Float,
        &.{ &left, &right },
        -2,
        64,
        &.{ &left_output, &right_output },
    );
    try std.testing.expectEqual(@as(Float, 0), left_output[0]);
    try std.testing.expectEqual(@as(Float, 0), left_output[1]);
    for (left_output[2..], right_output[2..], 0..) |
        left_value,
        right_value,
        index,
    | {
        const expected: Float = @floatFromInt(index + 1);
        try std.testing.expectEqual(expected, left_value);
        try std.testing.expectEqual(-expected, right_value);
    }

    try extractVorbisPcmBlock(
        Float,
        &.{ &left, &right },
        90,
        64,
        &.{ &left_output, &right_output },
    );
    for (left_output[0..10], right_output[0..10], 0..) |
        left_value,
        right_value,
        index,
    | {
        const expected: Float = @floatFromInt(index + 91);
        try std.testing.expectEqual(expected, left_value);
        try std.testing.expectEqual(-expected, right_value);
    }
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 54),
        left_output[10..],
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 54),
        right_output[10..],
    );

    @memset(&left_output, 7);
    @memset(&right_output, 8);
    var invalid_right = right;
    invalid_right[99] = std.math.nan(Float);
    try std.testing.expectError(
        error.InvalidVorbisPcmSample,
        extractVorbisPcmBlock(
            Float,
            &.{ &left, &invalid_right },
            0,
            64,
            &.{ &left_output, &right_output },
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{7} ** 64),
        &left_output,
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{8} ** 64),
        &right_output,
    );
    try std.testing.expectError(
        error.OverlappingVorbisPcmBlockOutput,
        extractVorbisPcmBlock(
            Float,
            &.{&left},
            0,
            64,
            &.{left[0..64]},
        ),
    );
    var shared_output: [64]Float = undefined;
    try std.testing.expectError(
        error.OverlappingVorbisPcmBlockOutput,
        extractVorbisPcmBlock(
            Float,
            &.{ &left, &right },
            0,
            64,
            &.{ &shared_output, &shared_output },
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisPcmFrameRange,
        extractVorbisPcmBlock(
            Float,
            &.{&left},
            std.math.maxInt(i64),
            64,
            &.{&shared_output},
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockShape,
        extractVorbisPcmBlock(
            Float,
            &.{ &left, right[0..99] },
            0,
            64,
            &.{ &left_output, &right_output },
        ),
    );
}

test "Vorbis PCM block transforms commit channels transactionally" {
    try testVorbisPcmBlockTransform(f32);
    try testVorbisPcmBlockTransform(f64);
}

fn testVorbisPcmBlockTransform(comptime Float: type) !void {
    const Transform = VorbisPcmBlockTransform(Float, 2, 64, 256);
    var transform = Transform.init();
    const small_header = VorbisAudioPacketHeader{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = 64,
        .payload_bit_offset = 2,
    };
    try std.testing.expectEqual(
        @as(usize, 64),
        try Transform.requiredScratch(small_header),
    );
    var left: [64]Float = undefined;
    var right: [64]Float = undefined;
    for (&left, &right, 0..) |*left_value, *right_value, index| {
        const position: Float = @floatFromInt(index);
        left_value.* = @sin(position * 0.17);
        right_value.* = @cos(position * 0.11);
    }
    var left_output = [_]Float{99} ** 32;
    var right_output = [_]Float{99} ** 32;
    var scratch: [64]Float = undefined;
    try transform.process(
        small_header,
        &.{ &left, &right },
        &.{ &left_output, &right_output },
        &scratch,
    );

    const windows = VorbisWindowPlan(Float, 64, 256).init();
    const window = try windows.get(small_header);
    var reference = VorbisForwardMdct(Float, 64).init();
    var expected_left: [32]Float = undefined;
    var expected_right: [32]Float = undefined;
    try reference.processWindowed(&left, window, &expected_left);
    try reference.processWindowed(&right, window, &expected_right);
    try std.testing.expectEqualSlices(
        Float,
        &expected_left,
        &left_output,
    );
    try std.testing.expectEqualSlices(
        Float,
        &expected_right,
        &right_output,
    );

    var preserved_left = [_]Float{ 7, 7, 7, 7 } ** 8;
    var preserved_right = [_]Float{ 8, 8, 8, 8 } ** 8;
    var invalid_right = right;
    invalid_right[63] = std.math.nan(Float);
    try std.testing.expectError(
        error.InvalidVorbisPcmSample,
        transform.process(
            small_header,
            &.{ &left, &invalid_right },
            &.{ &preserved_left, &preserved_right },
            &scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{ 7, 7, 7, 7 } ** 8),
        &preserved_left,
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{ 8, 8, 8, 8 } ** 8),
        &preserved_right,
    );
    try std.testing.expectError(
        error.VorbisPcmBlockScratchTooSmall,
        transform.process(
            small_header,
            &.{ &left, &right },
            &.{ &preserved_left, &preserved_right },
            scratch[0..63],
        ),
    );

    var alias_storage: [64]Float = undefined;
    try std.testing.expectError(
        error.OverlappingVorbisPcmBlockScratch,
        transform.process(
            small_header,
            &.{ &left, &right },
            &.{ alias_storage[0..32], &preserved_right },
            &alias_storage,
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisPcmBlockScratch,
        transform.process(
            small_header,
            &.{ &left, &right },
            &.{ &preserved_left, &preserved_right },
            left[0..],
        ),
    );
    var shared_output: [32]Float = undefined;
    try std.testing.expectError(
        error.OverlappingVorbisPcmBlockOutput,
        transform.process(
            small_header,
            &.{ &left, &right },
            &.{ &shared_output, &shared_output },
            &scratch,
        ),
    );

    const InPlaceTransform =
        VorbisPcmBlockTransform(Float, 1, 64, 256);
    var in_place_transform = InPlaceTransform.init();
    var in_place = left;
    var in_place_scratch: [32]Float = undefined;
    try in_place_transform.process(
        small_header,
        &.{&in_place},
        &.{in_place[0..32]},
        &in_place_scratch,
    );
    try std.testing.expectEqualSlices(
        Float,
        &expected_left,
        in_place[0..32],
    );

    const large_header = VorbisAudioPacketHeader{
        .mode_number = 1,
        .large_block = true,
        .previous_window_flag = false,
        .next_window_flag = true,
        .block_size = 256,
        .payload_bit_offset = 4,
    };
    try std.testing.expectEqual(
        @as(usize, 256),
        try Transform.requiredScratch(large_header),
    );
    var large_left: [256]Float = undefined;
    var large_right: [256]Float = undefined;
    for (
        &large_left,
        &large_right,
        0..,
    ) |*left_value, *right_value, index| {
        const position: Float = @floatFromInt(index);
        left_value.* = @sin(position * 0.037);
        right_value.* = @cos(position * 0.061);
    }
    var large_left_output: [128]Float = undefined;
    var large_right_output: [128]Float = undefined;
    var large_scratch: [256]Float = undefined;
    try transform.process(
        large_header,
        &.{ &large_left, &large_right },
        &.{ &large_left_output, &large_right_output },
        &large_scratch,
    );
    const large_window = try windows.get(large_header);
    var large_reference = VorbisForwardMdct(Float, 256).init();
    var expected_large_left: [128]Float = undefined;
    var expected_large_right: [128]Float = undefined;
    try large_reference.processWindowed(
        &large_left,
        large_window,
        &expected_large_left,
    );
    try large_reference.processWindowed(
        &large_right,
        large_window,
        &expected_large_right,
    );
    try std.testing.expectEqualSlices(
        Float,
        &expected_large_left,
        &large_left_output,
    );
    try std.testing.expectEqualSlices(
        Float,
        &expected_large_right,
        &large_right_output,
    );
    var invalid_header = large_header;
    invalid_header.next_window_flag = null;
    try std.testing.expectError(
        error.InvalidVorbisWindowState,
        Transform.requiredScratch(invalid_header),
    );
}

test "Vorbis PCM frame analysis composes extraction transform and masking" {
    try testVorbisPcmFrameAnalysis(f32);
    try testVorbisPcmFrameAnalysis(f64);
}

fn testVorbisPcmFrameAnalysis(comptime Float: type) !void {
    const Analyzer = VorbisPcmFrameAnalyzer(Float, 2, 64, 256);
    var analyzer = Analyzer.init();
    const frame = VorbisPcmFramePlan{
        .packet_index = 7,
        .header = .{
            .mode_number = 0,
            .large_block = false,
            .previous_window_flag = null,
            .next_window_flag = null,
            .block_size = 64,
            .payload_bit_offset = 2,
        },
        .source_start = -16,
        .pcm_advance = 32,
        .next_center = 32,
    };
    try std.testing.expectEqual(
        VorbisPcmFrameAnalysisStorageRequirements{
            .pcm_values = 128,
            .transform_values = 64,
            .spectrum_values = 64,
            .analyses = 2,
            .floor_values = 64,
            .threshold_values = 64,
        },
        try Analyzer.requiredStorage(frame.header),
    );
    const large_header = VorbisAudioPacketHeader{
        .mode_number = 1,
        .large_block = true,
        .previous_window_flag = false,
        .next_window_flag = true,
        .block_size = 256,
        .payload_bit_offset = 4,
    };
    try std.testing.expectEqual(
        VorbisPcmFrameAnalysisStorageRequirements{
            .pcm_values = 512,
            .transform_values = 256,
            .spectrum_values = 256,
            .analyses = 2,
            .floor_values = 256,
            .threshold_values = 256,
        },
        try Analyzer.requiredStorage(large_header),
    );

    var left: [64]Float = undefined;
    for (&left, 0..) |*sample, index| {
        sample.* = @sin(@as(Float, @floatFromInt(index)) * 0.17);
    }
    const right = [_]Float{0} ** 64;
    const inputs = [_][]const Float{ &left, &right };
    var pcm_scratch: [128]Float = undefined;
    var transform_scratch: [64]Float = undefined;
    var spectrum_scratch: [64]Float = undefined;
    var floor_scratch: [64]Float = undefined;
    var threshold_scratch: [64]Float = undefined;
    const sentinel_analysis = VorbisPsychoacousticAnalysis{
        .silent = false,
        .active_band_count = 81,
        .peak = 82,
        .rms = 83,
        .spectral_flatness = 84,
        .tonality = 85,
        .masking_relaxation_db = 86,
    };
    var retained_spectra = [_]Float{91} ** 65;
    var retained_analyses =
        [_]VorbisPsychoacousticAnalysis{sentinel_analysis} ** 3;
    var retained_floor = [_]Float{92} ** 65;
    var retained_thresholds = [_]Float{93} ** 65;
    const plan = try analyzer.analyze(
        &inputs,
        frame,
        .{ .absolute_threshold = 0.000_000_001 },
        48_000,
        .{
            .pcm = &pcm_scratch,
            .transform = &transform_scratch,
            .spectra = &spectrum_scratch,
            .floor_targets = &floor_scratch,
            .noise_thresholds = &threshold_scratch,
        },
        .{
            .spectra = &retained_spectra,
            .analyses = &retained_analyses,
            .floor_targets = &retained_floor,
            .noise_thresholds = &retained_thresholds,
        },
    );
    try std.testing.expectEqual(frame, plan.frame);
    try std.testing.expectEqual(@as(usize, 32), plan.coefficient_count);
    try std.testing.expectEqual(@as(usize, 64), plan.spectra.len);
    try std.testing.expectEqual(@as(usize, 2), plan.analyses.len);
    try std.testing.expectEqual(
        @intFromPtr(retained_spectra[0..64].ptr),
        @intFromPtr(plan.spectra.ptr),
    );
    try std.testing.expectEqual(
        @intFromPtr(retained_floor[0..64].ptr),
        @intFromPtr(plan.floor_targets.ptr),
    );
    try std.testing.expect(!plan.analyses[0].silent);
    try std.testing.expect(plan.analyses[1].silent);
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 32),
        plan.spectra[32..],
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 32),
        plan.floor_targets[32..],
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 32),
        plan.noise_thresholds[32..],
    );
    var expected_pcm_left: [64]Float = undefined;
    var expected_pcm_right: [64]Float = undefined;
    try extractVorbisPcmBlock(
        Float,
        &inputs,
        frame.source_start,
        frame.header.block_size,
        &.{ &expected_pcm_left, &expected_pcm_right },
    );
    var reference_transform =
        VorbisPcmBlockTransform(Float, 2, 64, 256).init();
    var expected_left: [32]Float = undefined;
    var expected_right: [32]Float = undefined;
    var reference_scratch: [64]Float = undefined;
    try reference_transform.process(
        frame.header,
        &.{ &expected_pcm_left, &expected_pcm_right },
        &.{ &expected_left, &expected_right },
        &reference_scratch,
    );
    try std.testing.expectEqualSlices(
        Float,
        &expected_left,
        plan.spectra[0..32],
    );
    try std.testing.expectEqualSlices(
        Float,
        &expected_right,
        plan.spectra[32..64],
    );
    try std.testing.expectEqual(@as(Float, 91), retained_spectra[64]);
    try std.testing.expectEqual(sentinel_analysis, retained_analyses[2]);
    try std.testing.expectEqual(@as(Float, 92), retained_floor[64]);
    try std.testing.expectEqual(
        @as(Float, 93),
        retained_thresholds[64],
    );

    const preserved_spectra = retained_spectra;
    const preserved_analyses = retained_analyses;
    const preserved_floor = retained_floor;
    const preserved_thresholds = retained_thresholds;
    var invalid_right = right;
    invalid_right[63] = std.math.nan(Float);
    try std.testing.expectError(
        error.InvalidVorbisPcmSample,
        analyzer.analyze(
            &.{ &left, &invalid_right },
            frame,
            .{},
            48_000,
            .{
                .pcm = &pcm_scratch,
                .transform = &transform_scratch,
                .spectra = &spectrum_scratch,
                .floor_targets = &floor_scratch,
                .noise_thresholds = &threshold_scratch,
            },
            .{
                .spectra = &retained_spectra,
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_spectra,
        &retained_spectra,
    );
    try std.testing.expectEqualSlices(
        VorbisPsychoacousticAnalysis,
        &preserved_analyses,
        &retained_analyses,
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_floor,
        &retained_floor,
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_thresholds,
        &retained_thresholds,
    );
    try std.testing.expectError(
        error.InvalidVorbisPsychoacousticConfig,
        analyzer.analyze(
            &inputs,
            frame,
            .{ .quality = 1.1 },
            48_000,
            .{
                .pcm = &pcm_scratch,
                .transform = &transform_scratch,
                .spectra = &spectrum_scratch,
                .floor_targets = &floor_scratch,
                .noise_thresholds = &threshold_scratch,
            },
            .{
                .spectra = &retained_spectra,
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_spectra,
        &retained_spectra,
    );
    try std.testing.expectError(
        error.VorbisPcmFrameAnalysisScratchTooSmall,
        analyzer.analyze(
            &inputs,
            frame,
            .{},
            48_000,
            .{
                .pcm = pcm_scratch[0..127],
                .transform = &transform_scratch,
                .spectra = &spectrum_scratch,
                .floor_targets = &floor_scratch,
                .noise_thresholds = &threshold_scratch,
            },
            .{
                .spectra = &retained_spectra,
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectError(
        error.VorbisPcmFrameAnalysisStorageTooSmall,
        analyzer.analyze(
            &inputs,
            frame,
            .{},
            48_000,
            .{
                .pcm = &pcm_scratch,
                .transform = &transform_scratch,
                .spectra = &spectrum_scratch,
                .floor_targets = &floor_scratch,
                .noise_thresholds = &threshold_scratch,
            },
            .{
                .spectra = retained_spectra[0..63],
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisPcmFrameAnalysisStorage,
        analyzer.analyze(
            &inputs,
            frame,
            .{},
            48_000,
            .{
                .pcm = &pcm_scratch,
                .transform = pcm_scratch[0..64],
                .spectra = &spectrum_scratch,
                .floor_targets = &floor_scratch,
                .noise_thresholds = &threshold_scratch,
            },
            .{
                .spectra = &retained_spectra,
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );

    var aliased_spectra = [_]Float{0} ** 65;
    aliased_spectra[17] = 1;
    const aliased_inputs = [_][]const Float{
        aliased_spectra[0..64],
        &right,
    };
    try std.testing.expectError(
        error.OverlappingVorbisPcmFrameAnalysisStorage,
        analyzer.analyze(
            &aliased_inputs,
            frame,
            .{},
            48_000,
            .{
                .pcm = &pcm_scratch,
                .transform = &transform_scratch,
                .spectra = &spectrum_scratch,
                .floor_targets = &floor_scratch,
                .noise_thresholds = &threshold_scratch,
            },
            .{
                .spectra = &aliased_spectra,
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    var invalid_header = frame.header;
    invalid_header.block_size = 256;
    var invalid_frame = frame;
    invalid_frame.header = invalid_header;
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockShape,
        Analyzer.requiredStorage(invalid_frame.header),
    );
}

test "Vorbis audio packet headers select retained modes and windows" {
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 256,
        .large_block_size = 2048,
    };

    var large_packet_storage: [128]u8 = undefined;
    const large_setup_packet = makeTestVorbisSetup(
        &large_packet_storage,
        .unordered,
        true,
        false,
    );
    var large_codebooks: [1]VorbisCodebook = undefined;
    var large_entries: [2]VorbisCodebookEntry = undefined;
    var large_nodes: [1]VorbisHuffmanNode = undefined;
    var large_multiplicands: [2]u32 = undefined;
    var large_floors: [1]VorbisFloor = undefined;
    var large_residues: [1]VorbisResidue = undefined;
    var large_mappings: [1]VorbisMapping = undefined;
    var large_modes: [1]VorbisMode = undefined;
    const large_setup = try parseVorbisSetup(
        large_setup_packet.bytes,
        2,
        .{
            .codebooks = &large_codebooks,
            .codebook_entries = &large_entries,
            .huffman_nodes = &large_nodes,
            .codebook_multiplicands = &large_multiplicands,
            .floors = &large_floors,
            .residues = &large_residues,
            .mappings = &large_mappings,
            .modes = &large_modes,
        },
    );
    const large_header = try parseVorbisAudioPacketHeader(
        &.{0b00000110},
        identification,
        large_setup,
    );
    try std.testing.expect(large_header.large_block);
    try std.testing.expectEqual(@as(?bool, true), large_header.previous_window_flag);
    try std.testing.expectEqual(@as(?bool, true), large_header.next_window_flag);
    try std.testing.expectEqual(@as(u16, 2048), large_header.block_size);
    try std.testing.expectEqual(@as(usize, 3), large_header.payload_bit_offset);

    var small_packet_storage: [128]u8 = undefined;
    const small_setup_packet = makeTestVorbisSetup(
        &small_packet_storage,
        .unordered,
        false,
        false,
    );
    var small_codebooks: [1]VorbisCodebook = undefined;
    var small_entries: [2]VorbisCodebookEntry = undefined;
    var small_nodes: [1]VorbisHuffmanNode = undefined;
    var small_multiplicands: [2]u32 = undefined;
    var small_floors: [1]VorbisFloor = undefined;
    var small_residues: [1]VorbisResidue = undefined;
    var small_mappings: [1]VorbisMapping = undefined;
    var small_modes: [1]VorbisMode = undefined;
    const small_setup = try parseVorbisSetup(
        small_setup_packet.bytes,
        1,
        .{
            .codebooks = &small_codebooks,
            .codebook_entries = &small_entries,
            .huffman_nodes = &small_nodes,
            .codebook_multiplicands = &small_multiplicands,
            .floors = &small_floors,
            .residues = &small_residues,
            .mappings = &small_mappings,
            .modes = &small_modes,
        },
    );
    const small_header = try parseVorbisAudioPacketHeader(
        &.{0},
        identification,
        small_setup,
    );
    try std.testing.expect(!small_header.large_block);
    try std.testing.expectEqual(@as(u16, 256), small_header.block_size);
    try std.testing.expectEqual(@as(usize, 1), small_header.payload_bit_offset);
    try std.testing.expectError(
        error.InvalidVorbisAudioPacketType,
        parseVorbisAudioPacketHeader(&.{1}, identification, small_setup),
    );
    try std.testing.expectError(
        error.TruncatedVorbisAudioPacket,
        parseVorbisAudioPacketHeader(&.{}, identification, small_setup),
    );

    const modes = [_]VorbisMode{
        .{ .large_block = false, .mapping = 0 },
        .{ .large_block = false, .mapping = 0 },
        .{ .large_block = true, .mapping = 0 },
    };
    const multi_mode_setup = VorbisSetup{
        .summary = .{
            .codebook_count = 0,
            .codebook_entry_count = 0,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 3,
            .maximum_codebook_dimensions = 0,
            .maximum_codebook_entries = 0,
        },
        .codebooks = &.{},
        .codebook_entries = &.{},
        .huffman_nodes = &.{},
        .codebook_multiplicands = &.{},
        .floors = &.{},
        .residues = &.{},
        .mappings = &.{},
        .modes = &modes,
    };
    const selected = try parseVorbisAudioPacketHeader(
        &.{0b00001100},
        identification,
        multi_mode_setup,
    );
    try std.testing.expectEqual(@as(u8, 2), selected.mode_number);
    try std.testing.expectEqual(@as(?bool, true), selected.previous_window_flag);
    try std.testing.expectEqual(@as(?bool, false), selected.next_window_flag);
    try std.testing.expectEqual(@as(usize, 5), selected.payload_bit_offset);

    var small_window: [256]f64 = undefined;
    try synthesizeVorbisWindow(
        f64,
        identification,
        small_header,
        &small_window,
    );
    for (0..small_window.len / 2) |index| {
        try std.testing.expectApproxEqAbs(
            @as(f64, 1),
            small_window[index] * small_window[index] +
                small_window[small_window.len / 2 + index] *
                    small_window[small_window.len / 2 + index],
            1e-14,
        );
    }
    try std.testing.expect(small_window[0] > 0);
    try std.testing.expect(small_window[0] < small_window[1]);

    var transition_window: [2048]f32 = undefined;
    try synthesizeVorbisWindow(
        f32,
        identification,
        selected,
        &transition_window,
    );
    try std.testing.expect(transition_window[0] > 0);
    try std.testing.expectEqual(@as(f32, 1), transition_window[1024]);
    try std.testing.expect(transition_window[1599] > 0);
    try std.testing.expectEqual(@as(f32, 0), transition_window[1600]);
    try std.testing.expectEqual(@as(f32, 0), transition_window[2047]);
    const window_plan = VorbisWindowPlan(f32, 256, 2048).init();
    try std.testing.expectEqualSlices(
        f32,
        &transition_window,
        try window_plan.get(selected),
    );
    var small_window_f32: [256]f32 = undefined;
    try synthesizeVorbisWindow(
        f32,
        identification,
        small_header,
        &small_window_f32,
    );
    try std.testing.expectEqualSlices(
        f32,
        &small_window_f32,
        try window_plan.get(small_header),
    );

    var preserved_window = [_]f32{99} ** 256;
    var invalid_window_header = small_header;
    invalid_window_header.previous_window_flag = false;
    try std.testing.expectError(
        error.InvalidVorbisWindowState,
        synthesizeVorbisWindow(
            f32,
            identification,
            invalid_window_header,
            &preserved_window,
        ),
    );
    try std.testing.expectEqual(@as(f32, 99), preserved_window[0]);
    try std.testing.expectError(
        error.InvalidVorbisAudioPacketMode,
        parseVorbisAudioPacketHeader(
            &.{0b00000110},
            identification,
            multi_mode_setup,
        ),
    );
}

test "Vorbis audio packet decoder composes floor residue coupling and MDCT" {
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    const entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 0, .length = 1 },
    };
    const codebooks = [_]VorbisCodebook{
        .{
            .dimensions = 1,
            .entries = 1,
            .entry_offset = 0,
            .active_entry_count = 1,
            .lookup_type = 0,
        },
        .{
            .dimensions = 1,
            .entries = 1,
            .entry_offset = 1,
            .active_entry_count = 1,
            .lookup_type = 2,
            .delta_value = 1,
            .multiplicand_offset = 0,
            .multiplicand_count = 1,
        },
    };
    var x_list = [_]u16{0} ** 65;
    x_list[1] = 32;
    const floors = [_]VorbisFloor{.{
        .one = .{
            .partition_count = 0,
            .partition_classes = [_]u4{0} ** 31,
            .class_count = 0,
            .classes = [_]VorbisFloorOneClass{.{
                .dimensions = 0,
                .subclass_bits = 0,
                .masterbook = -1,
                .subclass_books = [_]i16{-1} ** 8,
            }} ** 16,
            .multiplier = 1,
            .range_bits = 5,
            .point_count = 2,
            .x_list = x_list,
        },
    }};
    var cascades = [_]u8{0} ** 64;
    cascades[0] = 1;
    var books = [_][8]i16{[_]i16{-1} ** 8} ** 64;
    books[0][0] = 1;
    const residues = [_]VorbisResidue{.{
        .kind = .two,
        .begin = 0,
        .end = 64,
        .partition_size = 1,
        .classification_count = 1,
        .classbook = 0,
        .cascades = cascades,
        .books = books,
    }};
    var coupling_steps = [_]VorbisCouplingStep{.{
        .magnitude = 0,
        .angle = 0,
    }} ** 256;
    coupling_steps[0] = .{ .magnitude = 0, .angle = 1 };
    const mappings = [_]VorbisMapping{.{
        .submap_count = 1,
        .coupling_step_count = 1,
        .coupling_steps = coupling_steps,
        .channel_mux = [_]u4{0} ** 255,
        .submaps = [_]VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    }};
    const modes = [_]VorbisMode{.{
        .large_block = false,
        .mapping = 0,
    }};
    const setup = VorbisSetup{
        .summary = .{
            .codebook_count = 2,
            .codebook_entry_count = 2,
            .huffman_node_count = 0,
            .codebook_multiplicand_count = 1,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 1,
            .maximum_codebook_entries = 1,
        },
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &.{},
        .codebook_multiplicands = &.{1},
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    };

    var packet_storage: [32]u8 = undefined;
    var packet_writer = TestVorbisBitWriter.init(&packet_storage);
    packet_writer.write(0, 1);
    packet_writer.write(1, 1);
    packet_writer.write(255, 8);
    packet_writer.write(255, 8);
    packet_writer.write(0, 1);
    for (0..64) |_| {
        packet_writer.write(0, 1);
        packet_writer.write(0, 1);
    }
    const packet =
        packet_storage[0 .. (packet_writer.bit_offset + 7) / 8];
    const header = try parseVorbisAudioPacketHeader(
        packet,
        identification,
        setup,
    );
    const requirements = try requiredVorbisAudioPacketScratch(
        identification,
        setup,
        header,
    );
    try std.testing.expectEqual(@as(usize, 64), requirements.spectrum_values);
    try std.testing.expectEqual(@as(usize, 128), requirements.time_values);
    try std.testing.expectEqual(@as(usize, 64), requirements.classification_bytes);

    var spectra: [64]f64 = undefined;
    var floor_curves: [64]f64 = undefined;
    var coupling: [64]f64 = undefined;
    var time: [128]f64 = undefined;
    var classifications: [64]u8 = undefined;
    var left = [_]f64{99} ** 64;
    var right = [_]f64{99} ** 64;
    const outputs = [_][]f64{ &left, &right };
    var decoder = VorbisAudioPacketDecoder(f64, 2, 64, 64).init();
    const result = try decoder.decode(
        packet,
        identification,
        setup,
        &outputs,
        .{
            .spectra = &spectra,
            .floor_curves = &floor_curves,
            .coupling = &coupling,
            .time = &time,
            .classifications = &classifications,
        },
    );
    try std.testing.expect(!result.truncated);
    try std.testing.expect(!result.floor_truncated);
    try std.testing.expect(!result.residue_truncated);
    try std.testing.expectEqual(packet_writer.bit_offset, result.decoded_bit_count);
    try std.testing.expectEqualSlices(f64, &([_]f64{0} ** 64), &right);

    var window: [64]f64 = undefined;
    try synthesizeVorbisWindow(f64, identification, header, &window);
    for (&left, window, 0..) |actual, window_value, sample_index| {
        var sum: f64 = 0;
        for (0..32) |coefficient_index| {
            const angle = std.math.pi / 32.0 *
                (@as(f64, @floatFromInt(sample_index)) + 16.5) *
                (@as(f64, @floatFromInt(coefficient_index)) + 0.5);
            sum += @cos(angle);
        }
        const expected = window_value * sum;
        try std.testing.expectApproxEqAbs(expected, actual, 1e-12);
    }

    @memset(&left, 99);
    @memset(&right, 99);
    const truncated = try decoder.decode(
        packet[0..6],
        identification,
        setup,
        &outputs,
        .{
            .spectra = &spectra,
            .floor_curves = &floor_curves,
            .coupling = &coupling,
            .time = &time,
            .classifications = &classifications,
        },
    );
    try std.testing.expect(truncated.truncated);
    try std.testing.expect(!truncated.floor_truncated);
    try std.testing.expect(truncated.residue_truncated);
    for (left) |sample| try std.testing.expect(std.math.isFinite(sample));
    for (right) |sample| try std.testing.expect(std.math.isFinite(sample));

    @memset(&left, 99);
    @memset(&right, 99);
    const truncated_floor = try decoder.decode(
        packet[0..2],
        identification,
        setup,
        &outputs,
        .{
            .spectra = &spectra,
            .floor_curves = &floor_curves,
            .coupling = &coupling,
            .time = &time,
            .classifications = &classifications,
        },
    );
    try std.testing.expect(truncated_floor.truncated);
    try std.testing.expect(truncated_floor.floor_truncated);
    try std.testing.expect(!truncated_floor.residue_truncated);
    try std.testing.expectEqualSlices(f64, &([_]f64{0} ** 64), &left);
    try std.testing.expectEqualSlices(f64, &([_]f64{0} ** 64), &right);

    @memset(&left, 99);
    @memset(&right, 99);
    try std.testing.expectError(
        error.VorbisAudioPacketScratchTooSmall,
        decoder.decode(
            packet,
            identification,
            setup,
            &outputs,
            .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = time[0..127],
                .classifications = &classifications,
            },
        ),
    );
    try std.testing.expectEqual(@as(f64, 99), left[0]);
    try std.testing.expectEqual(@as(f64, 99), right[0]);

    var invalid_mappings = mappings;
    invalid_mappings[0].coupling_steps[0].angle = 0;
    var invalid_setup = setup;
    invalid_setup.mappings = &invalid_mappings;
    try std.testing.expectError(
        error.InvalidVorbisMappingState,
        decoder.decode(
            packet,
            identification,
            invalid_setup,
            &outputs,
            .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
        ),
    );
    try std.testing.expectEqual(@as(f64, 99), left[0]);

    var stream = VorbisPcmStreamDecoder(f64, 2, 64, 64).init();
    var stream_windowed: [128]f64 = undefined;
    var first_empty_left: [0]f64 = .{};
    var first_empty_right: [0]f64 = .{};
    const first_empty_outputs =
        [_][]f64{ &first_empty_left, &first_empty_right };
    const first_stream_result = try stream.decode(
        .{
            .bytes = packet,
            .granule_position = unknown_granule,
            .beginning = false,
            .end = false,
        },
        identification,
        setup,
        &first_empty_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(@as(usize, 0), first_stream_result.sample_count);

    var stream_left = [_]f64{99} ** 32;
    var stream_right = [_]f64{99} ** 32;
    const stream_outputs = [_][]f64{ &stream_left, &stream_right };
    try std.testing.expectError(
        error.InvalidVorbisAudioPacketType,
        stream.decode(
            .{
                .bytes = &.{1},
                .granule_position = 32,
                .beginning = false,
                .end = false,
            },
            identification,
            setup,
            &stream_outputs,
            .{
                .packet = .{
                    .spectra = &spectra,
                    .floor_curves = &floor_curves,
                    .coupling = &coupling,
                    .time = &time,
                    .classifications = &classifications,
                },
                .windowed = &stream_windowed,
            },
        ),
    );
    try std.testing.expectEqual(@as(u64, 1), stream.audio_packet_count);
    try std.testing.expectEqual(@as(f64, 99), stream_left[0]);
    try std.testing.expectEqual(
        @as(usize, 64),
        stream.overlap.channels[0].previousBlockSize(),
    );
    const second_stream_result = try stream.decode(
        .{
            .bytes = packet,
            .granule_position = 32,
            .beginning = false,
            .end = false,
        },
        identification,
        setup,
        &stream_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(@as(usize, 32), second_stream_result.sample_count);
    try std.testing.expectEqual(@as(?i64, 0), second_stream_result.pcm_start);
    try std.testing.expectEqual(@as(?i64, 32), second_stream_result.pcm_end);
    for (stream_left) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
    }
    try std.testing.expectEqualSlices(
        f64,
        &([_]f64{0} ** 32),
        &stream_right,
    );

    const final_stream_result = try stream.decode(
        .{
            .bytes = packet,
            .granule_position = 60,
            .beginning = false,
            .end = true,
        },
        identification,
        setup,
        &stream_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(@as(usize, 28), final_stream_result.sample_count);
    try std.testing.expectEqual(@as(?i64, 32), final_stream_result.pcm_start);
    try std.testing.expectEqual(@as(?i64, 60), final_stream_result.pcm_end);
    try std.testing.expectError(
        error.VorbisPcmStreamAlreadyEnded,
        stream.decode(
            .{
                .bytes = packet,
                .granule_position = 92,
                .beginning = false,
                .end = true,
            },
            identification,
            setup,
            &stream_outputs,
            .{
                .packet = .{
                    .spectra = &spectra,
                    .floor_curves = &floor_curves,
                    .coupling = &coupling,
                    .time = &time,
                    .classifications = &classifications,
                },
                .windowed = &stream_windowed,
            },
        ),
    );
    stream.reset();
    try std.testing.expectEqual(@as(u64, 0), stream.audio_packet_count);

    var chained =
        VorbisChainedPcmStreamDecoder(f64, 2, 64, 64).init();
    try std.testing.expect(chained.valid());
    var corrupt_chained = chained;
    corrupt_chained.sample_rate = 48_000;
    const corrupt_chained_before = corrupt_chained;
    try std.testing.expect(!corrupt_chained.valid());
    try std.testing.expectError(
        error.InvalidVorbisChainedPcmStreamState,
        corrupt_chained.beginLogicalStream(identification),
    );
    try std.testing.expectEqualDeep(
        corrupt_chained_before,
        corrupt_chained,
    );
    try std.testing.expectError(
        error.VorbisLogicalStreamNotStarted,
        chained.decode(
            .{
                .bytes = packet,
                .granule_position = unknown_granule,
                .beginning = false,
                .end = false,
            },
            identification,
            setup,
            &first_empty_outputs,
            .{
                .packet = .{
                    .spectra = &spectra,
                    .floor_curves = &floor_curves,
                    .coupling = &coupling,
                    .time = &time,
                    .classifications = &classifications,
                },
                .windowed = &stream_windowed,
            },
        ),
    );
    try chained.beginLogicalStream(identification);
    try std.testing.expect(chained.valid());
    const chained_prime = try chained.decode(
        .{
            .bytes = packet,
            .granule_position = unknown_granule,
            .beginning = true,
            .end = false,
        },
        identification,
        setup,
        &first_empty_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expect(chained.valid());
    try std.testing.expectEqual(@as(u64, 0), chained_prime.global_pcm_start);
    try std.testing.expectEqual(@as(u64, 0), chained_prime.global_pcm_end);
    try std.testing.expectError(
        error.VorbisPreviousLogicalStreamNotEnded,
        chained.beginLogicalStream(identification),
    );
    try std.testing.expectError(
        error.InvalidVorbisAudioPacketType,
        chained.decode(
            .{
                .bytes = &.{1},
                .granule_position = 32,
                .beginning = false,
                .end = false,
            },
            identification,
            setup,
            &stream_outputs,
            .{
                .packet = .{
                    .spectra = &spectra,
                    .floor_curves = &floor_curves,
                    .coupling = &coupling,
                    .time = &time,
                    .classifications = &classifications,
                },
                .windowed = &stream_windowed,
            },
        ),
    );
    try std.testing.expectEqual(@as(u64, 0), chained.current_stream_pcm);
    var recovering = chained;
    const concealed =
        try recovering.concealMissingPacketUsingPreviousBlockSize(
            32,
            false,
            identification,
            &stream_outputs,
            &stream_windowed,
        );
    try std.testing.expectEqual(@as(u64, 0), concealed.global_pcm_start);
    try std.testing.expectEqual(@as(u64, 32), concealed.global_pcm_end);
    try std.testing.expectEqual(@as(u64, 1), concealed.stream.concealed_packet_count);
    try std.testing.expectEqual(@as(u64, 32), recovering.current_stream_pcm);
    try std.testing.expectEqual(@as(u64, 0), chained.current_stream_pcm);
    var following_recovery = chained;
    const fixed_following_header = VorbisAudioPacketHeader{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = 64,
        .payload_bit_offset = 1,
    };
    const following_concealed =
        try following_recovery.concealMissingPacketUsingFollowingHeader(
            fixed_following_header,
            32,
            false,
            identification,
            &stream_outputs,
            &stream_windowed,
        );
    try std.testing.expectEqual(
        @as(u16, 64),
        following_concealed.stream.block_size,
    );
    try std.testing.expectEqual(
        @as(u64, 32),
        following_concealed.global_pcm_end,
    );
    try std.testing.expectEqual(@as(u64, 0), chained.current_stream_pcm);
    const chained_middle = try chained.decode(
        .{
            .bytes = packet,
            .granule_position = 32,
            .beginning = false,
            .end = false,
        },
        identification,
        setup,
        &stream_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(@as(u64, 0), chained_middle.global_pcm_start);
    try std.testing.expectEqual(@as(u64, 32), chained_middle.global_pcm_end);
    const chained_end = try chained.decode(
        .{
            .bytes = packet,
            .granule_position = 60,
            .beginning = false,
            .end = true,
        },
        identification,
        setup,
        &stream_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(@as(u64, 32), chained_end.global_pcm_start);
    try std.testing.expectEqual(@as(u64, 60), chained_end.global_pcm_end);

    var changed_rate = identification;
    changed_rate.sample_rate += 1;
    try std.testing.expectError(
        error.VorbisChainedSampleRateChanged,
        chained.beginLogicalStream(changed_rate),
    );
    try chained.beginLogicalStream(identification);
    try std.testing.expectEqual(@as(u64, 1), chained.logical_stream_index);
    try std.testing.expectEqual(@as(u64, 60), chained.completed_pcm);
    const second_chain_prime = try chained.decode(
        .{
            .bytes = packet,
            .granule_position = unknown_granule,
            .beginning = true,
            .end = false,
        },
        identification,
        setup,
        &first_empty_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(
        @as(u64, 60),
        second_chain_prime.global_pcm_start,
    );
    const second_chain_end = try chained.decode(
        .{
            .bytes = packet,
            .granule_position = 32,
            .beginning = false,
            .end = true,
        },
        identification,
        setup,
        &stream_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(@as(u64, 60), second_chain_end.global_pcm_start);
    try std.testing.expectEqual(@as(u64, 92), second_chain_end.global_pcm_end);

    var changed_geometry = identification;
    changed_geometry.channel_count = 1;
    try std.testing.expectError(
        error.VorbisChainedStreamGeometryChanged,
        chained.beginLogicalStream(changed_geometry),
    );
    chained.current_stream_pcm = std.math.maxInt(u64) - 31;
    @memset(&stream_left, 99);
    try std.testing.expectError(
        error.InvalidVorbisChainedPcmStreamState,
        chained.decode(
            .{
                .bytes = packet,
                .granule_position = 64,
                .beginning = false,
                .end = true,
            },
            identification,
            setup,
            &stream_outputs,
            .{
                .packet = .{
                    .spectra = &spectra,
                    .floor_curves = &floor_curves,
                    .coupling = &coupling,
                    .time = &time,
                    .classifications = &classifications,
                },
                .windowed = &stream_windowed,
            },
        ),
    );
    try std.testing.expectEqual(@as(f64, 99), stream_left[0]);
    try std.testing.expectEqual(
        std.math.maxInt(u64) - 31,
        chained.current_stream_pcm,
    );
    chained.reset();
    try std.testing.expect(!chained.started);
    try std.testing.expectEqual(@as(?u32, null), chained.sample_rate);
}

test "Vorbis inverse MDCT matches its defining transform" {
    const block_size = 64;
    const coefficient_count = block_size / 2;
    var coefficients: [coefficient_count]f64 = undefined;
    for (&coefficients, 0..) |*coefficient, index| {
        coefficient.* =
            @sin(@as(f64, @floatFromInt(index + 1)) * 0.37) *
            (1.0 + @as(f64, @floatFromInt(index % 5)));
    }
    var expected: [block_size]f64 = undefined;
    for (&expected, 0..) |*sample, sample_index| {
        var sum: f64 = 0;
        for (coefficients, 0..) |coefficient, coefficient_index| {
            const angle = std.math.pi /
                @as(f64, @floatFromInt(coefficient_count)) *
                (@as(f64, @floatFromInt(sample_index)) + 0.5 +
                    @as(f64, @floatFromInt(coefficient_count)) / 2.0) *
                (@as(f64, @floatFromInt(coefficient_index)) + 0.5);
            sum += coefficient * @cos(angle);
        }
        sample.* = sum;
    }

    var plan = VorbisInverseMdct(f64, block_size).init();
    var actual: [block_size]f64 = undefined;
    try plan.process(&coefficients, &actual);
    for (actual, expected) |actual_sample, expected_sample| {
        try std.testing.expectApproxEqAbs(
            expected_sample,
            actual_sample,
            3e-11,
        );
    }

    @memset(&coefficients, 0);
    coefficients[0] = 1;
    try plan.process(&coefficients, &actual);
    for (actual, 0..) |actual_sample, sample_index| {
        const expected_sample = @cos(std.math.pi /
            @as(f64, @floatFromInt(coefficient_count)) *
            (@as(f64, @floatFromInt(sample_index)) + 0.5 +
                @as(f64, @floatFromInt(coefficient_count)) / 2.0) *
            0.5);
        try std.testing.expectApproxEqAbs(
            expected_sample,
            actual_sample,
            1e-12,
        );
    }

    var random_state = std.Random.DefaultPrng.init(0x564F_5242_4953_4D44);
    const random = random_state.random();
    for (0..16) |_| {
        for (&coefficients) |*coefficient| {
            coefficient.* = random.float(f64) * 200.0 - 100.0;
        }
        for (&expected, 0..) |*sample, sample_index| {
            var sum: f64 = 0;
            for (coefficients, 0..) |coefficient, coefficient_index| {
                const angle = std.math.pi /
                    @as(f64, @floatFromInt(coefficient_count)) *
                    (@as(f64, @floatFromInt(sample_index)) + 0.5 +
                        @as(f64, @floatFromInt(coefficient_count)) / 2.0) *
                    (@as(f64, @floatFromInt(coefficient_index)) + 0.5);
                sum += coefficient * @cos(angle);
            }
            sample.* = sum;
        }
        try plan.process(&coefficients, &actual);
        for (actual, expected) |actual_sample, expected_sample| {
            try std.testing.expectApproxEqAbs(
                expected_sample,
                actual_sample,
                2e-11,
            );
        }
    }

    var aliased: [block_size]f64 = undefined;
    @memcpy(aliased[0..coefficient_count], &coefficients);
    try plan.process(
        aliased[0..coefficient_count],
        &aliased,
    );
    for (aliased, expected) |actual_sample, expected_sample| {
        try std.testing.expectApproxEqAbs(
            expected_sample,
            actual_sample,
            3e-11,
        );
    }

    const window_plan = VorbisWindowPlan(f64, block_size, block_size).init();
    const window = try window_plan.get(.{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = block_size,
        .payload_bit_offset = 0,
    });
    try plan.processWindowed(&coefficients, window, &actual);
    for (actual, expected, window) |
        actual_sample,
        expected_sample,
        window_value,
    | {
        try std.testing.expectApproxEqAbs(
            expected_sample * window_value,
            actual_sample,
            3e-11,
        );
    }

    var invalid_coefficients = coefficients;
    invalid_coefficients[3] = std.math.nan(f64);
    var preserved = [_]f64{99} ** block_size;
    try std.testing.expectError(
        error.InvalidVorbisMdctInput,
        plan.process(&invalid_coefficients, &preserved),
    );
    try std.testing.expectEqual(@as(f64, 99), preserved[0]);
    try std.testing.expectError(
        error.InvalidVorbisMdctShape,
        plan.process(coefficients[0 .. coefficient_count - 1], &preserved),
    );
    try std.testing.expectEqual(@as(f64, 99), preserved[0]);

    var f32_plan = VorbisInverseMdct(f32, block_size).init();
    var f32_coefficients: [coefficient_count]f32 = undefined;
    for (&f32_coefficients, coefficients) |*target, source| {
        target.* = @floatCast(source);
    }
    var f32_output: [block_size]f32 = undefined;
    try f32_plan.process(&f32_coefficients, &f32_output);
    for (f32_output, expected) |actual_sample, expected_sample| {
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(expected_sample)),
            actual_sample,
            2e-3,
        );
    }

    comptime {
        _ = VorbisInverseMdct(f32, 8192);
    }
}

test "Vorbis forward MDCT matches its defining transform" {
    const block_size = 64;
    const coefficient_count = block_size / 2;
    var input: [block_size]f64 = undefined;
    for (&input, 0..) |*sample, index| {
        sample.* =
            @sin(@as(f64, @floatFromInt(index + 1)) * 0.23) *
            (1.0 + @as(f64, @floatFromInt(index % 7)));
    }
    var expected: [coefficient_count]f64 = undefined;
    for (&expected, 0..) |*coefficient, coefficient_index| {
        var sum: f64 = 0;
        for (input, 0..) |sample, sample_index| {
            const angle = std.math.pi /
                @as(f64, @floatFromInt(coefficient_count)) *
                (@as(f64, @floatFromInt(sample_index)) + 0.5 +
                    @as(f64, @floatFromInt(coefficient_count)) / 2.0) *
                (@as(f64, @floatFromInt(coefficient_index)) + 0.5);
            sum += sample * @cos(angle);
        }
        coefficient.* = 4.0 /
            @as(f64, @floatFromInt(block_size)) * sum;
    }

    var plan = VorbisForwardMdct(f64, block_size).init();
    var actual: [coefficient_count]f64 = undefined;
    try plan.process(&input, &actual);
    for (actual, expected) |actual_value, expected_value| {
        try std.testing.expectApproxEqAbs(
            expected_value,
            actual_value,
            2e-12,
        );
    }

    var random_state = std.Random.DefaultPrng.init(0x464F_5257_4D44_4354);
    const random = random_state.random();
    for (0..16) |_| {
        for (&input) |*sample|
            sample.* = random.float(f64) * 200.0 - 100.0;
        for (&expected, 0..) |*coefficient, coefficient_index| {
            var sum: f64 = 0;
            for (input, 0..) |sample, sample_index| {
                const angle = std.math.pi /
                    @as(f64, @floatFromInt(coefficient_count)) *
                    (@as(f64, @floatFromInt(sample_index)) + 0.5 +
                        @as(f64, @floatFromInt(coefficient_count)) / 2.0) *
                    (@as(f64, @floatFromInt(coefficient_index)) + 0.5);
                sum += sample * @cos(angle);
            }
            coefficient.* = 4.0 /
                @as(f64, @floatFromInt(block_size)) * sum;
        }
        try plan.process(&input, &actual);
        for (actual, expected) |actual_value, expected_value| {
            try std.testing.expectApproxEqAbs(
                expected_value,
                actual_value,
                2e-10,
            );
        }
    }

    var source_coefficients: [coefficient_count]f64 = undefined;
    for (&source_coefficients) |*coefficient|
        coefficient.* = random.float(f64) * 20.0 - 10.0;
    var inverse = VorbisInverseMdct(f64, block_size).init();
    var synthesized: [block_size]f64 = undefined;
    try inverse.process(&source_coefficients, &synthesized);
    try plan.process(&synthesized, &actual);
    for (actual, source_coefficients) |actual_value, expected_value| {
        try std.testing.expectApproxEqAbs(
            2.0 * expected_value,
            actual_value,
            2e-11,
        );
    }

    var aliased = input;
    try plan.process(&aliased, aliased[0..coefficient_count]);
    for (
        aliased[0..coefficient_count],
        expected,
    ) |actual_value, expected_value| {
        try std.testing.expectApproxEqAbs(
            expected_value,
            actual_value,
            2e-10,
        );
    }

    const window_plan = VorbisWindowPlan(
        f64,
        block_size,
        block_size,
    ).init();
    const window = try window_plan.get(.{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = block_size,
        .payload_bit_offset = 0,
    });
    var windowed_expected: [coefficient_count]f64 = undefined;
    for (
        &windowed_expected,
        0..,
    ) |*coefficient, coefficient_index| {
        var sum: f64 = 0;
        for (input, window, 0..) |sample, gain, sample_index| {
            const angle = std.math.pi /
                @as(f64, @floatFromInt(coefficient_count)) *
                (@as(f64, @floatFromInt(sample_index)) + 0.5 +
                    @as(f64, @floatFromInt(coefficient_count)) / 2.0) *
                (@as(f64, @floatFromInt(coefficient_index)) + 0.5);
            sum += sample * gain * @cos(angle);
        }
        coefficient.* = 4.0 /
            @as(f64, @floatFromInt(block_size)) * sum;
    }
    try plan.processWindowed(&input, window, &actual);
    for (actual, windowed_expected) |actual_value, expected_value| {
        try std.testing.expectApproxEqAbs(
            expected_value,
            actual_value,
            2e-10,
        );
    }

    var preserved = [_]f64{99} ** coefficient_count;
    var invalid_input = input;
    invalid_input[7] = std.math.nan(f64);
    try std.testing.expectError(
        error.InvalidVorbisMdctInput,
        plan.process(&invalid_input, &preserved),
    );
    try std.testing.expectEqual(@as(f64, 99), preserved[0]);
    try std.testing.expectError(
        error.InvalidVorbisMdctShape,
        plan.process(input[0 .. block_size - 1], &preserved),
    );
    try std.testing.expectEqual(@as(f64, 99), preserved[0]);

    var f32_plan = VorbisForwardMdct(f32, block_size).init();
    var f32_input: [block_size]f32 = undefined;
    for (&f32_input, input) |*target, source|
        target.* = @floatCast(source);
    var f32_output: [coefficient_count]f32 = undefined;
    try f32_plan.process(&f32_input, &f32_output);
    for (f32_output, expected) |actual_value, expected_value| {
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(expected_value)),
            actual_value,
            2e-3,
        );
    }

    comptime {
        _ = VorbisForwardMdct(f32, 8192);
    }
}

test "Vorbis floor application is transactional" {
    var spectrum = [_]f32{ 1, -2, 3, -4 };
    try applyVorbisFloor(
        f32,
        &spectrum,
        &.{ 0.5, 2, 0.25, 0 },
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.5, -4, 0.75, 0 },
        &spectrum,
    );

    var preserved = [_]f64{ 1, 2 };
    try std.testing.expectError(
        error.InvalidVorbisSpectrumValue,
        applyVorbisFloor(
            f64,
            &preserved,
            &.{ std.math.floatMax(f64), std.math.nan(f64) },
        ),
    );
    try std.testing.expectEqualSlices(f64, &.{ 1, 2 }, &preserved);
    try std.testing.expectError(
        error.InvalidVorbisSpectrumShape,
        applyVorbisFloor(f64, &preserved, &.{1}),
    );
    try std.testing.expectEqualSlices(f64, &.{ 1, 2 }, &preserved);
}

test "Vorbis overlap-add aligns every block-size transition" {
    var state = VorbisOverlapAdd(f64, 256){};
    var output = [_]f64{99} ** 80;
    const first = [_]f64{1} ** 64;
    try std.testing.expectEqual(
        @as(usize, 0),
        try state.push(&first, &output),
    );
    try std.testing.expect(state.primed());
    try std.testing.expectEqual(@as(usize, 64), state.previousBlockSize());
    try std.testing.expectEqual(@as(f64, 99), output[0]);

    const second = [_]f64{2} ** 64;
    try std.testing.expectEqual(
        @as(usize, 32),
        try state.push(&second, &output),
    );
    try std.testing.expectEqualSlices(f64, &([_]f64{3} ** 32), output[0..32]);
    try std.testing.expectEqual(@as(f64, 99), output[32]);

    const large = [_]f64{4} ** 256;
    @memset(&output, 99);
    try std.testing.expectEqual(
        @as(usize, 80),
        try state.push(&large, &output),
    );
    try std.testing.expectEqualSlices(f64, &([_]f64{6} ** 32), output[0..32]);
    try std.testing.expectEqualSlices(f64, &([_]f64{4} ** 48), output[32..80]);

    const final_short = [_]f64{8} ** 64;
    var short_output = [_]f64{99} ** 79;
    try std.testing.expectError(
        error.VorbisOverlapOutputTooSmall,
        state.push(&final_short, &short_output),
    );
    try std.testing.expectEqual(@as(usize, 256), state.previousBlockSize());
    try std.testing.expectEqual(@as(f64, 99), short_output[0]);

    @memset(&output, 99);
    try std.testing.expectEqual(
        @as(usize, 80),
        try state.push(&final_short, &output),
    );
    try std.testing.expectEqualSlices(f64, &([_]f64{4} ** 48), output[0..48]);
    try std.testing.expectEqualSlices(f64, &([_]f64{12} ** 32), output[48..80]);

    var non_finite = final_short;
    non_finite[5] = std.math.inf(f64);
    @memset(&output, 99);
    try std.testing.expectError(
        error.InvalidVorbisOverlapInput,
        state.push(&non_finite, &output),
    );
    try std.testing.expectEqual(@as(usize, 64), state.previousBlockSize());
    try std.testing.expectEqual(@as(f64, 99), output[0]);

    var overlapping_state = VorbisOverlapAdd(f32, 256){};
    const overlapping_first = [_]f32{1} ** 64;
    _ = try overlapping_state.push(&overlapping_first, &.{});
    var overlapping_current = [_]f32{2} ** 256;
    try std.testing.expectError(
        error.OverlappingVorbisOverlapBuffer,
        overlapping_state.push(
            &overlapping_current,
            overlapping_current[0..80],
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 64),
        overlapping_state.previousBlockSize(),
    );

    var overflow_state = VorbisOverlapAdd(f32, 64){};
    const maximum = [_]f32{std.math.floatMax(f32)} ** 64;
    _ = try overflow_state.push(&maximum, &.{});
    var preserved = [_]f32{99} ** 32;
    try std.testing.expectError(
        error.InvalidVorbisOverlapOutput,
        overflow_state.push(&maximum, &preserved),
    );
    try std.testing.expectEqual(@as(f32, 99), preserved[0]);
    try std.testing.expectEqual(
        @as(usize, 64),
        overflow_state.previousBlockSize(),
    );

    var hostile_state = VorbisOverlapAdd(f64, 256){};
    hostile_state.previous_size = 3;
    try std.testing.expect(!hostile_state.valid());
    try std.testing.expect(!hostile_state.primed());
    try std.testing.expectEqual(
        @as(usize, 0),
        hostile_state.previousBlockSize(),
    );
    @memset(&output, 99);
    try std.testing.expectError(
        error.InvalidVorbisOverlapState,
        hostile_state.push(&first, &output),
    );
    try std.testing.expectEqual(@as(f64, 99), output[0]);

    var non_finite_state = VorbisOverlapAdd(f64, 256){};
    _ = try non_finite_state.push(&first, &.{});
    non_finite_state.previous[0] = std.math.nan(f64);
    try std.testing.expect(!non_finite_state.valid());
    try std.testing.expect(!non_finite_state.primed());
    try std.testing.expectEqual(
        @as(usize, 0),
        non_finite_state.previousBlockSize(),
    );
    try std.testing.expectError(
        error.InvalidVorbisOverlapState,
        non_finite_state.push(&first, &output),
    );

    state.reset();
    try std.testing.expect(!state.primed());
    try std.testing.expectEqual(
        [_]f64{0} ** 256,
        state.previous,
    );
    try std.testing.expectEqual(
        [_]f64{0} ** 128,
        state.pending,
    );
}

test "Vorbis overlap retained-size accessors fail closed" {
    var state = VorbisOverlapAdd(f32, 256){};
    const candidates = [_]usize{
        0,
        1,
        63,
        64,
        65,
        127,
        128,
        129,
        255,
        256,
        257,
        std.math.maxInt(usize),
    };
    for (candidates) |candidate| {
        state.previous_size = candidate;
        const expected_valid = candidate == 0 or
            candidate == 64 or
            candidate == 128 or
            candidate == 256;
        try std.testing.expectEqual(expected_valid, state.valid());
        try std.testing.expectEqual(
            if (expected_valid) candidate else 0,
            state.previousBlockSize(),
        );
        try std.testing.expectEqual(
            expected_valid and candidate != 0,
            state.primed(),
        );
    }
}

test "Vorbis channel overlap-add commits every channel atomically" {
    var state = VorbisChannelOverlapAdd(f64, 2, 256){};
    const first_left = [_]f64{1} ** 64;
    const first_right = [_]f64{2} ** 64;
    const first = [_][]const f64{ &first_left, &first_right };
    var empty_left: [0]f64 = .{};
    var empty_right: [0]f64 = .{};
    const empty_outputs = [_][]f64{ &empty_left, &empty_right };
    try std.testing.expectEqual(
        @as(usize, 0),
        try state.push(&first, &empty_outputs),
    );
    try std.testing.expect(state.primed());

    const second_left = [_]f64{3} ** 64;
    const second_right = [_]f64{4} ** 64;
    const second = [_][]const f64{ &second_left, &second_right };
    var output_left = [_]f64{99} ** 32;
    var output_right = [_]f64{99} ** 32;
    const outputs = [_][]f64{ &output_left, &output_right };
    try std.testing.expectEqual(
        @as(usize, 32),
        try state.push(&second, &outputs),
    );
    try std.testing.expectEqualSlices(
        f64,
        &([_]f64{4} ** 32),
        &output_left,
    );
    try std.testing.expectEqualSlices(
        f64,
        &([_]f64{6} ** 32),
        &output_right,
    );

    const third_left = [_]f64{5} ** 256;
    var invalid_right = [_]f64{6} ** 256;
    invalid_right[100] = std.math.nan(f64);
    const invalid = [_][]const f64{ &third_left, &invalid_right };
    var preserved_left = [_]f64{99} ** 80;
    var preserved_right = [_]f64{99} ** 80;
    const preserved_outputs =
        [_][]f64{ &preserved_left, &preserved_right };
    try std.testing.expectError(
        error.InvalidVorbisOverlapInput,
        state.push(&invalid, &preserved_outputs),
    );
    try std.testing.expectEqual(@as(f64, 99), preserved_left[0]);
    try std.testing.expectEqual(@as(f64, 99), preserved_right[0]);
    try std.testing.expectEqual(
        @as(usize, 64),
        state.channels[0].previousBlockSize(),
    );
    try std.testing.expectEqual(
        @as(usize, 64),
        state.channels[1].previousBlockSize(),
    );

    var shared_output = [_]f64{99} ** 80;
    const overlapping_outputs =
        [_][]f64{ shared_output[0..32], shared_output[16..48] };
    const valid_third_right = [_]f64{6} ** 256;
    const valid_third =
        [_][]const f64{ &third_left, &valid_third_right };
    try std.testing.expectError(
        error.OverlappingVorbisChannelOverlapBuffer,
        state.push(&valid_third, &overlapping_outputs),
    );
    try std.testing.expectEqual(@as(f64, 99), shared_output[0]);

    state.channels[1].previous_size = 256;
    try std.testing.expect(!state.valid());
    try std.testing.expect(!state.primed());
    try std.testing.expectError(
        error.InvalidVorbisChannelOverlapState,
        state.previousBlockSize(),
    );
    try std.testing.expectError(
        error.InvalidVorbisChannelOverlapState,
        state.push(&valid_third, &preserved_outputs),
    );
    try std.testing.expectEqual(@as(f64, 99), preserved_left[0]);

    state.reset();
    try std.testing.expect(!state.primed());
    for (state.channels) |channel| {
        try std.testing.expectEqual(
            [_]f64{0} ** 256,
            channel.previous,
        );
        try std.testing.expectEqual(
            [_]f64{0} ** 128,
            channel.pending,
        );
    }
}

test "Vorbis granule tracking trims stream boundaries transactionally" {
    var normal = VorbisGranuleTracker{};
    try std.testing.expect(normal.valid());
    const unknown = try normal.trim(32, unknown_granule, false);
    try std.testing.expect(normal.valid());
    try std.testing.expectEqual(@as(usize, 0), unknown.source_start);
    try std.testing.expectEqual(@as(usize, 32), unknown.sample_count);
    try std.testing.expectEqual(@as(?i64, null), unknown.pcm_start);
    const positioned = try normal.trim(32, 64, false);
    try std.testing.expectEqual(@as(?i64, 32), positioned.pcm_start);
    try std.testing.expectEqual(@as(?i64, 64), positioned.pcm_end);
    try std.testing.expectEqual(@as(?i64, 0), normal.position_offset);
    const final = try normal.trim(32, 90, true);
    try std.testing.expectEqual(@as(usize, 26), final.sample_count);
    try std.testing.expectEqual(@as(?i64, 64), final.pcm_start);
    try std.testing.expectEqual(@as(?i64, 90), final.pcm_end);
    try std.testing.expect(normal.ended);
    try std.testing.expect(normal.valid());
    try std.testing.expectError(
        error.VorbisGranuleStreamAlreadyEnded,
        normal.trim(32, 122, true),
    );

    var negative_start = VorbisGranuleTracker{};
    const clipped_start = try negative_start.trim(32, 22, false);
    try std.testing.expectEqual(@as(usize, 10), clipped_start.source_start);
    try std.testing.expectEqual(@as(usize, 22), clipped_start.sample_count);
    try std.testing.expectEqual(@as(?i64, 0), clipped_start.pcm_start);
    try std.testing.expectEqual(@as(?i64, 22), clipped_start.pcm_end);
    try std.testing.expectEqual(
        @as(?i64, -10),
        negative_start.position_offset,
    );
    const clipped_end = try negative_start.trim(32, 50, true);
    try std.testing.expectEqual(@as(usize, 28), clipped_end.sample_count);
    try std.testing.expectEqual(@as(?i64, 22), clipped_end.pcm_start);
    try std.testing.expectEqual(@as(?i64, 50), clipped_end.pcm_end);

    var short_stream = VorbisGranuleTracker{};
    const short_end = try short_stream.trim(32, 28, true);
    try std.testing.expectEqual(@as(usize, 0), short_end.source_start);
    try std.testing.expectEqual(@as(usize, 28), short_end.sample_count);
    try std.testing.expectEqual(@as(?i64, 0), short_end.pcm_start);
    try std.testing.expectEqual(@as(?i64, 28), short_end.pcm_end);

    var positive_start = VorbisGranuleTracker{};
    const offset_start = try positive_start.trim(32, 37, false);
    try std.testing.expectEqual(@as(?i64, 5), offset_start.pcm_start);
    try std.testing.expectEqual(@as(?i64, 37), offset_start.pcm_end);

    var late = VorbisGranuleTracker{};
    _ = try late.trim(32, unknown_granule, false);
    const late_before = late;
    try std.testing.expectError(
        error.LateVorbisInitialGranule,
        late.trim(32, 54, false),
    );
    try std.testing.expectEqualDeep(late_before, late);

    var invalid = VorbisGranuleTracker{};
    _ = try invalid.trim(32, 32, false);
    const invalid_before = invalid;
    try std.testing.expectError(
        error.InvalidVorbisGranulePosition,
        invalid.trim(32, 63, false),
    );
    try std.testing.expectEqualDeep(invalid_before, invalid);
    try std.testing.expectError(
        error.MissingVorbisEndGranule,
        invalid.trim(32, unknown_granule, true),
    );
    try std.testing.expectEqualDeep(invalid_before, invalid);
    try std.testing.expectError(
        error.InvalidVorbisGranuleSampleCount,
        invalid.trim(0, 32, false),
    );
    try std.testing.expectEqualDeep(invalid_before, invalid);

    var corrupt = VorbisGranuleTracker{
        .decoded_samples = std.math.maxInt(u64),
        .position_offset = 0,
    };
    const corrupt_before = corrupt;
    try std.testing.expect(!corrupt.valid());
    try std.testing.expectError(
        error.InvalidVorbisGranuleTrackerState,
        corrupt.trim(32, 32, false),
    );
    try std.testing.expectEqualDeep(corrupt_before, corrupt);
    corrupt.reset();
    try std.testing.expect(corrupt.valid());

    const impossible_end = VorbisGranuleTracker{ .ended = true };
    try std.testing.expect(!impossible_end.valid());

    const overflowing_endpoint = VorbisGranuleTracker{
        .decoded_samples = 1,
        .position_offset = std.math.maxInt(i64),
    };
    try std.testing.expect(!overflowing_endpoint.valid());
    const negative_endpoint = VorbisGranuleTracker{
        .decoded_samples = 1,
        .position_offset = -2,
    };
    try std.testing.expect(!negative_endpoint.valid());

    invalid.reset();
    try std.testing.expect(invalid.valid());
    try std.testing.expectEqualDeep(VorbisGranuleTracker{}, invalid);
}

test "file-backed Ogg packet reader streams continued packets" {
    var encoded: [70_000]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 99);
    const packet = [_]u8{0x5a} ** 65_100;
    try writer.appendPacket(&packet, 65_100, true, true);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "packets.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, writer.bytes(), 0);
    try file.setLength(std.testing.io, writer.bytes().len);
    var reader = try FilePacketReader.init(std.testing.io, file);
    var page_storage: [maximum_page_bytes]u8 = undefined;
    var packet_storage: [packet.len]u8 = undefined;
    const actual = (try reader.next(
        &page_storage,
        &packet_storage,
    )).?;
    try std.testing.expect(actual.beginning);
    try std.testing.expect(actual.end);
    try std.testing.expectEqualSlices(u8, &packet, actual.bytes);
    try std.testing.expect(
        (try reader.next(&page_storage, &packet_storage)) == null,
    );
}

const ogg_fuzz_seed = "OggS";

test "fuzz bounded Ogg page and packet parsing" {
    try std.testing.fuzz({}, fuzzOgg, .{
        .corpus = &.{ogg_fuzz_seed},
    });
}

fn fuzzOgg(_: void, smith: *std.testing.Smith) !void {
    @disableInstrumentation();
    var encoded: [64 * 1024]u8 = undefined;
    var length: usize = switch (smith.valueRangeAtMost(u8, 0, 1)) {
        0 => smith.slice(&encoded),
        1 => generated: {
            var writer = StreamWriter.init(&encoded, smith.value(u32));
            var payload: [512]u8 = undefined;
            const packet_count = smith.valueRangeAtMost(u8, 1, 8);
            for (0..packet_count) |packet_index| {
                const packet_length = smith.slice(&payload);
                writer.appendPacket(
                    payload[0..packet_length],
                    smith.value(u64),
                    packet_index == 0,
                    packet_index + 1 == packet_count,
                ) catch break;
            }
            break :generated writer.bytes().len;
        },
        else => smith.slice(&encoded),
    };
    if (length != 0 and smith.value(bool)) {
        const mutation_count = smith.valueRangeAtMost(u8, 1, 32);
        for (0..mutation_count) |_|
            encoded[smith.index(length)] ^= smith.value(u8);
    }
    if (smith.value(bool)) {
        const maximum: u16 = @intCast(@min(length, std.math.maxInt(u16)));
        length = smith.valueRangeAtMost(u16, 0, maximum);
    } else if (length < encoded.len and smith.value(bool)) {
        const maximum_append: u16 = @intCast(@min(
            encoded.len - length,
            std.math.maxInt(u16),
        ));
        const append_length = smith.valueRangeAtMost(u16, 0, maximum_append);
        smith.bytes(encoded[length..][0..append_length]);
        length += append_length;
    }

    const limits = Limits{
        .max_stream_bytes = encoded.len,
        .max_pages = 256,
        .max_packets = 256,
        .max_logical_streams = 16,
    };
    var pages = PageIterator.initChainedWithLimits(
        encoded[0..length],
        limits,
    ) catch return;
    var previous_offset: usize = 0;
    while (pages.next() catch return) |_| {
        if (pages.offset <= previous_offset)
            return error.OggFuzzPageParserDidNotAdvance;
        previous_offset = pages.offset;
    }

    var packet_storage: [64 * 1024]u8 = undefined;
    var packets = PacketIterator.initChainedWithLimits(
        encoded[0..length],
        &packet_storage,
        limits,
    ) catch return;
    while (true) {
        const before = packets;
        const packet = packets.next() catch {
            if (!std.meta.eql(before, packets))
                return error.OggFuzzPacketFailureWasNotTransactional;
            return;
        } orelse break;
        if (packet.bytes.len > packet_storage.len or
            packets.packet_index != before.packet_index + 1)
        {
            return error.OggFuzzInvalidPacketProgress;
        }
    }
}
