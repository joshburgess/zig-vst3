#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>

void *zv3_auv2_class_info_create(
    const uint8_t *state_bytes,
    size_t state_size,
    uint32_t component_type,
    uint32_t component_subtype,
    uint32_t component_manufacturer,
    const uint8_t *name_bytes,
    size_t name_size)
{
    if (state_bytes == NULL || name_bytes == NULL ||
        state_size > (size_t)LONG_MAX || name_size > (size_t)LONG_MAX)
        return NULL;

    CFDataRef data = CFDataCreate(
        kCFAllocatorDefault,
        state_bytes,
        (CFIndex)state_size);
    CFStringRef name = CFStringCreateWithBytes(
        kCFAllocatorDefault,
        name_bytes,
        (CFIndex)name_size,
        kCFStringEncodingUTF8,
        false);
    int32_t type = (int32_t)component_type;
    int32_t subtype = (int32_t)component_subtype;
    int32_t manufacturer = (int32_t)component_manufacturer;
    int32_t version = 1;
    int32_t preset_number = -1;
    CFNumberRef type_number = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt32Type, &type);
    CFNumberRef subtype_number = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt32Type, &subtype);
    CFNumberRef manufacturer_number = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt32Type, &manufacturer);
    CFNumberRef version_number = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt32Type, &version);
    CFNumberRef preset_number_value = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt32Type, &preset_number);
    if (data == NULL || name == NULL || type_number == NULL ||
        subtype_number == NULL || manufacturer_number == NULL ||
        version_number == NULL || preset_number_value == NULL) {
        if (data != NULL)
            CFRelease(data);
        if (name != NULL)
            CFRelease(name);
        if (type_number != NULL)
            CFRelease(type_number);
        if (subtype_number != NULL)
            CFRelease(subtype_number);
        if (manufacturer_number != NULL)
            CFRelease(manufacturer_number);
        if (version_number != NULL)
            CFRelease(version_number);
        if (preset_number_value != NULL)
            CFRelease(preset_number_value);
        return NULL;
    }

    const void *keys[] = {
        CFSTR(kAUPresetTypeKey),
        CFSTR(kAUPresetSubtypeKey),
        CFSTR(kAUPresetManufacturerKey),
        CFSTR(kAUPresetVersionKey),
        CFSTR(kAUPresetNameKey),
        CFSTR(kAUPresetNumberKey),
        CFSTR(kAUPresetDataKey),
    };
    const void *values[] = {
        type_number,
        subtype_number,
        manufacturer_number,
        version_number,
        name,
        preset_number_value,
        data,
    };
    CFDictionaryRef result = CFDictionaryCreate(
        kCFAllocatorDefault,
        keys,
        values,
        7,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    CFRelease(data);
    CFRelease(name);
    CFRelease(type_number);
    CFRelease(subtype_number);
    CFRelease(manufacturer_number);
    CFRelease(version_number);
    CFRelease(preset_number_value);
    return (void *)result;
}

int zv3_auv2_class_info_copy_state(
    const void *property_list,
    uint8_t *destination,
    size_t destination_capacity,
    size_t *output_size)
{
    if (property_list == NULL || destination == NULL || output_size == NULL)
        return 0;

    CFTypeRef value = (CFTypeRef)property_list;
    if (CFGetTypeID(value) != CFDictionaryGetTypeID())
        return 0;

    CFTypeRef state = CFDictionaryGetValue(
        (CFDictionaryRef)value,
        CFSTR(kAUPresetDataKey));
    if (state == NULL || CFGetTypeID(state) != CFDataGetTypeID())
        return 0;

    CFIndex length = CFDataGetLength((CFDataRef)state);
    if (length < 0 || (size_t)length > destination_capacity)
        return 0;
    CFDataGetBytes(
        (CFDataRef)state,
        CFRangeMake(0, length),
        destination);
    *output_size = (size_t)length;
    return 1;
}
