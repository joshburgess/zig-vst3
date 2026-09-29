#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    uint32_t call_count;
    uint32_t last_type;
    int result;
    size_t format_size;
    size_t message_size;
    char format[16];
    char message[128];
} ZigLv2LogCapture;

int zig_lv2_log_capture_printf(
    void *raw_capture,
    uint32_t log_type,
    const char *format,
    ...
) {
    ZigLv2LogCapture *capture = raw_capture;
    if (capture == NULL || format == NULL) {
        return -1;
    }

    capture->call_count += 1;
    capture->last_type = log_type;
    capture->format_size = strlen(format);
    (void)snprintf(capture->format, sizeof(capture->format), "%s", format);

    va_list arguments;
    va_start(arguments, format);
    const int message_size = vsnprintf(
        capture->message,
        sizeof(capture->message),
        format,
        arguments
    );
    va_end(arguments);
    capture->message_size = message_size < 0 ? 0 : (size_t)message_size;
    return capture->result;
}
