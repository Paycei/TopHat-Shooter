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
/* AWINDOW_FLAG_* live here; native_activity.h declares
 * ANativeActivity_setWindowFlags but does not pull in the flag enum. */
#include <android/window.h>

extern struct android_app *GetAndroidApp(void);

const char *nimAndroidInternalDataPath(void) {
    struct android_app *app = GetAndroidApp();
    if (app != NULL && app->activity != NULL &&
        app->activity->internalDataPath != NULL) {
        return app->activity->internalDataPath;
    }
    return ".";
}

/* Keep the display awake for the whole session.
 *
 * raylib's Android backend only sets AWINDOW_FLAG_FULLSCREEN. The game
 * auto-fires from the aim stick, so a player holding still touches nothing for
 * long stretches and the screen dims and locks mid-run. KEEP_SCREEN_ON is a
 * window flag, not a permission, so no manifest entry is needed.
 */
void nimAndroidKeepScreenOn(void) {
    struct android_app *app = GetAndroidApp();
    if (app != NULL && app->activity != NULL) {
        ANativeActivity_setWindowFlags(app->activity,
                                       AWINDOW_FLAG_KEEP_SCREEN_ON, 0);
    }
}
