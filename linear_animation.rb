# Copyright 2011, 2014 Exavideo LLC.
# 
# This file is part of Exaboard.
# 
# Exaboard is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# Exaboard is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with Exaboard.  If not, see <http://www.gnu.org/licenses/>.


##
# A simple linear animation - i.e. a value that goes from zero to one,
# or one to zero, in a uniform ramp over a certain number of frames.
class LinearAnimation
    IN = 0
    OUT = 1

	##
	# Initializes the animation.
    def initialize
        @value = 0
        @total_frames = 0
        @frame = 0
        @direction = IN
        @transition_done_block = nil
    end

	##
	# Moves the animation to the next frame.
    def frame_advance
        if @total_frames > 0
            @frame += 1
            if @direction == IN
                @value = @frame.to_f / @total_frames.to_f
            else
                @value = 1.0 - (@frame.to_f / @total_frames.to_f)
            end

            if @frame == @total_frames
                @frame = 0
                @total_frames = 0

                if @transition_done_block
                    # copy to temporary in case the block calls in or out
                    the_block = @transition_done_block
                    @transition_done_block = nil
                    the_block.call
                end
            end
        end
    end

	##
	# Begin an animation from out (0) to in (1).
    def in(frames)
        if @total_frames == 0 and @value < 0.5
            @frame = 0
            @total_frames = frames
            @direction = IN

            if block_given?
                @transition_done_block = Proc.new { yield }
            end
        end
    end

	##
	# Begin an animation from in (1) to out (0)
    def out(frames)
        if @total_frames == 0 and @value > 0.5
            @frame = 0
            @total_frames = frames
            @direction = OUT

            if block_given?
                @transition_done_block = Proc.new { yield }
            end
        end
    end

	##
	# Immediately transition to the in (1) state.
    def cut_in
        @value = 1.0
    end

	##
	# Immediately transition to the out (0) state.
    def cut_out
        @value = 0.0
    end

    attr_reader :value
end

