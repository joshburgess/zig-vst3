#include <stddef.h>
#include <stdarg.h>
#include <stdint.h>

typedef void* LV2_Handle;
typedef void* LV2_State_Handle;
typedef uint32_t LV2_URID;
typedef void* LV2UI_Handle;
typedef void* LV2UI_Controller;
typedef void* LV2UI_Widget;

typedef struct {
	const char* URI;
	void* data;
} LV2_Feature;

typedef struct LV2_Descriptor LV2_Descriptor;

struct LV2_Descriptor {
	const char* URI;
	LV2_Handle (*instantiate)(
		const LV2_Descriptor*,
		double,
		const char*,
		const LV2_Feature* const*);
	void (*connect_port)(LV2_Handle, uint32_t, void*);
	void (*activate)(LV2_Handle);
	void (*run)(LV2_Handle, uint32_t);
	void (*deactivate)(LV2_Handle);
	void (*cleanup)(LV2_Handle);
	const void* (*extension_data)(const char*);
};

typedef struct LV2UI_Descriptor LV2UI_Descriptor;

struct LV2UI_Descriptor {
	const char* URI;
	LV2UI_Handle (*instantiate)(
		const LV2UI_Descriptor*,
		const char*,
		const char*,
		void (*)(LV2UI_Controller, uint32_t, uint32_t, uint32_t, const void*),
		LV2UI_Controller,
		LV2UI_Widget*,
		const LV2_Feature* const*);
	void (*cleanup)(LV2UI_Handle);
	void (*port_event)(LV2UI_Handle, uint32_t, uint32_t, uint32_t, const void*);
	const void* (*extension_data)(const char*);
};

typedef struct {
	int (*idle)(LV2UI_Handle);
} LV2UI_Idle_Interface;

typedef struct {
	LV2UI_Handle handle;
	int (*ui_resize)(LV2UI_Handle, int, int);
} LV2UI_Resize;

typedef struct {
	int (*ui_resize)(LV2UI_Handle, int, int);
} LV2UI_Resize_Interface;

typedef struct {
	int (*show)(LV2UI_Handle);
	int (*hide)(LV2UI_Handle);
} LV2UI_Show_Interface;

typedef struct {
	LV2UI_Handle handle;
	int (*touch)(LV2UI_Handle, uint32_t, _Bool);
} LV2UI_Touch;

typedef enum {
	LV2UI_REQUEST_VALUE_SUCCESS = 0,
	LV2UI_REQUEST_VALUE_BUSY = 1,
	LV2UI_REQUEST_VALUE_ERR_UNKNOWN = 2,
	LV2UI_REQUEST_VALUE_ERR_UNSUPPORTED = 3
} LV2UI_Request_Value_Status;

typedef struct {
	LV2UI_Handle handle;
	LV2UI_Request_Value_Status (*request)(
		LV2UI_Handle,
		LV2_URID,
		LV2_URID,
		const LV2_Feature* const*);
} LV2UI_Request_Value;

typedef struct {
	LV2UI_Handle handle;
	uint32_t (*port_index)(LV2UI_Handle, const char*);
} LV2UI_Port_Map;

typedef struct {
	LV2UI_Handle handle;
	uint32_t (*subscribe)(
		LV2UI_Handle,
		uint32_t,
		LV2_URID,
		const LV2_Feature* const*);
	uint32_t (*unsubscribe)(
		LV2UI_Handle,
		uint32_t,
		LV2_URID,
		const LV2_Feature* const*);
} LV2UI_Port_Subscribe;

typedef struct {
	uint32_t period_start;
	uint32_t period_size;
	float peak;
} LV2UI_Peak_Data;

typedef struct {
	void* handle;
	LV2_URID (*map)(void*, const char*);
} LV2_URID_Map;

typedef struct {
	void* handle;
	const char* (*unmap)(void*, LV2_URID);
} LV2_URID_Unmap;

typedef struct {
	void* handle;
	int (*printf)(void*, LV2_URID, const char*, ...);
	int (*vprintf)(void*, LV2_URID, const char*, va_list);
} LV2_Log_Log;

typedef enum {
	LV2_RESIZE_PORT_SUCCESS = 0,
	LV2_RESIZE_PORT_ERR_UNKNOWN = 1,
	LV2_RESIZE_PORT_ERR_NO_SPACE = 2
} LV2_Resize_Port_Status;

typedef struct {
	void* data;
	LV2_Resize_Port_Status (*resize)(void*, uint32_t, size_t);
} LV2_Resize_Port_Resize;

typedef struct {
	uint32_t size;
	uint32_t type;
} LV2_Atom;

typedef struct {
	union {
		int64_t frames;
		double beats;
	} time;
	LV2_Atom body;
} LV2_Atom_Event;

typedef struct {
	uint32_t unit;
	uint32_t pad;
} LV2_Atom_Sequence_Body;

typedef struct {
	LV2_Atom atom;
	LV2_Atom_Sequence_Body body;
} LV2_Atom_Sequence;

typedef struct {
	uint32_t id;
	uint32_t otype;
} LV2_Atom_Object_Body;

typedef struct {
	LV2_Atom atom;
	LV2_Atom_Object_Body body;
} LV2_Atom_Object;

typedef struct {
	uint32_t key;
	uint32_t context;
	LV2_Atom value;
} LV2_Atom_Property_Body;

typedef struct {
	LV2_Atom atom;
	float body;
} LV2_Atom_Float;

typedef struct {
	LV2_Atom atom;
	double body;
} LV2_Atom_Double;

typedef struct {
	LV2_Atom atom;
	int32_t body;
} LV2_Atom_Int;

typedef struct {
	LV2_Atom atom;
	int64_t body;
} LV2_Atom_Long;

typedef struct {
	LV2_Atom atom;
	int32_t body;
} LV2_Atom_Bool;

typedef struct {
	LV2_Atom atom;
	LV2_URID body;
} LV2_Atom_URID;

typedef enum {
	LV2_OPTIONS_INSTANCE = 0,
	LV2_OPTIONS_RESOURCE = 1,
	LV2_OPTIONS_BLANK = 2,
	LV2_OPTIONS_PORT = 3
} LV2_Options_Context;

typedef struct {
	LV2_Options_Context context;
	uint32_t subject;
	LV2_URID key;
	uint32_t size;
	LV2_URID type;
	const void* value;
} LV2_Options_Option;

typedef uint32_t LV2_Options_Status;

typedef struct {
	LV2_Options_Status (*get)(
		LV2_Handle,
		LV2_Options_Option*);
	LV2_Options_Status (*set)(
		LV2_Handle,
		const LV2_Options_Option*);
} LV2_Options_Interface;

typedef enum {
	LV2_WORKER_SUCCESS = 0,
	LV2_WORKER_ERR_UNKNOWN = 1,
	LV2_WORKER_ERR_NO_SPACE = 2
} LV2_Worker_Status;

typedef void* LV2_Worker_Respond_Handle;

typedef LV2_Worker_Status (*LV2_Worker_Respond_Function)(
	LV2_Worker_Respond_Handle,
	uint32_t,
	const void*);

typedef struct {
	void* handle;
	LV2_Worker_Status (*schedule_work)(
		void*,
		uint32_t,
		const void*);
} LV2_Worker_Schedule;

typedef struct {
	LV2_Worker_Status (*work)(
		LV2_Handle,
		LV2_Worker_Respond_Function,
		LV2_Worker_Respond_Handle,
		uint32_t,
		const void*);
	LV2_Worker_Status (*work_response)(
		LV2_Handle,
		uint32_t,
		const void*);
	LV2_Worker_Status (*end_run)(LV2_Handle);
} LV2_Worker_Interface;

typedef struct {
	uint32_t bank;
	uint32_t program;
	const char* name;
} LV2_Program_Descriptor;

typedef struct {
	const LV2_Program_Descriptor* (*get_program)(
		LV2_Handle,
		uint32_t);
	void (*select_program)(
		LV2_Handle,
		uint32_t,
		uint32_t);
} LV2_Programs_Interface;

typedef struct {
	void (*select_program)(
		LV2UI_Handle,
		uint32_t,
		uint32_t);
} LV2_Programs_UI_Interface;

typedef enum {
	LV2_STATE_SUCCESS = 0,
	LV2_STATE_ERR_UNKNOWN = 1,
	LV2_STATE_ERR_BAD_TYPE = 2,
	LV2_STATE_ERR_BAD_FLAGS = 3,
	LV2_STATE_ERR_NO_FEATURE = 4,
	LV2_STATE_ERR_NO_PROPERTY = 5,
	LV2_STATE_ERR_NO_SPACE = 6
} LV2_State_Status;

typedef LV2_State_Status (*LV2_State_Store_Function)(
	LV2_State_Handle,
	uint32_t,
	const void*,
	size_t,
	uint32_t,
	uint32_t);

typedef const void* (*LV2_State_Retrieve_Function)(
	LV2_State_Handle,
	uint32_t,
	size_t*,
	uint32_t*,
	uint32_t*);

typedef struct {
	LV2_State_Status (*save)(
		LV2_Handle,
		LV2_State_Store_Function,
		LV2_State_Handle,
		uint32_t,
		const LV2_Feature* const*);
	LV2_State_Status (*restore)(
		LV2_Handle,
		LV2_State_Retrieve_Function,
		LV2_State_Handle,
		uint32_t,
	    const LV2_Feature* const*);
} LV2_State_Interface;

typedef struct {
	LV2_State_Handle handle;
	char* (*abstract_path)(LV2_State_Handle, const char*);
	char* (*absolute_path)(LV2_State_Handle, const char*);
} LV2_State_Map_Path;

typedef struct {
	LV2_State_Handle handle;
	char* (*path)(LV2_State_Handle, const char*);
} LV2_State_Make_Path;

typedef struct {
	LV2_State_Handle handle;
	void (*free_path)(LV2_State_Handle, char*);
} LV2_State_Free_Path;

extern size_t zig_lv2_layout_value(uint32_t index);

int main(void)
{
	const size_t expected[] = {
		sizeof(LV2_Feature),
		_Alignof(LV2_Feature),
		offsetof(LV2_Feature, URI),
		offsetof(LV2_Feature, data),
		sizeof(LV2_Descriptor),
		_Alignof(LV2_Descriptor),
		offsetof(LV2_Descriptor, URI),
		offsetof(LV2_Descriptor, instantiate),
		offsetof(LV2_Descriptor, connect_port),
		offsetof(LV2_Descriptor, activate),
		offsetof(LV2_Descriptor, run),
		offsetof(LV2_Descriptor, deactivate),
		offsetof(LV2_Descriptor, cleanup),
		offsetof(LV2_Descriptor, extension_data),
		sizeof(LV2_URID_Map),
		_Alignof(LV2_URID_Map),
		offsetof(LV2_URID_Map, handle),
		offsetof(LV2_URID_Map, map),
		sizeof(LV2_State_Interface),
		_Alignof(LV2_State_Interface),
		offsetof(LV2_State_Interface, save),
		offsetof(LV2_State_Interface, restore),
		sizeof(LV2_State_Status),
		LV2_STATE_ERR_NO_SPACE,
		(1u << 0u) | (1u << 1u),
		sizeof(LV2_Atom),
		_Alignof(LV2_Atom),
		sizeof(LV2_Atom_Event),
		_Alignof(LV2_Atom_Event),
		offsetof(LV2_Atom_Event, time),
		offsetof(LV2_Atom_Event, body),
		sizeof(LV2_Atom_Sequence_Body),
		sizeof(LV2_Atom_Sequence),
		offsetof(LV2_Atom_Sequence, atom),
		offsetof(LV2_Atom_Sequence, body),
		sizeof(LV2_Atom_Object_Body),
		sizeof(LV2_Atom_Object),
		offsetof(LV2_Atom_Object, body),
		sizeof(LV2_Atom_Property_Body),
		offsetof(LV2_Atom_Property_Body, value),
		sizeof(LV2_Atom_Float),
		offsetof(LV2_Atom_Float, body),
		sizeof(LV2_Atom_Double),
		_Alignof(LV2_Atom_Double),
		offsetof(LV2_Atom_Double, body),
		sizeof(LV2_Atom_Int),
		sizeof(LV2_Atom_Long),
		_Alignof(LV2_Atom_Long),
		offsetof(LV2_Atom_Long, body),
		sizeof(LV2_Options_Context),
		LV2_OPTIONS_PORT,
		sizeof(LV2_Options_Option),
		_Alignof(LV2_Options_Option),
		offsetof(LV2_Options_Option, context),
		offsetof(LV2_Options_Option, subject),
		offsetof(LV2_Options_Option, key),
		offsetof(LV2_Options_Option, size),
		offsetof(LV2_Options_Option, type),
		offsetof(LV2_Options_Option, value),
		sizeof(LV2_Options_Status),
		sizeof(LV2_Options_Interface),
		_Alignof(LV2_Options_Interface),
		offsetof(LV2_Options_Interface, get),
		offsetof(LV2_Options_Interface, set),
		(1u << 0u) | (1u << 1u) | (1u << 2u) | (1u << 3u),
		sizeof(LV2_Worker_Status),
		LV2_WORKER_ERR_NO_SPACE,
		sizeof(LV2_Worker_Schedule),
		_Alignof(LV2_Worker_Schedule),
		offsetof(LV2_Worker_Schedule, handle),
		offsetof(LV2_Worker_Schedule, schedule_work),
		sizeof(LV2_Worker_Interface),
		_Alignof(LV2_Worker_Interface),
		offsetof(LV2_Worker_Interface, work),
		offsetof(LV2_Worker_Interface, work_response),
		offsetof(LV2_Worker_Interface, end_run),
		sizeof(LV2_Feature),
		_Alignof(LV2_Feature),
		sizeof(LV2UI_Descriptor),
		_Alignof(LV2UI_Descriptor),
		offsetof(LV2UI_Descriptor, URI),
		offsetof(LV2UI_Descriptor, instantiate),
		offsetof(LV2UI_Descriptor, cleanup),
		offsetof(LV2UI_Descriptor, port_event),
		offsetof(LV2UI_Descriptor, extension_data),
		sizeof(LV2UI_Idle_Interface),
		_Alignof(LV2UI_Idle_Interface),
		offsetof(LV2UI_Idle_Interface, idle),
		sizeof(LV2UI_Resize),
		_Alignof(LV2UI_Resize),
		offsetof(LV2UI_Resize, handle),
		offsetof(LV2UI_Resize, ui_resize),
		sizeof(LV2UI_Resize_Interface),
		_Alignof(LV2UI_Resize_Interface),
		offsetof(LV2UI_Resize_Interface, ui_resize),
		sizeof(LV2UI_Show_Interface),
		_Alignof(LV2UI_Show_Interface),
		offsetof(LV2UI_Show_Interface, show),
		offsetof(LV2UI_Show_Interface, hide),
		sizeof(LV2UI_Touch),
		_Alignof(LV2UI_Touch),
		offsetof(LV2UI_Touch, handle),
		offsetof(LV2UI_Touch, touch),
		sizeof(LV2_Program_Descriptor),
		_Alignof(LV2_Program_Descriptor),
		offsetof(LV2_Program_Descriptor, bank),
		offsetof(LV2_Program_Descriptor, program),
		offsetof(LV2_Program_Descriptor, name),
		sizeof(LV2_Programs_Interface),
		_Alignof(LV2_Programs_Interface),
		offsetof(LV2_Programs_Interface, get_program),
		offsetof(LV2_Programs_Interface, select_program),
		sizeof(LV2_Programs_UI_Interface),
		_Alignof(LV2_Programs_UI_Interface),
		offsetof(LV2_Programs_UI_Interface, select_program),
		sizeof(LV2_State_Map_Path),
		_Alignof(LV2_State_Map_Path),
		offsetof(LV2_State_Map_Path, handle),
		offsetof(LV2_State_Map_Path, abstract_path),
		offsetof(LV2_State_Map_Path, absolute_path),
		sizeof(LV2_State_Make_Path),
		_Alignof(LV2_State_Make_Path),
		offsetof(LV2_State_Make_Path, handle),
		offsetof(LV2_State_Make_Path, path),
		sizeof(LV2_State_Free_Path),
		_Alignof(LV2_State_Free_Path),
		offsetof(LV2_State_Free_Path, handle),
		offsetof(LV2_State_Free_Path, free_path),
		sizeof(LV2_Atom_Bool),
		_Alignof(LV2_Atom_Bool),
		offsetof(LV2_Atom_Bool, body),
		sizeof(LV2_Atom_URID),
		_Alignof(LV2_Atom_URID),
		offsetof(LV2_Atom_URID, body),
		sizeof(LV2_URID_Unmap),
		_Alignof(LV2_URID_Unmap),
		offsetof(LV2_URID_Unmap, handle),
		offsetof(LV2_URID_Unmap, unmap),
		sizeof(LV2_Resize_Port_Status),
		LV2_RESIZE_PORT_ERR_NO_SPACE,
		sizeof(LV2_Resize_Port_Resize),
		_Alignof(LV2_Resize_Port_Resize),
		offsetof(LV2_Resize_Port_Resize, data),
		offsetof(LV2_Resize_Port_Resize, resize),
		sizeof(LV2_Log_Log),
		_Alignof(LV2_Log_Log),
		offsetof(LV2_Log_Log, handle),
		offsetof(LV2_Log_Log, printf),
		offsetof(LV2_Log_Log, vprintf),
		sizeof(LV2UI_Request_Value_Status),
		LV2UI_REQUEST_VALUE_ERR_UNSUPPORTED,
		sizeof(LV2UI_Request_Value),
		_Alignof(LV2UI_Request_Value),
		offsetof(LV2UI_Request_Value, handle),
		offsetof(LV2UI_Request_Value, request),
		sizeof(LV2UI_Port_Map),
		_Alignof(LV2UI_Port_Map),
		offsetof(LV2UI_Port_Map, handle),
		offsetof(LV2UI_Port_Map, port_index),
		sizeof(LV2UI_Port_Subscribe),
		_Alignof(LV2UI_Port_Subscribe),
		offsetof(LV2UI_Port_Subscribe, handle),
		offsetof(LV2UI_Port_Subscribe, subscribe),
		offsetof(LV2UI_Port_Subscribe, unsubscribe),
		sizeof(LV2UI_Peak_Data),
		_Alignof(LV2UI_Peak_Data),
		offsetof(LV2UI_Peak_Data, period_start),
		offsetof(LV2UI_Peak_Data, period_size),
		offsetof(LV2UI_Peak_Data, peak),
		UINT32_MAX,
		sizeof(LV2_Atom),
		_Alignof(LV2_Atom),
		offsetof(LV2_Atom, size),
		offsetof(LV2_Atom, type),
	};
	const size_t count = sizeof(expected) / sizeof(expected[0]);
	for (size_t index = 0; index < count; ++index) {
		if (zig_lv2_layout_value((uint32_t)index) != expected[index])
			return (int)index + 1;
	}
	return 0;
}
