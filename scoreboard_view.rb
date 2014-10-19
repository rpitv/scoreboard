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

require_relative './linear_animation'
require_relative './scoreboard_helpers'

##
# A template used to render the scoreboard data to SVG images.
class ScoreboardView
	include ViewHelpers

	##
	# Creates a new view using the given SVG erb template.
	def initialize(filename)
		@template = Erubis::PI::Eruby.new(File.read(filename))

		@away_goal_flasher = LinearAnimation.new
		@home_goal_flasher = LinearAnimation.new
		@announce_text_dissolve = LinearAnimation.new
		@global_dissolve = LinearAnimation.new

		@global_dissolve.cut_in # hack
		@announce_text_dissolve.cut_in

		@animations = [ @away_goal_flasher, @home_goal_flasher, 
			@announce_text_dissolve, @global_dissolve ]
	end

	##
	# Starts a goal-flash animation on the given flasher.
	def goal_flash(flasher)
		n_frames = 15
		
		# chain together a bunch of transitions
		flasher.in(n_frames) { 
			flasher.out(n_frames) {
				flasher.in(n_frames) {
					flasher.out(n_frames) {
						flasher.in(n_frames) {
							flasher.out(n_frames) 
						}
					}
				}
			}
		}
	end

	##
	# Renders an SVG image using the current scoreboard data.
	def render
		# Process view commands from the queue.
		while command_queue.length > 0
			cmd = command_queue.shift
			if (cmd.has_key? 'down')
				@global_dissolve.out(15)
			elsif (cmd.has_key? 'up')
				@global_dissolve.in(15)
			elsif (cmd.has_key? 'announce_next')
				@announce_text_dissolve.out(10) {
					announce.next
					@announce_text_dissolve.in(10)
				}
			elsif (cmd.has_key? 'goal_scored_by')
				if cmd['goal_scored_by'] =~ /\/0$/
					goal_flash(@away_goal_flasher)
				elsif cmd['goal_scored_by'] =~ /\/1$/
					goal_flash(@home_goal_flasher)
				end
			end
		end

		# Advance all animations.
		@animations.each do |ani|
			ani.frame_advance
		end

		# Advance the announce queue periodically.
		if announce.is_up
			announce.frames += 1

			if announce.frames == 90
				announce.next
			end
		else
			announce.frames = 0
		end

		# Process the erb template.
		render_template
	end

	##
	# Returns the result of running the erb template.
	def render_template
		@template.result(binding)
	end

	##
	# Returns true if the global dissolve value is nonzero - i.e.
	# the scoreboard is currently up on screen.
	def is_up?
		@global_dissolve.value > 0.01
	end

	##
	# Returns the global alpha (dissolve) value.
	def galpha
		(255 * @global_dissolve.value).to_i
	end

	##
	# Return the opacity to be used for the announce text.
	def announce_text_opacity
		@announce_text_dissolve.value
	end

	##
	# Return the opacity for the away team goal flasher layer.
	def away_blink_opacity
		@away_goal_flasher.value
	end

	##
	# Return the opacity for the home team goal flasher layer.
	def home_blink_opacity
		@home_goal_flasher.value
	end

	attr_accessor :announce, :status, :away_team, :home_team, :clock
	attr_accessor :penalty_state, :command_queue
end
