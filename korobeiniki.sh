#!/bin/bash

# Korobeiniki v1.0 (July 26, 2012), music for the bastris game.
# Copyright (C) 2012 Daniel Suni
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# /dev/dsp default = 8000 frames per second, 1 byte per frame
declare -r FPS=8000
declare -r VOLUME=$'\xc0' # Max volume = \xff
declare -r MUTE=$'\x80' # Middle of the scale = No volume (\x00 would also be max vol)

# The "notes" look like this:
# oxxxxxxxxxxxxxxxxxxxxxxxxxxxxxoxxxxxxxxxxxxxxxxxxxxxxxxxxxxxoxxxxxxxxxxxxxxxxxxxxxxxxxxxxxoxx...
# ^                 ^           ^- Repeat previous sequence   ^- Repeat again, et.c.
# |-- "volume byte" |- N "mute bytes", where N is determined by the frequency desired.
#
# Since /dev/dsp uses 8000 fps, the frequency of the volume bytes should be 8000 / tone frequency
# E.g. for an "A" of 440 Hz the byte frequency should be 8000 / 440 ~= 18 , i.e.
# oxxxxxxxxxxxxxxxxxoxxxxxxxxxxxxxxxxxoxxxxxxxxxxxxxxxxxoxxx... et.c.
#
# The total number of bytes in the repeated sequences determines the duration of the note. (8000 bytes = 1s)
#
# Since this method does not use precise values, the notes will be somewhat off-key. This problem
# gets worse with increasing frequencies, as the rounding errors get bigger. With lower frequencies
# it's not really noticable to the untrained ear.

# Notes in hertz
declare -r c0=65
declare -r d0=73
declare -r eb0=78
declare -r f0=87
declare -r g0=98
declare -r ab0=104
declare -r a0=110
declare -r bb0=117
declare -r b0=123
declare -r c=131
declare -r d=147
declare -r eb=156
declare -r e=165
declare -r f=175
declare -r g=196
declare -r ab=208
declare -r a=220
declare -r bb=233
declare -r b=247
declare -r c2=262
declare -r d2=294
declare -r eb2=311
declare -r s=7999 # Silence

# Note durations ha = half, qu = quarter, et.c.
declare -r ha=8
declare -r qu=4
declare -r que=3
declare -r ei=2
declare -r si=1
declare -r ss=0 # Will be translated to a very short non-zero duration.

function note { # $1 = pitch (Hz) $2 = duration (bytes)
	mute_bytes_num=$(($FPS / $1 - 1))
	note_bytes="$VOLUME`yes $MUTE | tr -d '\n' | head -c $mute_bytes_num`" # Create 1 oxxx...-sequence
	yes $note_bytes | tr -d '\n' | head -c $2 # Create as many bytes of concatenated sequences as needed.
}

# Smaller value = faster tempo
declare -r TEMPO=900

function tune { # $1 = List of notes in the format pitch(Hz):duration(note)
	for n in $1 ; do
		pitch=`echo $n | sed 's/:.*//'`
		duration=`echo $n | sed 's/.*://'`
		((duration*=TEMPO))
		if [ $duration -eq 0 ] ; then
			duration=50
		fi
		echo -n "`note $pitch $duration`"
	done
}

# Korobeiniki is a Russian folk song (and as such, part of the public domain).
# It consists of 2 distinct parts.
tune_a="$g:$qu $d:$ei $eb:$ei $f:$qu $eb:$ei $d:$ei $c:$qu $s:$ss $c:$ei $eb:$ei $g:$qu $f:$ei
$eb:$ei $d:$qu $s:$ss $d:$ei $eb:$ei $f:$qu $g:$qu $eb:$qu $s:$ss $c:$qu $s:$ss $c:$qu $s:$qu
$f:$qu $s:$ss $f:$ei $ab:$ei $c2:$qu $bb:$ei $ab:$ei $g:$qu $s:$ss $g:$ei $eb:$ei $g:$qu $f:$ei
$eb:$ei $d:$qu $s:$ss $d:$ei $eb:$ei $f:$qu $g:$qu $eb:$qu $s:$ss $c:$qu $s:$ss $c:$qu $s:$qu"

tune_b="$g:$ha $eb:$ha $f:$ha $d:$ha $eb:$ha $c:$ha $b0:$ha $d:$ha $s:$ss $g:$ha $eb:$ha
$f:$ha $d:$ha $eb:$qu $g:$qu $c2:$qu $s:$ss $c2:$qu $b:$ha $b:$ha"

cr_tune_a=`tune "$tune_a"`
cr_tune_b=`tune "$tune_b"`

# Allow the parent (game) script to kill the process when it's not needed any more.
trap 'exit 0' SIGUSR2
while true ; do
	# Run echo command in a subshell to prevent the sound from going berserk when script exits.
	# (This will cause the tune to play until finished, then stop even if script is killed.)
	( echo -n "$cr_tune_a$cr_tune_a$cr_tune_b" > /dev/dsp ) &>/dev/null &
	wait
done
