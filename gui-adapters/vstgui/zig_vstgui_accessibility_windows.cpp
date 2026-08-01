#if defined(_WIN32)
#ifdef WIN32
#undef WIN32
#endif
#define WIN32 1
#endif

#include <windows.h>
#include <commctrl.h>
#include <uiautomation.h>

#include "zig_vstgui_accessibility_bridge.h"

#include "vstgui/lib/platform/iplatformframe.h"

#include <atomic>
#include <memory>
#include <utility>

namespace ZigVstgui {

namespace {

constexpr UINT_PTR subclass_id = 0x5a564153;

std::wstring wide(const std::string& value) {
    if (value.empty()) return {};
    const int length = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
    if (length <= 0) return {};
    std::wstring result(static_cast<std::size_t>(length), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), length);
    return result;
}

std::string narrow(const wchar_t* value) {
    if (!value || value[0] == L'\0') return {};
    const int length = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
    if (length <= 1) return {};
    std::string result(static_cast<std::size_t>(length), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value, -1, result.data(), length, nullptr, nullptr);
    result.resize(static_cast<std::size_t>(length - 1));
    return result;
}

void setString(VARIANT* value, const std::string& text) {
    const auto converted = wide(text);
    value->vt = VT_BSTR;
    value->bstrVal = SysAllocStringLen(converted.data(), static_cast<UINT>(converted.size()));
}

void setBool(VARIANT* value, bool state) {
    value->vt = VT_BOOL;
    value->boolVal = state ? VARIANT_TRUE : VARIANT_FALSE;
}

int controlType(AccessibilityRole role) {
    switch (role) {
        case AccessibilityRole::slider: return UIA_SliderControlTypeId;
        case AccessibilityRole::button: return UIA_ButtonControlTypeId;
        case AccessibilityRole::toggle: return UIA_CheckBoxControlTypeId;
        case AccessibilityRole::choice: return UIA_ComboBoxControlTypeId;
        case AccessibilityRole::text_field: return UIA_EditControlTypeId;
        case AccessibilityRole::meter: return UIA_ProgressBarControlTypeId;
        case AccessibilityRole::graph: return UIA_GroupControlTypeId;
        case AccessibilityRole::group: return UIA_GroupControlTypeId;
    }
}

struct WindowsState;

class Provider final : public IRawElementProviderSimple,
                       public IRawElementProviderFragment,
                       public IRawElementProviderFragmentRoot,
                       public IRangeValueProvider,
                       public IToggleProvider,
                       public IInvokeProvider,
                       public IValueProvider {
public:
    Provider(WindowsState* state, std::size_t index, bool root)
    : state(state), index(index), root(root) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void** result) override;
    ULONG STDMETHODCALLTYPE AddRef() override { return references.fetch_add(1) + 1; }
    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG remaining = references.fetch_sub(1) - 1;
        if (remaining == 0) delete this;
        return remaining;
    }
    HRESULT STDMETHODCALLTYPE get_ProviderOptions(ProviderOptions* result) override {
        if (!result) return E_INVALIDARG;
        *result = ProviderOptions_ServerSideProvider;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetPatternProvider(PATTERNID pattern, IUnknown** result) override;
    HRESULT STDMETHODCALLTYPE GetPropertyValue(PROPERTYID property, VARIANT* result) override;
    HRESULT STDMETHODCALLTYPE get_HostRawElementProvider(IRawElementProviderSimple** result) override;
    HRESULT STDMETHODCALLTYPE Navigate(NavigateDirection direction, IRawElementProviderFragment** result) override;
    HRESULT STDMETHODCALLTYPE GetRuntimeId(SAFEARRAY** result) override;
    HRESULT STDMETHODCALLTYPE get_BoundingRectangle(UiaRect* result) override;
    HRESULT STDMETHODCALLTYPE GetEmbeddedFragmentRoots(SAFEARRAY** result) override {
        if (!result) return E_INVALIDARG;
        *result = nullptr;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE SetFocus() override;
    HRESULT STDMETHODCALLTYPE get_FragmentRoot(IRawElementProviderFragmentRoot** result) override;
    HRESULT STDMETHODCALLTYPE ElementProviderFromPoint(double x, double y, IRawElementProviderFragment** result) override;
    HRESULT STDMETHODCALLTYPE GetFocus(IRawElementProviderFragment** result) override;
    HRESULT STDMETHODCALLTYPE SetValue(double value) override;
    HRESULT STDMETHODCALLTYPE get_Value(double* result) override;
    HRESULT STDMETHODCALLTYPE get_IsReadOnly(BOOL* result) override;
    HRESULT STDMETHODCALLTYPE get_Maximum(double* result) override;
    HRESULT STDMETHODCALLTYPE get_Minimum(double* result) override;
    HRESULT STDMETHODCALLTYPE get_LargeChange(double* result) override;
    HRESULT STDMETHODCALLTYPE get_SmallChange(double* result) override;
    HRESULT STDMETHODCALLTYPE Toggle() override;
    HRESULT STDMETHODCALLTYPE get_ToggleState(ToggleState* result) override;
    HRESULT STDMETHODCALLTYPE Invoke() override;
    HRESULT STDMETHODCALLTYPE SetValue(LPCWSTR value) override;
    HRESULT STDMETHODCALLTYPE get_Value(BSTR* result) override;

private:
    const AccessibilityNode* node() const;
    std::atomic<ULONG> references {1};
    WindowsState* state;
    std::size_t index;
    bool root;
};

struct Observer {
    const AccessibilityNode* node {nullptr};
    Provider* provider {nullptr};
};

struct WindowsState {
    HWND window {nullptr};
    std::vector<AccessibilityEntry> entries;
    Provider* root {nullptr};
    std::vector<Provider*> children;
    std::vector<std::unique_ptr<Observer>> observers;

    ~WindowsState() {
        for (const auto& observer : observers) observer->node->setObserver(nullptr, nullptr);
        for (auto* child : children) child->Release();
        if (root) root->Release();
    }
};

HRESULT Provider::QueryInterface(REFIID id, void** result) {
    if (!result) return E_INVALIDARG;
    *result = nullptr;
    if (IsEqualIID(id, IID_IUnknown) || IsEqualIID(id, IID_IRawElementProviderSimple)) {
        *result = static_cast<IRawElementProviderSimple*>(this);
    } else if (IsEqualIID(id, IID_IRawElementProviderFragment)) {
        *result = static_cast<IRawElementProviderFragment*>(this);
    } else if (root && IsEqualIID(id, IID_IRawElementProviderFragmentRoot)) {
        *result = static_cast<IRawElementProviderFragmentRoot*>(this);
    } else if (!root && IsEqualIID(id, __uuidof(IRangeValueProvider)) &&
               node() && node()->range().present && node()->supports(AccessibilityAction::set_value)) {
        *result = static_cast<IRangeValueProvider*>(this);
    } else if (!root && IsEqualIID(id, __uuidof(IToggleProvider)) &&
               node() && node()->role() == AccessibilityRole::toggle &&
               node()->supports(AccessibilityAction::press)) {
        *result = static_cast<IToggleProvider*>(this);
    } else if (!root && IsEqualIID(id, __uuidof(IInvokeProvider)) &&
               node() && node()->supports(AccessibilityAction::press) &&
               node()->role() != AccessibilityRole::toggle) {
        *result = static_cast<IInvokeProvider*>(this);
    } else if (!root && IsEqualIID(id, __uuidof(IValueProvider)) && node() &&
               node()->supports(AccessibilityAction::set_value) &&
               (node()->role() == AccessibilityRole::text_field || node()->role() == AccessibilityRole::choice)) {
        *result = static_cast<IValueProvider*>(this);
    } else {
        return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
}

const AccessibilityNode* Provider::node() const {
    if (root || !state || index >= state->entries.size()) return nullptr;
    return state->entries[index].node;
}

HRESULT Provider::GetPatternProvider(PATTERNID pattern, IUnknown** result) {
    if (!result) return E_INVALIDARG;
    *result = nullptr;
    HRESULT status = S_OK;
    if (pattern == UIA_RangeValuePatternId) {
        status = QueryInterface(__uuidof(IRangeValueProvider), reinterpret_cast<void**>(result));
    } else if (pattern == UIA_TogglePatternId) {
        status = QueryInterface(__uuidof(IToggleProvider), reinterpret_cast<void**>(result));
    } else if (pattern == UIA_InvokePatternId) {
        status = QueryInterface(__uuidof(IInvokeProvider), reinterpret_cast<void**>(result));
    } else if (pattern == UIA_ValuePatternId) {
        status = QueryInterface(__uuidof(IValueProvider), reinterpret_cast<void**>(result));
    }
    return status == E_NOINTERFACE ? S_OK : status;
}

HRESULT Provider::GetPropertyValue(PROPERTYID property, VARIANT* result) {
    if (!result) return E_INVALIDARG;
    VariantInit(result);
    if (root) {
        if (property == UIA_ControlTypePropertyId) {
            result->vt = VT_I4;
            result->lVal = UIA_PaneControlTypeId;
        } else if (property == UIA_NamePropertyId) {
            setString(result, "Plugin editor");
        } else if (property == UIA_IsControlElementPropertyId || property == UIA_IsContentElementPropertyId) {
            setBool(result, true);
        }
        return S_OK;
    }
    if (!state || index >= state->entries.size()) return static_cast<HRESULT>(UIA_E_ELEMENTNOTAVAILABLE);
    const auto& item = state->entries[index];
    const auto& node = *item.node;
    if (property == UIA_ControlTypePropertyId) {
        result->vt = VT_I4;
        result->lVal = controlType(node.role());
    } else if (property == UIA_NamePropertyId) {
        setString(result, node.name());
    } else if (property == UIA_HelpTextPropertyId) {
        setString(result, node.description());
    } else if (property == UIA_ValueValuePropertyId) {
        setString(result, node.valueText());
    } else if (property == UIA_RangeValueValuePropertyId && node.range().present) {
        result->vt = VT_R8;
        result->dblVal = node.range().current;
    } else if (property == UIA_RangeValueMinimumPropertyId && node.range().present) {
        result->vt = VT_R8;
        result->dblVal = node.range().minimum;
    } else if (property == UIA_RangeValueMaximumPropertyId && node.range().present) {
        result->vt = VT_R8;
        result->dblVal = node.range().maximum;
    } else if (property == UIA_ToggleToggleStatePropertyId && node.role() == AccessibilityRole::toggle) {
        result->vt = VT_I4;
        result->lVal = node.state().checked ? ToggleState_On : ToggleState_Off;
    } else if (property == UIA_IsEnabledPropertyId) {
        setBool(result, node.state().enabled);
    } else if (property == UIA_HasKeyboardFocusPropertyId) {
        setBool(result, node.state().focused);
    } else if (property == UIA_IsKeyboardFocusablePropertyId) {
        setBool(result, item.view->wantsFocus());
    } else if (property == UIA_IsOffscreenPropertyId) {
        setBool(result, !item.view->isVisible());
    } else if (property == UIA_IsControlElementPropertyId || property == UIA_IsContentElementPropertyId) {
        setBool(result, true);
    }
    return S_OK;
}

HRESULT Provider::get_HostRawElementProvider(IRawElementProviderSimple** result) {
    if (!result) return E_INVALIDARG;
    *result = nullptr;
    return root && state ? UiaHostProviderFromHwnd(state->window, result) : S_OK;
}

HRESULT Provider::Navigate(NavigateDirection direction, IRawElementProviderFragment** result) {
    if (!result) return E_INVALIDARG;
    *result = nullptr;
    Provider* destination = nullptr;
    if (root) {
        if (direction == NavigateDirection_FirstChild && !state->children.empty()) destination = state->children.front();
        if (direction == NavigateDirection_LastChild && !state->children.empty()) destination = state->children.back();
    } else {
        if (direction == NavigateDirection_Parent) destination = state->root;
        if (direction == NavigateDirection_PreviousSibling && index > 0) destination = state->children[index - 1];
        if (direction == NavigateDirection_NextSibling && index + 1 < state->children.size()) destination = state->children[index + 1];
    }
    if (destination) {
        destination->AddRef();
        *result = static_cast<IRawElementProviderFragment*>(destination);
    }
    return S_OK;
}

HRESULT Provider::GetRuntimeId(SAFEARRAY** result) {
    if (!result) return E_INVALIDARG;
    *result = nullptr;
    if (root) return S_OK;
    int values[] = {UiaAppendRuntimeId, static_cast<int>(index + 1)};
    auto* array = SafeArrayCreateVector(VT_I4, 0, 2);
    if (!array) return E_OUTOFMEMORY;
    for (LONG position = 0; position < 2; ++position) {
        if (FAILED(SafeArrayPutElement(array, &position, &values[position]))) {
            SafeArrayDestroy(array);
            return E_FAIL;
        }
    }
    *result = array;
    return S_OK;
}

HRESULT Provider::get_BoundingRectangle(UiaRect* result) {
    if (!result || !state) return E_INVALIDARG;
    RECT bounds {};
    if (root) {
        if (!GetWindowRect(state->window, &bounds)) return static_cast<HRESULT>(UIA_E_ELEMENTNOTAVAILABLE);
    } else {
        const auto* view = state->entries[index].view;
        const auto size = view->getViewSize();
        VSTGUI::CRect translated(0.0, 0.0, size.getWidth(), size.getHeight());
        view->translateToGlobal(translated, true);
        POINT top_left {static_cast<LONG>(translated.left), static_cast<LONG>(translated.top)};
        ClientToScreen(state->window, &top_left);
        bounds = {top_left.x, top_left.y,
            top_left.x + static_cast<LONG>(translated.getWidth()),
            top_left.y + static_cast<LONG>(translated.getHeight())};
    }
    *result = {static_cast<double>(bounds.left), static_cast<double>(bounds.top),
        static_cast<double>(bounds.right - bounds.left), static_cast<double>(bounds.bottom - bounds.top)};
    return S_OK;
}

HRESULT Provider::SetFocus() {
    if (root || !state || index >= state->entries.size()) return S_OK;
    return state->entries[index].node->perform(AccessibilityAction::focus) ? S_OK : UIA_E_NOTSUPPORTED;
}

HRESULT Provider::get_FragmentRoot(IRawElementProviderFragmentRoot** result) {
    if (!result || !state || !state->root) return E_INVALIDARG;
    state->root->AddRef();
    *result = static_cast<IRawElementProviderFragmentRoot*>(state->root);
    return S_OK;
}

HRESULT Provider::ElementProviderFromPoint(double x, double y, IRawElementProviderFragment** result) {
    if (!result || !state || !root) return E_INVALIDARG;
    *result = nullptr;
    for (auto* child : state->children) {
        UiaRect bounds {};
        if (SUCCEEDED(child->get_BoundingRectangle(&bounds)) && x >= bounds.left && x <= bounds.left + bounds.width &&
            y >= bounds.top && y <= bounds.top + bounds.height) {
            child->AddRef();
            *result = static_cast<IRawElementProviderFragment*>(child);
            break;
        }
    }
    return S_OK;
}

HRESULT Provider::GetFocus(IRawElementProviderFragment** result) {
    if (!result || !state || !root) return E_INVALIDARG;
    *result = nullptr;
    for (std::size_t child = 0; child < state->entries.size(); ++child) {
        if (!state->entries[child].node->state().focused) continue;
        state->children[child]->AddRef();
        *result = static_cast<IRawElementProviderFragment*>(state->children[child]);
        break;
    }
    return S_OK;
}

HRESULT Provider::SetValue(double value) {
    const auto* semantic = node();
    return semantic && semantic->perform(AccessibilityAction::set_value, value) ? S_OK : UIA_E_NOTSUPPORTED;
}

HRESULT Provider::get_Value(double* result) {
    const auto* semantic = node();
    if (!result || !semantic || !semantic->range().present) return E_INVALIDARG;
    *result = semantic->range().current;
    return S_OK;
}

HRESULT Provider::get_IsReadOnly(BOOL* result) {
    const auto* semantic = node();
    if (!result || !semantic) return E_INVALIDARG;
    *result = semantic->state().read_only || !semantic->supports(AccessibilityAction::set_value);
    return S_OK;
}

HRESULT Provider::get_Maximum(double* result) {
    const auto* semantic = node();
    if (!result || !semantic || !semantic->range().present) return E_INVALIDARG;
    *result = semantic->range().maximum;
    return S_OK;
}

HRESULT Provider::get_Minimum(double* result) {
    const auto* semantic = node();
    if (!result || !semantic || !semantic->range().present) return E_INVALIDARG;
    *result = semantic->range().minimum;
    return S_OK;
}

HRESULT Provider::get_LargeChange(double* result) {
    if (!result) return E_INVALIDARG;
    *result = 0.1;
    return S_OK;
}

HRESULT Provider::get_SmallChange(double* result) {
    if (!result) return E_INVALIDARG;
    *result = 0.01;
    return S_OK;
}

HRESULT Provider::Toggle() {
    const auto* semantic = node();
    return semantic && semantic->perform(AccessibilityAction::press) ? S_OK : UIA_E_NOTSUPPORTED;
}

HRESULT Provider::get_ToggleState(ToggleState* result) {
    const auto* semantic = node();
    if (!result || !semantic) return E_INVALIDARG;
    *result = semantic->state().checked ? ToggleState_On : ToggleState_Off;
    return S_OK;
}

HRESULT Provider::Invoke() {
    const auto* semantic = node();
    return semantic && semantic->perform(AccessibilityAction::press) ? S_OK : UIA_E_NOTSUPPORTED;
}

HRESULT Provider::SetValue(LPCWSTR value) {
    const auto* semantic = node();
    const auto converted = narrow(value);
    return semantic && semantic->perform(AccessibilityAction::set_value, 0.0, converted.c_str())
        ? S_OK
        : UIA_E_NOTSUPPORTED;
}

HRESULT Provider::get_Value(BSTR* result) {
    const auto* semantic = node();
    if (!result || !semantic) return E_INVALIDARG;
    const auto converted = wide(semantic->valueText());
    *result = SysAllocStringLen(converted.data(), static_cast<UINT>(converted.size()));
    return *result ? S_OK : E_OUTOFMEMORY;
}

void accessibilityChanged(void* userdata, AccessibilityChange change) {
    auto* observer = static_cast<Observer*>(userdata);
    if (!observer || !observer->provider) return;
    if (change == AccessibilityChange::text_caret ||
        change == AccessibilityChange::text_selection) return;
    PROPERTYID property = UIA_ValueValuePropertyId;
    if (change == AccessibilityChange::role) property = UIA_ControlTypePropertyId;
    if (change == AccessibilityChange::name) property = UIA_NamePropertyId;
    if (change == AccessibilityChange::description) property = UIA_HelpTextPropertyId;
    if (change == AccessibilityChange::focus) property = UIA_HasKeyboardFocusPropertyId;
    if (change == AccessibilityChange::range) property = UIA_RangeValueValuePropertyId;
    if (change == AccessibilityChange::state) property = UIA_IsEnabledPropertyId;
    VARIANT old_value;
    VARIANT new_value;
    VariantInit(&old_value);
    VariantInit(&new_value);
    observer->provider->GetPropertyValue(property, &new_value);
    UiaRaiseAutomationPropertyChangedEvent(observer->provider, property, old_value, new_value);
    VariantClear(&new_value);
    if (change == AccessibilityChange::focus) {
        UiaRaiseAutomationEvent(observer->provider, UIA_AutomationFocusChangedEventId);
    }
    if (change == AccessibilityChange::state) {
        VariantInit(&new_value);
        observer->provider->GetPropertyValue(UIA_ToggleToggleStatePropertyId, &new_value);
        if (new_value.vt != VT_EMPTY) {
            UiaRaiseAutomationPropertyChangedEvent(
                observer->provider, UIA_ToggleToggleStatePropertyId, old_value, new_value
            );
        }
        VariantClear(&new_value);
    }
}

LRESULT CALLBACK subclassProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam,
                              UINT_PTR, DWORD_PTR reference) {
    auto* state = reinterpret_cast<WindowsState*>(reference);
    if (message == WM_GETOBJECT && state && state->root) {
        return UiaReturnRawElementProvider(window, wparam, lparam, state->root);
    }
    return DefSubclassProc(window, message, wparam, lparam);
}

}

class NativeAccessibilityBridge::Impl {
public:
    std::unique_ptr<WindowsState> state;
};

NativeAccessibilityBridge::NativeAccessibilityBridge() = default;
NativeAccessibilityBridge::~NativeAccessibilityBridge() { close(); }

bool NativeAccessibilityBridge::open(
    VSTGUI::CFrame* frame,
    const std::vector<AccessibilityEntry>& entries,
    std::shared_ptr<AccessibilityClipboard>
) {
    close();
    if (!frame || !frame->getPlatformFrame()) return false;
    auto* window = static_cast<HWND>(frame->getPlatformFrame()->getPlatformRepresentation());
    if (!window) return false;
    auto next = std::make_unique<Impl>();
    next->state = std::make_unique<WindowsState>();
    auto& state = *next->state;
    state.window = window;
    for (const auto& item : entries) {
        if (item.node && item.view) state.entries.push_back(item);
    }
    state.root = new Provider(&state, 0, true);
    for (std::size_t index = 0; index < state.entries.size(); ++index) {
        auto* child = new Provider(&state, index, false);
        state.children.push_back(child);
        auto observer = std::make_unique<Observer>();
        observer->node = state.entries[index].node;
        observer->provider = child;
        observer->node->setObserver(observer.get(), accessibilityChanged);
        state.observers.push_back(std::move(observer));
    }
    if (!SetWindowSubclass(window, subclassProc, subclass_id, reinterpret_cast<DWORD_PTR>(&state))) return false;
    impl = std::move(next);
    UiaRaiseStructureChangedEvent(impl->state->root, StructureChangeType_ChildrenInvalidated, nullptr, 0);
    return true;
}

void NativeAccessibilityBridge::close() {
    if (!impl) return;
    RemoveWindowSubclass(impl->state->window, subclassProc, subclass_id);
    impl.reset();
}

void NativeAccessibilityBridge::dispatch() {}

void NativeAccessibilityBridge::layoutChanged() {
    if (impl) UiaRaiseStructureChangedEvent(impl->state->root, StructureChangeType_ChildrenInvalidated, nullptr, 0);
}

bool NativeAccessibilityBridge::active() const { return impl && impl->state; }
std::size_t NativeAccessibilityBridge::elementCount() const { return impl ? impl->state->entries.size() : 0; }

}
