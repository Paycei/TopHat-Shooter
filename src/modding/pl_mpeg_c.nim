## Raw bindings to the vendored pl_mpeg (vendor/pl_mpeg, see its LICENSE): an
## MPEG-1 video and MP2 audio decoder for MPEG program streams (.mpg files),
## compiled into the exe through pl_mpeg_impl.c (no DLL). Only what
## mod_media.nim uses is declared here; mod videos reach it through mod_media.

{.compile: "pl_mpeg_impl.c".}

const PlmAudioSamplesPerFrame* = 1152

type
  Plm* = distinct pointer       ## plm_t*
  PlmFrame* = distinct pointer  ## plm_frame_t*: only handed back to plm_frame_to_rgba
  PlmSamples* = object
    ## plm_samples_t (PLM_AUDIO_SEPARATE_CHANNELS is not defined): always
    ## stereo, left and right interleaved, -1..1
    time*: cdouble
    count*: cuint
    interleaved*: array[PlmAudioSamplesPerFrame * 2, cfloat]
  PlmVideoCallback* = proc (plm: Plm, frame: PlmFrame, user: pointer) {.cdecl.}
  PlmAudioCallback* = proc (plm: Plm, samples: ptr PlmSamples, user: pointer) {.cdecl.}

{.push importc, cdecl.}
proc plm_create_with_filename*(filename: cstring): Plm
proc plm_destroy*(self: Plm)
proc plm_has_headers*(self: Plm): cint
proc plm_get_num_video_streams*(self: Plm): cint
proc plm_get_num_audio_streams*(self: Plm): cint
proc plm_get_width*(self: Plm): cint
proc plm_get_height*(self: Plm): cint
proc plm_get_framerate*(self: Plm): cdouble
proc plm_get_samplerate*(self: Plm): cint
proc plm_set_audio_enabled*(self: Plm, enabled: cint)
proc plm_set_audio_lead_time*(self: Plm, leadTime: cdouble)
proc plm_get_time*(self: Plm): cdouble
proc plm_get_duration*(self: Plm): cdouble
proc plm_rewind*(self: Plm)
proc plm_set_loop*(self: Plm, loop: cint)
proc plm_has_ended*(self: Plm): cint
proc plm_set_video_decode_callback*(self: Plm, fp: PlmVideoCallback, user: pointer)
proc plm_set_audio_decode_callback*(self: Plm, fp: PlmAudioCallback, user: pointer)
proc plm_decode*(self: Plm, seconds: cdouble)
proc plm_decode_video*(self: Plm): PlmFrame
proc plm_decode_audio*(self: Plm): ptr PlmSamples
proc plm_seek*(self: Plm, time: cdouble, seekExact: cint): cint
proc plm_frame_to_rgba*(frame: PlmFrame, dest: ptr uint8, stride: cint)
{.pop.}

proc isNil*(p: Plm): bool {.inline.} = pointer(p).isNil
proc isNil*(f: PlmFrame): bool {.inline.} = pointer(f).isNil

proc time*(f: PlmFrame): float {.inline.} =
  ## The picture's time in seconds: plm_frame_t's first field.
  cast[ptr cdouble](f)[].float
