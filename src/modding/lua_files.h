/* The mod file sandbox at the C level. Included by the files that compile
   Lua's io, os, auxiliary (loadfile/dofile) and package (require's file
   searcher) libraries, ahead of the unmodified vendor source: every fopen,
   freopen, remove and rename those make goes through tophat_file_check
   (lua_bridge.nim), which resolves the path for the mod whose code is running
   and refuses it outside that mod's folders (reads: the mod's folder and
   mod.dataDir(); writes: mod.dataDir() only). A refused file fails like one
   without permission (EACCES); the gate logs why to the mod's log.
   The originals stay out of Lua's reach (they are C calls, not Lua values),
   so no table, upvalue or registry walk gets around this. */
#ifndef tophat_lua_files_h
#define tophat_lua_files_h

#include "../../vendor/lua/lprefix.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* 1 and the resolved path in `out` when the running mod may open `path`. */
extern int tophat_file_check(const char *path, int write, char *out, int cap);

#define TOPHAT_PATH_CAP 4096

static FILE *tophat_fopen(const char *path, const char *mode) {
  char real[TOPHAT_PATH_CAP];
  int write = mode != NULL && strpbrk(mode, "wa+") != NULL;
  if (!tophat_file_check(path, write, real, TOPHAT_PATH_CAP)) { errno = EACCES; return NULL; }
  return fopen(real, mode);
}

static FILE *tophat_freopen(const char *path, const char *mode, FILE *f) {
  char real[TOPHAT_PATH_CAP];
  int write = mode != NULL && strpbrk(mode, "wa+") != NULL;
  if (path == NULL) return freopen(NULL, mode, f);
  if (!tophat_file_check(path, write, real, TOPHAT_PATH_CAP)) {
    if (f != NULL) fclose(f);   /* (a failed freopen closes the stream) */
    errno = EACCES;
    return NULL;
  }
  return freopen(real, mode, f);
}

static int tophat_remove(const char *path) {
  char real[TOPHAT_PATH_CAP];
  if (!tophat_file_check(path, 1, real, TOPHAT_PATH_CAP)) { errno = EACCES; return -1; }
  return remove(real);
}

static int tophat_rename(const char *from, const char *to) {
  char realFrom[TOPHAT_PATH_CAP], realTo[TOPHAT_PATH_CAP];
  if (!tophat_file_check(from, 1, realFrom, TOPHAT_PATH_CAP) ||
      !tophat_file_check(to, 1, realTo, TOPHAT_PATH_CAP)) { errno = EACCES; return -1; }
  return rename(realFrom, realTo);
}

/* After the definitions above (which call the real ones) and after every
   system header the vendor file includes (their include guards keep them
   from being read again under these names). */
#define fopen tophat_fopen
#define freopen tophat_freopen
#define remove tophat_remove
#define rename tophat_rename

#endif
