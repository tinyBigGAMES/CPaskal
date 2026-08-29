/*******************************************************************************
 * runtime.cpp - CPaskal C++ Runtime
 *
 * Copyright © 2026-present tinyBigGAMES™ LLC
 * All Rights Reserved.
 *
 * https://cpaskal.org
 *
 * Minimal C++ runtime support for CPaskal language features.
 ******************************************************************************/

#include "runtime.h"

#include <locale>
#include <codecvt>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <exception>

// WebAssembly's setjmp.h hard-#errors unless the unstandardized EH proposal
// is enabled, so the header itself must not be pulled in on wasm.
#if !defined(__wasm__)
    #include <csetjmp>
#endif

#if defined(__wasm__)
    // No VEH, no POSIX signals. Nothing to include.
#elif defined(_WIN32)
    #define WIN32_LEAN_AND_MEAN
    #include <windows.h>
    #include <io.h>
    #include <fcntl.h>
#else
    #include <signal.h>
#endif

/*******************************************************************************
 * Exception Handling Implementation
 ******************************************************************************/

/** Internal C++ exception type for software exceptions. */
struct RtException {
    int32_t code;
    const char* msg;
};

// Thread-local exception state
static thread_local int32_t g_exc_code = 0;
static thread_local const char* g_exc_msg = nullptr;
#if !defined(__wasm__)
static thread_local jmp_buf* g_jmp_target = nullptr;
#endif

#if defined(__wasm__)

// wasm has no hardware fault trapping and no longjmp escape route.
static void rt_install_hw_handler() {
}

#elif defined(_WIN32)

// Check if exception code is a real hardware fault
static bool IsHardwareException(DWORD code) {
    switch (code) {
        case EXCEPTION_ACCESS_VIOLATION:
        case EXCEPTION_INT_DIVIDE_BY_ZERO:
        case EXCEPTION_FLT_DIVIDE_BY_ZERO:
        case EXCEPTION_STACK_OVERFLOW:
        case EXCEPTION_INT_OVERFLOW:
        case EXCEPTION_ILLEGAL_INSTRUCTION:
        case EXCEPTION_PRIV_INSTRUCTION:
        case EXCEPTION_IN_PAGE_ERROR:
        case EXCEPTION_FLT_INVALID_OPERATION:
        case EXCEPTION_FLT_OVERFLOW:
        case EXCEPTION_FLT_UNDERFLOW:
            return true;
        default:
            return false;
    }
}

// Vectored Exception Handler for Windows
static LONG WINAPI RtVehHandler(PEXCEPTION_POINTERS ep) {
    DWORD code = ep->ExceptionRecord->ExceptionCode;
    
    if (g_jmp_target == nullptr)
        return EXCEPTION_CONTINUE_SEARCH;
    
    if (!IsHardwareException(code))
        return EXCEPTION_CONTINUE_SEARCH;
    
    // Map Windows exception codes to RT_ codes
    switch (code) {
        case EXCEPTION_ACCESS_VIOLATION:
        case EXCEPTION_IN_PAGE_ERROR:
            g_exc_code = RT_EXC_ACCESS_VIOLATION;
            g_exc_msg = "Access violation";
            break;
        case EXCEPTION_INT_DIVIDE_BY_ZERO:
        case EXCEPTION_FLT_DIVIDE_BY_ZERO:
            g_exc_code = RT_EXC_DIV_BY_ZERO;
            g_exc_msg = "Divide by zero";
            break;
        case EXCEPTION_STACK_OVERFLOW:
            g_exc_code = RT_EXC_STACK_OVERFLOW;
            g_exc_msg = "Stack overflow";
            break;
        case EXCEPTION_INT_OVERFLOW:
        case EXCEPTION_FLT_OVERFLOW:
        case EXCEPTION_FLT_UNDERFLOW:
            g_exc_code = RT_EXC_INTEGER_OVERFLOW;
            g_exc_msg = "Numeric overflow";
            break;
        case EXCEPTION_ILLEGAL_INSTRUCTION:
        case EXCEPTION_PRIV_INSTRUCTION:
            g_exc_code = RT_EXC_ILLEGAL_INSTRUCTION;
            g_exc_msg = "Illegal instruction";
            break;
        default:
            g_exc_code = RT_EXC_UNKNOWN;
            g_exc_msg = "Hardware exception";
            break;
    }
    
    longjmp(*g_jmp_target, g_exc_code);
    return EXCEPTION_CONTINUE_SEARCH;
}

static PVOID g_veh_handle = nullptr;

static void rt_install_hw_handler() {
    if (g_veh_handle == nullptr) {
        g_veh_handle = AddVectoredExceptionHandler(1, RtVehHandler);
    }
}

#else

// Signal handler for POSIX systems
static void rt_signal_handler(int sig) {
    if (g_jmp_target == nullptr)
        return;
    
    switch (sig) {
        case SIGFPE:
            g_exc_code = RT_EXC_DIV_BY_ZERO;
            g_exc_msg = "Divide by zero";
            break;
        case SIGSEGV:
            g_exc_code = RT_EXC_ACCESS_VIOLATION;
            g_exc_msg = "Segmentation fault";
            break;
        case SIGBUS:
            g_exc_code = RT_EXC_BUS_ERROR;
            g_exc_msg = "Bus error";
            break;
        case SIGILL:
            g_exc_code = RT_EXC_ILLEGAL_INSTRUCTION;
            g_exc_msg = "Illegal instruction";
            break;
        default:
            g_exc_code = RT_EXC_UNKNOWN;
            g_exc_msg = "Hardware exception";
            break;
    }
    
    longjmp(*g_jmp_target, g_exc_code);
}

static void rt_install_hw_handler() {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = rt_signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    
    sigaction(SIGFPE, &sa, nullptr);
    sigaction(SIGSEGV, &sa, nullptr);
    sigaction(SIGBUS, &sa, nullptr);
    sigaction(SIGILL, &sa, nullptr);
}

#endif

// WebAssembly has no exception handling. Zig's libcxxabi provides no
// __cxa_throw / __cxa_allocate_exception for wasm, and wasi-libc's
// setjmp/longjmp needs the unstandardized EH proposal (it fails to link on
// __c_longjmp). Both escape routes are closed, so wasm builds compile with
// -fno-exceptions and any raise becomes a hard abort.
//
// The compiler rejects guard/except on wasm before reaching here; this path
// exists for raises that originate inside the runtime itself.
#if defined(__wasm__)

int32_t rt_try_call(RtTryFn try_fn, void* context) {
    // No unwinding is possible: run the body directly. An exception raised
    // inside it aborts the process from rt_throw.
    rt_install_hw_handler();
    try_fn(context);
    return RT_EXC_NONE;
}

void rt_throw(int32_t code, const char* msg) {
    g_exc_code = code;
    g_exc_msg = msg;
    std::fprintf(stderr, "runtime: unhandled exception %d: %s\n", code,
                 msg ? msg : "");
    std::abort();
}

#else

int32_t rt_try_call(RtTryFn try_fn, void* context) {
    rt_install_hw_handler();
    
    jmp_buf buf;
    jmp_buf* old_target = g_jmp_target;
    g_jmp_target = &buf;
    
    // setjmp returns RT_EXC_NONE on the initial call; a hardware fault handler
    // longjmps back with the RT_EXC_ code of the fault.
    int jmp_result = setjmp(buf);
    
    if (jmp_result == RT_EXC_NONE) {
        try {
            try_fn(context);
            g_jmp_target = old_target;
            return RT_EXC_NONE;
        } 
        catch (const RtException& e) {
            g_exc_code = e.code;
            g_exc_msg = e.msg;
            g_jmp_target = old_target;
            return RT_EXC_SOFTWARE;
        } 
        catch (const std::exception& e) {
            g_exc_code = RT_EXC_UNKNOWN;
            g_exc_msg = e.what();
            g_jmp_target = old_target;
            return RT_EXC_SOFTWARE;
        } 
        catch (...) {
            g_exc_code = RT_EXC_UNKNOWN;
            g_exc_msg = "Unknown C++ exception";
            g_jmp_target = old_target;
            return RT_EXC_SOFTWARE;
        }
    } 
    else {
        // Reached via longjmp from the hardware fault handler, which passed
        // the RT_EXC_ code of the fault and stored it in g_exc_code.
        g_jmp_target = old_target;
        return jmp_result;
    }
}

void rt_throw(int32_t code, const char* msg) {
    g_exc_code = code;
    g_exc_msg = msg;
    throw RtException{code, msg};
}

#endif  // __wasm__

int32_t rt_exc_code() {
    return g_exc_code;
}

const char* rt_exc_msg() {
    return g_exc_msg ? g_exc_msg : "";
}

void rt_exc_clear() {
    g_exc_code = 0;
    g_exc_msg = nullptr;
}

void rt_init_exceptions() {
    rt_install_hw_handler();
}

/*******************************************************************************
 * Console Initialization
 ******************************************************************************/

void rt_initconsole() {
#ifdef _WIN32
    // Set console to UTF-8
    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCP(CP_UTF8);
    
    // Set stdout/stderr to binary mode for UTF-8
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);
    
    // Enable ANSI escape sequences (for colors, etc.)
    HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
    if (hOut != INVALID_HANDLE_VALUE) {
        DWORD dwMode = 0;
        if (GetConsoleMode(hOut, &dwMode)) {
            dwMode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
            SetConsoleMode(hOut, dwMode);
        }
    }
#endif
}

/*******************************************************************************
 * String Conversion
 ******************************************************************************/

std::string rt_utf8(const std::wstring& s) {
    if (s.empty()) {
        return std::string();
    }
    
    std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
    return converter.to_bytes(s);
}

char16_t* rt_wstr(const std::string& s) {
    if (s.empty()) {
        // Return a heap-allocated empty null-terminated char16_t buffer
        char16_t* buf = static_cast<char16_t*>(malloc(sizeof(char16_t)));
        if (buf) buf[0] = 0;
        return buf;
    }

    // First pass: count UTF-16 code units needed
    size_t count = 0;
    const unsigned char* p = reinterpret_cast<const unsigned char*>(s.data());
    const unsigned char* end = p + s.size();

    while (p < end) {
        uint32_t cp;
        if (*p < 0x80) {
            cp = *p++;
        } else if ((*p & 0xE0) == 0xC0) {
            cp = (*p++ & 0x1F) << 6;
            if (p < end) cp |= (*p++ & 0x3F);
        } else if ((*p & 0xF0) == 0xE0) {
            cp = (*p++ & 0x0F) << 12;
            if (p < end) cp |= (*p++ & 0x3F) << 6;
            if (p < end) cp |= (*p++ & 0x3F);
        } else if ((*p & 0xF8) == 0xF0) {
            cp = (*p++ & 0x07) << 18;
            if (p < end) cp |= (*p++ & 0x3F) << 12;
            if (p < end) cp |= (*p++ & 0x3F) << 6;
            if (p < end) cp |= (*p++ & 0x3F);
        } else {
            p++; // skip invalid byte
            count++;
            continue;
        }
        count += (cp > 0xFFFF) ? 2 : 1; // surrogate pair for supplementary
    }

    // Allocate buffer (count + 1 for null terminator)
    char16_t* buf = static_cast<char16_t*>(malloc((count + 1) * sizeof(char16_t)));
    if (!buf) return nullptr;

    // Second pass: encode UTF-16
    p = reinterpret_cast<const unsigned char*>(s.data());
    char16_t* out = buf;

    while (p < end) {
        uint32_t cp;
        if (*p < 0x80) {
            cp = *p++;
        } else if ((*p & 0xE0) == 0xC0) {
            cp = (*p++ & 0x1F) << 6;
            if (p < end) cp |= (*p++ & 0x3F);
        } else if ((*p & 0xF0) == 0xE0) {
            cp = (*p++ & 0x0F) << 12;
            if (p < end) cp |= (*p++ & 0x3F) << 6;
            if (p < end) cp |= (*p++ & 0x3F);
        } else if ((*p & 0xF8) == 0xF0) {
            cp = (*p++ & 0x07) << 18;
            if (p < end) cp |= (*p++ & 0x3F) << 12;
            if (p < end) cp |= (*p++ & 0x3F) << 6;
            if (p < end) cp |= (*p++ & 0x3F);
        } else {
            p++;
            *out++ = 0xFFFD; // replacement character
            continue;
        }

        if (cp > 0xFFFF) {
            // Surrogate pair
            cp -= 0x10000;
            *out++ = static_cast<char16_t>(0xD800 + (cp >> 10));
            *out++ = static_cast<char16_t>(0xDC00 + (cp & 0x3FF));
        } else {
            *out++ = static_cast<char16_t>(cp);
        }
    }
    *out = 0; // null terminate

    return buf;
}

/*******************************************************************************
 * Command Line API
 ******************************************************************************/

static int g_argc = 0;
static char** g_argv = nullptr;

void rt_init_args(int argc, char** argv) {
    g_argc = argc;
    g_argv = argv;
}

int32_t rt_paramcount() {
    return g_argc > 0 ? g_argc - 1 : 0;
}

const char* rt_paramstr(int32_t index) {
    if (index < 0 || index >= g_argc || g_argv == nullptr) {
        return "";
    }
    return g_argv[index];
}

/*******************************************************************************
 * Memory Management
 ******************************************************************************/

void* rt_getmem(size_t size) {
    return std::malloc(size);
}

void* rt_resizemem(void* ptr, size_t size) {
    return std::realloc(ptr, size);
}

void rt_freemem(void* ptr) {
    std::free(ptr);
}

/*******************************************************************************
 * Unit Testing Implementation
 ******************************************************************************/

struct RtTestInfo {
    const char* name;
    RtTestFn func;
    const char* file;
    int32_t line;
};

static RtTestInfo rt_tests[RT_MAX_TESTS];
static int rt_test_count = 0;
static bool rt_test_failed = false;
static char rt_test_error_buffer[RT_ERROR_BUFFER_SIZE];
static int rt_test_error_pos = 0;

int32_t rt_test_register(const char* name, RtTestFn func, const char* file, int32_t line) {
    if (rt_test_count >= RT_MAX_TESTS) {
        std::fprintf(stderr, "ERROR: Maximum test count (%d) exceeded\n", RT_MAX_TESTS);
        return 0;
    }
    rt_tests[rt_test_count].name = name;
    rt_tests[rt_test_count].func = func;
    rt_tests[rt_test_count].file = file;
    rt_tests[rt_test_count].line = line;
    rt_test_count++;
    return 1;
}

int32_t rt_test_run_all(void) {
    int passed = 0;
    int failed = 0;
    
    // Box-drawing header (UTF-8 encoded)
    std::printf("\n");
    std::printf("\xE2\x95\x94");  // ╔
    for (int i = 0; i < 62; i++) std::printf("\xE2\x95\x90");  // ═
    std::printf("\xE2\x95\x97\n");  // ╗
    
    std::printf("\xE2\x95\x91                     Unit Test Runner                         \xE2\x95\x91\n");  // ║...║
    
    std::printf("\xE2\x95\x9A");  // ╚
    for (int i = 0; i < 62; i++) std::printf("\xE2\x95\x90");  // ═
    std::printf("\xE2\x95\x9D\n");  // ╝
    
    std::printf("\n");
    std::printf("Running %d test(s)...\n\n", rt_test_count);
    
    // Run each test
    for (int i = 0; i < rt_test_count; i++) {
        // Reset test state
        rt_test_failed = false;
        rt_test_error_buffer[0] = '\0';
        rt_test_error_pos = 0;
        
        // Run the test
        rt_tests[i].func();
        
        // Report result
        if (rt_test_failed) {
            std::printf("\xE2\x9D\x8C FAIL: %s\n", rt_tests[i].name);  // ❌
            if (rt_test_error_buffer[0] != '\0') {
                std::printf("%s", rt_test_error_buffer);
            }
            failed++;
        } else {
            std::printf("\xE2\x9C\x85 PASS: %s\n", rt_tests[i].name);  // ✅
            passed++;
        }
    }
    
    // Results footer
    std::printf("\n");
    for (int i = 0; i < 64; i++) std::printf("\xE2\x95\x90");  // ═
    std::printf("\n");
    std::printf("Results: %d passed, %d failed, %d total\n", passed, failed, rt_test_count);
    for (int i = 0; i < 64; i++) std::printf("\xE2\x95\x90");  // ═
    std::printf("\n");
    
    return (failed > 0) ? 1 : 0;
}

/*******************************************************************************
 * Test Assertion Implementations
 ******************************************************************************/

void rt_test_assert_impl(bool condition, const char* file, int32_t line) {
    if (!condition) {
        rt_test_failed = true;
        rt_test_error_pos += std::snprintf(
            rt_test_error_buffer + rt_test_error_pos,
            RT_ERROR_BUFFER_SIZE - rt_test_error_pos,
            "  \xF0\x9F\x94\xB4 TestAssert failed at %s:%d\n", file, line);  // 🔴
    }
}

void rt_test_assert_true_impl(bool condition, const char* file, int32_t line) {
    if (!condition) {
        rt_test_failed = true;
        rt_test_error_pos += std::snprintf(
            rt_test_error_buffer + rt_test_error_pos,
            RT_ERROR_BUFFER_SIZE - rt_test_error_pos,
            "  \xF0\x9F\x94\xB4 TestAssertTrue failed at %s:%d: expected TRUE, got FALSE\n", file, line);
    }
}

void rt_test_assert_false_impl(bool condition, const char* file, int32_t line) {
    if (condition) {
        rt_test_failed = true;
        rt_test_error_pos += std::snprintf(
            rt_test_error_buffer + rt_test_error_pos,
            RT_ERROR_BUFFER_SIZE - rt_test_error_pos,
            "  \xF0\x9F\x94\xB4 TestAssertFalse failed at %s:%d: expected FALSE, got TRUE\n", file, line);
    }
}

/*******************************************************************************
 * Comparison Assertion Support
 ******************************************************************************/

void rt_test_cmp_fail(const char* keyword, const char* detail,
                      const char* msg, const char* file, int32_t line) {
    rt_test_failed = true;
    rt_test_error_pos += std::snprintf(
        rt_test_error_buffer + rt_test_error_pos,
        RT_ERROR_BUFFER_SIZE - rt_test_error_pos,
        "  \xF0\x9F\x94\xB4 %s failed at %s:%d: %s",
        keyword, file, line, detail);

    if (msg != nullptr && msg[0] != '\0') {
        rt_test_error_pos += std::snprintf(
            rt_test_error_buffer + rt_test_error_pos,
            RT_ERROR_BUFFER_SIZE - rt_test_error_pos,
            " - %s", msg);
    }

    rt_test_error_pos += std::snprintf(
        rt_test_error_buffer + rt_test_error_pos,
        RT_ERROR_BUFFER_SIZE - rt_test_error_pos, "\n");
}

void rt_test_assert_cmp_float_tol(double expected, double actual, double epsilon,
                                  int32_t relation, const char* msg,
                                  const char* file, int32_t line) {
    double diff = expected - actual;
    if (diff < 0) diff = -diff;
    bool differ = (diff > epsilon);

    bool fail = (relation == RT_CMP_EQ && differ) ||
                (relation == RT_CMP_NEQ && !differ);
    if (!fail) return;

    char detail[512];
    const char* neg = (relation == RT_CMP_NEQ) ? "not " : "";
    std::snprintf(detail, sizeof(detail),
        "expected %s%g, got %g (epsilon %g, diff %g)", neg,
        expected, actual, epsilon, diff);

    const char* keyword = (relation == RT_CMP_NEQ) ? "assertneqf" : "asserteqf";
    rt_test_cmp_fail(keyword, detail, msg, file, line);
}

void rt_test_assert_cmp_str(const char* expected, const char* actual,
                            int32_t relation, const char* msg,
                            const char* file, int32_t line) {
    // Both null counts as equal
    bool differ;
    if (expected == nullptr && actual == nullptr) {
        differ = false;
    } else if (expected == nullptr || actual == nullptr) {
        differ = true;
    } else {
        differ = (std::strcmp(expected, actual) != 0);
    }

    bool fail = (relation == RT_CMP_EQ && differ) ||
                (relation == RT_CMP_NEQ && !differ);
    if (!fail) return;

    char detail[512];
    const char* neg = (relation == RT_CMP_NEQ) ? "not " : "";
    std::snprintf(detail, sizeof(detail),
        "expected %s\"%s\", got \"%s\"", neg,
        expected ? expected : "(null)", actual ? actual : "(null)");

    const char* keyword = (relation == RT_CMP_NEQ) ? "assertneq" : "asserteq";
    rt_test_cmp_fail(keyword, detail, msg, file, line);
}

void rt_test_assert_cmp_wstr(const char16_t* expected, const char16_t* actual,
                             int32_t relation, const char* msg,
                             const char* file, int32_t line) {
    // Compare char16_t strings manually (portable, no platform dependency)
    bool differ;
    if (expected == nullptr && actual == nullptr) {
        differ = false;
    } else if (expected == nullptr || actual == nullptr) {
        differ = true;
    } else {
        const char16_t* a = expected;
        const char16_t* b = actual;
        while (*a && *b && *a == *b) { a++; b++; }
        differ = (*a != *b);
    }

    bool fail = (relation == RT_CMP_EQ && differ) ||
                (relation == RT_CMP_NEQ && !differ);
    if (!fail) return;

    char detail[512];
    const char* neg = (relation == RT_CMP_NEQ) ? "not " : "";
    std::snprintf(detail, sizeof(detail),
        "expected %s(wstring), got (wstring) -- values differ", neg);

    const char* keyword = (relation == RT_CMP_NEQ) ? "assertneq" : "asserteq";
    rt_test_cmp_fail(keyword, detail, msg, file, line);
}

void rt_test_assert_nil_impl(void* ptr, const char* file, int32_t line) {
    if (ptr != nullptr) {
        rt_test_failed = true;
        rt_test_error_pos += std::snprintf(
            rt_test_error_buffer + rt_test_error_pos,
            RT_ERROR_BUFFER_SIZE - rt_test_error_pos,
            "  \xF0\x9F\x94\xB4 TestAssertNil failed at %s:%d: expected NIL, got %p\n", 
            file, line, ptr);
    }
}

void rt_test_assert_not_nil_impl(void* ptr, const char* file, int32_t line) {
    if (ptr == nullptr) {
        rt_test_failed = true;
        rt_test_error_pos += std::snprintf(
            rt_test_error_buffer + rt_test_error_pos,
            RT_ERROR_BUFFER_SIZE - rt_test_error_pos,
            "  \xF0\x9F\x94\xB4 TestAssertNotNil failed at %s:%d: expected not NIL\n", 
            file, line);
    }
}

void rt_test_fail_impl(const char* message, const char* file, int32_t line) {
    rt_test_failed = true;
    rt_test_error_pos += std::snprintf(
        rt_test_error_buffer + rt_test_error_pos,
        RT_ERROR_BUFFER_SIZE - rt_test_error_pos,
        "  \xF0\x9F\x94\xB4 TestFail at %s:%d: %s\n", 
        file, line, message ? message : "(no message)");
}
