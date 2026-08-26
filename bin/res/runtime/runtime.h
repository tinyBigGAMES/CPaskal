/*******************************************************************************
 * runtime.h - LangVM C++ Runtime
 *
 * Copyright © 2025-present tinyBigGAMES™ LLC
 * All Rights Reserved.
 *
 * https://langvm.org
 *
 * Minimal C++ runtime support for LangVM language features.
 ******************************************************************************/

#ifndef RT_RUNTIME_H
#define RT_RUNTIME_H

#include <string>
#include <cstdint>
#include <cstdio>
#include <algorithm>
#include <type_traits>
#include <format>

/*******************************************************************************
 * std::formatter<char16_t> - char16_t has no default formatter in C++23.
 * This specialization converts the code point to its UTF-8 representation
 * so char16_t values print as characters (e.g. Ω) rather than failing.
 ******************************************************************************/

template<>
struct std::formatter<char16_t> : std::formatter<std::string> {
    auto format(char16_t c, auto& ctx) const {
        std::string utf8;
        if (c < 0x80) {
            utf8 += static_cast<char>(c);
        } else if (c < 0x800) {
            utf8 += static_cast<char>(0xC0 | (c >> 6));
            utf8 += static_cast<char>(0x80 | (c & 0x3F));
        } else {
            utf8 += static_cast<char>(0xE0 | (c >> 12));
            utf8 += static_cast<char>(0x80 | ((c >> 6) & 0x3F));
            utf8 += static_cast<char>(0x80 | (c & 0x3F));
        }
        return std::formatter<std::string>::format(utf8, ctx);
    }
};

/*******************************************************************************
 * std::formatter<enum> - C++23 has no default formatter for enum types.
 * This specialization formats any enum as its underlying integer value.
 ******************************************************************************/

template<typename T>
    requires std::is_enum_v<T>
struct std::formatter<T> : std::formatter<std::underlying_type_t<T>> {
    auto format(T value, auto& ctx) const {
        return std::formatter<std::underlying_type_t<T>>::format(
            static_cast<std::underlying_type_t<T>>(value), ctx);
    }
};

/*******************************************************************************
 * Exception Codes (Platform-Independent)
 ******************************************************************************/

#define RT_EXC_NONE               0   // No exception
#define RT_EXC_SOFTWARE           1   // Software exception (raiseexception)
#define RT_EXC_DIV_BY_ZERO        2   // Integer or float divide by zero
#define RT_EXC_ACCESS_VIOLATION   3   // Invalid memory access
#define RT_EXC_STACK_OVERFLOW     4   // Stack overflow
#define RT_EXC_INTEGER_OVERFLOW   5   // Integer overflow
#define RT_EXC_ILLEGAL_INSTRUCTION 6  // Invalid CPU instruction
#define RT_EXC_BUS_ERROR          7   // Bus error
#define RT_EXC_UNKNOWN            99  // Unknown hardware exception

/*******************************************************************************
 * Exception Handling API
 ******************************************************************************/

/** Function pointer type for try blocks. */
typedef void (*RtTryFn)(void* context);

/**
 * Execute a try block with full exception handling.
 * Catches BOTH software exceptions AND hardware exceptions.
 * @param try_fn  Function pointer to the try block code
 * @param context User context passed to try_fn (can be NULL)
 * @return RT_EXC_NONE, RT_EXC_SOFTWARE, or the RT_EXC_ code of the hardware fault
 */
int32_t rt_try_call(RtTryFn try_fn, void* context);

/**
 * Throw a software exception.
 * @param code  Exception code (user-defined)
 * @param msg   Exception message
 */
void rt_throw(int32_t code, const char* msg);

/**
 * Get the code of the last caught exception.
 * @return Exception code, or 0 if no exception
 */
int32_t rt_exc_code();

/**
 * Get the message of the last caught exception.
 * @return Exception message, or empty string if no exception
 */
const char* rt_exc_msg();

/**
 * Clear the exception state.
 */
void rt_exc_clear();

/**
 * Initialize exception handling (VEH/signals).
 * Call at the start of main() for exe modules, DllMain() for dll modules.
 */
void rt_init_exceptions();

/*******************************************************************************
 * Console Initialization
 ******************************************************************************/

/**
 * Initialize console for UTF-8 output.
 * Call at the start of main() for exe modules.
 */
void rt_initconsole();

/*******************************************************************************
 * String Conversion
 ******************************************************************************/

/**
 * Convert wide string (UTF-16) to UTF-8.
 * @param s  Wide string to convert
 * @return UTF-8 encoded string
 */
std::string rt_utf8(const std::wstring& s);

/**
 * Convert UTF-8 string to a heap-allocated UTF-16 (char16_t) buffer.
 * Caller receives ownership of the returned pointer.
 * @param s  UTF-8 encoded string
 * @return Heap-allocated char16_t buffer (null-terminated), cast to void*
 */
void* rt_wstr(const std::string& s);

/**
 * Return length of a container (.size()) or C-style array (element count).
 */
template<typename T>
auto rt_len(const T& container) -> decltype(container.size()) {
    return container.size();
}

template<typename T, size_t N>
constexpr size_t rt_len(const T(&)[N]) {
    return N;
}

/*******************************************************************************
 * Command Line API
 ******************************************************************************/

/**
 * Initialize command line arguments (call at program start).
 * @param argc Argument count from main()
 * @param argv Argument vector from main()
 */
void rt_init_args(int argc, char** argv);

/**
 * Get number of command line arguments (excludes program name).
 * @return Number of arguments (argc - 1)
 */
int32_t rt_paramcount();

/**
 * Get command line argument by index.
 * @param index 0 = program name, 1..n = arguments
 * @return Pointer to argument string (valid for program lifetime)
 */
const char* rt_paramstr(int32_t index);

/*******************************************************************************
 * Memory Management
 ******************************************************************************/

/**
 * Allocate memory.
 * @param size Number of bytes to allocate
 * @return Pointer to allocated memory, or nullptr on failure
 */
void* rt_getmem(size_t size);

/**
 * Resize previously allocated memory.
 * @param ptr Pointer to memory block (may be nullptr)
 * @param size New size in bytes
 * @return Pointer to resized memory, or nullptr on failure
 */
void* rt_resizemem(void* ptr, size_t size);

/**
 * Free previously allocated memory.
 * @param ptr Pointer to memory block (may be nullptr)
 */
void rt_freemem(void* ptr);

/**
 * Create (allocate and default-construct) a typed object.
 * Works for both classes and records. The variable must be a pointer type.
 * @param p Pointer variable to receive the new instance
 */
#define rt_create(p) ((p) = new std::remove_pointer_t<decltype(p)>())

/**
 * Destroy (delete and null) a typed object.
 * Works for both classes and records. Safe to call on nullptr.
 * @param p Pointer variable to delete and set to nullptr
 */
#define rt_destroy(p) do { delete (p); (p) = nullptr; } while(0)

/*******************************************************************************
 * Unit Testing API
 ******************************************************************************/

#define RT_MAX_TESTS 256
#define RT_ERROR_BUFFER_SIZE 4096

/**
 * Test function signature.
 */
typedef void (*RtTestFn)(void);

/**
 * Register a test function.
 * @param name  Test name (displayed in output)
 * @param func  Test function pointer
 * @param file  Source file path
 * @param line  Source line number
 * @return 1 on success, 0 if max tests exceeded
 */
int32_t rt_test_register(const char* name, RtTestFn func, const char* file, int32_t line);

/**
 * Run all registered tests.
 * @return 0 if all tests pass, 1 if any test fails
 */
int32_t rt_test_run_all(void);

/*******************************************************************************
 * Comparison Relations
 ******************************************************************************/

#define RT_CMP_EQ  0
#define RT_CMP_NEQ 1

/*******************************************************************************
 * Test Assertion Functions
 *
 * Called by generated code with source file/line for error reporting.
 * Assertions continue after failure (all failures accumulate per test).
 *
 * Simple assertions (condition-based):
 *   rt_test_assert_impl      -- assert(condition)
 *   rt_test_assert_true_impl -- assertTrue(condition)
 *   rt_test_assert_false_impl-- assertFalse(condition)
 *
 * Comparison assertions (template-based, covers all value types):
 *   rt_test_assert_cmp<T>    -- int64, uint64, double, bool, char, char16_t, void*
 *   rt_test_assert_cmp_float_tol -- double with explicit epsilon
 *   rt_test_assert_cmp_str   -- C strings (uses strcmp)
 *   rt_test_assert_cmp_wstr  -- wide strings (uses wcscmp on Windows, manual on Linux)
 *
 * Null assertions:
 *   rt_test_assert_nil_impl  -- assertNil(ptr)
 *   rt_test_assert_not_nil_impl -- assertNotNil(ptr)
 *
 * Explicit failure:
 *   rt_test_fail_impl        -- fail(msg)
 ******************************************************************************/

void rt_test_assert_impl(bool condition, const char* file, int32_t line);
void rt_test_assert_true_impl(bool condition, const char* file, int32_t line);
void rt_test_assert_false_impl(bool condition, const char* file, int32_t line);
void rt_test_assert_nil_impl(void* ptr, const char* file, int32_t line);
void rt_test_assert_not_nil_impl(void* ptr, const char* file, int32_t line);
void rt_test_fail_impl(const char* message, const char* file, int32_t line);

/**
 * Report a comparison failure. Internal -- called by rt_test_assert_cmp<T>.
 * @param keyword   "asserteq" or "assertneq"
 * @param detail    Formatted "expected ... got ..." string
 * @param msg       Optional caller message (may be nullptr)
 * @param file      Source file
 * @param line      Source line
 */
void rt_test_cmp_fail(const char* keyword, const char* detail,
                      const char* msg, const char* file, int32_t line);

/**
 * Generic comparison assertion. Handles int64_t, uint64_t, double, bool,
 * char, char16_t, and void* through if-constexpr formatting.
 *
 * @param expected  Expected value
 * @param actual    Actual value
 * @param relation  RT_CMP_EQ (0) or RT_CMP_NEQ (1)
 * @param msg       Optional message (nullptr for none)
 * @param file      Source file path
 * @param line      Source line number
 */
template<typename T>
void rt_test_assert_cmp(T expected, T actual, int32_t relation,
                        const char* msg, const char* file, int32_t line) {
    bool differ;
    if constexpr (std::is_floating_point_v<T>) {
        differ = (expected != actual);
    } else {
        differ = (expected != actual);
    }

    bool fail = (relation == RT_CMP_EQ && differ) ||
                (relation == RT_CMP_NEQ && !differ);
    if (!fail) return;

    char detail[512];
    const char* neg = (relation == RT_CMP_NEQ) ? "not " : "";

    if constexpr (std::is_same_v<T, int64_t>) {
        std::snprintf(detail, sizeof(detail),
            "expected %s%lld, got %lld", neg,
            (long long)expected, (long long)actual);
    } else if constexpr (std::is_same_v<T, uint64_t>) {
        std::snprintf(detail, sizeof(detail),
            "expected %s%llu, got %llu", neg,
            (unsigned long long)expected, (unsigned long long)actual);
    } else if constexpr (std::is_floating_point_v<T>) {
        std::snprintf(detail, sizeof(detail),
            "expected %s%g, got %g", neg, (double)expected, (double)actual);
    } else if constexpr (std::is_same_v<T, bool>) {
        std::snprintf(detail, sizeof(detail),
            "expected %s%s, got %s", neg,
            expected ? "TRUE" : "FALSE", actual ? "TRUE" : "FALSE");
    } else if constexpr (std::is_same_v<T, char>) {
        std::snprintf(detail, sizeof(detail),
            "expected %s'%c' (%d), got '%c' (%d)", neg,
            expected, (int)expected, actual, (int)actual);
    } else if constexpr (std::is_same_v<T, char16_t>) {
        std::snprintf(detail, sizeof(detail),
            "expected %sU+%04X, got U+%04X", neg,
            (unsigned)expected, (unsigned)actual);
    } else if constexpr (std::is_pointer_v<T>) {
        std::snprintf(detail, sizeof(detail),
            "expected %s%p, got %p", neg,
            (const void*)expected, (const void*)actual);
    } else {
        std::snprintf(detail, sizeof(detail),
            "expected %s(value), got (value)", neg);
    }

    const char* keyword = (relation == RT_CMP_NEQ) ? "assertneq" : "asserteq";
    rt_test_cmp_fail(keyword, detail, msg, file, line);
}

/**
 * Float comparison with explicit tolerance (epsilon).
 */
void rt_test_assert_cmp_float_tol(double expected, double actual, double epsilon,
                                  int32_t relation, const char* msg,
                                  const char* file, int32_t line);

/**
 * C string comparison (uses strcmp).
 */
void rt_test_assert_cmp_str(const char* expected, const char* actual,
                            int32_t relation, const char* msg,
                            const char* file, int32_t line);

/**
 * Wide string comparison.
 */
void rt_test_assert_cmp_wstr(const char16_t* expected, const char16_t* actual,
                             int32_t relation, const char* msg,
                             const char* file, int32_t line);

/*******************************************************************************
 * Variadic Arguments Support
 ******************************************************************************/

#include <cstdarg>

/**
 * Type-safe variadic arguments wrapper.
 * Provides object-style access to variadic function arguments.
 * Automatically cleans up va_list when destroyed.
 *
 * Usage:
 *   routine myFunc(const count: int32; ...): int32;
 *   begin
 *     x := varargs.next(int32);   // get next arg as int32
 *     args2 := varargs.copy();    // save cursor position
 *   end;
 */
struct rt_varargs {
    va_list ap;
    bool active = false;
    int32_t count = 0;

    /**
     * Get next argument as specified type and advance cursor.
     * @tparam T The type to retrieve
     * @return The next argument cast to type T
     */
    template<typename T>
    T next() {
        return va_arg(ap, T);
    }

    /**
     * Copy current cursor position for multi-pass iteration.
     * @return New rt_varargs with copied cursor position
     */
    rt_varargs copy() {
        rt_varargs result;
        va_copy(result.ap, ap);
        result.active = true;
        result.count = count;
        return result;
    }

    /**
     * Destructor - automatically calls va_end if active.
     */
    ~rt_varargs() {
        if (active) va_end(ap);
    }
};

/**
 * Initialize a rt_varargs from the hidden count parameter.
 * The compiler injects __rt_vararg_count as a hidden first parameter.
 * @param va The rt_varargs variable to initialize
 * @param count_param The hidden count parameter (__rt_vararg_count)
 */
#define rt_varargs_start(va, count_param) \
    va_start((va).ap, count_param); \
    (va).count = count_param; \
    (va).active = true


/*******************************************************************************
 * Set Support (bitmask-based, up to 64 elements with base offset)
 ******************************************************************************/

/**
 * RtSet - Bitmask-based set type supporting up to 64 elements.
 *
 * Elements are stored relative to a base offset, allowing sets like
 * set of 100..163 to work within a 64-bit bitmask.
 *
 * Arithmetic operators are overloaded for set semantics:
 *   + = union (bitwise OR)
 *   * = intersection (bitwise AND)
 *   - = difference (AND NOT)
 */
struct RtSet {
  uint64_t bits;
  int32_t base;

  RtSet() : bits(0), base(0) {}
  RtSet(uint64_t b, int32_t base) : bits(b), base(base) {}

  // Union: reconcile bases and OR
  RtSet operator+(const RtSet& rhs) const {
    if (bits == 0) return rhs;
    if (rhs.bits == 0) return *this;
    int32_t nb = std::min(base, rhs.base);
    return RtSet((bits << (base - nb)) | (rhs.bits << (rhs.base - nb)), nb);
  }

  // Intersection: reconcile bases and AND
  RtSet operator*(const RtSet& rhs) const {
    if (bits == 0 || rhs.bits == 0) return RtSet();
    int32_t nb = std::min(base, rhs.base);
    return RtSet((bits << (base - nb)) & (rhs.bits << (rhs.base - nb)), nb);
  }

  // Difference: reconcile bases and AND NOT
  RtSet operator-(const RtSet& rhs) const {
    if (bits == 0) return RtSet();
    if (rhs.bits == 0) return *this;
    int32_t nb = std::min(base, rhs.base);
    return RtSet((bits << (base - nb)) & ~(rhs.bits << (rhs.base - nb)), nb);
  }

  // Equality: reconcile bases and compare
  bool operator==(const RtSet& rhs) const {
    if (bits == 0 && rhs.bits == 0) return true;
    if (bits == 0 || rhs.bits == 0) return false;
    int32_t nb = std::min(base, rhs.base);
    return (bits << (base - nb)) == (rhs.bits << (rhs.base - nb));
  }
  bool operator!=(const RtSet& rhs) const { return !(*this == rhs); }

  // Assignment from uint64_t (base-0 set)
  RtSet& operator=(uint64_t b) { bits = b; base = 0; return *this; }

  // Conversion to integer types for casting
  explicit operator int8_t() const { return static_cast<int8_t>(bits); }
  explicit operator int16_t() const { return static_cast<int16_t>(bits); }
  explicit operator int32_t() const { return static_cast<int32_t>(bits); }
  explicit operator int64_t() const { return static_cast<int64_t>(bits); }
  explicit operator uint8_t() const { return static_cast<uint8_t>(bits); }
  explicit operator uint16_t() const { return static_cast<uint16_t>(bits); }
  explicit operator uint32_t() const { return static_cast<uint32_t>(bits); }
  explicit operator uint64_t() const { return bits; }
};

/**
 * Create a single-element set from an element value.
 * Elements 0..63 use base=0 (traditional bitmask).
 * Elements >= 64 use element value as base (offset sets).
 */
inline RtSet rt_elem(int32_t val) {
  if (val < 64) {
    return RtSet(1ULL << val, 0);
  } else {
    return RtSet(1ULL, val);
  }
}

/**
 * Create a set for a range of elements [low..high].
 * Ranges starting < 64 use base=0; ranges >= 64 use low as base.
 */
inline RtSet rt_range(int32_t low, int32_t high) {
  int32_t b = (low < 64) ? 0 : low;
  uint64_t r = 0;
  for (int32_t i = low; i <= high; i++) r |= (1ULL << (i - b));
  return RtSet(r, b);
}

/**
 * Test whether an element is in a set.
 */
inline bool rt_contains(RtSet s, int32_t elem) {
  int32_t bit = elem - s.base;
  if (bit < 0 || bit >= 64) return false;
  return (s.bits & (1ULL << bit)) != 0;
}

/*******************************************************************************
 * Guard/Except Helper
 ******************************************************************************/

/**
 * Execute a guard body with full exception handling (software + hardware).
 * Wraps a capturing lambda into rt_try_call via template trampoline.
 * @param body  Callable (typically a capturing lambda)
 * @return RT_EXC_NONE, RT_EXC_SOFTWARE, or the RT_EXC_ code of the hardware fault
 */
template<typename F>
int32_t rt_guard(F&& body) {
  auto wrapper = [](void* ctx) {
    (*static_cast<std::remove_reference_t<F>*>(ctx))();
  };
  return rt_try_call(wrapper, &body);
}

#endif /* RT_RUNTIME_H */
