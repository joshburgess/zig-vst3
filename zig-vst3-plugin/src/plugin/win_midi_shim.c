#define WIN32_LEAN_AND_MEAN

#include "win_midi_shim.h"
#include "midi_scheduler_queue.h"

#include <windows.h>
#include <mmsystem.h>
#include <mmddk.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

static int copy_utf8(
    const WCHAR *source,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    int source_length;
    int required;
    if (source == NULL || output == NULL || output_length == NULL ||
        output_capacity > INT_MAX) {
        return -1;
    }
    source_length = (int)wcslen(source);
    if (source_length == 0) {
        return -1;
    }
    required = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        source,
        source_length,
        NULL,
        0,
        NULL,
        NULL
    );
    if (required <= 0 || (size_t)required > output_capacity) {
        return -1;
    }
    if (WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        source,
        source_length,
        (char *)output,
        required,
        NULL,
        NULL
    ) != required) {
        return -1;
    }
    *output_length = (size_t)required;
    return 0;
}

static MMRESULT query_interface_size(
    uint32_t direction,
    size_t index,
    DWORD *output
)
{
    if (index > UINT_MAX || output == NULL) {
        return MMSYSERR_INVALPARAM;
    }
    if (direction == ZV3_WIN_MIDI_INPUT) {
        return midiInMessage(
            (HMIDIIN)(UINT_PTR)index,
            DRV_QUERYDEVICEINTERFACESIZE,
            (DWORD_PTR)output,
            0
        );
    }
    return midiOutMessage(
        (HMIDIOUT)(UINT_PTR)index,
        DRV_QUERYDEVICEINTERFACESIZE,
        (DWORD_PTR)output,
        0
    );
}

static MMRESULT query_interface(
    uint32_t direction,
    size_t index,
    WCHAR *output,
    DWORD output_bytes
)
{
    if (direction == ZV3_WIN_MIDI_INPUT) {
        return midiInMessage(
            (HMIDIIN)(UINT_PTR)index,
            DRV_QUERYDEVICEINTERFACE,
            (DWORD_PTR)output,
            output_bytes
        );
    }
    return midiOutMessage(
        (HMIDIOUT)(UINT_PTR)index,
        DRV_QUERYDEVICEINTERFACE,
        (DWORD_PTR)output,
        output_bytes
    );
}

uint64_t zv3_win_midi_now_nanoseconds(void)
{
    LARGE_INTEGER frequency;
    LARGE_INTEGER counter;
    uint64_t quotient;
    uint64_t remainder;
    if (!QueryPerformanceFrequency(&frequency) ||
        !QueryPerformanceCounter(&counter) ||
        frequency.QuadPart <= 0 ||
        counter.QuadPart < 0) {
        return 0;
    }
    quotient = (uint64_t)counter.QuadPart /
        (uint64_t)frequency.QuadPart;
    remainder = (uint64_t)counter.QuadPart %
        (uint64_t)frequency.QuadPart;
    return quotient * 1000000000u +
        (remainder * 1000000000u) /
            (uint64_t)frequency.QuadPart;
}

int32_t zv3_win_midi_device_count(
    uint32_t direction,
    size_t *output
)
{
    if (output == NULL || direction > ZV3_WIN_MIDI_OUTPUT) {
        return -1;
    }
    *output = direction == ZV3_WIN_MIDI_INPUT
        ? (size_t)midiInGetNumDevs()
        : (size_t)midiOutGetNumDevs();
    return 0;
}

int32_t zv3_win_midi_device_id(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    DWORD interface_bytes = 0;
    WCHAR *interface_name;
    int result;
    if (direction > ZV3_WIN_MIDI_OUTPUT || index > UINT_MAX ||
        output == NULL || output_length == NULL ||
        output_capacity == 0) {
        return -1;
    }
    if (query_interface_size(
            direction,
            index,
            &interface_bytes
        ) != MMSYSERR_NOERROR ||
        interface_bytes < sizeof(WCHAR) ||
        interface_bytes > INT_MAX) {
        WCHAR fallback_name[MAXPNAMELEN];
        int prefix_length;
        size_t name_length;
        if (direction == ZV3_WIN_MIDI_INPUT) {
            MIDIINCAPSW capabilities;
            memset(&capabilities, 0, sizeof(capabilities));
            if (midiInGetDevCapsW(
                (UINT_PTR)index,
                &capabilities,
                sizeof(capabilities)
            ) != MMSYSERR_NOERROR) {
                return -1;
            }
            memcpy(
                fallback_name,
                capabilities.szPname,
                sizeof(fallback_name)
            );
            prefix_length = snprintf(
                (char *)output,
                output_capacity,
                "winmm:i:%u:%u:%lu:%zu:",
                capabilities.wMid,
                capabilities.wPid,
                (unsigned long)capabilities.vDriverVersion,
                index
            );
        } else {
            MIDIOUTCAPSW capabilities;
            memset(&capabilities, 0, sizeof(capabilities));
            if (midiOutGetDevCapsW(
                (UINT_PTR)index,
                &capabilities,
                sizeof(capabilities)
            ) != MMSYSERR_NOERROR) {
                return -1;
            }
            memcpy(
                fallback_name,
                capabilities.szPname,
                sizeof(fallback_name)
            );
            prefix_length = snprintf(
                (char *)output,
                output_capacity,
                "winmm:o:%u:%u:%lu:%zu:",
                capabilities.wMid,
                capabilities.wPid,
                (unsigned long)capabilities.vDriverVersion,
                index
            );
        }
        fallback_name[MAXPNAMELEN - 1] = L'\0';
        if (prefix_length <= 0 ||
            (size_t)prefix_length >= output_capacity) {
            return -1;
        }
        if (copy_utf8(
            fallback_name,
            output + prefix_length,
            output_capacity - (size_t)prefix_length,
            &name_length
        ) != 0) {
            return -1;
        }
        *output_length = (size_t)prefix_length + name_length;
        return 0;
    }
    interface_name = calloc(1, interface_bytes);
    if (interface_name == NULL) {
        return -1;
    }
    if (query_interface(
        direction,
        index,
        interface_name,
        interface_bytes
    ) != MMSYSERR_NOERROR) {
        free(interface_name);
        return -1;
    }
    interface_name[interface_bytes / sizeof(WCHAR) - 1] = L'\0';
    result = copy_utf8(
        interface_name,
        output,
        output_capacity,
        output_length
    );
    free(interface_name);
    return result;
}

int32_t zv3_win_midi_device_name(
    uint32_t direction,
    size_t index,
    uint8_t *output,
    size_t output_capacity,
    size_t *output_length
)
{
    if (index > UINT_MAX || direction > ZV3_WIN_MIDI_OUTPUT) {
        return -1;
    }
    if (direction == ZV3_WIN_MIDI_INPUT) {
        MIDIINCAPSW capabilities;
        memset(&capabilities, 0, sizeof(capabilities));
        if (midiInGetDevCapsW(
            (UINT_PTR)index,
            &capabilities,
            sizeof(capabilities)
        ) != MMSYSERR_NOERROR) {
            return -1;
        }
        return copy_utf8(
            capabilities.szPname,
            output,
            output_capacity,
            output_length
        );
    }
    {
        MIDIOUTCAPSW capabilities;
        memset(&capabilities, 0, sizeof(capabilities));
        if (midiOutGetDevCapsW(
            (UINT_PTR)index,
            &capabilities,
            sizeof(capabilities)
        ) != MMSYSERR_NOERROR) {
            return -1;
        }
        return copy_utf8(
            capabilities.szPname,
            output,
            output_capacity,
            output_length
        );
    }
}

struct zv3_win_midi_input {
    HMIDIIN handle;
    void *context;
    zv3_win_midi_receive_fn receive;
    uint64_t start_nanoseconds;
    uint64_t timestamp_epoch_milliseconds;
    DWORD last_timestamp_milliseconds;
    CRITICAL_SECTION timestamp_lock;
    volatile LONG running;
    volatile LONG64 driver_errors;
};

static size_t short_message_length(uint8_t status)
{
    if (status < 0x80) {
        return 0;
    }
    if (status < 0xf0) {
        return (status & 0xf0) == 0xc0 ||
            (status & 0xf0) == 0xd0
            ? 2
            : 3;
    }
    switch (status) {
        case 0xf1:
        case 0xf3:
            return 2;
        case 0xf2:
            return 3;
        default:
            return 1;
    }
}

static void CALLBACK input_callback(
    HMIDIIN handle,
    UINT message,
    DWORD_PTR instance_value,
    DWORD_PTR packed_message,
    DWORD_PTR timestamp_milliseconds
)
{
    zv3_win_midi_input *input =
        (zv3_win_midi_input *)instance_value;
    uint8_t bytes[3];
    size_t length;
    DWORD timestamp;
    uint64_t absolute_milliseconds;
    (void)handle;
    if (input == NULL ||
        InterlockedCompareExchange(&input->running, 0, 0) == 0) {
        return;
    }
    if (message == MIM_ERROR || message == MIM_LONGERROR) {
        InterlockedIncrement64(&input->driver_errors);
        return;
    }
    if (message != MIM_DATA && message != MIM_MOREDATA) {
        return;
    }
    bytes[0] = (uint8_t)(packed_message & 0xffu);
    bytes[1] = (uint8_t)((packed_message >> 8u) & 0xffu);
    bytes[2] = (uint8_t)((packed_message >> 16u) & 0xffu);
    length = short_message_length(bytes[0]);
    if (length == 0) {
        InterlockedIncrement64(&input->driver_errors);
        return;
    }
    timestamp = (DWORD)timestamp_milliseconds;
    EnterCriticalSection(&input->timestamp_lock);
    if (timestamp < input->last_timestamp_milliseconds &&
        input->last_timestamp_milliseconds - timestamp >
            0x80000000u) {
        input->timestamp_epoch_milliseconds += 1ull << 32u;
    }
    input->last_timestamp_milliseconds = timestamp;
    absolute_milliseconds =
        input->timestamp_epoch_milliseconds + timestamp;
    LeaveCriticalSection(&input->timestamp_lock);
    input->receive(
        input->context,
        input->start_nanoseconds +
            absolute_milliseconds * 1000000u,
        bytes,
        length
    );
}

int32_t zv3_win_midi_start_input(
    size_t index,
    void *context,
    zv3_win_midi_receive_fn receive,
    zv3_win_midi_input **output
)
{
    zv3_win_midi_input *input;
    if (index > UINT_MAX || receive == NULL || output == NULL) {
        return -1;
    }
    *output = NULL;
    input = calloc(1, sizeof(*input));
    if (input == NULL) {
        return -1;
    }
    input->context = context;
    input->receive = receive;
    InitializeCriticalSection(&input->timestamp_lock);
    if (midiInOpen(
        &input->handle,
        (UINT)index,
        (DWORD_PTR)input_callback,
        (DWORD_PTR)input,
        CALLBACK_FUNCTION | MIDI_IO_STATUS
    ) != MMSYSERR_NOERROR) {
        DeleteCriticalSection(&input->timestamp_lock);
        free(input);
        return -1;
    }
    input->start_nanoseconds = zv3_win_midi_now_nanoseconds();
    if (input->start_nanoseconds == 0) {
        midiInClose(input->handle);
        DeleteCriticalSection(&input->timestamp_lock);
        free(input);
        return -1;
    }
    InterlockedExchange(&input->running, 1);
    if (midiInStart(input->handle) != MMSYSERR_NOERROR) {
        InterlockedExchange(&input->running, 0);
        midiInClose(input->handle);
        DeleteCriticalSection(&input->timestamp_lock);
        free(input);
        return -1;
    }
    *output = input;
    return 0;
}

void zv3_win_midi_get_input_statistics(
    const zv3_win_midi_input *input,
    zv3_win_midi_input_statistics *output
)
{
    if (input == NULL || output == NULL) {
        return;
    }
    output->driver_errors = (uint64_t)InterlockedCompareExchange64(
        (volatile LONG64 *)&input->driver_errors,
        0,
        0
    );
}

void zv3_win_midi_stop_input(
    zv3_win_midi_input *input,
    zv3_win_midi_input_statistics *final_statistics
)
{
    if (input == NULL) {
        return;
    }
    InterlockedExchange(&input->running, 0);
    if (midiInStop(input->handle) != MMSYSERR_NOERROR) {
        InterlockedIncrement64(&input->driver_errors);
    }
    if (midiInReset(input->handle) != MMSYSERR_NOERROR) {
        InterlockedIncrement64(&input->driver_errors);
    }
    if (midiInClose(input->handle) != MMSYSERR_NOERROR) {
        InterlockedIncrement64(&input->driver_errors);
    }
    zv3_win_midi_get_input_statistics(input, final_statistics);
    DeleteCriticalSection(&input->timestamp_lock);
    free(input);
}

struct zv3_win_midi_output {
    HMIDIOUT handle;
    CRITICAL_SECTION lock;
    CONDITION_VARIABLE condition;
    HANDLE thread;
    int stop_requested;
    zv3_midi_scheduler_queue queue;
    volatile LONG64 queued;
    volatile LONG64 delivered;
    volatile LONG64 late;
    volatile LONG64 rejected;
    volatile LONG64 canceled;
    volatile LONG64 driver_errors;
};

static MMRESULT send_short_message(
    zv3_win_midi_output *output,
    const zv3_midi_scheduled_message *message
)
{
    DWORD packed = message->bytes[0];
    if (message->length > 1) {
        packed |= (DWORD)message->bytes[1] << 8u;
    }
    if (message->length > 2) {
        packed |= (DWORD)message->bytes[2] << 16u;
    }
    return midiOutShortMsg(output->handle, packed);
}

static DWORD WINAPI output_thread(void *context)
{
    zv3_win_midi_output *output = context;
    EnterCriticalSection(&output->lock);
    while (!output->stop_requested) {
        zv3_midi_scheduled_message message;
        uint64_t now;
        if (output->queue.count == 0) {
            SleepConditionVariableCS(
                &output->condition,
                &output->lock,
                INFINITE
            );
            continue;
        }
        now = zv3_win_midi_now_nanoseconds();
        if (now == 0) {
            InterlockedIncrement64(&output->driver_errors);
            output->stop_requested = 1;
            break;
        }
        if (output->queue.messages[0].timestamp_nanoseconds > now) {
            uint64_t delta =
                output->queue.messages[0].timestamp_nanoseconds - now;
            uint64_t milliseconds =
                (delta + 999999u) / 1000000u;
            DWORD timeout = milliseconds >= (uint64_t)(INFINITE - 1u)
                ? INFINITE - 1u
                : (DWORD)milliseconds;
            SleepConditionVariableCS(
                &output->condition,
                &output->lock,
                timeout
            );
            continue;
        }
        if (!zv3_midi_scheduler_pop_due(
            &output->queue,
            now,
            &message
        ))
            continue;
        LeaveCriticalSection(&output->lock);
        if (message.timestamp_nanoseconds < now) {
            InterlockedIncrement64(&output->late);
        }
        if (send_short_message(output, &message) == MMSYSERR_NOERROR) {
            InterlockedIncrement64(&output->delivered);
        } else {
            InterlockedIncrement64(&output->driver_errors);
        }
        EnterCriticalSection(&output->lock);
    }
    InterlockedExchangeAdd64(
        &output->canceled,
        (LONG64)zv3_midi_scheduler_clear(&output->queue)
    );
    LeaveCriticalSection(&output->lock);
    return 0;
}

int32_t zv3_win_midi_open_output(
    size_t index,
    zv3_win_midi_output **output
)
{
    zv3_win_midi_output *midi_output;
    if (index > UINT_MAX || output == NULL) {
        return -1;
    }
    *output = NULL;
    midi_output = calloc(1, sizeof(*midi_output));
    if (midi_output == NULL) {
        return -1;
    }
    InitializeCriticalSection(&midi_output->lock);
    InitializeConditionVariable(&midi_output->condition);
    if (midiOutOpen(
        &midi_output->handle,
        (UINT)index,
        0,
        0,
        CALLBACK_NULL
    ) != MMSYSERR_NOERROR) {
        DeleteCriticalSection(&midi_output->lock);
        free(midi_output);
        return -1;
    }
    midi_output->thread = CreateThread(
        NULL,
        0,
        output_thread,
        midi_output,
        0,
        NULL
    );
    if (midi_output->thread == NULL) {
        midiOutClose(midi_output->handle);
        DeleteCriticalSection(&midi_output->lock);
        free(midi_output);
        return -1;
    }
    *output = midi_output;
    return 0;
}

int32_t zv3_win_midi_send(
    zv3_win_midi_output *output,
    uint64_t timestamp_nanoseconds,
    const uint8_t *bytes,
    size_t length
)
{
    if (output == NULL || bytes == NULL ||
        timestamp_nanoseconds == 0 ||
        length == 0 || length > 3) {
        return -1;
    }
    if (!TryEnterCriticalSection(&output->lock)) {
        InterlockedIncrement64(&output->rejected);
        return -2;
    }
    if (output->stop_requested ||
        output->queue.count == ZV3_MIDI_SCHEDULER_CAPACITY) {
        InterlockedIncrement64(&output->rejected);
        LeaveCriticalSection(&output->lock);
        return -2;
    }
    if (zv3_midi_scheduler_insert(
        &output->queue,
        timestamp_nanoseconds,
        bytes,
        length
    ) != 0) {
        InterlockedIncrement64(&output->rejected);
        LeaveCriticalSection(&output->lock);
        return -2;
    }
    InterlockedIncrement64(&output->queued);
    WakeConditionVariable(&output->condition);
    LeaveCriticalSection(&output->lock);
    return 0;
}

void zv3_win_midi_get_output_statistics(
    const zv3_win_midi_output *output,
    zv3_win_midi_output_statistics *statistics
)
{
    if (output == NULL || statistics == NULL) {
        return;
    }
    statistics->queued = (uint64_t)InterlockedCompareExchange64(
        (volatile LONG64 *)&output->queued,
        0,
        0
    );
    statistics->delivered = (uint64_t)InterlockedCompareExchange64(
        (volatile LONG64 *)&output->delivered,
        0,
        0
    );
    statistics->late = (uint64_t)InterlockedCompareExchange64(
        (volatile LONG64 *)&output->late,
        0,
        0
    );
    statistics->rejected = (uint64_t)InterlockedCompareExchange64(
        (volatile LONG64 *)&output->rejected,
        0,
        0
    );
    statistics->canceled = (uint64_t)InterlockedCompareExchange64(
        (volatile LONG64 *)&output->canceled,
        0,
        0
    );
    statistics->driver_errors = (uint64_t)InterlockedCompareExchange64(
        (volatile LONG64 *)&output->driver_errors,
        0,
        0
    );
}

void zv3_win_midi_close_output(
    zv3_win_midi_output *output,
    zv3_win_midi_output_statistics *final_statistics
)
{
    if (output == NULL) {
        return;
    }
    EnterCriticalSection(&output->lock);
    output->stop_requested = 1;
    WakeConditionVariable(&output->condition);
    LeaveCriticalSection(&output->lock);
    WaitForSingleObject(output->thread, INFINITE);
    CloseHandle(output->thread);
    if (midiOutReset(output->handle) != MMSYSERR_NOERROR) {
        InterlockedIncrement64(&output->driver_errors);
    }
    if (midiOutClose(output->handle) != MMSYSERR_NOERROR) {
        InterlockedIncrement64(&output->driver_errors);
    }
    zv3_win_midi_get_output_statistics(output, final_statistics);
    DeleteCriticalSection(&output->lock);
    free(output);
}
