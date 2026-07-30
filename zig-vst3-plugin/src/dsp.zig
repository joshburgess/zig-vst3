pub const aiff_writer = @import("dsp/aiff_writer.zig");
pub const adm = @import("dsp/adm.zig");
pub const adm_binaural = @import("dsp/adm_binaural.zig");
pub const adm_diffuse = @import("dsp/adm_diffuse.zig");
pub const adm_direct_speaker_mapping =
    @import("dsp/adm_direct_speaker_mapping.zig");
pub const adm_hoa_decoder = @import("dsp/adm_hoa_decoder.zig");
pub const adm_hoa_matrix = @import("dsp/adm_hoa_matrix.zig");
pub const adm_render = @import("dsp/adm_render.zig");
pub const adm_time = @import("dsp/adm_time.zig");
pub const adm_xml = @import("dsp/adm_xml.zig");
pub const hrtf = @import("dsp/hrtf.zig");
pub const hrtf_sofa = @import("dsp/hrtf_sofa.zig");
pub const audio_block = @import("dsp/audio_block.zig");
pub const audio_file_reader = @import("dsp/audio_file_reader.zig");
pub const audio_metadata = @import("dsp/audio_metadata.zig");
pub const ballistics = @import("dsp/ballistics.zig");
pub const biquad = @import("dsp/biquad.zig");
pub const broadcast_metadata = @import("dsp/broadcast_metadata.zig");
pub const butterworth_design = @import("dsp/butterworth_design.zig");
pub const chorus = @import("dsp/chorus.zig");
pub const chebyshev2_design = @import("dsp/chebyshev2_design.zig");
pub const chebyshev_design = @import("dsp/chebyshev_design.zig");
pub const convolution = @import("gui_ir_convolution.zig");
pub const delay = @import("dsp/delay.zig");
pub const denormals = @import("dsp/denormals.zig");
pub const dry_wet = @import("dsp/dry_wet.zig");
pub const dynamics = @import("dsp/dynamics.zig");
pub const elliptic_design = @import("dsp/elliptic_design.zig");
pub const equiripple_design = @import("dsp/equiripple_design.zig");
pub const fft = @import("dsp/fft.zig");
pub const file_writer_io = @import("dsp/file_writer_io.zig");
const file_writer_faults = @import("dsp/file_writer_faults.zig");
pub const fir = @import("dsp/fir.zig");
pub const fir_design = @import("dsp/fir_design.zig");
pub const first_order_tpt = @import("dsp/first_order_tpt.zig");
pub const fixed_rate = @import("dsp/fixed_rate.zig");
pub const fast_math = @import("dsp/fast_math.zig");
pub const flac = @import("dsp/flac.zig");
pub const flanger = @import("dsp/flanger.zig");
pub const fixture_runner = @import("dsp/fixture_runner.zig");
pub const kernel_dispatch = @import("dsp/kernel_dispatch.zig");
pub const inter_sample_limiter = @import("dsp/inter_sample_limiter.zig");
pub const id3 = @import("dsp/id3.zig");
pub const ixml = @import("dsp/ixml.zig");
pub const ladder = @import("dsp/ladder.zig");
pub const linkwitz_riley = @import("dsp/linkwitz_riley.zig");
pub const log_ramp = @import("dsp/log_ramp.zig");
pub const lookup_table = @import("dsp/lookup_table.zig");
pub const matrix = @import("dsp/matrix.zig");
pub const mixed_oversampling = @import("dsp/mixed_oversampling.zig");
pub const mp3 = @import("dsp/mp3.zig");
pub const modulated_delay = @import("dsp/modulated_delay.zig");
pub const modulation_rate = @import("dsp/modulation_rate.zig");
pub const multiband_dynamics = @import("dsp/multiband_dynamics.zig");
pub const multichannel_oversampling = @import("dsp/multichannel_oversampling.zig");
pub const multichannel_polyphase_iir_oversampling =
    @import("dsp/multichannel_polyphase_iir_oversampling.zig");
pub const ogg = @import("dsp/ogg.zig");
pub const oscillator = @import("dsp/oscillator.zig");
pub const oversampling = @import("dsp/oversampling.zig");
pub const panner = @import("dsp/panner.zig");
pub const phase = @import("dsp/phase.zig");
pub const pcm_dither = @import("dsp/pcm_dither.zig");
pub const phaser = @import("dsp/phaser.zig");
pub const processor_chain = @import("dsp/processor_chain.zig");
pub const process_context = @import("dsp/process_context.zig");
pub const processor_duplicator = @import("dsp/processor_duplicator.zig");
pub const polynomial = @import("dsp/polynomial.zig");
pub const polyphase_fir = @import("dsp/polyphase_fir.zig");
pub const polyphase_iir = @import("dsp/polyphase_iir.zig");
pub const polyphase_iir_oversampling =
    @import("dsp/polyphase_iir_oversampling.zig");
pub const resampler = @import("dsp/resampler.zig");
pub const reverb = @import("dsp/reverb.zig");
pub const realtime_snapshot = @import("dsp/realtime_snapshot.zig");
pub const rf64_writer = @import("dsp/rf64_writer.zig");
pub const gain_bias = @import("dsp/gain_bias.zig");
pub const shared_processor_duplicator =
    @import("dsp/shared_processor_duplicator.zig");
pub const simd_register = @import("dsp/simd_register.zig");
pub const smoothed_value = @import("dsp/smoothed_value.zig");
pub const state_variable = @import("dsp/state_variable.zig");
pub const stereo_modulation = @import("dsp/stereo_modulation.zig");
pub const special_functions = @import("dsp/special_functions.zig");
pub const vibrato = @import("dsp/vibrato.zig");
pub const waveshaper = @import("dsp/waveshaper.zig");
pub const wav_writer = @import("dsp/wav_writer.zig");
pub const wave64_writer = @import("dsp/wave64_writer.zig");
pub const wave64_metadata = @import("dsp/wave64_metadata.zig");
pub const window = @import("dsp/window.zig");

pub const AudioBlock = audio_block.AudioBlock;
pub const AudioFileContainer = audio_file_reader.Container;
pub const AudioFileEncoding = audio_file_reader.Encoding;
pub const AudioFileInfo = audio_file_reader.Info;
pub const AudioFileMetadataKind = audio_file_reader.MetadataKind;
pub const AudioFileReader = audio_file_reader.FileReader;
pub const AudioFileAdmMetadata = audio_file_reader.AdmMetadata;
pub const AudioFileAdmMetadataRequirements =
    audio_file_reader.AdmMetadataRequirements;
pub const FileWriterOperations = file_writer_io.Operations;
pub const FileWriterCheckpoint = file_writer_io.Checkpoint;
pub const AudioMetadataEntry = audio_metadata.Entry;
pub const AdmChannelAllocation = adm.ChannelAllocation;
pub const AdmChannelAllocationEntry = adm.Entry;
pub const AdmChannelAllocationIterator = adm.Iterator;
pub const AdmChannelAllocationView = adm.View;
pub const AdmIdentifier = adm.Identifier;
pub const AdmIdentifierKind = adm.IdentifierKind;
pub const AdmDirectSpeakerRouter = adm_render.DirectSpeakerRouter;
pub const AdmDirectSpeakerPositionRouter =
    adm_render.DirectSpeakerPositionRouter;
pub const AdmPolarPointSourcePanner =
    adm_render.PolarPointSourcePanner;
pub const AdmPolarExtentPanner =
    adm_render.PolarExtentPanner;
pub const AdmCartesianPointSourcePanner =
    adm_render.CartesianPointSourcePanner;
pub const AdmCartesianExtentPanner =
    adm_render.CartesianExtentPanner;
pub const AdmDirectSpeakerRoute = adm_render.DirectSpeakerRoute;
pub const AdmDirectSpeakerRoutingContext =
    adm_render.DirectSpeakerRoutingContext;
pub const AdmDirectSpeakerCommonPackMapping =
    adm_render.DirectSpeakerCommonPackMapping;
pub const AdmObjectRenderingContext =
    adm_render.ObjectRenderingContext;
pub const AdmObjectPointGainPlan =
    adm_render.ObjectPointGainPlan;
pub const AdmObjectPolarExtentGainPlan =
    adm_render.ObjectPolarExtentGainPlan;
pub const AdmObjectCartesianExtentGainPlan =
    adm_render.ObjectCartesianExtentGainPlan;
pub const AdmObjectGainTimeline =
    adm_render.ObjectGainTimeline;
pub const AdmObjectDiffuseProcessor =
    adm_diffuse.ObjectDiffuseProcessor;
pub const AdmOutputSpeaker = adm_render.OutputSpeaker;
pub const AdmPolarPosition = adm_render.PolarPosition;
pub const AdmCartesianPosition = adm_render.CartesianPosition;
pub const AdmScreenEdges = adm_render.ScreenEdges;
pub const resolveAdmDirectSpeakerRoute =
    adm_render.resolveDirectSpeakerRoute;
pub const AdmStaticMatrixMixer = adm_render.StaticMatrixMixer;
pub const AdmMatrixCoefficientMixer =
    adm_render.MatrixCoefficientMixer;
pub const AdmVariableMatrixCoefficientMixer =
    adm_render.VariableMatrixCoefficientMixer;
pub const AdmMatrixVariableKind = adm_render.MatrixVariableKind;
pub const AdmMatrixVariableInterpolation =
    adm_render.MatrixVariableInterpolation;
pub const AdmMatrixVariablePoint = adm_render.MatrixVariablePoint;
pub const AdmMatrixVariableTimeline =
    adm_render.MatrixVariableTimeline;
pub const AdmHoaMatrixDecoder = adm_hoa_decoder.MatrixDecoder;
pub const AdmHoaLoudspeakerMatrix =
    adm_hoa_matrix.LoudspeakerMatrix;
pub const AdmHoaLoudspeaker = adm_hoa_matrix.Loudspeaker;
pub const AdmHoaOrderWeighting = adm_hoa_matrix.OrderWeighting;
pub const AdmHoaMatrixGenerationOptions =
    adm_hoa_matrix.GenerationOptions;
pub const evaluateAdmHoaBasis =
    adm_hoa_matrix.realSphericalHarmonic;
pub const maximum_supported_adm_hoa_order =
    adm_hoa_decoder.maximum_supported_order;
pub const AdmBinauralStereoMixer = adm_binaural.StereoMixer;
pub const AdmBinauralStereoGainTimeline =
    adm_binaural.StereoGainTimeline;
pub const HrtfDatabase = hrtf.Database;
pub const HrtfRenderer = hrtf.Renderer;
pub const HrtfMotionRenderer = hrtf.MotionRenderer;
pub const HrtfDirection = hrtf.Direction;
pub const HrtfPosition = hrtf.Position;
pub const HrtfHeadPose = hrtf.HeadPose;
pub const HrtfMotionPoint = hrtf.MotionPoint;
pub const HrtfInterpolation = hrtf.Interpolation;
pub const HrtfSofaLoader = hrtf_sofa.Loader;
pub const maximum_adm_renderer_input_channels =
    adm_render.maximum_input_channels;
pub const adm_polar_extent_spreading_direction_count =
    adm_render.polar_extent_spreading_direction_count;
pub const maximum_adm_renderer_output_channels =
    adm_render.maximum_output_channels;
pub const adm_object_diffuse_filter_length =
    adm_diffuse.filter_length;
pub const adm_object_direct_delay_samples =
    adm_diffuse.direct_delay_samples;
pub const AdmXmlDeclaration = adm_xml.Declaration;
pub const AdmXmlDeclarationIterator = adm_xml.DeclarationIterator;
pub const AdmXmlBlockFormat = adm_xml.BlockFormat;
pub const AdmXmlBlockIterator = adm_xml.BlockIterator;
pub const AdmXmlChannelLock = adm_xml.ChannelLock;
pub const AdmXmlCartesianExclusionZone =
    adm_xml.CartesianExclusionZone;
pub const AdmXmlCoordinate = adm_xml.Coordinate;
pub const AdmXmlDocument = adm_xml.Document;
pub const AdmXmlExtension = adm_xml.Extension;
pub const AdmXmlExtensionAttribute = adm_xml.ExtensionAttribute;
pub const AdmXmlExtensionAttributeIterator =
    adm_xml.ExtensionAttributeIterator;
pub const AdmXmlExtensionIterator = adm_xml.ExtensionIterator;
pub const AdmXmlUntypedElement = adm_xml.UntypedElement;
pub const AdmXmlUntypedElementIterator = adm_xml.UntypedElementIterator;
pub const AdmXmlUntypedAttribute = adm_xml.UntypedAttribute;
pub const AdmXmlUntypedAttributeIterator = adm_xml.UntypedAttributeIterator;
pub const AdmXmlGain = adm_xml.Gain;
pub const AdmXmlGainUnit = adm_xml.GainUnit;
pub const AdmXmlFrequency = adm_xml.Frequency;
pub const AdmXmlHeadphoneVirtualise = adm_xml.HeadphoneVirtualise;
pub const AdmXmlHoaNormalization = adm_xml.HoaNormalization;
pub const AdmXmlJumpPosition = adm_xml.JumpPosition;
pub const AdmXmlMatrixCoefficient = adm_xml.MatrixCoefficient;
pub const AdmXmlObjectDivergence = adm_xml.ObjectDivergence;
pub const AdmXmlExclusionZone = adm_xml.ExclusionZone;
pub const AdmXmlPolarExclusionZone = adm_xml.PolarExclusionZone;
pub const AdmXmlPosition = adm_xml.Position;
pub const AdmXmlPositionBound = adm_xml.PositionBound;
pub const AdmXmlProfile = adm_xml.Profile;
pub const AdmXmlEmissionProfileLevel = adm_xml.EmissionProfileLevel;
pub const AdmXmlEmissionPcmEssence = adm_xml.EmissionPcmEssence;
pub const AdmXmlEmissionSerialFlowState = adm_xml.EmissionSerialFlowState;
pub const AdmXmlProfileIterator = adm_xml.ProfileIterator;
pub const AdmXmlReference = adm_xml.Reference;
pub const AdmXmlReferenceIterator = adm_xml.ReferenceIterator;
pub const AdmXmlReferenceKind = adm_xml.ReferenceKind;
pub const AdmXmlScreenEdge = adm_xml.ScreenEdge;
pub const AdmXmlSpeakerLabel = adm_xml.SpeakerLabel;
pub const AdmXmlTag = adm_xml.Tag;
pub const AdmXmlTagItem = adm_xml.TagItem;
pub const AdmXmlTagIterator = adm_xml.TagIterator;
pub const AdmXmlTagTarget = adm_xml.TagTarget;
pub const AdmXmlText = adm_xml.AdmText;
pub const maximum_adm_matrix_coefficients =
    adm_xml.max_adm_matrix_coefficients;
pub const maximum_adm_exclusion_zones =
    adm_xml.max_adm_exclusion_zones;
pub const maximum_adm_positions = adm_xml.max_adm_positions;
pub const maximum_adm_speaker_label_bytes =
    adm_xml.max_adm_speaker_label_bytes;
pub const maximum_adm_speaker_labels =
    adm_xml.max_adm_speaker_labels;
pub const AdmTimeFormat = adm_time.Format;
pub const AdmTimeValue = adm_time.Value;
pub const BroadcastDate = broadcast_metadata.Date;
pub const BroadcastExtension = broadcast_metadata.Extension;
pub const BroadcastLoudness = broadcast_metadata.Loudness;
pub const BroadcastMetadataView = broadcast_metadata.View;
pub const BroadcastTime = broadcast_metadata.Time;
pub const BroadcastVersion = broadcast_metadata.Version;
pub const RiffMetadata = audio_metadata.RiffMetadata;
pub const RiffXmlKind = audio_metadata.RiffXmlKind;
pub const RiffXmlView = audio_metadata.RiffXmlView;
pub const encodeBroadcastMetadata = broadcast_metadata.encode;
pub const encodeAdmChannelAllocation = adm.encode;
pub const AiffTextMetadataIterator = audio_metadata.AiffTextIterator;
pub const encodeRiffXmlMetadata = audio_metadata.encodeRiffXml;
pub const RiffInfoMetadataView = audio_metadata.RiffInfoView;
pub const encodeAiffTextMetadata = audio_metadata.encodeAiffText;
pub const encodeRiffInfoMetadata = audio_metadata.encodeRiffInfo;
pub const requiredAiffTextMetadataBytes =
    audio_metadata.requiredAiffTextBytes;
pub const requiredBroadcastMetadataBytes =
    broadcast_metadata.requiredBytes;
pub const requiredAdmChannelAllocationBytes = adm.requiredBytes;
pub const requiredRiffMetadataBytes =
    audio_metadata.requiredRiffMetadataBytes;
pub const requiredRiffInfoMetadataBytes =
    audio_metadata.requiredRiffInfoBytes;
pub const requiredRiffXmlMetadataBytes =
    audio_metadata.requiredRiffXmlBytes;
pub const Id3DecodedFrame = id3.DecodedFrame;
pub const Id3EncodeOptions = id3.EncodeOptions;
pub const Id3EncodedFrame = id3.EncodedFrame;
pub const Id3ExtendedHeader = id3.ExtendedHeader;
pub const Id3Frame = id3.Frame;
pub const Id3Header = id3.Header;
pub const Id3Iterator = id3.Iterator;
pub const Id3Text = id3.Text;
pub const Id3TextEncoding = id3.TextEncoding;
pub const Id3View = id3.View;
pub const Id3V1Tag = id3.V1Tag;
pub const Id3V1View = id3.V1View;
pub const Id3V23EncodeOptions = id3.V23EncodeOptions;
pub const Id3V23EncodedFrame = id3.V23EncodedFrame;
pub const Id3V23ExtendedHeader = id3.V23ExtendedHeader;
pub const Id3V23Frame = id3.V23Frame;
pub const Id3V23Header = id3.V23Header;
pub const Id3V23Iterator = id3.V23Iterator;
pub const Id3V23View = id3.V23View;
pub const encodeId3 = id3.encode;
pub const encodeId3V1 = id3.encodeV1;
pub const encodeId3V23 = id3.encodeV23;
pub const encodeId3V23TextPayload = id3.encodeV23TextPayload;
pub const encodeId3Utf8TextPayload = id3.encodeUtf8TextPayload;
pub const requiredId3Bytes = id3.requiredBytes;
pub const requiredId3V23Bytes = id3.requiredV23Bytes;
pub const requiredId3V23TextPayloadBytes =
    id3.requiredV23TextPayloadBytes;
pub const requiredId3Utf8TextPayloadBytes =
    id3.requiredUtf8TextPayloadBytes;
pub const Mp3ChannelMode = mp3.ChannelMode;
pub const Mp3AnalyzedEncoderChannel =
    mp3.AnalyzedEncoderChannel;
pub const Mp3AnalyzedEncoderFrame = mp3.AnalyzedEncoderFrame;
pub const Mp3DecoderFormat = mp3.DecoderFormat;
pub const Mp3EncodedHuffmanChannel = mp3.EncodedHuffmanChannel;
pub const Mp3EncodedScaleFactors = mp3.EncodedScaleFactors;
pub const Mp3EncoderAnalysis = mp3.EncoderAnalysis;
pub const Mp3EncoderBlockClassifier =
    mp3.EncoderBlockClassifier;
pub const Mp3EncoderConfig = mp3.EncoderConfig;
pub const Mp3EncoderPsychoacousticChannel =
    mp3.EncoderPsychoacousticChannel;
pub const Mp3EncoderPsychoacousticConfig =
    mp3.EncoderPsychoacousticConfig;
pub const Mp3EncoderPsychoacousticModel =
    mp3.EncoderPsychoacousticModel;
pub const Mp3EncoderPsychoacousticTimeline =
    mp3.EncoderPsychoacousticTimeline;
pub const Mp3EncoderQuantizer = mp3.EncoderQuantizer;
pub const Mp3EncoderScaleFactors = mp3.EncoderScaleFactors;
pub const Mp3EncoderStreamSummary = mp3.EncoderStreamSummary;
pub const Mp3FileFrame = mp3.FileFrame;
pub const Mp3FileReader = mp3.FileReader;
pub const Mp3FileSummary = mp3.FileSummary;
pub const Mp3Frame = mp3.Frame;
pub const Mp3FrameDecoder = mp3.FrameDecoder;
pub const Mp3FrameEncoder = mp3.FrameEncoder;
pub const Mp3GaplessPlan = mp3.GaplessPlan;
pub const Mp3Granule = mp3.Granule;
pub const Mp3GranuleChannel = mp3.GranuleChannel;
pub const Mp3Header = mp3.Header;
pub const Mp3HybridAnalysis = mp3.HybridAnalysis;
pub const Mp3HybridSamples = mp3.HybridSamples;
pub const Mp3HybridSynthesis = mp3.HybridSynthesis;
pub const Mp3MainData = mp3.MainData;
pub const Mp3MainDataReservoir = mp3.MainDataReservoir;
pub const Mp3PcmGranule = mp3.PcmGranule;
pub const Mp3PcmFrame = mp3.PcmFrame;
pub const Mp3PcmEncoder = mp3.PcmEncoder;
pub const Mp3PcmFileEncoder = mp3.PcmFileEncoder;
pub const Mp3PcmRange = mp3.PcmRange;
pub const Mp3PcmReservoirAppend = mp3.PcmReservoirAppend;
pub const Mp3PcmReservoirEncoder = mp3.PcmReservoirEncoder;
pub const Mp3PcmReservoirFileEncoder =
    mp3.PcmReservoirFileEncoder;
pub const Mp3PcmReservoirFileSummary =
    mp3.PcmReservoirFileSummary;
pub const Mp3PcmReservoirStreamEncoder =
    mp3.PcmReservoirStreamEncoder;
pub const Mp3PcmReservoirStreamFinish =
    mp3.PcmReservoirStreamFinish;
pub const Mp3PcmStreamEncoder = mp3.PcmStreamEncoder;
pub const Mp3PcmStreamFinish = mp3.PcmStreamFinish;
pub const Mp3PolyphaseAnalysis = mp3.PolyphaseAnalysis;
pub const Mp3PolyphaseSynthesis = mp3.PolyphaseSynthesis;
pub const Mp3QuantizedSpectrum = mp3.QuantizedSpectrum;
pub const Mp3QuantizedEncoderChannel =
    mp3.QuantizedEncoderChannel;
pub const Mp3QuantizedEncoderFrame = mp3.QuantizedEncoderFrame;
pub const Mp3RequantizedSpectrum = mp3.RequantizedSpectrum;
pub const Mp3StereoSpectrum = mp3.StereoSpectrum;
pub const Mp3ScaleFactorBands = mp3.ScaleFactorBands;
pub const Mp3ScaleFactorChannel = mp3.ScaleFactorChannel;
pub const Mp3ScaleFactorGranule = mp3.ScaleFactorGranule;
pub const Mp3ScaleFactors = mp3.ScaleFactors;
pub const Mp3SeekPoint = mp3.SeekPoint;
pub const Mp3SideInformation = mp3.SideInformation;
pub const Mp3Stream = mp3.Stream;
pub const Mp3StreamDecoder = mp3.StreamDecoder;
pub const Mp3Summary = mp3.Summary;
pub const Mp3TrimmedPcmFrame = mp3.TrimmedPcmFrame;
pub const Mp3Vbri = mp3.Vbri;
pub const Mp3VbriEncoderMetadata = mp3.VbriEncoderMetadata;
pub const Mp3VbriSummary = mp3.VbriSummary;
pub const Mp3VbrEncoderConfig = mp3.VbrEncoderConfig;
pub const Mp3VbrPcmEncoder = mp3.VbrPcmEncoder;
pub const Mp3VbrPcmFileEncoder = mp3.VbrPcmFileEncoder;
pub const Mp3VbrPcmFileSummary = mp3.VbrPcmFileSummary;
pub const Mp3VbrPcmFrame = mp3.VbrPcmFrame;
pub const Mp3VbrPcmReservoirAppend =
    mp3.VbrPcmReservoirAppend;
pub const Mp3VbrPcmReservoirEncoder =
    mp3.VbrPcmReservoirEncoder;
pub const Mp3VbrPcmReservoirFileEncoder =
    mp3.VbrPcmReservoirFileEncoder;
pub const Mp3VbrPcmReservoirFileSummary =
    mp3.VbrPcmReservoirFileSummary;
pub const Mp3VbrPcmReservoirSelection =
    mp3.VbrPcmReservoirSelection;
pub const Mp3VbrPcmReservoirStreamEncoder =
    mp3.VbrPcmReservoirStreamEncoder;
pub const Mp3VbrPcmReservoirStreamFinish =
    mp3.VbrPcmReservoirStreamFinish;
pub const Mp3VbrPcmStreamEncoder = mp3.VbrPcmStreamEncoder;
pub const Mp3VbrPcmStreamFinish = mp3.VbrPcmStreamFinish;
pub const Mp3Version = mp3.Version;
pub const Mp3Xing = mp3.Xing;
pub const Mp3XingEncoderMetadata = mp3.XingEncoderMetadata;
pub const Mp3XingKind = mp3.XingKind;
pub const buildMp3SeekIndex = mp3.buildSeekIndex;
pub const buildMp3FileSeekIndex = mp3.buildFileSeekIndex;
pub const buildMp3VbriToc = mp3.buildVbriToc;
pub const appendMp3Id3v1FileTail = mp3.appendId3v1FileTail;
pub const decodeMp3HuffmanChannel = mp3.decodeHuffmanChannel;
pub const decodeMp3ScaleFactors = mp3.decodeScaleFactors;
pub const encodeMp3HuffmanChannel = mp3.encodeHuffmanChannel;
pub const encodeMp3InfoFrame = mp3.encodeInfoFrame;
pub const encodeMp3VbriFrame = mp3.encodeVbriFrame;
pub const encodeMp3XingFrame = mp3.encodeXingFrame;
pub const encodeMp3ScaleFactors = mp3.encodeScaleFactors;
pub const encodeMp3SideInformation = mp3.encodeSideInformation;
pub const findMp3SeekPoint = mp3.findSeekPoint;
pub const mp3HuffmanRegionEnds = mp3.huffmanRegionEnds;
pub const mp3ScaleFactorBands = mp3.scaleFactorBands;
pub const requiredMp3FileSeekPoints = mp3.requiredFileSeekPoints;
pub const requiredMp3SeekPoints = mp3.requiredSeekPoints;
pub const requiredMp3VbriTocBytes = mp3.requiredVbriTocBytes;
pub const writeMp3Id3v2FilePrefix = mp3.writeId3v2FilePrefix;
pub const requantizeMp3Channel = mp3.requantizeChannel;
pub const processMp3Stereo = mp3.processStereo;
pub const prepareMp3AliasesForEncoding =
    mp3.prepareAliasesForEncoding;
pub const prepareMp3EncoderStereo = mp3.prepareEncoderStereo;
pub const reduceMp3Aliases = mp3.reduceAliases;
pub const maximumMp3FreeFormatFrameBytes =
    mp3.maximum_free_format_frame_bytes;
pub const maximumMp3EncodedFrameBytes =
    mp3.maximum_encoded_frame_bytes;
pub const ConstAudioBlock = audio_block.ConstAudioBlock;
pub const AiffEncoding = aiff_writer.Encoding;
pub const AiffSpec = aiff_writer.Spec;
pub const AiffWriter = aiff_writer.Writer;
pub const AiffFileWriter = aiff_writer.FileWriter;
pub const requiredAiffBytes = aiff_writer.requiredBytes;
pub const writeInterleavedAiff = aiff_writer.writeInterleaved;
pub const writeInterleavedAiffDithered =
    aiff_writer.writeInterleavedDithered;
pub const BallisticsConfig = ballistics.Config;
pub const BallisticsFilter = ballistics.BallisticsFilter;
pub const BallisticsMode = ballistics.Mode;
pub const BiquadConfig = biquad.Config;
pub const BiquadCoefficients = biquad.Coefficients;
pub const BiquadComplexResponse = biquad.ComplexResponse;
pub const BiquadKind = biquad.Kind;
pub const SmoothedBiquad = biquad.SmoothedBiquad;
pub const ButterworthDesigner = butterworth_design.Designer;
pub const ButterworthCascade = butterworth_design.Cascade;
pub const ButterworthSpecification = butterworth_design.Specification;
pub const ButterworthSpecificationDesign =
    butterworth_design.SpecificationDesign;
pub const maximum_butterworth_sections =
    butterworth_design.maximum_sections;
pub const Chorus = chorus.Chorus;
pub const ChorusConfig = chorus.Config;
pub const ChebyshevConfig = chebyshev_design.Config;
pub const ChebyshevDesigner = chebyshev_design.Designer;
pub const ChebyshevSpecification = chebyshev_design.Specification;
pub const ChebyshevTypeIIConfig = chebyshev2_design.Config;
pub const ChebyshevTypeIIDesigner = chebyshev2_design.Designer;
pub const ChebyshevTypeIISpecification = chebyshev2_design.Specification;
pub const ChebyshevTypeIISpecificationDesign =
    chebyshev2_design.SpecificationDesign;
pub const PartitionedConvolver = convolution.PartitionedConvolver;
pub const ConvolutionMetadata = convolution.Metadata;
pub const ConvolutionStageError = convolution.StageError;
pub const ConvolutionLatencyMode = convolution.LatencyMode;
pub const ConvolutionRouting = convolution.Routing;
pub const ConvolutionOptions = convolution.Options;
pub const ConvolutionPreparationQueue =
    convolution.PreparationQueue;
pub const DelayLine = delay.DelayLine;
pub const DelayInterpolation = delay.Interpolation;
pub const DenormalScope = denormals.Scope;
pub const DryWetConfig = dry_wet.Config;
pub const DryWetMixer = dry_wet.DryWetMixer;
pub const DryWetMixingRule = dry_wet.MixingRule;
pub const dryWetMixingGains = dry_wet.mixingGains;
pub const Compressor = dynamics.Compressor;
pub const CompressorConfig = dynamics.CompressorConfig;
pub const Limiter = dynamics.Limiter;
pub const LimiterConfig = dynamics.LimiterConfig;
pub const LookaheadLimiter = dynamics.LookaheadLimiter;
pub const LookaheadLimiterConfig = dynamics.LookaheadLimiterConfig;
pub const LookaheadCompressor = dynamics.LookaheadCompressor;
pub const LookaheadCompressorConfig =
    dynamics.LookaheadCompressorConfig;
pub const NoiseGate = dynamics.NoiseGate;
pub const NoiseGateConfig = dynamics.NoiseGateConfig;
pub const EllipticConfig = elliptic_design.Config;
pub const EllipticDesigner = elliptic_design.Designer;
pub const EllipticSpecification = elliptic_design.Specification;
pub const FirEquirippleBand = equiripple_design.Band;
pub const FirEquirippleDesigner = equiripple_design.Designer;
pub const FirEquirippleOptions = equiripple_design.Options;
pub const FirEquirippleReport = equiripple_design.Report;
pub const FirEquirippleSymmetry = equiripple_design.Symmetry;
pub const maximum_fir_equiripple_bands =
    equiripple_design.maximum_bands;
pub const maximum_fir_equiripple_grid_density =
    equiripple_design.maximum_grid_density;
pub const maximum_fir_equiripple_taps =
    equiripple_design.maximum_taps;
pub const Fft = fft.Transform;
pub const FirFilter = fir.FirFilter;
pub const FirDesigner = fir_design.Designer;
pub const FirLeastSquaresBand = fir_design.LeastSquaresBand;
pub const maximum_fir_least_squares_taps =
    fir_design.maximum_least_squares_taps;
pub const FirstOrderTptConfig = first_order_tpt.Config;
pub const FirstOrderTptFilter = first_order_tpt.FirstOrderTptFilter;
pub const FirstOrderTptKind = first_order_tpt.Kind;
pub const FixedRateConfig = fixed_rate.Config;
pub const FixedRatePipeline = fixed_rate.FixedRatePipeline;
pub const maximum_fixed_rate_ratio = fixed_rate.maximum_rate_ratio;
pub const FastMathApproximations = fast_math.Approximations;
pub const FastMathOperation = fast_math.Operation;
pub const FlacDecodeResult = flac.DecodeResult;
pub const FlacComment = flac.Comment;
pub const FlacCommentIterator = flac.CommentIterator;
pub const FlacComments = flac.Comments;
pub const FlacEncoding = flac.Encoding;
pub const FlacFileReader = flac.FileReader;
pub const FlacInfo = flac.Info;
pub const FlacFileWriter = flac.FileWriter;
pub const FlacFileWriterMetadata = flac.FileWriterMetadata;
pub const FlacMetadata = flac.Metadata;
pub const FlacSeekPoint = flac.SeekPoint;
pub const FlacSeekTableIterator = flac.SeekTableIterator;
pub const FlacSpec = flac.Spec;
pub const decodeInterleavedFlac = flac.decodeInterleaved;
pub const decodeInterleavedFlacWithWideScratch =
    flac.decodeInterleavedWithWideScratch;
pub const decodeInterleavedFlacRange = flac.decodeInterleavedRange;
pub const decodeInterleavedFlacRangeWithWideScratch =
    flac.decodeInterleavedRangeWithWideScratch;
pub const encodeInterleavedFlac = flac.encodeInterleaved;
pub const encodeInterleavedFlacWithComments =
    flac.encodeInterleavedWithComments;
pub const encodeInterleavedFlacWithSeekTable =
    flac.encodeInterleavedWithSeekTable;
pub const encodeInterleavedFlacWithMetadata =
    flac.encodeInterleavedWithMetadata;
pub const readInterleavedFlacFile = flac.readInterleavedFile;
pub const readInterleavedFlacFileRange =
    flac.readInterleavedFileRange;
pub const readInterleavedFlacFileRangeWithWideScratch =
    flac.readInterleavedFileRangeWithWideScratch;
pub const requiredFlacBytes = flac.requiredBytes;
pub const requiredFlacBytesWithComments =
    flac.requiredBytesWithComments;
pub const requiredFlacBytesWithSeekTable =
    flac.requiredBytesWithSeekTable;
pub const requiredFlacBytesWithMetadata =
    flac.requiredBytesWithMetadata;
pub const requiredFlacCommentMetadataBytes =
    flac.requiredCommentMetadataBytes;
pub const requiredFlacFrameStorageBytes =
    flac.requiredFrameStorageBytes;
pub const requiredFlacFileWriterMetadataBytes =
    flac.requiredFileWriterMetadataBytes;
pub const requiredFlacFileReaderMetadataBytes =
    flac.requiredFileReaderMetadataBytes;
pub const requiredFlacPendingSamples =
    flac.requiredPendingSamples;
pub const writeInterleavedFlacFile = flac.writeInterleavedFile;
pub const writeInterleavedFlacFileWithComments =
    flac.writeInterleavedFileWithComments;
pub const writeInterleavedFlacFileWithMetadata =
    flac.writeInterleavedFileWithMetadata;
pub const OggFilePacketReader = ogg.FilePacketReader;
pub const OggFilePageReader = ogg.FilePageReader;
pub const OggFileWriter = ogg.FileWriter;
pub const OggPacket = ogg.Packet;
pub const OggPacketIterator = ogg.PacketIterator;
pub const OggPage = ogg.Page;
pub const OggPageIterator = ogg.PageIterator;
pub const OggStreamWriter = ogg.StreamWriter;
pub const maximum_ogg_page_body_bytes =
    ogg.maximum_page_body_bytes;
pub const maximum_ogg_page_bytes = ogg.maximum_page_bytes;
pub const maximum_ogg_page_segments = ogg.maximum_page_segments;
pub const analyzeVorbisPcmBlock = ogg.analyzeVorbisPcmBlock;
pub const analyzeVorbisAudioPsychoacoustics =
    ogg.analyzeVorbisAudioPsychoacoustics;
pub const analyzeVorbisPsychoacoustics =
    ogg.analyzeVorbisPsychoacoustics;
pub const allocateVorbisResidueBitBudgets =
    ogg.allocateVorbisResidueBitBudgets;
pub const applyVorbisFloor = ogg.applyVorbisFloor;
pub const buildVorbisFileSeekIndex = ogg.buildVorbisFileSeekIndex;
pub const buildVorbisSeekIndex = ogg.buildVorbisSeekIndex;
pub const encodeVorbisCommentPacket = ogg.encodeVorbisCommentPacket;
pub const encodeVorbisIdentificationPacket =
    ogg.encodeVorbisIdentificationPacket;
pub const encodeVorbisAudioPacket = ogg.encodeVorbisAudioPacket;
pub const encodeVorbisPcmPacketTrial =
    ogg.encodeVorbisPcmPacketTrial;
pub const encodeVorbisPcmPacket = ogg.encodeVorbisPcmPacket;
pub const encodeVorbisSetupPacket = ogg.encodeVorbisSetupPacket;
pub const evaluateVorbisRateDistortion =
    ogg.evaluateVorbisRateDistortion;
pub const extractVorbisPcmBlock = ogg.extractVorbisPcmBlock;
pub const findVorbisSeekPoint = ogg.findVorbisSeekPoint;
pub const fitVorbisFloorOne = ogg.fitVorbisFloorOne;
pub const fitVorbisAudioFloorOne = ogg.fitVorbisAudioFloorOne;
pub const forwardCoupleVorbisChannels =
    ogg.forwardCoupleVorbisChannels;
pub const forwardCoupleVorbisNoiseThresholds =
    ogg.forwardCoupleVorbisNoiseThresholds;
pub const measureVorbisAudioPacketFixedCost =
    ogg.measureVorbisAudioPacketFixedCost;
pub const normalizeVorbisResidue = ogg.normalizeVorbisResidue;
pub const normalizeVorbisNoiseThresholds =
    ogg.normalizeVorbisNoiseThresholds;
pub const parseVorbisAudioPacketHeader =
    ogg.parseVorbisAudioPacketHeader;
pub const planVorbisEncodingBlock = ogg.planVorbisEncodingBlock;
pub const parseVorbisSetup = ogg.parseVorbisSetup;
pub const prepareVorbisAudioResidue =
    ogg.prepareVorbisAudioResidue;
pub const quantizeVorbisResidue = ogg.quantizeVorbisResidue;
pub const quantizeVorbisResidueAdaptive =
    ogg.quantizeVorbisResidueAdaptive;
pub const quantizeVorbisAudioResiduesAdaptive =
    ogg.quantizeVorbisAudioResiduesAdaptive;
pub const quantizeVorbisVector = ogg.quantizeVorbisVector;
pub const quantizeVorbisVectors = ogg.quantizeVorbisVectors;
pub const inverseCoupleVorbisChannels =
    ogg.inverseCoupleVorbisChannels;
pub const requiredVorbisCouplingScratch =
    ogg.requiredVorbisCouplingScratch;
pub const requiredVorbisCommentPacketBytes =
    ogg.requiredVorbisCommentPacketBytes;
pub const requiredVorbisAudioPacketScratch =
    ogg.requiredVorbisAudioPacketScratch;
pub const requiredVorbisResidueClassifications =
    ogg.requiredVorbisResidueClassifications;
pub const requiredVorbisResidueQuantizationScratch =
    ogg.requiredVorbisResidueQuantizationScratch;
pub const requiredVorbisResidueQuantizationEntries =
    ogg.requiredVorbisResidueQuantizationEntries;
pub const requiredVorbisAudioPacketBytes =
    ogg.requiredVorbisAudioPacketBytes;
pub const requiredVorbisAudioFloorOneStorage =
    ogg.requiredVorbisAudioFloorOneStorage;
pub const requiredVorbisAudioResiduePreparationStorage =
    ogg.requiredVorbisAudioResiduePreparationStorage;
pub const requiredVorbisAudioResidueQuantizationStorage =
    ogg.requiredVorbisAudioResidueQuantizationStorage;
pub const requiredVorbisAudioPsychoacousticStorage =
    ogg.requiredVorbisAudioPsychoacousticStorage;
pub const requiredVorbisPcmPacketEncodingStorage =
    ogg.requiredVorbisPcmPacketEncodingStorage;
pub const requiredVorbisSetupPacketBytes =
    ogg.requiredVorbisSetupPacketBytes;
pub const requiredVorbisFileSeekPoints =
    ogg.requiredVorbisFileSeekPoints;
pub const requiredVorbisSeekPoints = ogg.requiredVorbisSeekPoints;
pub const selectVorbisEncodingMode = ogg.selectVorbisEncodingMode;
pub const synthesizeVorbisFloorZero = ogg.synthesizeVorbisFloorZero;
pub const synthesizeVorbisFloorOne = ogg.synthesizeVorbisFloorOne;
pub const synthesizeVorbisWindow = ogg.synthesizeVorbisWindow;
pub const validateVorbisSetup = ogg.validateVorbisSetup;
pub const VorbisAudioPacketDecoder = ogg.VorbisAudioPacketDecoder;
pub const VorbisAudioPacketHeader = ogg.VorbisAudioPacketHeader;
pub const VorbisAudioPacketResult = ogg.VorbisAudioPacketResult;
pub const VorbisAudioPacketEncoding = ogg.VorbisAudioPacketEncoding;
pub const VorbisAudioPacketEncodingResult =
    ogg.VorbisAudioPacketEncodingResult;
pub const VorbisAudioPacketFixedCost =
    ogg.VorbisAudioPacketFixedCost;
pub const VorbisAudioPacketPrefixEncoding =
    ogg.VorbisAudioPacketPrefixEncoding;
pub const VorbisAudioPacketScratch = ogg.VorbisAudioPacketScratch;
pub const VorbisAudioPacketScratchRequirements =
    ogg.VorbisAudioPacketScratchRequirements;
pub const VorbisAdaptiveResidueConfig =
    ogg.VorbisAdaptiveResidueConfig;
pub const VorbisAdaptiveResidueQuantization =
    ogg.VorbisAdaptiveResidueQuantization;
pub const VorbisAdaptiveResidueScratch =
    ogg.VorbisAdaptiveResidueScratch;
pub const VorbisBitReservoir = ogg.VorbisBitReservoir;
pub const VorbisCodebook = ogg.VorbisCodebook;
pub const VorbisCodebookEntry = ogg.VorbisCodebookEntry;
pub const VorbisChannelOverlapAdd = ogg.VorbisChannelOverlapAdd;
pub const VorbisComment = ogg.VorbisComment;
pub const VorbisCommentIterator = ogg.VorbisCommentIterator;
pub const VorbisCouplingStep = ogg.VorbisCouplingStep;
pub const VorbisFloor = ogg.VorbisFloor;
pub const VorbisFloorOneEncoding = ogg.VorbisFloorOneEncoding;
pub const VorbisFloorOneFit = ogg.VorbisFloorOneFit;
pub const VorbisFloorOne = ogg.VorbisFloorOne;
pub const VorbisAudioFloorOnePlan = ogg.VorbisAudioFloorOnePlan;
pub const VorbisAudioFloorOneScratch =
    ogg.VorbisAudioFloorOneScratch;
pub const VorbisAudioFloorOneStorage =
    ogg.VorbisAudioFloorOneStorage;
pub const VorbisAudioFloorOneStorageRequirements =
    ogg.VorbisAudioFloorOneStorageRequirements;
pub const VorbisAudioResiduePreparationPlan =
    ogg.VorbisAudioResiduePreparationPlan;
pub const VorbisAudioResiduePreparationScratch =
    ogg.VorbisAudioResiduePreparationScratch;
pub const VorbisAudioResiduePreparationStorage =
    ogg.VorbisAudioResiduePreparationStorage;
pub const VorbisAudioResiduePreparationStorageRequirements =
    ogg.VorbisAudioResiduePreparationStorageRequirements;
pub const VorbisAudioResidueQuantizationConfig =
    ogg.VorbisAudioResidueQuantizationConfig;
pub const VorbisAudioResidueQuantizationPlan =
    ogg.VorbisAudioResidueQuantizationPlan;
pub const VorbisAudioResidueQuantizationScratch =
    ogg.VorbisAudioResidueQuantizationScratch;
pub const VorbisAudioResidueQuantizationStorage =
    ogg.VorbisAudioResidueQuantizationStorage;
pub const VorbisAudioResidueQuantizationStorageRequirements =
    ogg.VorbisAudioResidueQuantizationStorageRequirements;
pub const VorbisAudioResidueSubmapResult =
    ogg.VorbisAudioResidueSubmapResult;
pub const VorbisAudioPsychoacousticPlan =
    ogg.VorbisAudioPsychoacousticPlan;
pub const VorbisAudioPsychoacousticScratch =
    ogg.VorbisAudioPsychoacousticScratch;
pub const VorbisAudioPsychoacousticStorage =
    ogg.VorbisAudioPsychoacousticStorage;
pub const VorbisAudioPsychoacousticStorageRequirements =
    ogg.VorbisAudioPsychoacousticStorageRequirements;
pub const VorbisFloorOneClass = ogg.VorbisFloorOneClass;
pub const VorbisFloorOnePacket = ogg.VorbisFloorOnePacket;
pub const VorbisFloorZero = ogg.VorbisFloorZero;
pub const VorbisFloorZeroPacket = ogg.VorbisFloorZeroPacket;
pub const VorbisFloorZeroEncoding = ogg.VorbisFloorZeroEncoding;
pub const VorbisFloorPacketEncoding = ogg.VorbisFloorPacketEncoding;
pub const VorbisForwardMdct = ogg.VorbisForwardMdct;
pub const VorbisGranuleRange = ogg.VorbisGranuleRange;
pub const VorbisGranuleTracker = ogg.VorbisGranuleTracker;
pub const VorbisHeaders = ogg.VorbisHeaders;
pub const VorbisHuffmanNode = ogg.VorbisHuffmanNode;
pub const VorbisIdentification = ogg.VorbisIdentification;
pub const VorbisInverseMdct = ogg.VorbisInverseMdct;
pub const VorbisMode = ogg.VorbisMode;
pub const VorbisMapping = ogg.VorbisMapping;
pub const VorbisOverlapAdd = ogg.VorbisOverlapAdd;
pub const VorbisPacketLocation = ogg.VorbisPacketLocation;
pub const VorbisPacketBitBudget = ogg.VorbisPacketBitBudget;
pub const VorbisPacketReader = ogg.VorbisPacketReader;
pub const VorbisPacketWriter = ogg.VorbisPacketWriter;
pub const VorbisPcmBlockAnalysis = ogg.VorbisPcmBlockAnalysis;
pub const VorbisPcmBlockAnalysisConfig =
    ogg.VorbisPcmBlockAnalysisConfig;
pub const VorbisPcmBlockClassification =
    ogg.VorbisPcmBlockClassification;
pub const VorbisPcmBlockClassifier =
    ogg.VorbisPcmBlockClassifier;
pub const VorbisPcmBlockClassifierConfig =
    ogg.VorbisPcmBlockClassifierConfig;
pub const VorbisPcmBlockLookahead = ogg.VorbisPcmBlockLookahead;
pub const VorbisPcmBlockTransform = ogg.VorbisPcmBlockTransform;
pub const VorbisPcmFrameAnalysisPlan =
    ogg.VorbisPcmFrameAnalysisPlan;
pub const VorbisPcmFrameAnalysisScratch =
    ogg.VorbisPcmFrameAnalysisScratch;
pub const VorbisPcmFrameAnalysisStorage =
    ogg.VorbisPcmFrameAnalysisStorage;
pub const VorbisPcmFrameAnalysisStorageRequirements =
    ogg.VorbisPcmFrameAnalysisStorageRequirements;
pub const VorbisPcmFrameAnalyzer = ogg.VorbisPcmFrameAnalyzer;
pub const VorbisPcmFramePlan = ogg.VorbisPcmFramePlan;
pub const VorbisPcmFramePlanner = ogg.VorbisPcmFramePlanner;
pub const VorbisPcmPacketCommit = ogg.VorbisPcmPacketCommit;
pub const VorbisPcmPacketEncodingScratch =
    ogg.VorbisPcmPacketEncodingScratch;
pub const VorbisPcmPacketEncodingStorage =
    ogg.VorbisPcmPacketEncodingStorage;
pub const VorbisPcmPacketEncodingStorageRequirements =
    ogg.VorbisPcmPacketEncodingStorageRequirements;
pub const VorbisPcmPacketEncodingTrial =
    ogg.VorbisPcmPacketEncodingTrial;
pub const VorbisPcmPacketOrchestrationScratch =
    ogg.VorbisPcmPacketOrchestrationScratch;
pub const VorbisPcmPacketPlan = ogg.VorbisPcmPacketPlan;
pub const VorbisPcmPacketSequence = ogg.VorbisPcmPacketSequence;
pub const VorbisPcmPacketSequenceConfig =
    ogg.VorbisPcmPacketSequenceConfig;
pub const VorbisPcmSeekCursor = ogg.VorbisPcmSeekCursor;
pub const VorbisPcmStreamDecoder = ogg.VorbisPcmStreamDecoder;
pub const VorbisPcmStreamResult = ogg.VorbisPcmStreamResult;
pub const VorbisPcmStreamScratch = ogg.VorbisPcmStreamScratch;
pub const VorbisPsychoacousticAnalysis =
    ogg.VorbisPsychoacousticAnalysis;
pub const VorbisPsychoacousticConfig =
    ogg.VorbisPsychoacousticConfig;
pub const VorbisRateCommit = ogg.VorbisRateCommit;
pub const VorbisRateControlConfig = ogg.VorbisRateControlConfig;
pub const VorbisRateDistortion = ogg.VorbisRateDistortion;
pub const VorbisVectorBatchQuantization =
    ogg.VorbisVectorBatchQuantization;
pub const VorbisVectorQuantization = ogg.VorbisVectorQuantization;
pub const VorbisResidue = ogg.VorbisResidue;
pub const VorbisResidueEncoding = ogg.VorbisResidueEncoding;
pub const VorbisResidueKind = ogg.VorbisResidueKind;
pub const VorbisResidueBitAllocation =
    ogg.VorbisResidueBitAllocation;
pub const VorbisResiduePacket = ogg.VorbisResiduePacket;
pub const VorbisResidueQuantization =
    ogg.VorbisResidueQuantization;
pub const VorbisResidueQuantizationScratch =
    ogg.VorbisResidueQuantizationScratch;
pub const VorbisResidueQuantizationScratchRequirements =
    ogg.VorbisResidueQuantizationScratchRequirements;
pub const VorbisSetup = ogg.VorbisSetup;
pub const VorbisSetupStorage = ogg.VorbisSetupStorage;
pub const VorbisSetupSummary = ogg.VorbisSetupSummary;
pub const VorbisSeekPoint = ogg.VorbisSeekPoint;
pub const VorbisSubmap = ogg.VorbisSubmap;
pub const VorbisWindowPlan = ogg.VorbisWindowPlan;
pub const Flanger = flanger.Flanger;
pub const FlangerConfig = flanger.Config;
pub const BlockProcessor = fixture_runner.BlockProcessor;
pub const KernelBackend = kernel_dispatch.Backend;
pub const BufferProcessorDispatcher =
    kernel_dispatch.BufferProcessorDispatcher;
pub const KernelDispatcher = kernel_dispatch.Dispatcher;
pub const KernelFeatures = kernel_dispatch.Features;
pub const InterSampleLimiter = inter_sample_limiter.InterSampleLimiter;
pub const InterSampleLimiterConfig = inter_sample_limiter.Config;
pub const IxmlMetadata = ixml.Metadata;
pub const IxmlBext = ixml.Bext;
pub const IxmlFileSet = ixml.FileSet;
pub const IxmlHistory = ixml.History;
pub const IxmlLocation = ixml.Location;
pub const IxmlLocationGps = ixml.LocationGps;
pub const IxmlLoudness = ixml.Loudness;
pub const IxmlParseStorage = ixml.ParseStorage;
pub const IxmlRatio = ixml.Ratio;
pub const IxmlRequirements = ixml.Requirements;
pub const IxmlSpeed = ixml.Speed;
pub const IxmlSyncPoint = ixml.SyncPoint;
pub const IxmlSyncPointType = ixml.SyncPointType;
pub const IxmlTimecodeFlag = ixml.TimecodeFlag;
pub const IxmlTrack = ixml.Track;
pub const IxmlUser = ixml.User;
pub const IxmlView = ixml.View;
pub const encodeIxmlMetadata = ixml.encode;
pub const parseIxmlMetadata = ixml.parse;
pub const requiredIxmlMetadataBytes = ixml.requiredBytes;
pub const requiredIxmlParseStorage = ixml.requirements;
pub const LadderConfig = ladder.Config;
pub const LadderFilter = ladder.LadderFilter;
pub const LadderMode = ladder.Mode;
pub const LinkwitzRileyConfig = linkwitz_riley.Config;
pub const LinkwitzRileyFilter = linkwitz_riley.LinkwitzRileyFilter;
pub const LinkwitzRileySplit = linkwitz_riley.Split;
pub const LogRampedValue = log_ramp.LogRampedValue;
pub const LookupTable = lookup_table.LookupTable;
pub const Matrix = matrix.Matrix;
pub const DynamicMatrix = matrix.DynamicMatrix;
pub const DynamicLuDecomposition = matrix.DynamicLuDecomposition;
pub const DynamicQrDecomposition = matrix.DynamicQrDecomposition;
pub const DynamicSvdDecomposition = matrix.DynamicSvdDecomposition;
pub const Vector = matrix.Vector;
pub const LuDecomposition = matrix.LuDecomposition;
pub const QrDecomposition = matrix.QrDecomposition;
pub const SvdDecomposition = matrix.SvdDecomposition;
pub const MixedOversampler = mixed_oversampling.Oversampler;
pub const MixedMultichannelOversampler =
    mixed_oversampling.MultichannelOversampler;
pub const MixedOversamplingFilterSpec =
    mixed_oversampling.FilterSpec;
pub const MixedOversamplingDirectionalConfig =
    mixed_oversampling.DirectionalConfig;
pub const MixedOversamplingStageConfig =
    mixed_oversampling.StageConfig;
pub const MixedOversamplingOptions = mixed_oversampling.Options;
pub const ModulatedDelay = modulated_delay.Processor;
pub const ModulatedDelayConfig = modulated_delay.Config;
pub const ModulationNoteDivision = modulation_rate.NoteDivision;
pub const ModulationRateSmoother = modulation_rate.RateSmoother;
pub const modulationRateHz = modulation_rate.rateHz;
pub const modulationRateHzForBeats = modulation_rate.rateHzForBeats;
pub const modulationTempoFromTransport =
    modulation_rate.tempoFromTransport;
pub const modulationPhaseFromTransport =
    modulation_rate.phaseFromTransport;
pub const TwoBandCompressor = multiband_dynamics.TwoBandCompressor;
pub const TwoBandCompressorConfig = multiband_dynamics.Config;
pub const MultibandCompressor = multiband_dynamics.MultibandCompressor;
pub const MultibandCompressorConfig =
    multiband_dynamics.MultibandConfig;
pub const LinkedMultibandCompressor =
    multiband_dynamics.LinkedMultibandCompressor;
pub const maximum_multiband_compressor_bands =
    multiband_dynamics.maximum_bands;
pub const maximum_linked_multiband_channels =
    multiband_dynamics.maximum_linked_channels;
pub const MultichannelOversampler =
    multichannel_oversampling.MultichannelOversampler;
pub const MultichannelPolyphaseIirOversampler =
    multichannel_polyphase_iir_oversampling.MultichannelOversampler;
pub const RuntimeMultichannelPolyphaseIirOversampler =
    multichannel_polyphase_iir_oversampling.RuntimeMultichannelOversampler;
pub const Oscillator = oscillator.Oscillator;
pub const OscillatorWaveform = oscillator.Waveform;
pub const Oversampler = oversampling.Oversampler;
pub const DummyOversampler = oversampling.DummyOversampler;
pub const SelectableOversampler = oversampling.SelectableOversampler;
pub const OversamplingSelection = oversampling.Selection;
pub const Phase = phase.Phase;
pub const StereoPanner = panner.StereoPanner;
pub const PannerRule = panner.Rule;
pub const PcmDither = pcm_dither.PcmDither;
pub const PcmDitherConfig = pcm_dither.Config;
pub const PcmDitherMode = pcm_dither.Mode;
pub const maximum_pcm_dither_channels =
    pcm_dither.maximum_channels;
pub const Phaser = phaser.Phaser;
pub const PhaserConfig = phaser.Config;
pub const ProcessorChain = processor_chain.ProcessorChain;
pub const ProcessContextNonReplacing = process_context.ProcessContextNonReplacing;
pub const ProcessContextReplacing = process_context.ProcessContextReplacing;
pub const ProcessSpec = process_context.ProcessSpec;
pub const ProcessorDuplicator = processor_duplicator.ProcessorDuplicator;
pub const Polynomial = polynomial.Polynomial;
pub const PolyphaseFirBank = polyphase_fir.Bank;
pub const PolyphaseAllpassDesign = polyphase_iir.Design;
pub const PolyphaseAllpassDesigner = polyphase_iir.Designer;
pub const PolyphaseAllpassHalfBandFilter =
    polyphase_iir.HalfBandFilter;
pub const PolyphaseAllpassSplit = polyphase_iir.Split;
pub const maximum_polyphase_allpass_sections =
    polyphase_iir.maximum_sections;
pub const PolyphaseIirOversampler =
    polyphase_iir_oversampling.Oversampler;
pub const RuntimePolyphaseIirOversampler =
    polyphase_iir_oversampling.RuntimeOversampler;
pub const PolyphaseIirOversamplingConfig =
    polyphase_iir_oversampling.Config;
pub const PolyphaseIirOversamplingOptions =
    polyphase_iir_oversampling.Options;
pub const ResamplerConfig = resampler.Config;
pub const StreamingResampler = resampler.StreamingResampler;
pub const maximum_resampler_rate_correction_ppm =
    resampler.maximum_rate_correction_ppm;
pub const Reverb = reverb.Reverb;
pub const ReverbConfig = reverb.Config;
pub const RealtimeSnapshotPublisher = realtime_snapshot.Publisher;
pub const RealtimeReferencePublisher =
    realtime_snapshot.ReferencePublisher;
pub const Rf64Encoding = rf64_writer.Encoding;
pub const Rf64FileWriter = rf64_writer.FileWriter;
pub const Rf64Spec = rf64_writer.Spec;
pub const requiredRf64Bytes = rf64_writer.requiredBytes;
pub const Bw64FileWriter = rf64_writer.FileWriter;
pub const Bw64Encoding = rf64_writer.Encoding;
pub const Bw64Spec = rf64_writer.Spec;
pub const makeBw64Header = rf64_writer.makeBw64Header;
pub const requiredBw64Bytes = rf64_writer.requiredBytes;
pub const ReverbStereoSample = reverb.StereoSample;
pub const SharedProcessorDuplicator =
    shared_processor_duplicator.SharedProcessorDuplicator;
pub const SimdRegister = simd_register.Register;
pub const NativeSimdRegister = simd_register.NativeRegister;
pub const ComplexSimdRegister = simd_register.ComplexRegister;
pub const NativeComplexSimdRegister = simd_register.NativeComplexRegister;
pub const nativeSimdLaneCount = simd_register.nativeLaneCount;
pub const LinearSmoothedValue = smoothed_value.Linear;
pub const MultiplicativeSmoothedValue = smoothed_value.Multiplicative;
pub const StateVariableConfig = state_variable.Config;
pub const StateVariableFilter = state_variable.StateVariableFilter;
pub const StateVariableKind = state_variable.Kind;
pub const StereoModulation = stereo_modulation.StereoProcessor;
pub const Bias = gain_bias.Bias;
pub const Gain = gain_bias.Gain;
pub const WindowKind = window.Kind;
pub const WindowNormalization = window.Normalization;
pub const WaveShaper = waveshaper.WaveShaper;
pub const WaveShaperConfig = waveshaper.Config;
pub const WaveShaperKind = waveshaper.Kind;
pub const Vibrato = vibrato.Vibrato;
pub const VibratoConfig = vibrato.Config;
pub const WavEncoding = wav_writer.Encoding;
pub const WavSpec = wav_writer.Spec;
pub const WavWriter = wav_writer.Writer;
pub const WavFileWriter = wav_writer.FileWriter;
pub const Wave64Encoding = wave64_writer.Encoding;
pub const Wave64FileWriter = wave64_writer.FileWriter;
pub const Wave64Metadata = wave64_metadata.Metadata;
pub const Wave64Spec = wave64_writer.Spec;
pub const requiredWave64Bytes = wave64_writer.requiredBytes;
pub const requiredWave64BytesWithMetadata =
    wave64_writer.requiredBytesWithMetadata;
pub const requiredWave64MetadataBytes = wave64_metadata.requiredBytes;
pub const requiredWavBytes = wav_writer.requiredBytes;
pub const writeInterleavedWav = wav_writer.writeInterleaved;
pub const writeInterleavedWavDithered =
    wav_writer.writeInterleavedDithered;
pub const shapeSample = waveshaper.shape;
pub const besselI0 = special_functions.besselI0;
pub const ellipticIntegralK = special_functions.ellipticIntegralK;
pub const ellipticIntegralF = special_functions.ellipticIntegralF;
pub const jacobiElliptic = special_functions.jacobiElliptic;
pub const jacobiEllipticFunction =
    special_functions.jacobiEllipticFunction;
pub const complexJacobiElliptic = special_functions.complexJacobiElliptic;
pub const complexJacobiEllipticFunction =
    special_functions.complexJacobiEllipticFunction;
pub const complexJacobiCd = special_functions.complexJacobiCd;
pub const inverseJacobiSn = special_functions.inverseJacobiSn;
pub const inverseJacobiCn = special_functions.inverseJacobiCn;
pub const inverseJacobiDn = special_functions.inverseJacobiDn;
pub const inverseComplexJacobiSn =
    special_functions.inverseComplexJacobiSn;
pub const JacobiValues = special_functions.JacobiValues;
pub const ComplexJacobiValues = special_functions.ComplexJacobiValues;
pub const JacobiFunction = special_functions.JacobiFunction;
pub const applyKaiserWindow = window.applyKaiser;
pub const applyWindow = window.apply;
pub const fillKaiserWindow = window.fillKaiser;
pub const fillWindow = window.fill;

test {
    _ = aiff_writer;
    _ = adm_binaural;
    _ = adm_render;
    _ = adm_hoa_decoder;
    _ = adm_hoa_matrix;
    _ = hrtf;
    _ = adm_diffuse;
    _ = adm_direct_speaker_mapping;
    _ = audio_block;
    _ = audio_file_reader;
    _ = audio_metadata;
    _ = ballistics;
    _ = biquad;
    _ = broadcast_metadata;
    _ = butterworth_design;
    _ = chorus;
    _ = chebyshev2_design;
    _ = chebyshev_design;
    _ = convolution;
    _ = delay;
    _ = denormals;
    _ = dry_wet;
    _ = dynamics;
    _ = elliptic_design;
    _ = equiripple_design;
    _ = fft;
    _ = fir;
    _ = fir_design;
    _ = first_order_tpt;
    _ = fixed_rate;
    _ = fast_math;
    _ = file_writer_faults;
    _ = flac;
    _ = flanger;
    _ = fixture_runner;
    _ = kernel_dispatch;
    _ = inter_sample_limiter;
    _ = id3;
    _ = ixml;
    _ = ladder;
    _ = linkwitz_riley;
    _ = log_ramp;
    _ = lookup_table;
    _ = matrix;
    _ = mixed_oversampling;
    _ = mp3;
    _ = modulated_delay;
    _ = modulation_rate;
    _ = multiband_dynamics;
    _ = multichannel_oversampling;
    _ = ogg;
    _ = oscillator;
    _ = oversampling;
    _ = panner;
    _ = phase;
    _ = phaser;
    _ = processor_chain;
    _ = process_context;
    _ = processor_duplicator;
    _ = polynomial;
    _ = polyphase_fir;
    _ = resampler;
    _ = reverb;
    _ = realtime_snapshot;
    _ = rf64_writer;
    _ = shared_processor_duplicator;
    _ = simd_register;
    _ = smoothed_value;
    _ = state_variable;
    _ = stereo_modulation;
    _ = special_functions;
    _ = gain_bias;
    _ = waveshaper;
    _ = vibrato;
    _ = wav_writer;
    _ = wave64_writer;
    _ = wave64_metadata;
    _ = window;
}
