# VST3 Interface Inventory

SDK source: Steinberg VST3 SDK `v3.8.0_build_66`, commit `9fad9770f2ae8542ab1a548a68c1ad1ac690abe0`.

This inventory covers `pluginterfaces/base`, `pluginterfaces/vst`, and `pluginterfaces/gui` interfaces that declare an IID with `DECLARE_CLASS_IID`. Priorities are initial planning values:

- P0: required for the first valid gain plugin
- P1: required for typical effects, instruments, automation, state, and generic editors
- P2: advanced or host-integration features
- P3: wrappers, legacy bridges, tests, or rarely needed interfaces

| Interface | SDK path | TUID source | Inheritance | Side | Priority |
|---|---|---|---|---|---|
| `FUnknown` | `pluginterfaces/base/funknown.h` | `0x00000000, 0x00000000, 0xC0000000, 0x00000046` | root | both | P0 |
| `IPluginBase` | `pluginterfaces/base/ipluginbase.h` | `0x22888DDB, 0x156E45AE, 0x8358B348, 0x08190625` | `FUnknown` | plugin | P0 |
| `IPluginFactory` | `pluginterfaces/base/ipluginbase.h` | `0x7A4D811C, 0x52114A1F, 0xAED9D2EE, 0x0B43BF9F` | `FUnknown` | plugin | P0 |
| `IPluginFactory2` | `pluginterfaces/base/ipluginbase.h` | `0x0007B650, 0xF24B4C0B, 0xA464EDB9, 0xF00B2ABB` | `IPluginFactory` | plugin | P0 |
| `IPluginFactory3` | `pluginterfaces/base/ipluginbase.h` | `0x4555A2AB, 0xC1234E57, 0x9B122910, 0x36878931` | `IPluginFactory2` | plugin | P0 |
| `IBStream` | `pluginterfaces/base/ibstream.h` | `0xC3BF6EA2, 0x30994752, 0x9B6BF990, 0x1EE33E9B` | `FUnknown` | both | P0 |
| `ISizeableStream` | `pluginterfaces/base/ibstream.h` | `0x04F9549E, 0xE02F4E6E, 0x87E86A87, 0x47F4E17F` | `FUnknown` | host | P1 |
| `IComponent` | `pluginterfaces/vst/ivstcomponent.h` | `0xE831FF31, 0xF2D54301, 0x928EBBEE, 0x25697802` | `IPluginBase` | plugin | P0 |
| `IAudioProcessor` | `pluginterfaces/vst/ivstaudioprocessor.h` | `0x42043F99, 0xB7DA453C, 0xA569E79D, 0x9AAEC33D` | `FUnknown` | plugin | P0 |
| `IEditController` | `pluginterfaces/vst/ivsteditcontroller.h` | `0xDCD7BBE3, 0x7742448D, 0xA874AACC, 0x979C759E` | `IPluginBase` | plugin | P0 |
| `IEditController2` | `pluginterfaces/vst/ivsteditcontroller.h` | `0x7F4EFE59, 0xF3204967, 0xAC27A3AE, 0xAFB63038` | `FUnknown` | plugin | P1 |
| `IComponentHandler` | `pluginterfaces/vst/ivsteditcontroller.h` | `0x93A0BEA3, 0x0BD045DB, 0x8E890B0C, 0xC1E46AC6` | `FUnknown` | host | P0 |
| `IComponentHandler2` | `pluginterfaces/vst/ivsteditcontroller.h` | `0xF040B4B3, 0xA36045EC, 0xABCDC045, 0xB4D5A2CC` | `FUnknown` | host | P1 |
| `IComponentHandler3` | `pluginterfaces/vst/ivstcontextmenu.h` | `0x69F11617, 0xD26B400D, 0xA4B6B964, 0x7B6EBBAB` | `FUnknown` | host | P2 |
| `IComponentHandlerBusActivation` | `pluginterfaces/vst/ivsteditcontroller.h` | `0x067D02C1, 0x5B4E274D, 0xA92D90FD, 0x6EAF7240` | `FUnknown` | host | P2 |
| `IComponentHandlerSystemTime` | `pluginterfaces/vst/ivsteditcontroller.h` | `0xF9E53056, 0xD1554CD5, 0xB7695E1B, 0x7B0F7745` | `FUnknown` | host | P2 |
| `IParameterChanges` | `pluginterfaces/vst/ivstparameterchanges.h` | `0xA4779663, 0x0BB64A56, 0xB44384A8, 0x466FEB9D` | `FUnknown` | host | P0 |
| `IParamValueQueue` | `pluginterfaces/vst/ivstparameterchanges.h` | `0x01263A18, 0xED074F6F, 0x98C9D356, 0x4686F9BA` | `FUnknown` | host | P0 |
| `IEventList` | `pluginterfaces/vst/ivstevents.h` | `0x3A2C4214, 0x346349FE, 0xB2C4F397, 0xB9695A44` | `FUnknown` | host | P0 |
| `IConnectionPoint` | `pluginterfaces/vst/ivstmessage.h` | `0x70A4156F, 0x6E6E4026, 0x989148BF, 0xAA60D8D1` | `FUnknown` | both | P0 |
| `IMessage` | `pluginterfaces/vst/ivstmessage.h` | `0x936F033B, 0xC6C047DB, 0xBB0882F8, 0x13C1E613` | `FUnknown` | both | P0 |
| `IAttributeList` | `pluginterfaces/vst/ivstattributes.h` | `0x1E5F0AEB, 0xCC7F4533, 0xA2544011, 0x38AD5EE4` | `FUnknown` | host | P0 |
| `IHostApplication` | `pluginterfaces/vst/ivsthostapplication.h` | `0x58E595CC, 0xDB2D4969, 0x8B6AAF8C, 0x36A664E5` | `FUnknown` | host | P0 |
| `IPlugView` | `pluginterfaces/gui/iplugview.h` | `0x5BC32507, 0xD06049EA, 0xA6151B52, 0x2B755B29` | `FUnknown` | plugin | P1 |
| `IPlugFrame` | `pluginterfaces/gui/iplugview.h` | `0x367FAF01, 0xAFA94693, 0x8D4DA2A0, 0xED0882A3` | `FUnknown` | host | P1 |
| `IPlugViewContentScaleSupport` | `pluginterfaces/gui/iplugviewcontentscalesupport.h` | `0x65ED9690, 0x8AC44525, 0x8AADEF7A, 0x72EA703F` | `FUnknown` | plugin | P1 |
| `IUnitInfo` | `pluginterfaces/vst/ivstunits.h` | `0x3D4BD6B5, 0x913A4FD2, 0xA886E768, 0xA5EB92C1` | `FUnknown` | plugin | P1 |
| `IProgramListData` | `pluginterfaces/vst/ivstunits.h` | `0x8683B01F, 0x7B354F70, 0xA2651DEC, 0x353AF4FF` | `FUnknown` | plugin | P1 |
| `IUnitData` | `pluginterfaces/vst/ivstunits.h` | `0x6C389611, 0xD391455D, 0xB870B833, 0x94A0EFDD` | `FUnknown` | plugin | P1 |
| `IUnitHandler` | `pluginterfaces/vst/ivstunits.h` | `0x4B5147F8, 0x4654486B, 0x8DAB30BA, 0x163A3C56` | `FUnknown` | host | P1 |
| `IUnitHandler2` | `pluginterfaces/vst/ivstunits.h` | `0xF89F8CDF, 0x699E4BA5, 0x96AAC9A4, 0x81452B01` | `FUnknown` | host | P1 |
| `IMidiMapping` | `pluginterfaces/vst/ivsteditcontroller.h` | `0xDF0FF9F7, 0x49B74669, 0xB63AB732, 0x7ADBF5E5` | `FUnknown` | plugin | P1 |
| `IMidiLearn` | `pluginterfaces/vst/ivstmidilearn.h` | `0x6B2449CC, 0x419740B5, 0xAB3C79DA, 0xC5FE5C86` | `FUnknown` | plugin | P1 |
| `IMidiMapping2` | `pluginterfaces/vst/ivstmidimapping2.h` | `0x6DE14B88, 0x03F94F09, 0xA2552F0F, 0x9326593E` | `FUnknown` | plugin | P1 |
| `IMidiLearn2` | `pluginterfaces/vst/ivstmidimapping2.h` | `0xF07E498A, 0x78864327, 0x8B431CED, 0xA3C553FC` | `FUnknown` | plugin | P1 |
| `INoteExpressionController` | `pluginterfaces/vst/ivstnoteexpression.h` | `0xB7F8F859, 0x41234872, 0x91169581, 0x4F3721A3` | `FUnknown` | plugin | P1 |
| `IKeyswitchController` | `pluginterfaces/vst/ivstnoteexpression.h` | `0x1F2F76D3, 0xBFFB4B96, 0xB99527A5, 0x5EBCCEF4` | `FUnknown` | plugin | P1 |
| `IAudioPresentationLatency` | `pluginterfaces/vst/ivstaudioprocessor.h` | `0x309ECE78, 0xEB7D4fae, 0x8B2225D9, 0x09FD08B6` | `FUnknown` | plugin | P1 |
| `IProcessContextRequirements` | `pluginterfaces/vst/ivstaudioprocessor.h` | `0x2A654303, 0xEF764E3D, 0x95B5FE83, 0x730EF6D0` | `FUnknown` | plugin | P1 |
| `IStreamAttributes` | `pluginterfaces/vst/ivstattributes.h` | `0xD6CE2FFC, 0xEFAF4B8C, 0x9E74F1BB, 0x12DA44B4` | `FUnknown` | host | P2 |
| `IParameterFinder` | `pluginterfaces/vst/ivstplugview.h` | `0x0F618302, 0x215D4587, 0xA512073C, 0x77B9D383` | `FUnknown` | plugin | P2 |
| `IParameterFunctionName` | `pluginterfaces/vst/ivstparameterfunctionname.h` | `0x6D21E1DC, 0x91199D4B, 0xA2A02FEF, 0x6C1AE55C` | `FUnknown` | plugin | P2 |
| `IEditControllerHostEditing` | `pluginterfaces/vst/ivsteditcontroller.h` | `0xC1271208, 0x70594098, 0xB9DD34B3, 0x6BB0195E` | `FUnknown` | plugin | P2 |
| `IPlugInterfaceSupport` | `pluginterfaces/vst/ivstpluginterfacesupport.h` | `0x4FB58B9E, 0x9EAA4E0F, 0xAB361C1C, 0xCCB56FEA` | `FUnknown` | plugin | P2 |
| `IXmlRepresentationController` | `pluginterfaces/vst/ivstrepresentation.h` | `0xA81A0471, 0x48C34DC4, 0xAC30C9E1, 0x3C8393D5` | `FUnknown` | plugin | P2 |
| `IContextMenu` | `pluginterfaces/vst/ivstcontextmenu.h` | `0x2E93C863, 0x0C9C4588, 0x97DBECF5, 0xAD17817D` | `FUnknown` | host | P2 |
| `IContextMenuTarget` | `pluginterfaces/vst/ivstcontextmenu.h` | `0x3CDF2E75, 0x85D34144, 0xBF86D36B, 0xD7C4894D` | `FUnknown` | plugin | P2 |
| `IRemapParamID` | `pluginterfaces/vst/ivstremapparamid.h` | `0x2B88021E, 0x6286B646, 0xB49DF76A, 0x5663061C` | `FUnknown` | plugin | P2 |
| `INoteExpressionPhysicalUIMapping` | `pluginterfaces/vst/ivstphysicalui.h` | `0xB03078FF, 0x94D24AC8, 0x90CCD303, 0xD4133324` | `FUnknown` | plugin | P2 |
| `IInfoListener` | `pluginterfaces/vst/ivstchannelcontextinfo.h` | `0x0F194781, 0x8D984ADA, 0xBBA0C1EF, 0xC011D8D0` | `FUnknown` | host | P2 |
| `IPrefetchableSupport` | `pluginterfaces/vst/ivstprefetchablesupport.h` | `0x8AE54FDA, 0xE93046B9, 0xA28555BC, 0xDC98E21E` | `FUnknown` | plugin | P2 |
| `IAutomationState` | `pluginterfaces/vst/ivstautomationstate.h` | `0xB4E8287F, 0x1BB346AA, 0x83A46667, 0x68937BAB` | `FUnknown` | host | P2 |
| `IDataExchangeHandler` | `pluginterfaces/vst/ivstdataexchange.h` | `0x36D551BD, 0x6FF54F08, 0xB48E830D, 0x8BD5A03B` | `FUnknown` | host | P2 |
| `IDataExchangeReceiver` | `pluginterfaces/vst/ivstdataexchange.h` | `0x45A759DC, 0x84FA4907, 0xABCB6175, 0x2FC786B6` | `FUnknown` | plugin | P2 |
| `IWaylandHost` | `pluginterfaces/gui/iwaylandframe.h` | `0x5E9582EE, 0x86594652, 0xB213678E, 0x7F1A705E` | `FUnknown` | host | P2 |
| `IWaylandFrame` | `pluginterfaces/gui/iwaylandframe.h` | `0x809FAEC6, 0x231C4FFA, 0x98ED046C, 0x6E9E2003` | `FUnknown` | plugin | P2 |
| `IEventHandler` | `pluginterfaces/gui/iplugview.h` | `0x561E65C9, 0x13A0496F, 0x813A2C35, 0x654D7983` | `FUnknown` | host | P3 |
| `ITimerHandler` | `pluginterfaces/gui/iplugview.h` | `0x10BDD94F, 0x41424774, 0x821FAD8F, 0xECA72CA9` | `FUnknown` | host | P3 |
| `IRunLoop` | `pluginterfaces/gui/iplugview.h` | `0x18C35366, 0x97764F1A, 0x9C5B8385, 0x7A871389` | `FUnknown` | host | P3 |
| `IStringResult` | `pluginterfaces/base/istringresult.h` | `0x550798BC, 0x872049DB, 0x84920A15, 0x3B50B7A8` | `FUnknown` | both | P3 |
| `IString` | `pluginterfaces/base/istringresult.h` | `0xF99DB7A3, 0x0FC14821, 0x800B0CF9, 0x8E348EDF` | `FUnknown` | both | P3 |
| `IErrorContext` | `pluginterfaces/base/ierrorcontext.h` | `0x12BCD07B, 0x7C694336, 0xB7DA77C3, 0x444A0CD0` | `FUnknown` | both | P3 |
| `ICloneable` | `pluginterfaces/base/icloneable.h` | `0xD45406B9, 0x3A2D4443, 0x9DAD9BA9, 0x85A1454B` | `FUnknown` | both | P3 |
| `IPersistent` | `pluginterfaces/base/ipersistent.h` | `0xBA1A4637, 0x3C9F46D0, 0xA65DBA0E, 0xB85DA829` | `FUnknown` | both | P3 |
| `IAttributes` | `pluginterfaces/base/ipersistent.h` | `0xFA1E32F9, 0xCA6D46F5, 0xA982F956, 0xB1191B58` | `FUnknown` | both | P3 |
| `IAttributes2` | `pluginterfaces/base/ipersistent.h` | `0x1382126A, 0xFECA4871, 0x97D52A45, 0xB042AE99` | `IAttributes` | both | P3 |
| `IUpdateHandler` | `pluginterfaces/base/iupdatehandler.h` | `0xF5246D56, 0x86544d60, 0xB026AFB5, 0x7B697B37` | `FUnknown` | both | P3 |
| `IDependent` | `pluginterfaces/base/iupdatehandler.h` | `0xF52B7AAE, 0xDE72416d, 0x8AF18ACE, 0x9DD7BD5E` | `FUnknown` | both | P3 |
| `IPluginCompatibility` | `pluginterfaces/base/iplugincompatibility.h` | `0x4AFD4B6A, 0x35D7C240, 0xA5C31414, 0xFB7D15E6` | `FUnknown` | host | P3 |
| `IProgress` | `pluginterfaces/vst/ivsteditcontroller.h` | `0x00C9DC5B, 0x9D904254, 0x91A388C8, 0xB4E91B69` | `FUnknown` | host | P3 |
| `IInterAppAudioHost` | `pluginterfaces/vst/ivstinterappaudio.h` | `0x0CE5743D, 0x68DF415E, 0xAE285BD4, 0xE2CDC8FD` | `FUnknown` | host | P3 |
| `IInterAppAudioConnectionNotification` | `pluginterfaces/vst/ivstinterappaudio.h` | `0x6020C72D, 0x5FC24AA1, 0xB0950DB5, 0xD7D6D5CF` | `FUnknown` | plugin | P3 |
| `IInterAppAudioPresetManager` | `pluginterfaces/vst/ivstinterappaudio.h` | `0xADE6FCC4, 0x46C94E1D, 0xB3B49A80, 0xC93FEFDD` | `FUnknown` | plugin | P3 |
| `IVst3ToVst2Wrapper` | `pluginterfaces/vst/ivsthostapplication.h` | `0x29633AEC, 0x1D1C47E2, 0xBB85B97B, 0xD36EAC61` | `FUnknown` | wrapper | P3 |
| `IVst3ToAUWrapper` | `pluginterfaces/vst/ivsthostapplication.h` | `0xA3B8C6C5, 0xC0954688, 0xB0916F0B, 0xB697AA44` | `FUnknown` | wrapper | P3 |
| `IVst3ToAAXWrapper` | `pluginterfaces/vst/ivsthostapplication.h` | `0x6D319DC6, 0x60C56242, 0xB32C951B, 0x93BEF4C6` | `FUnknown` | wrapper | P3 |
| `IVst3WrapperMPESupport` | `pluginterfaces/vst/ivsthostapplication.h` | `0x44149067, 0x42CF4BF9, 0x8800B750, 0xF7359FE3` | `FUnknown` | wrapper | P3 |
| `ITestPlugProvider` | `pluginterfaces/vst/ivsttestplugprovider.h` | `0x86BE70EE, 0x4E99430F, 0x978F1E6E, 0xD68FB5BA` | `FUnknown` | test | P3 |
| `ITestPlugProvider2` | `pluginterfaces/vst/ivsttestplugprovider.h` | `0xC7C75364, 0x7B8343AC, 0xA4495B0A, 0x3E5A46C7` | `ITestPlugProvider` | test | P3 |

## Translation Status

| Interface group | Status |
|---|---|
| `FUnknown` | Initial translation and C ABI harness complete |
| `IPluginBase` | Initial vtable translation complete |
| `IPluginFactory`, `IPluginFactory2`, `IPluginFactory3` | Initial vtable and struct translation complete |
| `PFactoryInfo`, `PClassInfo`, `PClassInfo2`, `PClassInfoW` | Layout checked against the pinned SDK with `zig build pluginbase-abi` |
| `IBStream`, `ISizeableStream` | Initial vtable translation complete; IIDs and seek constants checked with `zig build ibstream-abi` |
| `IComponent`, `BusInfo`, `RoutingInfo` | Initial vtable and struct translation complete; layout checked against the pinned SDK with `zig build component-abi` |
| `IAudioProcessor`, `IAudioPresentationLatency`, `IProcessContextRequirements` | Initial vtable and struct translation complete; layout checked against the pinned SDK with `zig build audio-processor-abi` |
| `IEditController`, `IComponentHandler`, `IMidiMapping`, and adjacent edit-controller extensions | Initial vtable and struct translation complete; layout checked against the pinned SDK with `zig build edit-controller-abi` |
| `IParameterChanges`, `IParamValueQueue` | Initial vtable translation complete; IIDs checked with `zig build parameter-changes-abi` |
| `IEventList`, `Event`, and event payload structs | Initial vtable and struct translation complete; layout checked against the pinned SDK with `zig build events-abi` |
| `IConnectionPoint`, `IMessage`, `IAttributeList`, `IHostApplication`, and adjacent host/wrapper interfaces | Initial vtable translation complete; IIDs checked with `zig build host-message-abi` |
| `IPlugView`, `IPlugFrame`, `IPlugViewContentScaleSupport`, and Linux run loop interfaces | Initial vtable and struct translation complete; layout checked against the pinned SDK with `zig build plugview-abi` |
| `IUnitInfo`, `IProgramListData`, `IUnitData`, `IUnitHandler`, `IUnitHandler2`, `UnitInfo`, `ProgramListInfo` | Initial vtable and struct translation complete; layout checked against the pinned SDK with `zig build units-abi` |
| `IMidiLearn`, `IMidiMapping2`, `IMidiLearn2`, and MIDI controller mapping structs | Initial vtable and struct translation complete; layout checked against the pinned SDK with `zig build midi-mapping-abi` |
| `INoteExpressionController`, `IKeyswitchController`, `NoteExpressionTypeInfo`, `KeyswitchInfo` | Initial vtable and struct translation complete; layout checked against the pinned SDK with `zig build note-expression-abi` |
| `IPlugInterfaceSupport`, `IPrefetchableSupport`, `IAutomationState` | Initial vtable translation complete; constants and IIDs checked with `zig build capability-state-abi` |
| `IParameterFinder`, `IParameterFunctionName`, `IRemapParamID` | Initial vtable translation complete; constants and IIDs checked with `zig build parameter-helpers-abi` |
| `IComponentHandler3`, `IContextMenu`, `IContextMenuTarget`, `IContextMenuItem` | Initial vtable and struct translation complete; layout checked against the pinned SDK with `zig build context-menu-abi` |

## Phase 2 P0 Seed List

Translate these first:

`FUnknown`, `IPluginBase`, `IPluginFactory`, `IPluginFactory2`, `IPluginFactory3`, `IBStream`, `IComponent`, `IAudioProcessor`, `IEditController`, `IComponentHandler`, `IParameterChanges`, `IParamValueQueue`, `IEventList`, `IConnectionPoint`, `IMessage`, `IAttributeList`, and `IHostApplication`.

## 3.8.0 Additions Tracked Explicitly

The SDK 3.8.0 interfaces `IMidiMapping2`, `IMidiLearn2`, `IWaylandHost`, and `IWaylandFrame` are included above. They should not block the first gain plugin, but they must stay visible so the binding set does not silently target an older SDK surface.
