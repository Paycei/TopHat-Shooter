/* Android-only C shim: expose the app's writable internal-data path to Nim.
 *
 * The game persists saves with Nim's std writeFile/readFile, which call libc
 * fopen directly and therefore bypass raylib's android_fopen (which would
 * otherwise prepend internalDataPath). So we fetch internalDataPath ourselves
 * and build absolute save paths from it (see save_system.getAppDataPath).
 *
 * GetAndroidApp() is provided (non-static) by raylib's rcore_android.c; the
 * android_app / ANativeActivity structs come from the NDK's native_app_glue,
 * whose include dir raylib.nim already adds to the C flags.
 *
 * Compiled only on Android via {.compile.} guarded by `when defined(android)`.
 */
#include <android_native_app_glue.h>

extern struct android_app *GetAndroidApp(void);

const char *nimAndroidInternalDataPath(void) {
    struct android_app *app = GetAndroidApp();
    if (app != NULL && app->activity != NULL &&
        app->activity->internalDataPath != NULL) {
        return app->activity->internalDataPath;
    }
    return ".";
}
