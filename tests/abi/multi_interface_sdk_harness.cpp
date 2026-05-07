#include "pluginterfaces/base/funknown.h"

#include <cstdint>

using uint32 = uint32_t;

class TestA : public Steinberg::FUnknown {
public:
    virtual uint32 PLUGIN_API callA() = 0;
};

class TestB : public Steinberg::FUnknown {
public:
    virtual uint32 PLUGIN_API callB() = 0;
};

class TestC : public Steinberg::FUnknown {
public:
    virtual uint32 PLUGIN_API callC() = 0;
};

struct InterfaceHeader {
    const void* vtable;
};

struct MultiTestObject {
    Steinberg::FUnknown* unknown;
    uint32 ref_count;
    void* destroy;
    InterfaceHeader a;
    InterfaceHeader b;
    InterfaceHeader c;
    uint32 a_calls;
    uint32 b_calls;
    uint32 c_calls;
};

extern "C" Steinberg::FUnknown* make_multi_test_object(MultiTestObject* out);
extern "C" const Steinberg::TUID* test_a_iid();
extern "C" const Steinberg::TUID* test_b_iid();
extern "C" const Steinberg::TUID* test_c_iid();
extern "C" uint32 multi_object_a_calls(const MultiTestObject* object);
extern "C" uint32 multi_object_b_calls(const MultiTestObject* object);
extern "C" uint32 multi_object_c_calls(const MultiTestObject* object);

int main()
{
    MultiTestObject object;
    Steinberg::FUnknown* unknown = make_multi_test_object(&object);

    TestA* a = nullptr;
    if (unknown->queryInterface(*test_a_iid(), reinterpret_cast<void**>(&a)) != Steinberg::kResultOk)
        return 1;
    if (a != reinterpret_cast<TestA*>(&object.a))
        return 2;
    if (a->callA() != 1)
        return 3;

    TestB* b = nullptr;
    if (a->queryInterface(*test_b_iid(), reinterpret_cast<void**>(&b)) != Steinberg::kResultOk)
        return 4;
    if (b != reinterpret_cast<TestB*>(&object.b))
        return 5;
    if (b->callB() != 1)
        return 6;

    TestC* c = nullptr;
    if (b->queryInterface(*test_c_iid(), reinterpret_cast<void**>(&c)) != Steinberg::kResultOk)
        return 7;
    if (c != reinterpret_cast<TestC*>(&object.c))
        return 8;
    if (c->callC() != 1)
        return 9;

    TestA* a_again = nullptr;
    if (c->queryInterface(*test_a_iid(), reinterpret_cast<void**>(&a_again)) != Steinberg::kResultOk)
        return 10;
    if (a_again != a)
        return 11;

    if (multi_object_a_calls(&object) != 1)
        return 12;
    if (multi_object_b_calls(&object) != 1)
        return 13;
    if (multi_object_c_calls(&object) != 1)
        return 14;

    return 0;
}
