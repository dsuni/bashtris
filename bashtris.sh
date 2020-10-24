#!/bin/bash

# Bashtris v1.0 (July 26, 2012), a puzzle game for the command line.
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

# Define some constants:
# Define arrow keys
declare -r UPARROW=$'\x1b[A'
declare -r DOWNARROW=$'\x1b[B'
declare -r LEFTARROW=$'\x1b[D'
declare -r RIGHTARROW=$'\x1b[C'

# Color codes (pre-escaped strings, so they can be fed directly to sed)
declare -r BLACK='\\E\[37;40m'
declare -r RED='\\E\[0;41m'
declare -r GREEN='\\E\[0;42m'
declare -r BROWN='\\E\[0;43m'
declare -r BLUE='\\E\[0;44m'
declare -r LILAC='\\E\[0;45m'
declare -r CYAN='\\E\[0;46m'
declare -r GREY='\\E\[0;47m'
declare -r WHITE='\\E\[0;48m'

# Game setting related constants
declare -r GRAPHICS="st_basil_cathedral.txt"
declare -r MUSIC="korobeiniki.sh"
declare -r HISCORE="hiscore.txt"
declare -r INITIAL_DROP_TIME=500000000 # Initial pause between block drops (in nanoseconds)
declare -r LEVEL_DROP_TIME_REDUCE=25000000 # How much the pause should be reduced with each level up.
declare -r MIN_DROP_SPEED=10000000 # Minimum pause between block drops
declare -r MIN_X=29 # X-coordinate of the left side of the playing field
declare -r GRAPHICS_LINES_MIN=22 # Minimum number of terminal lines on which the game is playable.
declare -r MAX_LEVEL=20 # Maximum level
declare -r LEVEL_UP_ROWS=10 # Level up after this many rows have been cleared.
declare -r SCORE_Y=2 # Y-coordinate of position where score is to be printed
declare -r SCORE_X=10 # X-coordinate of the same
declare -r LEVEL_Y=4 # Y-coordinate of position where current level is to be printed
declare -r LEVEL_X=10
declare -r NEXT_Y=4 # Y-coordinate of position where the next block is shown
declare -r NEXT_X=63

# Initialize various variables:

# Variable containing the playing field. "W" = wall " " = empty,
# [IJLOSTZ] = square belonging to block of corresponding shape,
# "A" = active (i.e. falling) block.
field="W          W
W          W
W          W
W          W
W          W
W          W
W          W
W          W
W          W
W          W
W          W
W          W
W          W
W          W
W          W
W          W
W          W
W          W
W          W
W          W
WWWWWWWWWWWW"

level=0 # Current level
rows_removed_in_level=0 # Number of rows removed since last level-up
# Coordinates of the 4 x 4 "megablock" which can hold any of the actual
# blocks regardless of their rotation.
x=0
y=0

pieces="IJLOSTZ" # Possible pieces
next_piece="${pieces:$(($RANDOM % 7)):1}"
current_piece=''
current_color=''
current_rotation=0 # Values 0-3 for 4 possible orientations.
score=0
# When exiting this is used to check if the process was killed (e.g. Ctrl-C) or not.
killed=false

# $1 == Line to start redrawing from. $2 == Number of lines to redraw.
# No parameters given == Redraw everything
function redraw {
	# Each square is physically represented by a block 1 char high, and 2 chars wide.
	# Add the color coding to the lines to be redrawn. Use "s" instead of "  " here to
	# avoid parameter clipping by the for loop. (Replace with "  " on echo.)
	if [ -z $2 ] ; then
		lines=`echo "$field" | head -n -1 | sed "s/W/|/g;s/A/$current_color $WHITE/g;s/O/$BLUE $WHITE/g;s/I/$RED $WHITE/g;s/ /s/g;s/S/$GREEN $WHITE/g;s/ /s/g;s/Z/$CYAN $WHITE/g;s/ /s/g;s/L/$LILAC $WHITE/g;s/ /s/g;s/J/$BROWN $WHITE/g;s/ /s/g;s/T/$GREY $WHITE/g;s/ /s/g"`
		current_y=0
	else
		lines=`echo "$field" | sed -n ${1},$(($1 + $2))p | sed "s/WWWWWWWWWWWW/+--------------------+/;s/W/|/g;s/A/$current_color $WHITE/g;s/O/$BLUE $WHITE/g;s/I/$RED $WHITE/g;s/ /s/g;s/S/$GREEN $WHITE/g;s/ /s/g;s/Z/$CYAN $WHITE/g;s/ /s/g;s/L/$LILAC $WHITE/g;s/ /s/g;s/J/$BROWN $WHITE/g;s/ /s/g;s/T/$GREY $WHITE/g;s/ /s/g"`
		current_y=$(($1 - 1)) # Subtract 1, because tput starts counting lines from 0, but sed from 1.
	fi
	for line in $lines ; do
		tput cup $current_y $MIN_X
		echo -ne "$line" | sed 's/s/  /g'
		((++current_y))
	done
}

# Returns 0 (true) if collision detected
function detect_collision {
	# Maps the coordinates of the individual squares of the active block to substrings
	# in the "field" variable and greps them for collisions with walls & other blocks.
	echo "${field:$((13 * ($y_1 - 1) + $x_1 - 1)):1}${field:$((13 * ($y_2 - 1) + $x_2 - 1)):1}${field:$((13 * ($y_3 - 1) + $x_3 - 1)):1}${field:$((13 * ($y_4 - 1) + $x_4 - 1)):1}" | grep -q [IJLOSTWZ]
	return $?
}

# If the block can't be rotated due to wall proximity, we try to move it sideways
# and see if it can be rotated that way. Returns 0 upon success, 1 upon failure.
function wall_kick {
	# Try kicking right
	((++x_1))
	((++x_2))
	((++x_3))
	((++x_4))
	if ! detect_collision ; then
		((++x))
		return 0
	fi
	# Try kicking left
	((x_1-=2))
	((x_2-=2))
	((x_3-=2))
	((x_4-=2))
	if ! detect_collision ; then
		((--x))
		return 0
	fi
	# If it's an "I" block, try kicking more left
	if [ "$current_piece" == "I" ] ; then
		((--x_1))
		((--x_2))
		((--x_3))
		((--x_4))
		if ! detect_collision ; then
			((x-=2))
			return 0
		fi
	fi
	# Wall kick failed
	return 1
}

function rotate {
	case $current_piece in
		O) # O-pieces don't rotate.
			return
			;;
		I|S|Z) # These pieces have 2 rotational positions.
			# Try rotating and see if there are collisions.
			if [ $current_rotation -eq 0 ] ; then
				current_rotation=1
			else
				current_rotation=0
			fi
			calculate_square_coordinates
			if detect_collision ; then
				# If a collision is detected, see if we can still rotate with a wall kick.
				if ! wall_kick ; then
					# Collision detected, wall kick failed. Revert rotation.
					if [ $current_rotation -eq 0 ] ; then
						current_rotation=1
					else
						current_rotation=0
					fi
					return
				fi
			fi
			;;
		L|J|T) # These pieces have 4 rotational positions.
			((++current_rotation))
			if [ $current_rotation -gt 3 ] ; then
				current_rotation=0
			fi
			calculate_square_coordinates
			if detect_collision ; then
				if ! wall_kick ; then
					((--current_rotation))
					if [ $current_rotation -lt 0 ] ; then
						current_rotation=3
					fi
					return
				fi
			fi
			;;
	esac
	recalculate_field
	case $current_piece in
		I)
			redraw $y 4
			;;
		*)
			redraw $y 3
			;;
	esac
}

function moveleft {
	# Check if an "A" anywhere is preceded by another letter. If any are found,
	# it means the block can not be moved left, and we do nothing.
	if ! echo "$field" | grep -q [IJLOSTWZ]A ; then
		((--x))
		# Replaces the first instance of " A", with "A", and the last instance of "A"
		# with "A ", effectively moving the block one step left.
		field=`echo "$field" | sed 's/ A/A/;s/\(.*\)A/\1A /'`
		redraw $y $span
	fi
}

function moveright {
	if ! echo "$field" | grep -q A[IJLOSTWZ] ; then
		((++x))
		field=`echo "$field" | sed 's/A /A/;s/A/ A/'`
		redraw $y $span
	fi
}

# Drops the active block as far as it can go.
function drop {
	rows=0
	filler="..........."
	# Check how far it can go. (By adding 12 dots every time we add 1 row, since the
	# field has rows of 10 squares + 1 wall on each side and dots match any character.)
	until echo "$field" | tr -d "\n" | grep -q A$filler[IJLOSTWZ] ; do
		((++rows))
		filler="${filler}............"
	done
	((y+=$rows))
	calculate_square_coordinates
	recalculate_field
	field=`echo "$field" | sed "s/A/$current_piece/g"` # Lock the piece in place
	remove_completed_rows
	nextblock
	set_nextdrop
}

# Drops the block one step.
function dropone {
	if ! echo "$field" | tr -d "\n" | grep -q A...........[IJLOSTWZ] ; then
		((++y))
		calculate_square_coordinates
		recalculate_field
		redraw $(($y - 1)) $(($span + 1))
	else
		# The block can't fall any further. Lock it in place.
		field=`echo "$field" | sed "s/A/$current_piece/g"`
		remove_completed_rows
		nextblock
	fi
	set_nextdrop
}

function recalculate_field {
	# First remove all active squares ("A"), then re-insert them in the new position.
	# ${y}s/./A/${x} replaces the xth character on the yth row. (Dots match any char.)
	field=`echo "$field" | sed "s/A/ /g;${y_1}s/./A/${x_1};${y_2}s/./A/${x_2};${y_3}s/./A/${x_3};${y_4}s/./A/${x_4}"`
}

# Calculate the new coordinates for each of the 4 squares occupied by the falling block,
# based on the coordinates of the 4x4 "superblock", the block's shape & orientation.
function calculate_square_coordinates {
	case $current_piece in
		O)
			x_1=$(($x + 1)) # |-- (x,y)
			y_1=$y          # v
			x_2=$(($x + 2)) # .##.
			y_2=$y          # .##.
			x_3=$x_1        # ....
			y_3=$(($y + 1)) # ....
			x_4=$x_2
			y_4=$y_3
			span=2 # Number of vertical rows this orientation spans from the top.
			;;
		I)
			case $current_rotation in
				0)
					x_1=$x
					y_1=$(($y + 1))
					x_2=$(($x + 1)) # ....
					y_2=$y_1        # ####
					x_3=$(($x + 2)) # ....
					y_3=$y_1        # ....
					x_4=$(($x + 3))
					y_4=$y_1
					span=2 # 2 not 1, because it occupies the second row from the top.
					;;
				1)
					x_1=$(($x + 1))
					y_1=$y
					x_2=$x_1        # .#..
					y_2=$(($y + 1)) # .#..
					x_3=$x_1        # .#..
					y_3=$(($y + 2)) # .#..
					x_4=$x_1
					y_4=$(($y + 3))
					span=4
					;;
			esac
			;;
		S)
			case $current_rotation in
				0)
					x_1=$(($x + 1))
					y_1=$y
					x_2=$(($x + 2)) # .##.
					y_2=$y          # ##..
					x_3=$x          # ....
					y_3=$(($y + 1)) # ....
					x_4=$x_1
					y_4=$y_3
					span=2
					;;
				1)
					x_1=$(($x + 1))
					y_1=$y
					x_2=$x_1        # .#..
					y_2=$(($y + 1)) # .##.
					x_3=$(($x + 2)) # ..#.
					y_3=$y_2        # ....
					x_4=$x_3
					y_4=$(($y + 2))
					span=3
					;;
			esac
			;;
		Z)
			case $current_rotation in
				0)
					x_1=$x
					y_1=$y
					x_2=$(($x + 1)) # ##..
					y_2=$y          # .##.
					x_3=$x_2        # ....
					y_3=$(($y + 1)) # ....
					x_4=$(($x + 2))
					y_4=$y_3
					span=2
					;;
				1)
					x_1=$(($x + 2))
					y_1=$y
					x_2=$x_1        # ..#.
					y_2=$(($y + 1)) # .##.
					x_3=$(($x + 1)) # .#..
					y_3=$y_2        # ....
					x_4=$x_3
					y_4=$(($y + 2))
					span=3
					;;
			esac
			;;
		L)
			case $current_rotation in
				0)
					x_1=$(($x + 2))
					y_1=$y
					x_2=$x_1        # ..#.
					y_2=$(($y + 1)) # ###.
					x_3=$(($x + 1)) # ....
					y_3=$y_2        # ....
					x_4=$x
					y_4=$y_2
					span=2
					;;
				1)
					x_1=$(($x + 1))
					y_1=$y
					x_2=$x_1        # .#..
					y_2=$(($y + 1)) # .#..
					x_3=$x_1        # .##.
					y_3=$(($y + 2)) # ....
					x_4=$(($x + 2))
					y_4=$y_3
					span=3
					;;
				2)
					x_1=$x
					y_1=$y
					x_2=$(($x + 1)) # ###.
					y_2=$y          # #...
					x_3=$(($x + 2)) # ....
					y_3=$y          # ....
					x_4=$x
					y_4=$(($y + 1))
					span=2
					;;
				3)
					x_1=$(($x + 1))
					y_1=$y
					x_2=$(($x + 2)) # .##.
					y_2=$y          # ..#.
					x_3=$x_2        # ..#.
					y_3=$(($y + 1)) # ....
					x_4=$x_2
					y_4=$(($y + 2))
					span=3
					;;
			esac
			;;
		J)
			case $current_rotation in
				0)
					x_1=$x
					y_1=$y
					x_2=$x          # #...
					y_2=$(($y + 1)) # ###.
					x_3=$(($x + 1)) # ....
					y_3=$y_2        # ....
					x_4=$(($x + 2))
					y_4=$y_2
					span=2
					;;
				1)
					x_1=$(($x + 1))
					y_1=$y
					x_2=$x_1        # .##.
					y_2=$(($y + 1)) # .#..
					x_3=$x_1        # .#..
					y_3=$(($y + 2)) # ....
					x_4=$(($x + 2))
					y_4=$y
					span=3
					;;
				2)
					x_1=$x
					y_1=$y
					x_2=$(($x + 1)) # ###.
					y_2=$y          # ..#.
					x_3=$(($x + 2)) # ....
					y_3=$y          # ....
					x_4=$x_3
					y_4=$(($y + 1))
					span=2
					;;
				3)
					x_1=$(($x + 1))
					y_1=$(($y + 2))
					x_2=$(($x + 2)) # ..#.
					y_2=$y          # ..#.
					x_3=$x_2        # .##.
					y_3=$(($y + 1)) # ....
					x_4=$x_2
					y_4=$y_1
					span=3
					;;
			esac
			;;
		T)
			case $current_rotation in
				0)
					x_1=$x
					y_1=$y
					x_2=$(($x + 1)) # ###.
					y_2=$y          # .#..
					x_3=$(($x + 2)) # ....
					y_3=$y          # ....
					x_4=$x_2
					y_4=$(($y + 1))
					span=2
					;;
				1)
					x_1=$(($x + 2))
					y_1=$y
					x_2=$x_1        # ..#.
					y_2=$(($y + 1)) # .##.
					x_3=$(($x + 1)) # ..#.
					y_3=$y_2        # ....
					x_4=$x_1
					y_4=$(($y + 2))
					span=3
					;;
				2)
					x_1=$(($x + 1))
					y_1=$y
					x_2=$x          # .#..
					y_2=$(($y + 1)) # ###.
					x_3=$x_1        # ....
					y_3=$y_2        # ....
					x_4=$(($x + 2))
					y_4=$y_2
					span=2
					;;
				3)
					x_1=$(($x + 1))
					y_1=$y
					x_2=$x_1        # .#..
					y_2=$(($y + 1)) # .##.
					x_3=$x_1        # .#..
					y_3=$(($y + 2)) # ....
					x_4=$(($x + 2))
					y_4=$y_2
					span=3
					;;
			esac
			;;
	esac
}

function remove_completed_rows {
	# Completed lines are the lines that don't contain spaces, with the exception of the last
	# line, which is always "WWWWWWWWWWWW". (The "bottom wall".) We count them before removal
	# so that the score can be appropriately updated.
	matches=`echo "$field" | head -n -1 | grep -vc " "`
	# Remove the rows replacing them by adding empty lines at the top.
	field=`yes "W          W" | head -n $matches && echo "$field" | grep -e " " -e "WW"`
	update_score $matches
}

# $1 = Number of removed rows.
function update_score {
	case $1 in
		1)
			((score+=$((40 * ($level + 1)))))
			;;
		2)
			((score+=$((100 * ($level + 1)))))
			;;
		3)
			((score+=$((300 * ($level + 1)))))
			;;
		4)
			((score+=$((1200 * ($level + 1)))))
			;;
	esac
	((rows_removed_in_level+=$1))
	tput cup $SCORE_Y $SCORE_X
	echo "$score"
	# Is it time for a level up?
	if [ $rows_removed_in_level -ge $LEVEL_UP_ROWS -a $level -lt $MAX_LEVEL ] ; then
		((++level))
		((rows_removed_in_level-=$LEVEL_UP_ROWS))
		tput cup $LEVEL_Y $LEVEL_X
		echo $level
		set_timeout # Update the block drop timeout to match the new level
	fi
}

function set_color {
	case $1 in
		O)
			current_color=$BLUE
			;;
		I)
			current_color=$RED
			;;
		S)
			current_color=$GREEN
			;;
		Z)
			current_color=$CYAN
			;;
		L)
			current_color=$LILAC
			;;
		J)
			current_color=$BROWN
			;;
		T)
			current_color=$GREY
			;;
	esac
}

# B = Block, S = Space
function printnext {
	case $1 in
		O)
			echo -en "SBBS\nSBBS"
			;;
		I)
			echo -en "SSSS\nBBBB"
			;;
		S)
			echo -en "SBBS\nBBSS"
			;;
		Z)
			echo -en "BBSS\nSBBS"
			;;
		L)
			echo -en "SSBS\nBBBS"
			;;
		J)
			echo -en "BSSS\nBBBS"
			;;
		T)
			echo -en "SBSS\nBBBS"
			;;
	esac
}

function nextblock {
	current_rotation=0
	current_piece=$next_piece
	next_piece="${pieces:$(($RANDOM % 7)):1}"
	# Display next piece
	set_color $next_piece
	count=0
	for line in `printnext $next_piece` ; do
		line=`echo "$line" | sed "s/B/$current_color  $WHITE/g;s/S/  /g"`
		tput cup $(($NEXT_Y + $count)) $NEXT_X
		echo -ne "$line"
		((++count))
	done
	y=1
	x=5
	calculate_square_coordinates
	if detect_collision ; then
		# Oops. The inserted block instantly collided with one already in place.
		game_over
	fi
	recalculate_field
	set_color $current_piece
	redraw
}

# Sets the block drop timeout according to the current level.
function set_timeout {
	timeout_nanos=$(($INITIAL_DROP_TIME - $LEVEL_DROP_TIME_REDUCE * $level))
	if [ $timeout_nanos -lt $MIN_DROP_SPEED ] ; then
		timeout_nanos=$MIN_DROP_SPEED
	fi
}

# Schedules the time when the active block will fall one line further.
function set_nextdrop {
	nextdrop=$((`date +%s%N` + $timeout_nanos))
}

function new_hiscore {
	echo "You have a new hiscore. Please enter your name."
	# We don't want to read the last arrowpresses of someone trying to desperately clear
	# one more line before bobming out. This will discard anything in the stdin buffer.
	read -s -t 1 -n 10000 discard
	read name
	name=`echo "$name" | sed 's/://g' | tr -cd [:print:] | head -c 30`
	if [ -z "$name" ] ; then
		name="Anonymous"
	fi
	echo "$name:$level:$score" >> $HISCORE
	hiscores=`cat $HISCORE | sort -n -r -t : -k 3 -k 2 | head -10`
	echo "$hiscores" > $HISCORE
	max_tabs=0
	i=1
	# Get the "tab equivalent" space occupied by each name
	for n in `echo "$hiscores" | tr " " "_"` ; do
		# In the console 8 spaces = 1 tab
		num_tabs[$i]=$((`echo -n "$n" | sed 's/:.*//' | wc -c` / 8 + 1))
		if [ ${num_tabs[$i]} -gt $max_tabs ] ; then
			max_tabs=${num_tabs[$i]}
		fi
		((++i))
	done
	# Use "yes | head" -construct to fill in correct number of tabs.
	echo -e "Rank\tName`yes "\t" | tr -d "\n" | head -c $(($max_tabs * 2))`Level\tScore\n"
	i=1
	for n in `echo "$hiscores" | tr " " "_"` ; do
		echo -e "$i\t$n" | sed "s/:/`yes "\t" | tr -d "\n" | head -c $((($max_tabs - ${num_tabs[$i]}) * 2 + 2))`/;s/:/\t/g;s/_/ /g"
		((++i))
	done
}

function game_over {
	# Tell the music to stop.
	if [ $music ] ; then
		kill -s 12 $music
	fi
	# Display the classic "GAME OVER" text.
	tput cup 10 $(($MIN_X + 2))
	echo -ne "[0m+----------------+"
	tput cup 11 $(($MIN_X + 2))
	echo -ne "[0m|    GAME OVER   |"
	tput cup 12 $(($MIN_X + 2))
	echo -ne "[0m+----------------+"
	tput cup $(($graphics_lines + 1)) 0 # Place the cursor below the playing field
	tput cnorm # Return cursor to normal
	echo -ne "[0m" # Return colors to normal
	stty echo # Turn echoing back on
	echo
	# If the process was killed by e.g. Ctrl-C, we just quit here.
	if $killed ; then
		echo "Oops. Caught a kill signal. Exiting."
		exit 0
	fi
	touch $HISCORE || exit 0 # If we can't write to the hiscore file, we just exit too.
	# Did the player make it to the top 10?
	if [ `cat $HISCORE | wc -l` -lt 10 ] ; then
		new_hiscore
	elif [ `tail -1 $HISCORE | sed 's/.*://'` -lt $score ] ; then
		new_hiscore
	fi 
	exit 0
}

# Make sure that the working directory is that of the script, since other
# things (music, graphics, hiscore) depends on it.
cd `dirname "$0"`
# Check that the terminal window is big enough.
graphics_lines=0
if [ -r ./$GRAPHICS ] ; then
	graphics_lines=$((`cat $GRAPHICS | wc -l` + 1))
	graphics_cols=`cat $GRAPHICS | head -1 | tr -d "\n" | wc -c`
	# If the graphics doesn't quite fit the screen, we cut it from the bottom.
	if [ $graphics_lines -gt `tput lines` ] ; then
		graphics_lines=`tput lines`
	fi
else
	graphics_lines=$GRAPHICS_LINES_MIN
	graphics_cols=$(($NEXT_X + 8))
fi

# If the terminal is too small, then tough luck. Better to exit than to show a
# line wrapped garbled unplayable mess.
if [ $GRAPHICS_LINES_MIN -gt `tput lines` -o $graphics_cols -gt `tput cols` ] ; then
	echo -e "ERROR: Your terminal is too small.\nA minimum of $graphics_cols columns by $GRAPHICS_LINES_MIN lines required." >&2
	exit 1
fi

# Start the music if possible
music=""
if [ ! -x ./$MUSIC ] ; then
	echo "WARNING: Music file not found, or has insufficient permissions. Music will be disabled." >&2
	echo "         Press any key to continue." >&2
	read -s n1
elif [ -e /dev/dsp ] || [ -e /usr/bin/aplay ] ; then
	( ./$MUSIC ) &
	music=$!
else
	echo "WARNING: Neither OSS nor ALSA is installed on your system. Music will be disabled." >&2
	echo "         Press any key to continue." >&2
	read -s n1
fi

if [ ! -r ./$GRAPHICS ] ; then
	echo "WARNING: Graphics file not found, or has insufficient permissions. Game will start without." >&2
	echo "         Press any key to continue." >&2
	read -s n1
	clear
else
	clear
	cat $GRAPHICS | head -n $(($graphics_lines - 1))
	echo -n "+------------------------------------------------------------------------------+"
fi

# We don't want to leave the subshell running if someone presses CTRL+C
trap 'killed=true ; game_over' SIGINT SIGTERM
tput cup $SCORE_Y $SCORE_X
echo "$score"
tput cup $LEVEL_Y $LEVEL_X
echo "$level"
tput civis # Make cursor invisible
stty -echo # Turn echo off
set_timeout
nextblock

set_nextdrop
# Main loop
while true ; do
	now=`date +%s%N`
	# If the time to make the block drop a notch has expired (while doing
	# other operations), drop it before doing anything else.
	if [ $now -ge $nextdrop ] ; then
		dropone
	# Read the keyboard, but time out when it's time to drop the block a notch.
	# (read will exit with 0 status from keyboard input, and non-0 from timeout.)
	elif read -s -n3 -t0.`printf %.9d $(($nextdrop - $now))` keypress ; then
		case "$keypress" in
			$UPARROW)
			rotate
			;;
			$DOWNARROW)
			drop
			;;
			$LEFTARROW)
			moveleft
			;;
			$RIGHTARROW)
			moveright
			;;
		esac
	else
		# Being here means read timed out.
		dropone
	fi
done
