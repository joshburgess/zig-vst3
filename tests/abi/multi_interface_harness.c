#include <stdint.h>

typedef int32_t tresult;
typedef uint32_t uint32;
typedef uint8_t TUID[16];

typedef struct FUnknownVTable FUnknownVTable;
typedef struct FUnknownHeader FUnknownHeader;
typedef struct InterfaceHeader InterfaceHeader;
typedef struct TestAVTable TestAVTable;
typedef struct TestBVTable TestBVTable;
typedef struct TestCVTable TestCVTable;

struct FUnknownVTable {
	tresult (*queryInterface) (void*, const TUID*, void**);
	uint32 (*addRef) (void*);
	uint32 (*release) (void*);
};

struct FUnknownHeader {
	const FUnknownVTable* vtable;
	uint32 ref_count;
	void* destroy;
};

struct InterfaceHeader {
	const void* vtable;
};

struct TestAVTable {
	tresult (*queryInterface) (void*, const TUID*, void**);
	uint32 (*addRef) (void*);
	uint32 (*release) (void*);
	uint32 (*callA) (void*);
};

struct TestBVTable {
	tresult (*queryInterface) (void*, const TUID*, void**);
	uint32 (*addRef) (void*);
	uint32 (*release) (void*);
	uint32 (*callB) (void*);
};

struct TestCVTable {
	tresult (*queryInterface) (void*, const TUID*, void**);
	uint32 (*addRef) (void*);
	uint32 (*release) (void*);
	uint32 (*callC) (void*);
};

typedef struct MultiTestObject {
	FUnknownHeader unknown;
	InterfaceHeader a;
	InterfaceHeader b;
	InterfaceHeader c;
	uint32 a_calls;
	uint32 b_calls;
	uint32 c_calls;
} MultiTestObject;

extern FUnknownHeader* make_multi_test_object (MultiTestObject* out);
extern const TUID* test_a_iid (void);
extern const TUID* test_b_iid (void);
extern const TUID* test_c_iid (void);
extern uint32 multi_object_a_calls (const MultiTestObject* object);
extern uint32 multi_object_b_calls (const MultiTestObject* object);
extern uint32 multi_object_c_calls (const MultiTestObject* object);

int main (void)
{
	MultiTestObject object;
	FUnknownHeader* unknown = make_multi_test_object (&object);
	void* out = 0;

	if (unknown->vtable->queryInterface (unknown, test_a_iid (), &out) != 0)
		return 1;
	if (out != &object.a)
		return 2;

	InterfaceHeader* a = (InterfaceHeader*)out;
	const TestAVTable* a_vtable = (const TestAVTable*)a->vtable;
	if (a_vtable->callA (a) != 1)
		return 3;

	if (a_vtable->queryInterface (a, test_b_iid (), &out) != 0)
		return 4;
	if (out != &object.b)
		return 5;

	InterfaceHeader* b = (InterfaceHeader*)out;
	const TestBVTable* b_vtable = (const TestBVTable*)b->vtable;
	if (b_vtable->callB (b) != 1)
		return 6;

	if (b_vtable->queryInterface (b, test_c_iid (), &out) != 0)
		return 7;
	if (out != &object.c)
		return 8;

	InterfaceHeader* c = (InterfaceHeader*)out;
	const TestCVTable* c_vtable = (const TestCVTable*)c->vtable;
	if (c_vtable->callC (c) != 1)
		return 9;

	if (c_vtable->queryInterface (c, test_a_iid (), &out) != 0)
		return 10;
	if (out != &object.a)
		return 11;

	if (multi_object_a_calls (&object) != 1)
		return 12;
	if (multi_object_b_calls (&object) != 1)
		return 13;
	if (multi_object_c_calls (&object) != 1)
		return 14;

	return 0;
}
