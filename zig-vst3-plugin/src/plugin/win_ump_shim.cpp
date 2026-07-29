#include "win_ump_shim.h"

#include <atomic>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

#define NOMINMAX
#include <windows.h>
#include <roapi.h>

#include <winmidi/init/Microsoft.Windows.Devices.Midi2.Initialization.hpp>
#include <winmidi/WindowsMidiServicesAppSdkComExtensions.h>
#include <winmidi/WindowsMidiServicesAppSdkComExtensions_i.c>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Microsoft.Windows.Devices.Midi2.h>

namespace midi2 = winrt::Microsoft::Windows::Devices::Midi2;
namespace initialization =
    Microsoft::Windows::Devices::Midi2::Initialization;

namespace {

struct endpoint {
    std::string id;
    std::string name;
};

struct runtime_state {
    std::mutex mutex;
    initialization::MidiDesktopAppSdkInitializer initializer;
    std::vector<endpoint> inputs;
    std::vector<endpoint> outputs;
    std::string client_name;
    std::thread::id apartment_thread;
    uint32_t references = 0;
    bool apartment_owned = false;
};

runtime_state runtime;

void reset_runtime_locked() noexcept
{
    runtime.inputs.clear();
    runtime.outputs.clear();
    runtime.client_name.clear();
    try {
        runtime.initializer.ShutdownSdkRuntime();
    } catch (...) {
    }
    if (runtime.apartment_owned) {
        RoUninitialize();
    }
    runtime.apartment_thread = {};
    runtime.references = 0;
    runtime.apartment_owned = false;
}

bool valid_direction(uint32_t direction)
{
    return direction == ZV3_WIN_UMP_INPUT ||
        direction == ZV3_WIN_UMP_OUTPUT;
}

std::vector<endpoint> &endpoints_for(uint32_t direction)
{
    return direction == ZV3_WIN_UMP_INPUT
        ? runtime.inputs
        : runtime.outputs;
}

uint8_t packet_word_count(uint32_t first_word)
{
    switch (first_word >> 28) {
    case 0x0:
    case 0x1:
    case 0x2:
    case 0x6:
    case 0x7:
        return 1;
    case 0x3:
    case 0x4:
    case 0x8:
    case 0x9:
    case 0xa:
        return 2;
    case 0xb:
    case 0xc:
        return 3;
    default:
        return 4;
    }
}

uint64_t qpc_frequency()
{
    LARGE_INTEGER frequency{};
    if (!QueryPerformanceFrequency(&frequency) || frequency.QuadPart <= 0) {
        return 0;
    }
    return static_cast<uint64_t>(frequency.QuadPart);
}

uint64_t qpc_now()
{
    LARGE_INTEGER value{};
    if (!QueryPerformanceCounter(&value) || value.QuadPart <= 0) {
        return 0;
    }
    return static_cast<uint64_t>(value.QuadPart);
}

uint64_t ticks_to_nanoseconds(uint64_t ticks)
{
    const uint64_t frequency = qpc_frequency();
    if (frequency == 0) {
        return 0;
    }
    const uint64_t seconds = ticks / frequency;
    if (seconds > std::numeric_limits<uint64_t>::max() / 1000000000ULL) {
        return 0;
    }
    return seconds * 1000000000ULL +
        (ticks % frequency) * 1000000000ULL / frequency;
}

uint64_t nanoseconds_to_ticks(uint64_t nanoseconds)
{
    const uint64_t frequency = qpc_frequency();
    if (frequency == 0) {
        return 0;
    }
    const uint64_t seconds = nanoseconds / 1000000000ULL;
    if (seconds > std::numeric_limits<uint64_t>::max() / frequency) {
        return 0;
    }
    return seconds * frequency +
        (nanoseconds % 1000000000ULL) * frequency / 1000000000ULL;
}

bool copy_text(
    const std::string &source,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    if (output_length == nullptr) {
        return false;
    }
    *output_length = source.size();
    if (source.empty() || output == nullptr ||
        output_capacity < source.size()) {
        return false;
    }
    std::memcpy(output, source.data(), source.size());
    return true;
}

class receive_callback final
    : public IMidiEndpointConnectionMessagesReceivedCallback {
public:
    receive_callback(
        void *context,
        zv3_win_ump_receive_fn receive
    ) : context_(context), receive_(receive)
    {
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(
        REFIID iid,
        void **object
    ) override
    {
        if (object == nullptr) {
            return E_POINTER;
        }
        if (iid == IID_IUnknown ||
            iid == IID_IMidiEndpointConnectionMessagesReceivedCallback) {
            *object =
                static_cast<IMidiEndpointConnectionMessagesReceivedCallback *>(
                    this
                );
            AddRef();
            return S_OK;
        }
        *object = nullptr;
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef() override
    {
        return references_.fetch_add(1, std::memory_order_relaxed) + 1;
    }

    ULONG STDMETHODCALLTYPE Release() override
    {
        const ULONG remaining =
            references_.fetch_sub(1, std::memory_order_acq_rel) - 1;
        if (remaining == 0) {
            delete this;
        }
        return remaining;
    }

    HRESULT STDMETHODCALLTYPE MessagesReceived(
        GUID,
        GUID,
        UINT64 timestamp,
        UINT32 word_count,
        UINT32 *messages
    ) override
    {
        if (receive_ == nullptr || messages == nullptr || word_count == 0) {
            failures_.fetch_add(1, std::memory_order_relaxed);
            return E_INVALIDARG;
        }
        const uint64_t timestamp_nanoseconds =
            ticks_to_nanoseconds(timestamp);
        if (timestamp_nanoseconds == 0) {
            failures_.fetch_add(1, std::memory_order_relaxed);
            return E_FAIL;
        }
        receive_(
            context_,
            timestamp_nanoseconds,
            messages,
            static_cast<size_t>(word_count)
        );
        return S_OK;
    }

    uint64_t failures() const
    {
        return failures_.load(std::memory_order_acquire);
    }

private:
    std::atomic<ULONG> references_{1};
    std::atomic<uint64_t> failures_{0};
    void *context_;
    zv3_win_ump_receive_fn receive_;
};

std::string session_name(std::string_view suffix)
{
    std::lock_guard<std::mutex> lock(runtime.mutex);
    std::string result = runtime.client_name;
    result.push_back(' ');
    result.append(suffix);
    return result;
}

bool endpoint_directions(
    const midi2::MidiEndpointDeviceInformation &information,
    bool &input,
    bool &output
)
{
    input = false;
    output = false;
    bool found_active = false;
    for (const auto &block : information.GetDeclaredFunctionBlocks()) {
        if (!block.IsActive()) {
            continue;
        }
        found_active = true;
        switch (block.Direction()) {
        case midi2::MidiFunctionBlockDirection::BlockInput:
            output = true;
            break;
        case midi2::MidiFunctionBlockDirection::BlockOutput:
            input = true;
            break;
        case midi2::MidiFunctionBlockDirection::Bidirectional:
            input = true;
            output = true;
            break;
        default:
            break;
        }
    }
    if (!found_active) {
        input = true;
        output = true;
    }
    return input || output;
}

}

struct zv3_win_ump_input {
    midi2::MidiSession session{nullptr};
    midi2::MidiEndpointConnection connection{nullptr};
    winrt::com_ptr<IMidiEndpointConnectionRaw> raw;
    receive_callback *callback = nullptr;
};

struct zv3_win_ump_output {
    midi2::MidiSession session{nullptr};
    midi2::MidiEndpointConnection connection{nullptr};
    winrt::com_ptr<IMidiEndpointConnectionRaw> raw;
    std::atomic<uint64_t> queued{0};
    std::atomic<uint64_t> delivered{0};
    std::atomic<uint64_t> late{0};
    std::atomic<uint64_t> rejected{0};
    std::atomic<uint64_t> write_failures{0};
};

extern "C" int32_t zv3_win_ump_available(void)
{
    const HRESULT apartment_result = RoInitialize(RO_INIT_MULTITHREADED);
    const bool usable_apartment =
        SUCCEEDED(apartment_result) ||
        apartment_result == RPC_E_CHANGED_MODE;
    if (!usable_apartment) {
        return 0;
    }
    initialization::MidiDesktopAppSdkInitializer initializer;
    try {
        const bool available =
            initializer.IsServiceInstalled() &&
            initializer.InitializeSdkRuntime() &&
            initializer.CheckForMinimumRequiredSdkVersion(1, 0, 17) &&
            initializer.EnsureServiceAvailable();
        initializer.ShutdownSdkRuntime();
        if (SUCCEEDED(apartment_result)) {
            RoUninitialize();
        }
        return available ? 1 : 0;
    } catch (...) {
        try {
            initializer.ShutdownSdkRuntime();
        } catch (...) {
        }
        if (SUCCEEDED(apartment_result)) {
            RoUninitialize();
        }
        return 0;
    }
}

extern "C" int32_t zv3_win_ump_acquire(
    const uint8_t *client_name,
    size_t client_name_length
)
{
    if (client_name == nullptr || client_name_length == 0) {
        return -1;
    }
    bool starting_runtime = false;
    try {
        std::lock_guard<std::mutex> lock(runtime.mutex);
        if (runtime.references != 0) {
            if (runtime.apartment_thread != std::this_thread::get_id() ||
                runtime.references ==
                    std::numeric_limits<uint32_t>::max()) {
                return -1;
            }
            ++runtime.references;
            return 0;
        }
        starting_runtime = true;

        const HRESULT apartment_result =
            RoInitialize(RO_INIT_MULTITHREADED);
        if (FAILED(apartment_result) &&
            apartment_result != RPC_E_CHANGED_MODE) {
            return -1;
        }
        runtime.apartment_owned = SUCCEEDED(apartment_result);
        runtime.apartment_thread = std::this_thread::get_id();
        runtime.client_name.assign(
            reinterpret_cast<const char *>(client_name),
            client_name_length
        );

        if (!runtime.initializer.IsServiceInstalled() ||
            !runtime.initializer.InitializeSdkRuntime() ||
            !runtime.initializer.CheckForMinimumRequiredSdkVersion(
                1,
                0,
                17
            ) ||
            !runtime.initializer.EnsureServiceAvailable()) {
            runtime.initializer.ShutdownSdkRuntime();
            runtime.client_name.clear();
            if (runtime.apartment_owned) {
                RoUninitialize();
            }
            runtime.apartment_owned = false;
            return -1;
        }
        runtime.references = 1;
        return 0;
    } catch (...) {
        if (starting_runtime) {
            try {
                std::lock_guard<std::mutex> lock(runtime.mutex);
                reset_runtime_locked();
            } catch (...) {
            }
        }
        return -1;
    }
}

extern "C" void zv3_win_ump_release(void)
{
    try {
        std::lock_guard<std::mutex> lock(runtime.mutex);
        if (runtime.references == 0 ||
            runtime.apartment_thread != std::this_thread::get_id()) {
            return;
        }
        --runtime.references;
        if (runtime.references != 0) {
            return;
        }
        reset_runtime_locked();
    } catch (...) {
    }
}

extern "C" int32_t zv3_win_ump_refresh_topology(void)
{
    try {
        std::vector<endpoint> inputs;
        std::vector<endpoint> outputs;
        for (const auto &information :
            midi2::MidiEndpointDeviceInformation::FindAll()) {
            bool input = false;
            bool output = false;
            if (!endpoint_directions(information, input, output)) {
                continue;
            }
            endpoint value{
                winrt::to_string(information.EndpointDeviceId()),
                winrt::to_string(information.Name())
            };
            if (value.id.empty() || value.name.empty()) {
                continue;
            }
            if (input) {
                inputs.push_back(value);
            }
            if (output) {
                outputs.push_back(std::move(value));
            }
        }
        std::lock_guard<std::mutex> lock(runtime.mutex);
        if (runtime.references == 0) {
            return -1;
        }
        runtime.inputs = std::move(inputs);
        runtime.outputs = std::move(outputs);
        return 0;
    } catch (...) {
        return -3;
    }
}

extern "C" uint64_t zv3_win_ump_now_nanoseconds(void)
{
    return ticks_to_nanoseconds(qpc_now());
}

extern "C" int32_t zv3_win_ump_device_count(
    uint32_t direction,
    size_t *output
)
{
    if (!valid_direction(direction) || output == nullptr) {
        return -3;
    }
    try {
        std::lock_guard<std::mutex> lock(runtime.mutex);
        if (runtime.references == 0) {
            return -1;
        }
        *output = endpoints_for(direction).size();
        return 0;
    } catch (...) {
        return -1;
    }
}

static int32_t device_text(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length,
    bool name
)
{
    if (!valid_direction(direction)) {
        return -3;
    }
    try {
        std::lock_guard<std::mutex> lock(runtime.mutex);
        const auto &endpoints = endpoints_for(direction);
        if (runtime.references == 0 || index >= endpoints.size()) {
            return -3;
        }
        const std::string &value =
            name ? endpoints[index].name : endpoints[index].id;
        return copy_text(
            value,
            output,
            output_capacity,
            output_length
        ) ? 0 : -2;
    } catch (...) {
        return -1;
    }
}

extern "C" int32_t zv3_win_ump_device_id(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    return device_text(
        direction,
        index,
        output,
        output_capacity,
        output_length,
        false
    );
}

extern "C" int32_t zv3_win_ump_device_name(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    return device_text(
        direction,
        index,
        output,
        output_capacity,
        output_length,
        true
    );
}

extern "C" int32_t zv3_win_ump_start_input(
    const uint8_t *endpoint_id,
    size_t endpoint_id_length,
    void *context,
    zv3_win_ump_receive_fn receive,
    zv3_win_ump_input **output
)
{
    if (endpoint_id == nullptr || endpoint_id_length == 0 ||
        context == nullptr || receive == nullptr || output == nullptr) {
        return -5;
    }
    *output = nullptr;
    try {
        std::unique_ptr<zv3_win_ump_input> input(
            new (std::nothrow) zv3_win_ump_input
        );
        if (input == nullptr) {
            return -1;
        }
        const std::string id(
            reinterpret_cast<const char *>(endpoint_id),
            endpoint_id_length
        );
        input->session = midi2::MidiSession::Create(
            winrt::to_hstring(session_name("input"))
        );
        input->connection = input->session.CreateEndpointConnection(
            winrt::to_hstring(id)
        );
        input->raw = input->connection.as<IMidiEndpointConnectionRaw>();
        input->callback = new (std::nothrow) receive_callback(
            context,
            receive
        );
        if (input->callback == nullptr ||
            FAILED(input->raw->SetMessagesReceivedCallback(
                input->callback
            )) ||
            !input->connection.Open()) {
            if (input->callback != nullptr) {
                input->raw->RemoveMessagesReceivedCallback();
                input->callback->Release();
            }
            return -1;
        }
        *output = input.release();
        return 0;
    } catch (...) {
        return -1;
    }
}

extern "C" void zv3_win_ump_stop_input(
    zv3_win_ump_input *input,
    zv3_win_ump_input_statistics *final_statistics
)
{
    if (final_statistics != nullptr) {
        final_statistics->read_failures =
            input != nullptr && input->callback != nullptr
            ? input->callback->failures()
            : 0;
    }
    if (input == nullptr) {
        return;
    }
    std::unique_ptr<zv3_win_ump_input> owned(input);
    try {
        if (input->raw) {
            input->raw->RemoveMessagesReceivedCallback();
        }
    } catch (...) {
    }
    input->raw = nullptr;
    input->connection = nullptr;
    try {
        if (input->session != nullptr) {
            input->session.Close();
        }
    } catch (...) {
    }
    input->session = nullptr;
    if (input->callback != nullptr) {
        input->callback->Release();
        input->callback = nullptr;
    }
}

extern "C" void zv3_win_ump_get_input_statistics(
    const zv3_win_ump_input *input,
    zv3_win_ump_input_statistics *output
)
{
    if (output != nullptr) {
        output->read_failures =
            input != nullptr && input->callback != nullptr
            ? input->callback->failures()
            : 0;
    }
}

extern "C" int32_t zv3_win_ump_open_output(
    const uint8_t *endpoint_id,
    size_t endpoint_id_length,
    zv3_win_ump_output **output
)
{
    if (endpoint_id == nullptr || endpoint_id_length == 0 ||
        output == nullptr) {
        return -5;
    }
    *output = nullptr;
    try {
        std::unique_ptr<zv3_win_ump_output> result(
            new (std::nothrow) zv3_win_ump_output
        );
        if (result == nullptr) {
            return -1;
        }
        const std::string id(
            reinterpret_cast<const char *>(endpoint_id),
            endpoint_id_length
        );
        result->session = midi2::MidiSession::Create(
            winrt::to_hstring(session_name("output"))
        );
        result->connection = result->session.CreateEndpointConnection(
            winrt::to_hstring(id)
        );
        result->raw =
            result->connection.as<IMidiEndpointConnectionRaw>();
        if (!result->connection.Open()) {
            return -1;
        }
        *output = result.release();
        return 0;
    } catch (...) {
        return -1;
    }
}

extern "C" int32_t zv3_win_ump_send(
    zv3_win_ump_output *output,
    uint64_t timestamp_nanoseconds,
    const uint32_t *words,
    size_t word_count
)
{
    if (output == nullptr || words == nullptr || word_count == 0 ||
        word_count > 4 || packet_word_count(words[0]) != word_count) {
        if (output != nullptr) {
            output->rejected.fetch_add(1, std::memory_order_relaxed);
        }
        return -5;
    }
    const uint64_t timestamp = nanoseconds_to_ticks(
        timestamp_nanoseconds
    );
    const uint64_t now = qpc_now();
    if (timestamp == 0 || now == 0) {
        output->rejected.fetch_add(1, std::memory_order_relaxed);
        output->write_failures.fetch_add(1, std::memory_order_relaxed);
        return -1;
    }
    output->queued.fetch_add(1, std::memory_order_relaxed);
    if (timestamp <= now) {
        output->late.fetch_add(1, std::memory_order_relaxed);
    }
    const HRESULT result = output->raw->SendMidiMessagesRaw(
        timestamp,
        static_cast<UINT32>(word_count),
        const_cast<UINT32 *>(words)
    );
    if (SUCCEEDED(result)) {
        output->delivered.fetch_add(1, std::memory_order_relaxed);
        return 0;
    }
    output->rejected.fetch_add(1, std::memory_order_relaxed);
    const uint16_t code = HRESULT_CODE(result);
    if (code == 0x620 || code == 0x621) {
        return -4;
    }
    output->write_failures.fetch_add(1, std::memory_order_relaxed);
    return -1;
}

static void output_statistics(
    const zv3_win_ump_output *output,
    zv3_win_ump_output_statistics *statistics
)
{
    if (statistics == nullptr) {
        return;
    }
    if (output == nullptr) {
        std::memset(statistics, 0, sizeof(*statistics));
        return;
    }
    statistics->queued = output->queued.load(std::memory_order_acquire);
    statistics->delivered =
        output->delivered.load(std::memory_order_acquire);
    statistics->late = output->late.load(std::memory_order_acquire);
    statistics->rejected =
        output->rejected.load(std::memory_order_acquire);
    statistics->canceled = 0;
    statistics->write_failures =
        output->write_failures.load(std::memory_order_acquire);
}

extern "C" void zv3_win_ump_get_output_statistics(
    const zv3_win_ump_output *output,
    zv3_win_ump_output_statistics *statistics
)
{
    output_statistics(output, statistics);
}

extern "C" void zv3_win_ump_close_output(
    zv3_win_ump_output *output,
    zv3_win_ump_output_statistics *final_statistics
)
{
    output_statistics(output, final_statistics);
    if (output == nullptr) {
        return;
    }
    std::unique_ptr<zv3_win_ump_output> owned(output);
    output->raw = nullptr;
    output->connection = nullptr;
    try {
        if (output->session != nullptr) {
            output->session.Close();
        }
    } catch (...) {
    }
    output->session = nullptr;
}
