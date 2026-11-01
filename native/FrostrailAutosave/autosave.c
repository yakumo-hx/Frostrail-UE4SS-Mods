/* MIT, Yuuka. Native save bridge for Demo 25985740 / UE4SS cdbc0b66 only.
 * Scheduling, exit handling and player messages belong to the Lua package.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdbool.h>
#include "MinHook.h"
#include "ue4ss_lua_api.h"

typedef struct lua_State lua_State;
typedef int (*LuaFunction)(lua_State *);
static int64_t (*lua_tointegerx)(lua_State *, int, int *);
static void (*lua_pushboolean)(lua_State *, int);
static const char *(*lua_pushstring)(lua_State *, const char *);
static void (*lua_pushinteger)(lua_State *, int64_t);
static void (*lua_pushcclosure)(lua_State *, LuaFunction, int);
static uintptr_t game;

typedef struct { void *data; int32_t count, capacity; } NativeArray;
typedef void *(*Lookup)(void *);
typedef bool (*Authority)(void *);
typedef void *(*Capture)(void *, void *);
typedef void (*Destroy)(void *);
typedef void (*WriteCampaign)(void *, void *, void *);
typedef bool (*WriteSlot)(NativeArray *, NativeArray *, int32_t);
static WriteSlot original_write;
static bool hook_ready;
static DWORD save_thread;
static unsigned write_count;
static bool write_success;
static char written_slot[512];

static bool image_matches(uintptr_t base, DWORD timestamp, DWORD image_size) {
    if (!base) return false;
    const IMAGE_DOS_HEADER *dos = (const void *)base;
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return false;
    const IMAGE_NT_HEADERS64 *nt = (const void *)(base + dos->e_lfanew);
    return nt->Signature == IMAGE_NT_SIGNATURE
        && nt->FileHeader.Machine == IMAGE_FILE_MACHINE_AMD64
        && nt->OptionalHeader.Magic == IMAGE_NT_OPTIONAL_HDR64_MAGIC
        && nt->FileHeader.TimeDateStamp == timestamp
        && nt->OptionalHeader.SizeOfImage == image_size;
}

static bool compatible_images(uintptr_t executable, uintptr_t loader) {
    return image_matches(executable, 0x9cfbe3de, 0xb182000)
        && image_matches(loader, 0x6ade4f39, 0x13c3000);
}

/* Observe only our synchronous campaign writer, on its calling thread.
 * Native saves from other call sites pass through unchanged. */
static bool observe_write(NativeArray *bytes, NativeArray *slot, int32_t user) {
    bool ours = save_thread == GetCurrentThreadId()
        && (uintptr_t)__builtin_return_address(0) == game + 0x5b2c8fc;
    bool result = original_write(bytes, slot, user);
    if (ours) {
        ++write_count;
        write_success = result;
        if (slot->data && slot->count > 1 && slot->count <= 32768) {
            int count = WideCharToMultiByte(CP_UTF8, 0, slot->data, slot->count - 1,
                                           written_slot, sizeof(written_slot) - 1, NULL, NULL);
            if (count > 0) written_slot[count] = 0;
        }
    }
    return result;
}

static int failure(lua_State *L, const char *message) {
    lua_pushboolean(L, false);
    lua_pushstring(L, message);
    return 2;
}

/* Lua passes a freshly resolved local host controller on the game thread.
 * Nothing here retains a UObject across calls. The engine owns the snapshot's
 * allocations; construction and destruction both use the native functions. */
static int save(lua_State *L) {
    if (save_thread) return failure(L, "save already in progress");
    int is_integer = 0;
    int64_t address = lua_tointegerx(L, 1, &is_integer);
    if (!is_integer || address <= 0) return failure(L, "no current controller");
    void *controller = (void *)(uintptr_t)address;
    /* Capture needs UWorld*, not WorldContextObject. GetWorld uses slot 0x180. */
    void *world = (*(Lookup *)(*(uintptr_t *)controller + 0x180))(controller);
    if (!world) return failure(L, "no current world");
    void *session = ((Lookup)(game + 0x5b177a0))(world);
    void *state = ((Lookup)(game + 0x4aa8c60))(world);
    void *level = ((Lookup)(game + 0x5add8a0))(world);
    if (!session || !state || !level || !((Authority)(game + 0x4a92730))(world))
        return failure(L, "missing authoritative gameplay context");
    const NativeArray *campaign = (const void *)((uintptr_t)session + 0x30);
    if (!campaign->data || campaign->count <= 1)
        return failure(L, "no active campaign");

    if (!hook_ready) {
        MH_STATUS error = MH_Initialize();
        if (error != MH_OK && error != MH_ERROR_ALREADY_INITIALIZED)
            return failure(L, MH_StatusToString(error));
        error = MH_CreateHook((void *)(game + 0x3d80a60), (void *)observe_write, (void **)&original_write);
        if (error != MH_OK) return failure(L, MH_StatusToString(error));
        error = MH_EnableHook((void *)(game + 0x3d80a60));
        if (error != MH_OK) {
            MH_RemoveHook((void *)(game + 0x3d80a60));
            return failure(L, MH_StatusToString(error));
        }
        hook_ready = true;
    }

    _Alignas(16) unsigned char snapshot[0x2b0];
    write_count = 0;
    write_success = false;
    written_slot[0] = 0;
    save_thread = GetCurrentThreadId();
    ((Capture)(game + 0x5b123c0))(snapshot, world);
    ((WriteCampaign)(game + 0x5b2c5e0))(session, world, snapshot);
    ((Destroy)(game + 0x59d8710))(snapshot);
    save_thread = 0;
    lua_pushboolean(L, write_count == 1 && write_success);
    lua_pushstring(L, write_count == 1 ? (write_success ? "native write succeeded" : "native write failed")
                                      : "expected exactly one native campaign write");
    lua_pushstring(L, written_slot);
    lua_pushinteger(L, write_count);
    return 4;
}

__declspec(dllexport) int luaopen_frostrail_autosave(lua_State *L) {
    uintptr_t loader = (uintptr_t)GetModuleHandleW(L"UE4SS.dll");
    uintptr_t executable = (uintptr_t)GetModuleHandleW(NULL);
    /* Do not call even a Lua C API address until BOTH fixed images match.
     * Zero results needs no Lua API and lets Lua report the disabled status. */
    if (!compatible_images(executable, loader)) return 0;
    game = executable;
#define BIND(name) name = (__typeof__(name))(loader + RVA_##name)
    BIND(lua_tointegerx); BIND(lua_pushboolean); BIND(lua_pushstring);
    BIND(lua_pushinteger); BIND(lua_pushcclosure);
#undef BIND
    lua_pushcclosure(L, save, 0);
    return 1;
}
