#define COBJMACROS
#define WIN32_LEAN_AND_MEAN

#include "wasapi_shim.h"

#include <windows.h>

#include <audioclient.h>
#include <avrt.h>
#include <propkeydef.h>
#include <functiondiscoverykeys_devpkey.h>
#include <ks.h>
#include <ksmedia.h>
#include <mmdeviceapi.h>
#include <propvarutil.h>

#include <stdlib.h>
#include <string.h>

struct zv3_wasapi_session {
    wchar_t *input_identifier;
    wchar_t *output_identifier;
    uint32_t sample_bytes;
    double sample_rate;
    uint32_t maximum_frames;
    uint32_t input_channels;
    uint32_t output_channels;
    void *context;
    zv3_wasapi_process_fn process;
    zv3_wasapi_capture_fn capture;
    zv3_wasapi_render_fn render;
    HANDLE ready_event;
    HANDLE stop_event;
    HANDLE capture_event;
    HANDLE render_event;
    HANDLE thread;
    HRESULT start_status;
    volatile LONG64 processed;
    volatile LONG64 callback_failures;
    volatile LONG64 capture_underflows;
    volatile LONG64 capture_overflows;
    volatile LONG64 device_failures;
    IAudioClient *capture_client;
    IAudioClient *render_client;
    IAudioCaptureClient *capture_service;
    IAudioRenderClient *render_service;
    uint32_t render_buffer_frames;
    uint32_t ring_capacity;
    uint32_t ring_read;
    uint32_t ring_write;
    uint32_t ring_count;
    uint8_t *input_planar;
    uint8_t *output_planar;
    uint8_t *capture_ring;
    void **input_views;
    void **output_views;
};

typedef struct {
    IMMNotificationClient base;
    volatile LONG reference_count;
    void *context;
    zv3_wasapi_topology_fn callback;
} notification_client;

struct zv3_wasapi_observer {
    void *context;
    zv3_wasapi_topology_fn callback;
    HANDLE ready_event;
    HANDLE stop_event;
    HANDLE thread;
    HRESULT start_status;
};

typedef struct {
    HRESULT status;
    BOOL uninitialize;
} com_scope;

static const GUID zv3_clsid_mm_device_enumerator = {
    0xbcde0395,
    0xe52f,
    0x467c,
    {0x8e, 0x3d, 0xc4, 0x57, 0x92, 0x91, 0x69, 0x2e},
};

static const GUID zv3_iid_mm_device_enumerator = {
    0xa95664d2,
    0x9614,
    0x4f35,
    {0xa7, 0x46, 0xde, 0x8d, 0xb6, 0x36, 0x17, 0xe6},
};

static const GUID zv3_iid_mm_notification_client = {
    0x7991eec9,
    0x7e89,
    0x4d85,
    {0x83, 0x90, 0x6c, 0x70, 0x3c, 0xec, 0x60, 0xc0},
};

static const GUID zv3_iid_audio_client = {
    0x1cb9ad4c,
    0xdbfa,
    0x4c32,
    {0xb1, 0x78, 0xc2, 0xf5, 0x68, 0xa7, 0x03, 0xb2},
};

static const GUID zv3_iid_audio_capture_client = {
    0xc8adbd64,
    0xe71e,
    0x48a0,
    {0xa4, 0xde, 0x18, 0x5c, 0x39, 0x5c, 0xd3, 0x17},
};

static const GUID zv3_iid_audio_render_client = {
    0xf294acfc,
    0x3146,
    0x4483,
    {0xa7, 0xbf, 0xad, 0xdc, 0xa7, 0xc2, 0x60, 0xe2},
};

static const GUID zv3_ieee_float_subtype = {
    0x00000003,
    0x0000,
    0x0010,
    {0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71},
};

static com_scope enter_com(void) {
    com_scope scope;
    scope.status = CoInitializeEx(
        NULL,
        COINIT_MULTITHREADED | COINIT_DISABLE_OLE1DDE
    );
    scope.uninitialize = scope.status == S_OK ||
        scope.status == S_FALSE;
    if (scope.status == RPC_E_CHANGED_MODE) {
        scope.status = S_OK;
        scope.uninitialize = FALSE;
    }
    return scope;
}

static void leave_com(com_scope scope) {
    if (scope.uninitialize) {
        CoUninitialize();
    }
}

static EDataFlow data_flow(uint32_t direction) {
    return direction == ZV3_WASAPI_CAPTURE
        ? eCapture
        : eRender;
}

static HRESULT create_enumerator(
    IMMDeviceEnumerator **output
) {
    return CoCreateInstance(
        &zv3_clsid_mm_device_enumerator,
        NULL,
        CLSCTX_INPROC_SERVER,
        &zv3_iid_mm_device_enumerator,
        (void **)output
    );
}

static int32_t utf16_to_utf8(
    const wchar_t *source,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
) {
    if (source == NULL || output == NULL || output_length == NULL ||
        output_capacity > INT_MAX) {
        return E_INVALIDARG;
    }
    const int required = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        source,
        -1,
        NULL,
        0,
        NULL,
        NULL
    );
    if (required <= 1 ||
        (size_t)(required - 1) > output_capacity) {
        return HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER);
    }
    const int converted = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        source,
        -1,
        (char *)output,
        required,
        NULL,
        NULL
    );
    if (converted != required) {
        return HRESULT_FROM_WIN32(GetLastError());
    }
    *output_length = (size_t)(converted - 1);
    return S_OK;
}

static HRESULT utf8_to_utf16(
    const uint8_t *source,
    size_t source_length,
    wchar_t **output
) {
    if (source == NULL || source_length == 0 ||
        source_length > INT_MAX || output == NULL) {
        return E_INVALIDARG;
    }
    const int required = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        (const char *)source,
        (int)source_length,
        NULL,
        0
    );
    if (required <= 0) {
        return HRESULT_FROM_WIN32(GetLastError());
    }
    wchar_t *result = (wchar_t *)CoTaskMemAlloc(
        ((size_t)required + 1) * sizeof(wchar_t)
    );
    if (result == NULL) {
        return E_OUTOFMEMORY;
    }
    const int converted = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        (const char *)source,
        (int)source_length,
        result,
        required
    );
    if (converted != required) {
        const HRESULT status = HRESULT_FROM_WIN32(GetLastError());
        CoTaskMemFree(result);
        return status;
    }
    result[required] = L'\0';
    *output = result;
    return S_OK;
}

static HRESULT device_from_utf8(
    IMMDeviceEnumerator *enumerator,
    const uint8_t *identifier,
    size_t identifier_length,
    IMMDevice **output
) {
    wchar_t *wide = NULL;
    HRESULT status = utf8_to_utf16(
        identifier,
        identifier_length,
        &wide
    );
    if (FAILED(status)) {
        return status;
    }
    status = IMMDeviceEnumerator_GetDevice(
        enumerator,
        wide,
        output
    );
    CoTaskMemFree(wide);
    return status;
}

static HRESULT active_collection(
    IMMDeviceEnumerator *enumerator,
    uint32_t direction,
    IMMDeviceCollection **output
) {
    if (direction != ZV3_WASAPI_CAPTURE &&
        direction != ZV3_WASAPI_RENDER) {
        return E_INVALIDARG;
    }
    return IMMDeviceEnumerator_EnumAudioEndpoints(
        enumerator,
        data_flow(direction),
        DEVICE_STATE_ACTIVE,
        output
    );
}

int32_t zv3_wasapi_device_count(
    uint32_t direction,
    size_t *output
) {
    if (output == NULL) {
        return E_INVALIDARG;
    }
    com_scope scope = enter_com();
    if (FAILED(scope.status)) {
        return scope.status;
    }
    IMMDeviceEnumerator *enumerator = NULL;
    IMMDeviceCollection *collection = NULL;
    HRESULT status = create_enumerator(&enumerator);
    if (SUCCEEDED(status)) {
        status = active_collection(
            enumerator,
            direction,
            &collection
        );
    }
    UINT count = 0;
    if (SUCCEEDED(status)) {
        status = IMMDeviceCollection_GetCount(
            collection,
            &count
        );
    }
    if (collection != NULL) {
        IMMDeviceCollection_Release(collection);
    }
    if (enumerator != NULL) {
        IMMDeviceEnumerator_Release(enumerator);
    }
    leave_com(scope);
    if (SUCCEEDED(status)) {
        *output = count;
    }
    return status;
}

int32_t zv3_wasapi_device_id(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
) {
    com_scope scope = enter_com();
    if (FAILED(scope.status)) {
        return scope.status;
    }
    IMMDeviceEnumerator *enumerator = NULL;
    IMMDeviceCollection *collection = NULL;
    IMMDevice *device = NULL;
    LPWSTR identifier = NULL;
    HRESULT status = create_enumerator(&enumerator);
    if (SUCCEEDED(status)) {
        status = active_collection(
            enumerator,
            direction,
            &collection
        );
    }
    if (SUCCEEDED(status)) {
        if (index > UINT_MAX) {
            status = E_INVALIDARG;
        } else {
            status = IMMDeviceCollection_Item(
                collection,
                (UINT)index,
                &device
            );
        }
    }
    if (SUCCEEDED(status)) {
        status = IMMDevice_GetId(device, &identifier);
    }
    if (SUCCEEDED(status)) {
        status = utf16_to_utf8(
            identifier,
            output,
            output_capacity,
            output_length
        );
    }
    CoTaskMemFree(identifier);
    if (device != NULL) {
        IMMDevice_Release(device);
    }
    if (collection != NULL) {
        IMMDeviceCollection_Release(collection);
    }
    if (enumerator != NULL) {
        IMMDeviceEnumerator_Release(enumerator);
    }
    leave_com(scope);
    return status;
}

int32_t zv3_wasapi_default_device_id(
    uint32_t direction,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
) {
    if (direction != ZV3_WASAPI_CAPTURE &&
        direction != ZV3_WASAPI_RENDER) {
        return E_INVALIDARG;
    }
    com_scope scope = enter_com();
    if (FAILED(scope.status)) {
        return scope.status;
    }
    IMMDeviceEnumerator *enumerator = NULL;
    IMMDevice *device = NULL;
    LPWSTR identifier = NULL;
    HRESULT status = create_enumerator(&enumerator);
    if (SUCCEEDED(status)) {
        status = IMMDeviceEnumerator_GetDefaultAudioEndpoint(
            enumerator,
            data_flow(direction),
            eMultimedia,
            &device
        );
    }
    if (SUCCEEDED(status)) {
        status = IMMDevice_GetId(device, &identifier);
    }
    if (SUCCEEDED(status)) {
        status = utf16_to_utf8(
            identifier,
            output,
            output_capacity,
            output_length
        );
    }
    CoTaskMemFree(identifier);
    if (device != NULL) {
        IMMDevice_Release(device);
    }
    if (enumerator != NULL) {
        IMMDeviceEnumerator_Release(enumerator);
    }
    leave_com(scope);
    return status;
}

int32_t zv3_wasapi_status_is_not_found(int32_t status) {
    return status == E_NOTFOUND;
}

int32_t zv3_wasapi_device_name(
    const uint8_t *identifier,
    size_t identifier_length,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
) {
    com_scope scope = enter_com();
    if (FAILED(scope.status)) {
        return scope.status;
    }
    IMMDeviceEnumerator *enumerator = NULL;
    IMMDevice *device = NULL;
    IPropertyStore *properties = NULL;
    PROPVARIANT name;
    PropVariantInit(&name);
    HRESULT status = create_enumerator(&enumerator);
    if (SUCCEEDED(status)) {
        status = device_from_utf8(
            enumerator,
            identifier,
            identifier_length,
            &device
        );
    }
    if (SUCCEEDED(status)) {
        status = IMMDevice_OpenPropertyStore(
            device,
            STGM_READ,
            &properties
        );
    }
    if (SUCCEEDED(status)) {
        status = IPropertyStore_GetValue(
            properties,
            &PKEY_Device_FriendlyName,
            &name
        );
    }
    if (SUCCEEDED(status) &&
        name.vt == VT_LPWSTR &&
        name.pwszVal != NULL) {
        status = utf16_to_utf8(
            name.pwszVal,
            output,
            output_capacity,
            output_length
        );
    } else if (SUCCEEDED(status)) {
        status = E_FAIL;
    }
    PropVariantClear(&name);
    if (properties != NULL) {
        IPropertyStore_Release(properties);
    }
    if (device != NULL) {
        IMMDevice_Release(device);
    }
    if (enumerator != NULL) {
        IMMDeviceEnumerator_Release(enumerator);
    }
    leave_com(scope);
    return status;
}

int32_t zv3_wasapi_device_channels(
    const uint8_t *identifier,
    size_t identifier_length,
    uint32_t *output
) {
    if (output == NULL) {
        return E_INVALIDARG;
    }
    com_scope scope = enter_com();
    if (FAILED(scope.status)) {
        return scope.status;
    }
    IMMDeviceEnumerator *enumerator = NULL;
    IMMDevice *device = NULL;
    IAudioClient *client = NULL;
    WAVEFORMATEX *format = NULL;
    HRESULT status = create_enumerator(&enumerator);
    if (SUCCEEDED(status)) {
        status = device_from_utf8(
            enumerator,
            identifier,
            identifier_length,
            &device
        );
    }
    if (SUCCEEDED(status)) {
        status = IMMDevice_Activate(
            device,
            &zv3_iid_audio_client,
            CLSCTX_INPROC_SERVER,
            NULL,
            (void **)&client
        );
    }
    if (SUCCEEDED(status)) {
        status = IAudioClient_GetMixFormat(client, &format);
    }
    if (SUCCEEDED(status) && format != NULL) {
        *output = format->nChannels;
    } else if (SUCCEEDED(status)) {
        status = E_FAIL;
    }
    CoTaskMemFree(format);
    if (client != NULL) {
        IAudioClient_Release(client);
    }
    if (device != NULL) {
        IMMDevice_Release(device);
    }
    if (enumerator != NULL) {
        IMMDeviceEnumerator_Release(enumerator);
    }
    leave_com(scope);
    return status;
}

static notification_client *notification_from_interface(
    IMMNotificationClient *base
) {
    return (notification_client *)base;
}

static HRESULT STDMETHODCALLTYPE notification_query_interface(
    IMMNotificationClient *base,
    REFIID identifier,
    void **output
) {
    if (output == NULL) {
        return E_POINTER;
    }
    if (IsEqualIID(identifier, &IID_IUnknown) ||
        IsEqualIID(identifier, &zv3_iid_mm_notification_client)) {
        *output = base;
        (void)IMMNotificationClient_AddRef(base);
        return S_OK;
    }
    *output = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE notification_add_ref(
    IMMNotificationClient *base
) {
    notification_client *client =
        notification_from_interface(base);
    return (ULONG)InterlockedIncrement(
        &client->reference_count
    );
}

static ULONG STDMETHODCALLTYPE notification_release(
    IMMNotificationClient *base
) {
    notification_client *client =
        notification_from_interface(base);
    return (ULONG)InterlockedDecrement(
        &client->reference_count
    );
}

static void notify_topology(notification_client *client) {
    if (client->callback != NULL) {
        client->callback(client->context);
    }
}

static HRESULT STDMETHODCALLTYPE notification_state_changed(
    IMMNotificationClient *base,
    LPCWSTR identifier,
    DWORD state
) {
    (void)identifier;
    (void)state;
    notify_topology(notification_from_interface(base));
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE notification_added(
    IMMNotificationClient *base,
    LPCWSTR identifier
) {
    (void)identifier;
    notify_topology(notification_from_interface(base));
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE notification_removed(
    IMMNotificationClient *base,
    LPCWSTR identifier
) {
    (void)identifier;
    notify_topology(notification_from_interface(base));
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE notification_default_changed(
    IMMNotificationClient *base,
    EDataFlow flow,
    ERole role,
    LPCWSTR identifier
) {
    (void)flow;
    (void)identifier;
    if (role == eMultimedia) {
        notify_topology(notification_from_interface(base));
    }
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE notification_property_changed(
    IMMNotificationClient *base,
    LPCWSTR identifier,
    const PROPERTYKEY key
) {
    (void)identifier;
    (void)key;
    notify_topology(notification_from_interface(base));
    return S_OK;
}

static IMMNotificationClientVtbl notification_vtable = {
    notification_query_interface,
    notification_add_ref,
    notification_release,
    notification_state_changed,
    notification_added,
    notification_removed,
    notification_default_changed,
    notification_property_changed
};

static DWORD WINAPI observer_thread(void *context) {
    zv3_wasapi_observer *observer =
        (zv3_wasapi_observer *)context;
    com_scope scope = enter_com();
    IMMDeviceEnumerator *enumerator = NULL;
    notification_client client;
    memset(&client, 0, sizeof(client));
    client.base.lpVtbl = &notification_vtable;
    client.reference_count = 1;
    client.context = observer->context;
    client.callback = observer->callback;

    HRESULT status = scope.status;
    if (SUCCEEDED(status)) {
        status = create_enumerator(&enumerator);
    }
    if (SUCCEEDED(status)) {
        status =
            IMMDeviceEnumerator_RegisterEndpointNotificationCallback(
                enumerator,
                &client.base
            );
    }
    observer->start_status = status;
    (void)SetEvent(observer->ready_event);
    if (SUCCEEDED(status)) {
        (void)WaitForSingleObject(
            observer->stop_event,
            INFINITE
        );
        (void)
            IMMDeviceEnumerator_UnregisterEndpointNotificationCallback(
                enumerator,
                &client.base
            );
    }
    if (enumerator != NULL) {
        IMMDeviceEnumerator_Release(enumerator);
    }
    leave_com(scope);
    return 0;
}

static void dispose_observer(zv3_wasapi_observer *observer) {
    if (observer == NULL) {
        return;
    }
    if (observer->thread != NULL) {
        CloseHandle(observer->thread);
    }
    if (observer->ready_event != NULL) {
        CloseHandle(observer->ready_event);
    }
    if (observer->stop_event != NULL) {
        CloseHandle(observer->stop_event);
    }
    free(observer);
}

int32_t zv3_wasapi_observe_topology(
    void *context,
    zv3_wasapi_topology_fn callback,
    zv3_wasapi_observer **output
) {
    if (context == NULL || callback == NULL || output == NULL) {
        return E_INVALIDARG;
    }
    zv3_wasapi_observer *observer =
        (zv3_wasapi_observer *)calloc(1, sizeof(*observer));
    if (observer == NULL) {
        return E_OUTOFMEMORY;
    }
    observer->context = context;
    observer->callback = callback;
    observer->ready_event = CreateEventW(
        NULL,
        TRUE,
        FALSE,
        NULL
    );
    observer->stop_event = CreateEventW(
        NULL,
        TRUE,
        FALSE,
        NULL
    );
    HRESULT status = S_OK;
    if (observer->ready_event == NULL ||
        observer->stop_event == NULL) {
        status = HRESULT_FROM_WIN32(GetLastError());
    }
    if (SUCCEEDED(status)) {
        observer->thread = CreateThread(
            NULL,
            0,
            observer_thread,
            observer,
            0,
            NULL
        );
        if (observer->thread == NULL) {
            status = HRESULT_FROM_WIN32(GetLastError());
        }
    }
    if (SUCCEEDED(status)) {
        const DWORD wait = WaitForSingleObject(
            observer->ready_event,
            10000
        );
        if (wait != WAIT_OBJECT_0) {
            status = wait == WAIT_TIMEOUT
                ? HRESULT_FROM_WIN32(ERROR_TIMEOUT)
                : HRESULT_FROM_WIN32(GetLastError());
        } else {
            status = observer->start_status;
        }
    }
    if (FAILED(status)) {
        if (observer->stop_event != NULL) {
            (void)SetEvent(observer->stop_event);
        }
        if (observer->thread != NULL) {
            (void)WaitForSingleObject(
                observer->thread,
                INFINITE
            );
        }
        dispose_observer(observer);
        return status;
    }
    *output = observer;
    return S_OK;
}

void zv3_wasapi_stop_observing(
    zv3_wasapi_observer *observer
) {
    if (observer == NULL) {
        return;
    }
    (void)SetEvent(observer->stop_event);
    (void)WaitForSingleObject(observer->thread, INFINITE);
    dispose_observer(observer);
}

static WAVEFORMATEXTENSIBLE requested_format(
    uint32_t sample_bytes,
    double sample_rate,
    uint32_t channels
) {
    WAVEFORMATEXTENSIBLE format;
    memset(&format, 0, sizeof(format));
    format.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
    format.Format.nChannels = (WORD)channels;
    format.Format.nSamplesPerSec = (DWORD)sample_rate;
    format.Format.nBlockAlign = (WORD)(channels * sample_bytes);
    format.Format.nAvgBytesPerSec =
        format.Format.nSamplesPerSec * format.Format.nBlockAlign;
    format.Format.wBitsPerSample = (WORD)(sample_bytes * 8);
    format.Format.cbSize = sizeof(WAVEFORMATEXTENSIBLE) -
        sizeof(WAVEFORMATEX);
    format.Samples.wValidBitsPerSample =
        format.Format.wBitsPerSample;
    format.dwChannelMask = 0;
    format.SubFormat = zv3_ieee_float_subtype;
    return format;
}

static HRESULT open_audio_client(
    IMMDeviceEnumerator *enumerator,
    const wchar_t *identifier,
    HANDLE event,
    const WAVEFORMATEXTENSIBLE *format,
    IAudioClient **client_output,
    uint32_t *buffer_frames
) {
    IMMDevice *device = NULL;
    IAudioClient *client = NULL;
    HRESULT status = IMMDeviceEnumerator_GetDevice(
        enumerator,
        identifier,
        &device
    );
    if (SUCCEEDED(status)) {
        status = IMMDevice_Activate(
            device,
            &zv3_iid_audio_client,
            CLSCTX_INPROC_SERVER,
            NULL,
            (void **)&client
        );
    }
    if (SUCCEEDED(status)) {
        status = IAudioClient_Initialize(
            client,
            AUDCLNT_SHAREMODE_SHARED,
            AUDCLNT_STREAMFLAGS_EVENTCALLBACK |
                AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
                AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
            0,
            0,
            &format->Format,
            NULL
        );
    }
    if (SUCCEEDED(status)) {
        status = IAudioClient_SetEventHandle(client, event);
    }
    UINT32 frames = 0;
    if (SUCCEEDED(status)) {
        status = IAudioClient_GetBufferSize(client, &frames);
    }
    if (device != NULL) {
        IMMDevice_Release(device);
    }
    if (FAILED(status)) {
        if (client != NULL) {
            IAudioClient_Release(client);
        }
        return status;
    }
    *client_output = client;
    *buffer_frames = frames;
    return S_OK;
}

static void release_audio_clients(
    zv3_wasapi_session *session
) {
    if (session->render_client != NULL) {
        (void)IAudioClient_Stop(session->render_client);
    }
    if (session->capture_client != NULL) {
        (void)IAudioClient_Stop(session->capture_client);
    }
    if (session->render_service != NULL) {
        IAudioRenderClient_Release(session->render_service);
        session->render_service = NULL;
    }
    if (session->capture_service != NULL) {
        IAudioCaptureClient_Release(session->capture_service);
        session->capture_service = NULL;
    }
    if (session->render_client != NULL) {
        IAudioClient_Release(session->render_client);
        session->render_client = NULL;
    }
    if (session->capture_client != NULL) {
        IAudioClient_Release(session->capture_client);
        session->capture_client = NULL;
    }
}

static HRESULT initialize_audio_clients(
    zv3_wasapi_session *session
) {
    IMMDeviceEnumerator *enumerator = NULL;
    HRESULT status = create_enumerator(&enumerator);
    if (FAILED(status)) {
        return status;
    }
    if (session->input_channels != 0) {
        const WAVEFORMATEXTENSIBLE format = requested_format(
            session->sample_bytes,
            session->sample_rate,
            session->input_channels
        );
        uint32_t capture_buffer_frames = 0;
        status = open_audio_client(
            enumerator,
            session->input_identifier,
            session->capture_event,
            &format,
            &session->capture_client,
            &capture_buffer_frames
        );
        if (SUCCEEDED(status) &&
            capture_buffer_frames > session->maximum_frames) {
            status = AUDCLNT_E_BUFFER_SIZE_ERROR;
        }
        if (SUCCEEDED(status)) {
            status = IAudioClient_GetService(
                session->capture_client,
                &zv3_iid_audio_capture_client,
                (void **)&session->capture_service
            );
        }
    }
    if (SUCCEEDED(status) && session->output_channels != 0) {
        const WAVEFORMATEXTENSIBLE format = requested_format(
            session->sample_bytes,
            session->sample_rate,
            session->output_channels
        );
        status = open_audio_client(
            enumerator,
            session->output_identifier,
            session->render_event,
            &format,
            &session->render_client,
            &session->render_buffer_frames
        );
        if (SUCCEEDED(status) &&
            session->render_buffer_frames >
                session->maximum_frames) {
            status = AUDCLNT_E_BUFFER_SIZE_ERROR;
        }
        if (SUCCEEDED(status)) {
            status = IAudioClient_GetService(
                session->render_client,
                &zv3_iid_audio_render_client,
                (void **)&session->render_service
            );
        }
    }
    IMMDeviceEnumerator_Release(enumerator);
    if (FAILED(status)) {
        release_audio_clients(session);
    }
    return status;
}

static void configure_views(
    zv3_wasapi_session *session,
    uint32_t frame_count
) {
    for (uint32_t channel = 0;
         channel < session->input_channels;
         ++channel) {
        session->input_views[channel] =
            session->input_planar +
            (size_t)channel * session->maximum_frames *
                session->sample_bytes;
        memset(
            session->input_views[channel],
            0,
            (size_t)frame_count * session->sample_bytes
        );
    }
    for (uint32_t channel = 0;
         channel < session->output_channels;
         ++channel) {
        session->output_views[channel] =
            session->output_planar +
            (size_t)channel * session->maximum_frames *
                session->sample_bytes;
        memset(
            session->output_views[channel],
            0,
            (size_t)frame_count * session->sample_bytes
        );
    }
}

static void push_capture(
    zv3_wasapi_session *session,
    const uint8_t *interleaved,
    uint32_t frame_count,
    BOOL silent
) {
    if (frame_count > session->ring_capacity -
        session->ring_count) {
        const uint32_t dropped = frame_count -
            (session->ring_capacity - session->ring_count);
        session->ring_read =
            (session->ring_read + dropped) %
                session->ring_capacity;
        session->ring_count -= dropped;
        (void)InterlockedIncrement64(
            &session->capture_overflows
        );
    }
    for (uint32_t frame = 0; frame < frame_count; ++frame) {
        for (uint32_t channel = 0;
             channel < session->input_channels;
             ++channel) {
            uint8_t *destination = session->capture_ring +
                ((size_t)channel * session->ring_capacity +
                 session->ring_write) *
                    session->sample_bytes;
            if (silent) {
                memset(destination, 0, session->sample_bytes);
            } else {
                const uint8_t *source = interleaved +
                    ((size_t)frame * session->input_channels +
                     channel) *
                        session->sample_bytes;
                memcpy(
                    destination,
                    source,
                    session->sample_bytes
                );
            }
        }
        session->ring_write =
            (session->ring_write + 1) % session->ring_capacity;
        session->ring_count += 1;
    }
}

static void pop_capture(
    zv3_wasapi_session *session,
    uint32_t frame_count
) {
    const uint32_t available = session->ring_count < frame_count
        ? session->ring_count
        : frame_count;
    if (available < frame_count) {
        (void)InterlockedIncrement64(
            &session->capture_underflows
        );
    }
    for (uint32_t frame = 0; frame < available; ++frame) {
        for (uint32_t channel = 0;
             channel < session->input_channels;
             ++channel) {
            const uint8_t *source = session->capture_ring +
                ((size_t)channel * session->ring_capacity +
                 session->ring_read) *
                    session->sample_bytes;
            uint8_t *destination =
                (uint8_t *)session->input_views[channel] +
                (size_t)frame * session->sample_bytes;
            memcpy(
                destination,
                source,
                session->sample_bytes
            );
        }
        session->ring_read =
            (session->ring_read + 1) % session->ring_capacity;
        session->ring_count -= 1;
    }
}

static HRESULT invoke_process(
    zv3_wasapi_session *session,
    uint32_t frame_count
) {
    const int32_t result = session->process(
        session->context,
        frame_count,
        (const void *const *)session->input_views,
        session->output_views
    );
    if (result != 0) {
        (void)InterlockedIncrement64(
            &session->callback_failures
        );
        for (uint32_t channel = 0;
             channel < session->output_channels;
             ++channel) {
            memset(
                session->output_views[channel],
                0,
                (size_t)frame_count * session->sample_bytes
            );
        }
        return E_FAIL;
    }
    (void)InterlockedIncrement64(&session->processed);
    return S_OK;
}

static HRESULT invoke_capture(
    zv3_wasapi_session *session,
    uint32_t frame_count
) {
    const int32_t result = session->capture(
        session->context,
        frame_count,
        (const void *const *)session->input_views
    );
    if (result != 0) {
        (void)InterlockedIncrement64(
            &session->callback_failures
        );
        return E_FAIL;
    }
    return S_OK;
}

static HRESULT invoke_render(
    zv3_wasapi_session *session,
    uint32_t frame_count
) {
    const int32_t result = session->render(
        session->context,
        frame_count,
        session->output_views
    );
    if (result != 0) {
        (void)InterlockedIncrement64(
            &session->callback_failures
        );
        for (uint32_t channel = 0;
             channel < session->output_channels;
             ++channel) {
            memset(
                session->output_views[channel],
                0,
                (size_t)frame_count * session->sample_bytes
            );
        }
        return E_FAIL;
    }
    (void)InterlockedIncrement64(&session->processed);
    return S_OK;
}

static HRESULT process_capture(
    zv3_wasapi_session *session
) {
    UINT32 packet_frames = 0;
    HRESULT status = IAudioCaptureClient_GetNextPacketSize(
        session->capture_service,
        &packet_frames
    );
    while (SUCCEEDED(status) && packet_frames != 0) {
        BYTE *data = NULL;
        UINT32 frame_count = 0;
        DWORD flags = 0;
        status = IAudioCaptureClient_GetBuffer(
            session->capture_service,
            &data,
            &frame_count,
            &flags,
            NULL,
            NULL
        );
        if (FAILED(status)) {
            break;
        }
        if (frame_count > session->maximum_frames) {
            status = AUDCLNT_E_BUFFER_SIZE_ERROR;
        } else if (session->capture != NULL) {
            if ((flags &
                 AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY) != 0) {
                (void)InterlockedIncrement64(
                    &session->capture_overflows
                );
            }
            configure_views(session, frame_count);
            if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) == 0) {
                for (uint32_t frame = 0;
                     frame < frame_count;
                     ++frame) {
                    for (uint32_t channel = 0;
                         channel < session->input_channels;
                         ++channel) {
                        memcpy(
                            (uint8_t *)session->input_views[channel] +
                                (size_t)frame *
                                    session->sample_bytes,
                            data +
                                ((size_t)frame *
                                     session->input_channels +
                                 channel) *
                                    session->sample_bytes,
                            session->sample_bytes
                        );
                    }
                }
            }
            (void)invoke_capture(session, frame_count);
        } else if (session->output_channels == 0) {
            if ((flags &
                 AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY) != 0) {
                (void)InterlockedIncrement64(
                    &session->capture_overflows
                );
            }
            configure_views(session, frame_count);
            if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) == 0) {
                for (uint32_t frame = 0;
                     frame < frame_count;
                     ++frame) {
                    for (uint32_t channel = 0;
                         channel < session->input_channels;
                         ++channel) {
                        memcpy(
                            (uint8_t *)session->input_views[channel] +
                                (size_t)frame *
                                    session->sample_bytes,
                            data +
                                ((size_t)frame *
                                     session->input_channels +
                                 channel) *
                                    session->sample_bytes,
                            session->sample_bytes
                        );
                    }
                }
            }
            (void)invoke_process(session, frame_count);
        } else {
            if ((flags &
                 AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY) != 0) {
                (void)InterlockedIncrement64(
                    &session->capture_overflows
                );
            }
            push_capture(
                session,
                data,
                frame_count,
                (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0
            );
        }
        const HRESULT release_status =
            IAudioCaptureClient_ReleaseBuffer(
                session->capture_service,
                frame_count
            );
        if (FAILED(status)) {
            break;
        }
        if (FAILED(release_status)) {
            status = release_status;
            break;
        }
        status = IAudioCaptureClient_GetNextPacketSize(
            session->capture_service,
            &packet_frames
        );
    }
    return status;
}

static HRESULT process_render(
    zv3_wasapi_session *session
) {
    UINT32 padding = 0;
    HRESULT status = IAudioClient_GetCurrentPadding(
        session->render_client,
        &padding
    );
    if (FAILED(status) || padding > session->render_buffer_frames) {
        return FAILED(status) ? status : E_FAIL;
    }
    const uint32_t frame_count =
        session->render_buffer_frames - padding;
    if (frame_count == 0) {
        return S_OK;
    }
    BYTE *destination = NULL;
    status = IAudioRenderClient_GetBuffer(
        session->render_service,
        frame_count,
        &destination
    );
    if (FAILED(status)) {
        return status;
    }
    configure_views(session, frame_count);
    if (session->process != NULL &&
        session->input_channels != 0) {
        pop_capture(session, frame_count);
    }
    const HRESULT process_status = session->render != NULL
        ? invoke_render(session, frame_count)
        : invoke_process(session, frame_count);
    for (uint32_t frame = 0; frame < frame_count; ++frame) {
        for (uint32_t channel = 0;
             channel < session->output_channels;
             ++channel) {
            memcpy(
                destination +
                    ((size_t)frame *
                         session->output_channels +
                     channel) *
                        session->sample_bytes,
                (uint8_t *)session->output_views[channel] +
                    (size_t)frame * session->sample_bytes,
                session->sample_bytes
            );
        }
    }
    const HRESULT release_status =
        IAudioRenderClient_ReleaseBuffer(
            session->render_service,
            frame_count,
            FAILED(process_status)
                ? AUDCLNT_BUFFERFLAGS_SILENT
                : 0
        );
    return FAILED(release_status)
        ? release_status
        : S_OK;
}

static HRESULT start_audio_clients(
    zv3_wasapi_session *session
) {
    if (session->capture_client != NULL) {
        HRESULT status = IAudioClient_Start(
            session->capture_client
        );
        if (FAILED(status)) {
            return status;
        }
    }
    if (session->render_client != NULL) {
        HRESULT status = IAudioClient_Start(
            session->render_client
        );
        if (FAILED(status)) {
            if (session->capture_client != NULL) {
                (void)IAudioClient_Stop(
                    session->capture_client
                );
            }
            return status;
        }
    }
    return S_OK;
}

static DWORD WINAPI audio_thread(void *context) {
    zv3_wasapi_session *session =
        (zv3_wasapi_session *)context;
    com_scope scope = enter_com();
    DWORD task_index = 0;
    HANDLE mmcss = AvSetMmThreadCharacteristicsW(
        L"Pro Audio",
        &task_index
    );
    HRESULT status = scope.status;
    if (SUCCEEDED(status)) {
        status = initialize_audio_clients(session);
    }
    if (SUCCEEDED(status)) {
        status = start_audio_clients(session);
    }
    session->start_status = status;
    (void)SetEvent(session->ready_event);
    if (FAILED(status)) {
        release_audio_clients(session);
        if (mmcss != NULL) {
            (void)AvRevertMmThreadCharacteristics(mmcss);
        }
        leave_com(scope);
        return 0;
    }

    HANDLE events[3];
    DWORD event_count = 1;
    events[0] = session->stop_event;
    DWORD capture_index = MAXDWORD;
    DWORD render_index = MAXDWORD;
    if (session->capture_client != NULL) {
        capture_index = event_count;
        events[event_count++] = session->capture_event;
    }
    if (session->render_client != NULL) {
        render_index = event_count;
        events[event_count++] = session->render_event;
    }

    BOOL running = TRUE;
    while (running) {
        const DWORD wait = WaitForMultipleObjects(
            event_count,
            events,
            FALSE,
            INFINITE
        );
        if (wait == WAIT_OBJECT_0) {
            break;
        }
        const DWORD index = wait - WAIT_OBJECT_0;
        if (wait == WAIT_FAILED || index >= event_count) {
            (void)InterlockedIncrement64(
                &session->device_failures
            );
            break;
        }
        if (index == capture_index) {
            status = process_capture(session);
        } else if (index == render_index) {
            status = process_render(session);
        } else {
            status = E_FAIL;
        }
        if (FAILED(status)) {
            (void)InterlockedIncrement64(
                &session->device_failures
            );
            running = FALSE;
        }
    }

    release_audio_clients(session);
    if (mmcss != NULL) {
        (void)AvRevertMmThreadCharacteristics(mmcss);
    }
    leave_com(scope);
    return 0;
}

static void dispose_session(zv3_wasapi_session *session) {
    if (session == NULL) {
        return;
    }
    if (session->thread != NULL) {
        CloseHandle(session->thread);
    }
    if (session->ready_event != NULL) {
        CloseHandle(session->ready_event);
    }
    if (session->stop_event != NULL) {
        CloseHandle(session->stop_event);
    }
    if (session->capture_event != NULL) {
        CloseHandle(session->capture_event);
    }
    if (session->render_event != NULL) {
        CloseHandle(session->render_event);
    }
    CoTaskMemFree(session->input_identifier);
    CoTaskMemFree(session->output_identifier);
    free(session->input_planar);
    free(session->output_planar);
    free(session->capture_ring);
    free(session->input_views);
    free(session->output_views);
    free(session);
}

static int32_t start_session(
    const uint8_t *input_identifier,
    size_t input_identifier_length,
    const uint8_t *output_identifier,
    size_t output_identifier_length,
    uint32_t sample_bytes,
    double sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_wasapi_process_fn process,
    zv3_wasapi_capture_fn capture,
    zv3_wasapi_render_fn render,
    zv3_wasapi_session **output
) {
    const BOOL combined = process != NULL;
    const BOOL split = capture != NULL || render != NULL;
    if ((sample_bytes != 4 && sample_bytes != 8) ||
        sample_rate <= 0.0 ||
        sample_rate > UINT32_MAX ||
        (double)(DWORD)sample_rate != sample_rate ||
        maximum_frames == 0 ||
        maximum_frames > UINT32_MAX / 4 ||
        input_channels > 128 ||
        output_channels > 128 ||
        (input_channels == 0 && output_channels == 0) ||
        (input_channels != 0 &&
         (input_identifier == NULL ||
          input_identifier_length == 0)) ||
        (output_channels != 0 &&
         (output_identifier == NULL ||
          output_identifier_length == 0)) ||
        context == NULL || output == NULL ||
        combined == split ||
        (split &&
         (capture == NULL ||
          render == NULL ||
          input_channels == 0 ||
          output_channels == 0))) {
        return E_INVALIDARG;
    }

    zv3_wasapi_session *session =
        (zv3_wasapi_session *)calloc(1, sizeof(*session));
    if (session == NULL) {
        return E_OUTOFMEMORY;
    }
    session->sample_bytes = sample_bytes;
    session->sample_rate = sample_rate;
    session->maximum_frames = maximum_frames;
    session->input_channels = input_channels;
    session->output_channels = output_channels;
    session->context = context;
    session->process = process;
    session->capture = capture;
    session->render = render;
    session->ring_capacity = maximum_frames * 4;
    if (session->ring_capacity < maximum_frames) {
        dispose_session(session);
        return E_INVALIDARG;
    }

    HRESULT status = S_OK;
    if (input_channels != 0) {
        status = utf8_to_utf16(
            input_identifier,
            input_identifier_length,
            &session->input_identifier
        );
    }
    if (SUCCEEDED(status) && output_channels != 0) {
        status = utf8_to_utf16(
            output_identifier,
            output_identifier_length,
            &session->output_identifier
        );
    }
    const size_t input_samples =
        (size_t)input_channels * maximum_frames;
    const size_t output_samples =
        (size_t)output_channels * maximum_frames;
    const size_t ring_samples =
        (size_t)input_channels * session->ring_capacity;
    if (SUCCEEDED(status) && input_channels != 0) {
        session->input_planar =
            (uint8_t *)calloc(input_samples, sample_bytes);
        session->capture_ring =
            (uint8_t *)calloc(ring_samples, sample_bytes);
        session->input_views =
            (void **)calloc(input_channels, sizeof(void *));
        if (session->input_planar == NULL ||
            session->capture_ring == NULL ||
            session->input_views == NULL) {
            status = E_OUTOFMEMORY;
        }
    }
    if (SUCCEEDED(status) && output_channels != 0) {
        session->output_planar =
            (uint8_t *)calloc(output_samples, sample_bytes);
        session->output_views =
            (void **)calloc(output_channels, sizeof(void *));
        if (session->output_planar == NULL ||
            session->output_views == NULL) {
            status = E_OUTOFMEMORY;
        }
    }
    if (SUCCEEDED(status)) {
        session->ready_event = CreateEventW(
            NULL,
            TRUE,
            FALSE,
            NULL
        );
        session->stop_event = CreateEventW(
            NULL,
            TRUE,
            FALSE,
            NULL
        );
        session->capture_event = CreateEventW(
            NULL,
            FALSE,
            FALSE,
            NULL
        );
        session->render_event = CreateEventW(
            NULL,
            FALSE,
            FALSE,
            NULL
        );
        if (session->ready_event == NULL ||
            session->stop_event == NULL ||
            session->capture_event == NULL ||
            session->render_event == NULL) {
            status = HRESULT_FROM_WIN32(GetLastError());
        }
    }
    if (SUCCEEDED(status)) {
        session->thread = CreateThread(
            NULL,
            0,
            audio_thread,
            session,
            0,
            NULL
        );
        if (session->thread == NULL) {
            status = HRESULT_FROM_WIN32(GetLastError());
        }
    }
    if (SUCCEEDED(status)) {
        const DWORD wait = WaitForSingleObject(
            session->ready_event,
            10000
        );
        if (wait != WAIT_OBJECT_0) {
            status = wait == WAIT_TIMEOUT
                ? HRESULT_FROM_WIN32(ERROR_TIMEOUT)
                : HRESULT_FROM_WIN32(GetLastError());
        } else {
            status = session->start_status;
        }
    }
    if (FAILED(status)) {
        if (session->stop_event != NULL) {
            (void)SetEvent(session->stop_event);
        }
        if (session->thread != NULL) {
            (void)WaitForSingleObject(
                session->thread,
                INFINITE
            );
        }
        dispose_session(session);
        return status;
    }
    *output = session;
    return S_OK;
}

int32_t zv3_wasapi_start(
    const uint8_t *input_identifier,
    size_t input_identifier_length,
    const uint8_t *output_identifier,
    size_t output_identifier_length,
    uint32_t sample_bytes,
    double sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_wasapi_process_fn process,
    zv3_wasapi_session **output
) {
    return start_session(
        input_identifier,
        input_identifier_length,
        output_identifier,
        output_identifier_length,
        sample_bytes,
        sample_rate,
        maximum_frames,
        input_channels,
        output_channels,
        context,
        process,
        NULL,
        NULL,
        output
    );
}

int32_t zv3_wasapi_start_split(
    const uint8_t *input_identifier,
    size_t input_identifier_length,
    const uint8_t *output_identifier,
    size_t output_identifier_length,
    uint32_t sample_bytes,
    double sample_rate,
    uint32_t maximum_frames,
    uint32_t input_channels,
    uint32_t output_channels,
    void *context,
    zv3_wasapi_capture_fn capture,
    zv3_wasapi_render_fn render,
    zv3_wasapi_session **output
) {
    return start_session(
        input_identifier,
        input_identifier_length,
        output_identifier,
        output_identifier_length,
        sample_bytes,
        sample_rate,
        maximum_frames,
        input_channels,
        output_channels,
        context,
        NULL,
        capture,
        render,
        output
    );
}

static uint64_t atomic_value(const volatile LONG64 *value) {
    return (uint64_t)InterlockedCompareExchange64(
        (volatile LONG64 *)value,
        0,
        0
    );
}

void zv3_wasapi_get_statistics(
    const zv3_wasapi_session *session,
    zv3_wasapi_statistics *output
) {
    if (session == NULL || output == NULL) {
        return;
    }
    output->processed = atomic_value(&session->processed);
    output->callback_failures =
        atomic_value(&session->callback_failures);
    output->capture_underflows =
        atomic_value(&session->capture_underflows);
    output->capture_overflows =
        atomic_value(&session->capture_overflows);
    output->device_failures =
        atomic_value(&session->device_failures);
}

void zv3_wasapi_stop(
    zv3_wasapi_session *session,
    zv3_wasapi_statistics *final_statistics
) {
    if (session == NULL) {
        return;
    }
    (void)SetEvent(session->stop_event);
    (void)WaitForSingleObject(session->thread, INFINITE);
    zv3_wasapi_get_statistics(session, final_statistics);
    dispose_session(session);
}
