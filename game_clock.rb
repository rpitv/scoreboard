##
# A class representing the game clock.
#
# The time is stored with resolution to the nearest 1/10 second; this is the
# resolution of most scoreboard sync feeds we deal with. The clock also keeps 
# track of clock-related game rules, such as period and overtime lengths and 
# the number of periods in the game.
#
# Times are always internally represented in 1/10 second increments. Depending
# on context, this is either time from the beginning of the game, or time 
# remaining in the current period.
#
# The time is stored internally as a time from the beginning of the game. This
# is a useful form for penalty queue calculations. However, this means that
# changing the clock settings may change this value.
class GameClock
	##
	# Object representing clock-related game rules. Keeps track of period
	# length and number, as well as overtime length. Immutable once created.
	class Settings
		def initialize(period_length, overtime_length, num_periods)
			@period_length = period_length
			@num_periods = num_periods
			@overtime_length = overtime_length
		end

		attr_reader :period_length
		attr_reader :overtime_length
		attr_reader :num_periods
	end

	##
	# Initializes the game clock.
	def initialize
		# Clock value, in tenths of seconds
		@value = 0
		@last_start = nil		
		@period = 1
		
		# load defaults for hockey, these can be changed using load_settings
		@period_length = 20*60*10
		@overtime_length = 5*60*10
		@num_periods = 3
		
	end
	
	##
	# Returns the time at the end of the current period, 
	# relative to the start of the game.
	def period_end
		if @period <= @num_periods
			@period_length * @period
		else
			@period_length * @num_periods + @overtime_length * (@period - @num_periods)
		end
	end

	##
	# Load new settings into the clock. This maintains the current period, 
	# and the time remaining in the period. However, the tim
	def load_settings(preset)
		current_time_remaining = period_remaining
		STDERR.puts "current_time_remaining #{current_time_remaining}"
		@period_length = preset.period_length
		@overtime_length = preset.overtime_length
		@num_periods = preset.num_periods
		
		self.period_remaining = current_time_remaining
	end

	##
	# Return the total time elapsed from the beginning of the game. This time 
	# may jump forwards or backwards if the clock is adjusted or if the clock
	# settings have changed.
	def time_elapsed
		if @last_start
			elapsed = Time.now - @last_start
			# compute the elapsed time in tenths of seconds

			value_now = @value + (elapsed * 10).to_i

			# we won't go past the end of a period without an explicit restart
			if value_now > period_end
				value_now = period_end
				@value = value_now
				@last_start = nil
			end

			value_now
		else
			@value
		end
	end
	
	##
	# Advance the clock from the end of the period to the start of the
	# subsequent period.
	def period_advance
		pl = @period_length
		if @period+1 > @num_periods
			pl = @overtime_length
		end
		reset_time(pl, @period+1)
	end

	##
	# Reset the time, given the current period and the time 
	# remaining in that period.
	def reset_time(remaining, newperiod)
		if newperiod <= @num_periods
			# normal period
			@value = @period_length - remaining + @period_length*(newperiod-1)
		else
			# overtime
			@value = @overtime_length*(newperiod-@num_periods) - remaining + @period_length*@num_periods
		end
		if @last_start != nil
			@last_start = Time.now
		end
		@period = newperiod
	end

	attr_reader :period
	attr_reader :num_periods
	attr_reader :overtime_length

	##
	# Start running the clock.
	def start
		if @value == @period_end
			period_advance
		end

		if @last_start == nil
		   @last_start = Time.now 
		end
	end

	##
	# Stop running the clock.
	def stop
		@value = time_elapsed
		@last_start = nil
	end

	##
	# Return true if the clock is currently running.
	def running?
		if @last_start
			true
		else
			false
		end
	end

	##
	# Set the amount of time remaining in the current period.
	def period_remaining=(tenths)
		@value = period_end - tenths
		if running?
			@last_start = Time.now
		end
	end

	## 
	# Return the amount of time remaining in the current period.
	def period_remaining
		period_end - time_elapsed
	end

	##
	# Convert a string representation of time to a numeric value
	# in 1/10 second increments.
	def self.parse_clock(time_str)
		if time_str =~ /^((\d+)?:)?([0-5]\d(\.\d)?)$/
			seconds = $3.to_f
			minutes = $2.to_i
			minutes * 600 + (seconds * 10).to_i
		else
			fail "invalid clock value"
		end
	end
end



