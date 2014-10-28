# Copyright 2014 Exavideo LLC.
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

class PlayClock
	##
	# Initialize the play clock.
	def initialize
		@tenths = 0
	end

	##
	# Return the amount of time remaining, in tenths of a second.
	def time_remaining
		@tenths
	end

	##
	# Set the amount of time remaining, in tenths of a second.
	def time_remaining=(tenths)
		@tenths = tenths
	end

	def to_json(*args)
		{
			'time_remaining' => @tenths
		}.to_json
	end
end
