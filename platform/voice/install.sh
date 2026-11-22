#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Install the voice prompts on the TS-328 (run as root on the NAS from a
# copy of this directory). Needs alsa-utils (aplay, amixer); python3 is
# only used for the buzzer fallback.
set -eu
cd "$(dirname "$0")"
install -D -m 0755 qnap-voice /usr/local/sbin/qnap-voice
install -D -m 0755 qnap-voice-poweroff /usr/lib/systemd/system-shutdown/qnap-voice-poweroff
install -D -m 0644 qnap-voice.service /etc/systemd/system/qnap-voice.service
[ -e /etc/default/qnap-voice ] || install -D -m 0644 qnap-voice.default /etc/default/qnap-voice
install -d /usr/local/share/qnap-voice
install -m 0644 sounds/*.wav README /usr/local/share/qnap-voice/
systemctl daemon-reload
systemctl enable qnap-voice.service
