#include <cstdint>

using tresult = int32_t;
using uint32 = uint32_t;
using TUID = uint8_t[16];

struct FUnknownVTable {
    tresult (*queryInterface)(void*, const TUID*, void**);
    uint32 (*addRef)(void*);
    uint32 (*release)(void*);
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
    tresult (*queryInterface)(void*, const TUID*, void**);
    uint32 (*addRef)(void*);
    uint32 (*release)(void*);
    uint32 (*callA)(void*);
};

struct TestBVTable {
    tresult (*queryInterface)(void*, const TUID*, void**);
    uint32 (*addRef)(void*);
    uint32 (*release)(void*);
    uint32 (*callB)(void*);
};

struct TestCVTable {
    tresult (*queryInterface)(void*, const TUID*, void**);
    uint32 (*addRef)(void*);
    uint32 (*release)(void*);
    uint32 (*callC)(void*);
};

struct MultiTestObject {
    FUnknownHeader unknown;
    InterfaceHeader a;
    InterfaceHeader b;
    InterfaceHeader c;
    uint32 a_calls;
    uint32 b_calls;
    uint32 c_calls;
};

extern "C" FUnknownHeader* make_multi_test_object(MultiTestObject* out);
extern "C" const TUID* test_a_iid();
extern "C" const TUID* test_b_iid();
extern "C" const TUID* test_c_iid();
extern "C" uint32 multi_object_a_calls(const MultiTestObject* object);
extern "C" uint32 multi_object_b_calls(const MultiTestObject* object);
extern "C" uint32 multi_object_c_calls(const MultiTestObject* object);

int main()
{
    MultiTestObject object;
    FUnknownHeader* unknown = make_multi_test_object(&object);
    void* out = nullptr;

    if (unknown->vtable->queryInterface(unknown, test_a_iid(), &out) != 0)
        return 1;
    if (out != &object.a)
        return 2;

    auto* a = static_cast<InterfaceHeader*>(out);
    auto* a_vtable = static_cast<const TestAVTable*>(a->vtable);
    if (a_vtable->callA(a) != 1)
        return 3;

    if (a_vtable->queryInterface(a, test_b_iid(), &out) != 0)
        return 4;
    if (out != &object.b)
        return 5;

    auto* b = static_cast<InterfaceHeader*>(out);
    auto* b_vtable = static_cast<const TestBVTable*>(b->vtable);
    if (b_vtable->callB(b) != 1)
        return 6;

    if (b_vtable->queryInterface(b, test_c_iid(), &out) != 0)
        return 7;
    if (out != &object.c)
        return 8;

    auto* c = static_cast<InterfaceHeader*>(out);
    auto* c_vtable = static_cast<const TestCVTable*>(c->vtable);
    if (c_vtable->callC(c) != 1)
        return 9;

    if (c_vtable->queryInterface(c, test_a_iid(), &out) != 0)
        return 10;
    if (out != &object.a)
        return 11;

    if (multi_object_a_calls(&object) != 1)
        return 12;
    if (multi_object_b_calls(&object) != 1)
        return 13;
    if (multi_object_c_calls(&object) != 1)
        return 14;

    return 0;
}
