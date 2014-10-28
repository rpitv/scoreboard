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

##
# Class representing all team state information.
class Team
	def initialize(name, fgcolor, bgcolor)
		@name = name
		@fgcolor = fgcolor
		@bgcolor = bgcolor
		@dataSerial = 0

		set_defaults
	end
	
	def set_defaults
		@dataSerial += 1
		@score = 0
		@shotsOnGoal = 0

		@timeoutsLeft = 3
		@timeoutNowInUse = false
		@penalties = {
			'activeQueues' => [ [], [] ],
			'activeQueueStarts' => [0, 0],
		}
		@autocompletePlayers = []
		@emptyNet = false
		@possession = false
		@fontWidth = 0
		@status = ''
		@statusColor = ''
	end

	def to_json(state=nil, depth=0)
		json_hash = {}
		instance_variables.each do |varname|
			json_hash[varname[1..-1] ] = instance_variable_get(varname)
		end

		json_hash.to_json
	end

	def merge!(hash)
		hash.each_pair do |key, value|
			if respond_to? "#{key}="
				send "#{key}=", value
			else
				key = "@" + key
				instance_variable_set key, value
			end
		end
	end


	attr_accessor :name, :fgcolor, :bgcolor, :dataSerial
	attr_accessor :score, :shotsOnGoal, :timeoutsLeft, :timeoutNowInUse
	attr_accessor :penalties, :autocompletePlayers, :emptyNet
	attr_accessor :possession, :fontWidth, :status, :statusColor

	# override the default accessors for these and force them to be numeric
	def score=(score)
		@score = score.to_i
	end

	def shotsOnGoal=(shots)
		@shotsOnGoal = shots.to_i
	end
end
