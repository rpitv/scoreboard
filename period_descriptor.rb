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
# Encapsulate the logic for obtaining text descriptions of periods in a game.
class PeriodDescriptor
	def initialize(clock, home_team, guest_team, rules)
		@clock = clock
		@home_team = home_team
		@guest_team = guest_team
		@rules = rules
	end

	##
	# Return true if the total number of periods can be evenly divided by two
	# (i.e. there is a period break that it makes sense to call halftime)
	def has_halftime
		@clock.num_periods % 2 == 0
	end

	##
	# Return a string describing the end of the period.
	def end_description_string
		if (@clock.period < @clock.num_periods)
			if (has_halftime and @clock.period == @clock.num_periods / 2)
				"Halftime"
			else
				"End of #{ordinal(@clock.period)} #{period_type}"
			end
		elsif @home_team.score != @guest_team.score
			"Final Score"
		elsif @clock.period == @clock.num_periods + @clock.num_overtimes
			"Final Score (OT)"
		elsif @clock.period == @clock.num_periods
			"End of Regulation"
		else
			overtime_number = @clock.period - @clock.num_periods
			"End of #{ordinal(overtime_number)} Overtime"
		end
	end

	##
	# Return a string describing the current period.
	def description_string
		if @clock.period <= @clock.num_periods
			"#{ordinal(@clock.period)} #{period_type}"
		elsif @clock.num_overtimes == 1
			"Overtime"
		else
			overtime_number = @clock.period - @clock.num_periods
			"#{ordinal(overtime_number)} Overtime"
		end
	end

	##
	# Return the period type.
	def period_type
		if @clock.num_periods == 2
			"Half"
		elsif @clock.num_periods == 4
			"Quarter"
		else
			"Period"
		end
	end

	def to_json(*args)
		{
			'current_period' => description_string,
			'end_of_period' => end_description_string
		}.to_json
	end

protected
	##
	# Return a string representation of an ordinal number.
	def ordinal(i)
		if (11..13).include? i
			"#{i}th"
		elsif i % 10 == 1
			"#{i}st"
		elsif i % 10 == 2
			"#{i}nd"
		elsif i % 10 == 3
			"#{i}rd"
		else
			"#{i}th"
		end
	end
end	
