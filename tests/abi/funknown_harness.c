#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef int32_t tresult;
typedef uint32_t uint32;
typedef uint8_t TUID[16];

typedef struct FUnknownVTable FUnknownVTable;
typedef struct FUnknownHeader FUnknownHeader;

struct FUnknownVTable {
	tresult (*queryInterface) (void*, const TUID*, void**);
	uint32 (*addRef) (void*);
	uint32 (*release) (void*);
};

struct FUnknownHeader {
	const FUnknownVTable* vtable;
};

typedef struct TestObject {
	FUnknownHeader unknown;
	uint32 ref_count;
	uint32 query_count;
} TestObject;

extern FUnknownHeader* make_test_object (TestObject* out);
extern const TUID* funknown_iid (void);
extern uint32 test_object_ref_count (const TestObject* object);
extern uint32 test_object_query_count (const TestObject* object);

int main (void)
{
	TestObject object;
	FUnknownHeader* unknown = make_test_object (&object);
	void* out = 0;

	if (unknown->vtable->queryInterface (unknown, funknown_iid (), &out) != 0)
		return 1;
	if (out != unknown)
		return 2;
	if (test_object_ref_count (&object) != 2)
		return 3;
	if (test_object_query_count (&object) != 1)
		return 4;
	if (unknown->vtable->release (unknown) != 1)
		return 5;

	TUID missing = {0};
	out = unknown;
	if (unknown->vtable->queryInterface (unknown, &missing, &out) != -1)
		return 6;
	if (out != 0)
		return 7;
	if (unknown->vtable->addRef (unknown) != 2)
		return 8;

	return 0;
}
