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
# Helper functions for accessing team data from within templates.
class TeamHelper
    attr_accessor :flag

    def initialize(team_data, clock)
        @team_data = team_data
        @clock = clock
    end

	##
	# Returns the team name.
    def name
        if @team_data['possession']
            "\xe2\x80\xa2" + @team_data['name']
        else
            @team_data['name']
        end
    end

	##
	# Returns the foreground color for representing this team.
    def fgcolor
        @team_data['fgcolor']
    end

	##
	# Returns the background color for representing this team.
    def bgcolor
        @team_data['bgcolor']
    end

	##
	# Returns a single color representing this team.
    def color
        bgcolor
    end
    
	##
	# Returns this team's current score.
    def score
        @team_data['score']
    end

	##
	# Returns the shots on goal for this team.
    def shots
        @team_data['shotsOnGoal']
    end

	##
	# Returns the number of timeouts remaining for this team.
    def timeouts
        @team_data['timeoutsLeft'].to_i
    end

	##
	# Returns a PenaltyHelper for accessing this team's penalty information.
    def penalties
        PenaltyHelper.new(@team_data['penalties'], @clock)
    end

	##
	# Returns the team's current numerical strength, in sports with 
	# time penalties.
    def strength
        penalties.strength
    end

	##
	# Returns true if this team is currently playing without a goaltender.
    def empty_net
        @team_data['emptyNet'] and @team_data['emptyNet'] != 'false'
    end

	##
	# Returns 1 if a narrower font should be used for this team name.
	# (FIXME: why is a bigger number a smaller width?)
    def fontWidth
        @team_data['fontWidth']
    end

	##
	# Returns status data associated with this team.
    def status
        @team_data['status']
    end

	##
	# Returns the color to be used for displaying the status field.
    def status_color
        if @team_data['statusColor'] && @team_data['statusColor'] != ''
            @team_data['statusColor']
        else
            'yellow'
        end
    end
end

##
# Helper functions for accessing penalty information from templates.
class PenaltyHelper
    def initialize(penalty_data, clock)
        @penalty_data = penalty_data
        @clock = clock
    end

	##
	# Return the team's current numerical strength.
    def strength
        s = 5
        @penalty_data['activeQueues'].each_with_index do |queue, i|
            qstart = @penalty_data['activeQueueStarts'][i].to_i
            qlength = queue_length(queue)
            if qlength > 0 and @clock.time_elapsed < qstart + qlength
                s -= 1
            end
        end

        s
    end

	##
	# Return the time (in tenths of a second) until this team's 
	# strength next changes.
    def time_to_strength_change
        result = -1

        @penalty_data['activeQueues'].each_with_index do |queue, i|
            time_remaining_on_queue = -1
            if queue.length > 0
                qstart = @penalty_data['activeQueueStarts'][i].to_i
                qlength = queue_length(queue)
                qend = qstart + qlength
                time_remaining_on_queue = qend - @clock.time_elapsed
            end

            if time_remaining_on_queue > 0
                if time_remaining_on_queue < result or result == -1
                    result = time_remaining_on_queue 
                end
            end
        end

        if result == -1
            result = 0
        end

        result
    end

protected
    def queue_length(q)
        time = 0
        q.each do |penalty|
            time += penalty['time'].to_i
        end
        
        time
    end

end

##
# Helper functions for accessing the announcement queue from templates.
class AnnounceHelper
    def initialize(announce_array)
        @announce = announce_array
        @announce_handled = false 
        @frames = 0
    end

	##
	# Return true if an announcement should be displayed.
    def is_up
        @announce.length > 0
    end

	##
	# Advance the queue to the next announcement.
    def next
        @frames = 0
        if @announce.length > 0
            @announce.shift
        else
            nil
        end
    end

	##
	# Return the announcement message that should be displayed.
    def message
        if @announce.length > 0
            @announce[0]
        else
            ''
        end
    end

	##
	# The number of frames that the announcement has been displayed for.
    attr_accessor :frames
end

##
# Helper functions for accessing general game-status data from templates.
class StatusHelper
    def initialize(app)
        @app = app
        @status_up = false
    end

	##
	# Return the status text.
    def text
        @app.status
    end

	##
	# Return the color for the status field.
    def color
        @app.status_color
    end

	##
	# Return true if the status field should be displayed, false otherwise.
    def is_up
        @app.status != '' 
    end
end

##
# Helper functions for accessing the game clock from templates.
class ClockHelper
    def initialize(clock)
        @clock = clock
    end

	##
	# Return game clock, formatted as a string.
    def time
        tenths = @clock.period_remaining

        seconds = tenths / 10
        tenths = tenths % 10

        minutes = seconds / 60
        seconds = seconds % 60

        if @clock.overtime_length == 0 && @clock.period > @clock.num_periods
            ''
        elsif minutes > 0
            format '%d:%02d', minutes, seconds
        else
            format ':%02d.%d', seconds, tenths
        end
    end

	##
	# Return a string representing the current period. This may be a numeral,
	# or OT, 2OT, 3OT etc., depending on the current clock settings.
    def period
        if @clock.period <= @clock.num_periods
            @clock.period.to_s
        elsif @clock.period == @clock.num_periods + 1
            'OT'
        else
            (@clock.period - @clock.num_periods).to_s + 'OT'
        end
    end
end

##
# Helper functions for formatting time values.
module TimeHelpers
	##
	# Format time value as string, truncating tenths.
    def format_time_without_tenths(time)
        seconds = time / 10
        minutes = seconds / 60
        seconds = seconds % 60

        format "%d:%02d", minutes, seconds
    end

	##
	# Format time value, rounding up to the next second.
    def format_time_without_tenths_round(time)
        seconds = (time + 9) / 10
        minutes = seconds / 60
        seconds = seconds % 60

        format "%d:%02d", minutes, seconds
    end

	##
	# Format time value as minutes:seconds when time is greater than
	# 1 minute, or :seconds.tenths when less than 1 minute.
    def format_time_with_tenths_conditional(time)
        tenths = time % 10
        seconds = time / 10
        
        minutes = seconds / 60
        seconds = seconds % 60

        if minutes == 0
            format ":%02d.%d", seconds, tenths
        else
            format "%d:%02d", minutes, seconds
        end
    end
end


##
# General-purpose functions made available in templates.
module ViewHelpers
    include TimeHelpers
end