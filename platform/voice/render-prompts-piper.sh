#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Render the TS-328 voice prompts with Piper (on the build PC). Voice: en_US-joe-medium,
# "nerdy cartoon" styling: faster, pitched up, nasal EQ. Output: S16_LE 48 kHz stereo.
set -eu
T=${TTS_DIR:-./tts}; O=${1:-./sounds}; mkdir -p "$O"
r() { echo "$2" | "$T/venv/bin/piper" -m "$T/voices/en_US-joe-medium.onnx" --length-scale 0.85 -f "$O/raw-$1.wav" 2>/dev/null
      sox "$O/raw-$1.wav" -r 48000 -c 2 -b 16 "$O/$1.wav" pitch 500 equalizer 1400 0.8q +4 bass -6 treble +2 norm -1 pad 0.2 0.6
      rm -f "$O/raw-$1.wav"; }
r boot-complete "Boot complete! All systems nominal. The storage device is ready, and so am I!"
r sd-a "Shutting down. Saving all the bits..."; r sd-b "Goodbye!"
sox -n -r 48000 -c 2 -b 16 "$O/gap.wav" trim 0.0 1.0
sox "$O/sd-a.wav" "$O/gap.wav" "$O/sd-b.wav" "$O/shutting-down.wav"; rm -f "$O/sd-a.wav" "$O/sd-b.wav" "$O/gap.wav"
r powering-down "Powering down. Initiating nap protocol!"
r raid-sync-complete "RAID sync complete. All three drives are protected."
r raid-warning "Warning! A drive in the RAID has a problem. Please check the storage page."
# A plain 1 kHz tone for "qnap-voice test" and speaker checks
sox -n -r 48000 -c 2 -b 16 "$O/test-tone-1k.wav" synth 1 sine 1000 vol 0.3
