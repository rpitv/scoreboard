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

require_relative './daktronics_rtd_sync'
require_relative './eversan_serial_sync'
require_relative './drycontact_sync'
require_relative './scoreboard_helpers'
require_relative './game_clock'
require_relative './play_clock'
require_relative './team'
require_relative './period_descriptor'

##
# The scoreboard Patchbay application.
# Responsible for all HTTP request handling.
# Also serves as the location for game state data.
class ScoreboardApp < Patchbay
	def initialize
		super

		# initialize game clock
		@clock = GameClock.new
		@play_clock = PlayClock.new

		# load initial team state
		@DATAFILE_NAME='scoreboard_state.dat'
		initialize_team_config
		if File.exists?(@DATAFILE_NAME)
			# load state from file if possible
			begin
				load_data
			rescue
				STDERR.puts "failed to load config, wiping it..."
			end
		end
		save_data

		# initialize global game state items
		@announces = []
		@status = ''
		@status_color = 'white'
		@status_use_play_clock = false

		@game_state = initialize_game_state

		@autosync_clock = false
		@autosync_score = false
		@autosync_other = false
		@sync_thread = nil
		@sport_settings = { }
	end

	attr_reader :status, :status_color, :status_use_play_clock

	##
	# Create default game state.
	def initialize_game_state
		{
			'down' => '1st',
			'distanceToGo' => 10,
			'ballPosition' => 50
		}
	end

	##
	# Create a default team configuration.
	def initialize_team_config
		@teams = [
			Team.new('UNION', '#ffffff', '#800000'),
			Team.new('RPI', '#ffffff', '#d40000')
		]
	end

	##
	# Get all the data in one request.
	get '/data.json' do
		render :json => {
			'home' => @teams[1],
			'away' => @teams[0],
			'clock' => @clock,
			'gameState' => @game_state,
			# this provides a string that describes the current period
			'periodDescription' => PeriodDescriptor.new(
				@clock, @teams[0], @teams[1], @sport_settings
			)
		}.to_json
	end

	##
	# PUT to game state. Used by UI to upload game state data.
	put '/gameState' do
		@game_state.merge!(incoming_json)
		render :json => @game_state.to_json
	end

	get '/gameState' do
		render :json => @game_state.to_json
	end

	##
	# PUT request to a team. Used by UI to upload team state data.
	put '/team/:id' do
		id = params[:id].to_i

		if id == 0 or id == 1
			if @teams[id].dataSerial < incoming_json['dataSerial']
				# the incoming data is based on the latest we have, so accept
				STDERR.puts "accepting request"
				Thread.exclusive {
					@teams[id].merge!(incoming_json)
				}
				save_data
				render :json => @teams[id].to_json
			else
				# the incoming data is based on outdated data pulled from us,
				# so we'll reject it.
				STDERR.puts "erroring out the request: #{@teams[id].to_json}"
				render :json => @teams[id].to_json, :status => 409
			end
		else
			STDERR.puts "invalid request"
			render :json => '', :status => 404
		end
	end

	##
	# GET request for team state data.
	get '/team/:id' do
		id = params[:id].to_i
		if id == 0 or id == 1
			render :json => @teams[id].to_json
		else
			render :json => '', :status => 404
		end
	end

	##
	# PUT request that resets team states to default.
	put '/reset_teams' do
		@teams[0].set_defaults
		@teams[1].set_defaults
		render :json => {}.to_json
	end

	##
	# PUT to clock state. Accepts a JSON object with time_str and period
	# properties and sets game clock.
	put '/clock' do
		time_str = incoming_json['time_str']
		period = incoming_json['period'].to_i
		period = @clock.period if period <= 0
		time = GameClock.parse_clock(time_str)
		if (time)
			@clock.reset_time(time, period)
		end
		render :json => ''
	end

	##
	# Start or stop the clock. Accepts a JSON object with a run property.
	# If run property is true, then starts the clock. Otherwise, stops it.
	put '/clock/running' do
		if incoming_json['run']
			@clock.start
		else
			@clock.stop
		end

		render :json => ''
	end

	##
	# If clock is stopped, start it. If it's running, stop it.
	put '/clock/toggle' do
		if @clock.running?
			@clock.stop
		else
			@clock.start
		end

		render :json => ''
	end

	##
	# Adjust the clock by the given offset.
	put '/clock/adjust' do
		time_offset = incoming_json['time'].to_i / 100
		time = @clock.period_remaining + time_offset;
		time = 0 if time < 0
		@clock.reset_time(time, @clock.period)

		render :json => ''
	end

	##
	# Advance clock from end of one period to start of next period.
	put '/clock/advance' do
		@clock.period_advance
		render :json => ''
	end

	##
	# Get current clock data.
	# Returns a JSON object with the following properties.
	#
	# [+running+]	True if the clock is running, false otherwise.
	# [+period_remaining+]	Time remaining in period in 1/10 sec units.
	# [+period+]	Current period number.
	# [+time_elapsed]	Amount of time elapsed since start of game.
	get '/clock' do
		render :json => @clock.to_json
	end

	##
	# Get current play clock.
	# Returns a JSON object with the following properties.
	#
	# [+time_remaining+]	Time remaining on play clock in 1/10 sec units.
	get '/play_clock' do
		render :json => @play_clock.to_json
	end

	##
	# Get all clocks.
	# Returns a JSON object with the following properties.
	#
	# [+game_clock+]	Game clock, with all properties returned by /clock.
	# [+play_clock+]	Play clock, with all properties returned by /play_clock.
	get '/clocks' do
		render :json => {
			'game_clock' => @clock,
			'play_clock' => @play_clock
		}.to_json
	end

	##
	# Get current autosync settings.
	# Returns a JSON object with the following properties.
	#
	# [+clock+]		True if clock data is being synchronized to external
	#				data feed.
	# [+score+]		As above, for score data.
	# [+other+]		As above, for all other types of data.
	get '/autosync' do
		render :json => {
			'clock' => @autosync_clock,
			'score' => @autosync_score,
			'other' => @autosync_other
		}.to_json
	end

	##
	# Set autosync settings.
	# Accepts a JSON object with the following properties.
	#
	# [+clock+]		True if clock data should be synchronized to external
	#				data feed.
	# [+score+]		As above, for score data.
	# [+other+]		As above, for all other types of data.
	put '/autosync' do
		@autosync_clock = incoming_json['clock']
		@autosync_score = incoming_json['score']
		@autosync_other = incoming_json['other']

		render :json => {
			'clock' => @autosync_clock,
			'score' => @autosync_score,
			'other' => @autosync_other
		}.to_json
	end

	##
	# Add item to announce queue.
	# Accepts a JSON object with exactly one of the following properties:
	#
	# [+messages+]	An array of string messages to be added to the queue.
	# [+message+]	A string message to be added to the queue.
	#
	# If both properties are included in the JSON object, +message+ will
	# be ignored.
	post '/announce' do
		if incoming_json.has_key? 'messages'
			@announces.concat(incoming_json['messages'])
		else
			@announces << incoming_json['message']
		end

		render :json => ''
	end

	##
	# Set game status string.
	# Accepts a JSON object with a +message+ property.
	put '/status' do
		@status = incoming_json['message']
		@status_color = incoming_json['color'] || 'white'
		@status_use_play_clock = incoming_json['enablePlayClock'] || false
		render :json => ''
	end

	##
	# Set scoreboard settings.
	# Accepts a JSON object of the format found in
	# +public_html/js/sports.json+
	put '/scoreboardSettings' do
		@sport_settings = incoming_json
		STDERR.puts @sport_settings.inspect

		number_of_periods = @sport_settings['periodQty'].to_i
		number_of_overtimes = @sport_settings['otPeriodQty']
		if number_of_overtimes =~ /^\d+/
			number_of_overtimes = number_of_overtimes.to_i
		else
			# non-numeric number of overtimes = infinite overtime
			number_of_overtimes = 9999
		end

		begin
			period_length = GameClock.parse_clock(@sport_settings['periodLength'])
			overtime_length = GameClock.parse_clock(@sport_settings['otPeriodLength'])
		rescue
			render :status => 400
			return
		end

		new_clock_settings = GameClock::Settings.new(
			period_length, overtime_length, number_of_periods, number_of_overtimes
		)
		@clock.load_settings(new_clock_settings)

		STDERR.puts "number_of_periods=#{number_of_periods}"
		render :json => ''
	end

	##
	# Add a command to the end of the view command queue.
	# The JSON object passed is added verbatim to the queue.
	put '/view_command' do
		command_queue << incoming_json
		render :json => ''
	end

	##
	# Get SVG image of current scoreboard
	get '/preview' do
		render :svg => @view.render_template
	end

	##
	# Get current view status.
	# This returns a JSON object with the following properties:
	#
	# [+is_up+]		True if the scoreboard is currently being displayed.
	get '/view_status' do
		render :json => { :is_up => @view.is_up? }.to_json
	end

	##
	# Set sync feed parsing mode.
	put '/sync_mode' do
		# we will match the requested mode against this list
		allowed_sync_types = {
			'DaktronicsRtdSync' => DaktronicsRtdSync,
			'DrycontactSync' => DrycontactSync,
			'EversanSerialSync' => EversanSerialSync,
		}

		msg = incoming_json
		if msg.has_key?('type')
			# shutdown any existing sync thread
			if @sync_thread
				@sync_thread.shutdown
				@sync_thread = nil
			end

			# create new sync thread from parameters
			type = allowed_sync_types[msg['type']] || nil
			if type
				# create a new thread of the given type
				@sync_thread = type.new(self, msg)
				render :json => incoming_json
			elsif msg['type'] == 'None'
				# nothing was selected, so don't create new thread
				render :json => incoming_json
			else
				# requested type was unavailable
				render :status => 400
			end
		else
			render :status => 400
		end
	end

	##
	# Set the template to be used for rendering the scoreboard.
	def view=(view)
		@view = view
		@view.announce = AnnounceHelper.new(@announces)
		@view.status = StatusHelper.new(self)
		@view.away_team = TeamHelper.new(self, @teams[0], @clock)
		@view.home_team = TeamHelper.new(self, @teams[1], @clock)
		@view.penalty_state = PenaltyStringHelper.new(
			self, @view.home_team, @view.away_team
		)
		@view.clock = ClockHelper.new(@clock)
		@view.play_clock = PlayClockHelper.new(@play_clock)
		@view.command_queue = command_queue
	end

	##
	# Get the current template.
	def view
		@view
	end

	self.files_dir = 'public_html'

	attr_reader :clock, :autosync_clock, :autosync_score, :autosync_other
	attr_reader :sport_settings

	##
	# Set the current home team score, if autosync is enabled.
	# Typically used by sync feed parsers.
	def sync_hscore(hscore)
		if @autosync_score
			if hscore > @teams[1].score.to_i
				command_queue << { "goal_scored_by" => "/teams/1" }
			end

			# don't update dataSerial unless something actually changes
			if hscore != @teams[1].score.to_i
				@teams[1].score = hscore
				@teams[1].dataSerial += 1
			end
		end
	end

	##
	# Set the current guest team score, if autosync is enabled.
	# Typically used by sync feed parsers.
	def sync_vscore(vscore)
		if @autosync_score
			if vscore > @teams[0].score.to_i
				command_queue << { "goal_scored_by" => "/teams/0" }
			end

			if vscore != @teams[0].score.to_i
				@teams[0].score = vscore
				@teams[0].dataSerial += 1
			end
		end
	end

	##
	# Set the current home team shots on goal, if autosync is enabled.
	# Typically used by sync feed parsers.
	def sync_hshots(hshots)
		if @autosync_other
			@teams[1].shotsOnGoal = hshots
			@teams[1].dataSerial += 1
		end
	end

	##
	# Set the current guest team shots on goal, if autosync is enabled.
	# Typically used by sync feed parsers.
	def sync_vshots(vshots)
		if @autosync_other
			@teams[0].shotsOnGoal = vshots
			@teams[0].dataSerial += 1
		end
	end

	##
	# Set the current down (football), if autosync is enabled.
	# Typically used by sync feed parsers.
	def sync_down(down)
		if @autosync_other
			@game_state['down'] = down
		end
	end

	##
	# Set the current distance to go (football) if autosync is enabled.
	# Typically used by sync feed parsers.
	def sync_distance(distance)
		if @autosync_other
			@game_state['distanceToGo'] = distance
		end
	end

	##
	# Set the ball position (for football) if autosync is enabled.
	# Typically used by sync feed parsers.
	def sync_ball_position(ball_pos)
		if @autosync_other
			@game_state['ballPosition'] = ball_pos
		end
	end

	##
	# Set the current time remaining if autosync is enabled.
	# Typically used by sync feed parsers.
	def sync_clock_time_remaining(tenths)
		if @autosync_clock
			@clock.period_remaining = tenths
		end
	end

	##
	# Set the current time period if autosync is enabled.
	# Typically used by sync feed parsers.
	def sync_clock_period(period)
		if @autosync_clock
			@clock.reset_time(@clock.period_remaining, period)
		end
	end

	##
	# Start the clock, if autosync is enabled.
	# Typically used by sync feed parsers.
	def sync_clock_start
		if @autosync_clock
			@clock.start
		end
	end

	##
	# Stop the clock, if autosync is enabled.
	# Typically used by sync feed parsers.
	def sync_clock_stop
		if @autosync_clock
			@clock.stop
		end
	end

	def sync_play_clock(tenths)
		if @autosync_clock
			@play_clock.time_remaining = tenths
		end
	end

	def sync_play_clock_seconds(seconds)
		if @autosync_clock
			@play_clock.time_remaining = seconds * 10
		end
	end

	##
	# Set possession to the given team (0 or 1; nil clears both teams)
	def sync_possession(team, state)
		if @autosync_other
			if team
				@teams[team].possession = state
				@teams[team].dataSerial += 1
				if state
					@teams[1-team].possession = false
					@teams[1-team].dataSerial += 1
				end
			else
				@teams[0]['possession'] = false
				@teams[1]['possession'] = false
				@teams[0].dataSerial += 1
				@teams[1].dataSerial += 1
			end
		end
	end

	##
	# Sync penalty data for a given team.
	# penalty_data needs to provide methods strength and
	# time_to_strength_change.
	def sync_penalties(team, penalty_data)
		@teams[team].syncedPenalties = penalty_data
		# note we don't need to update dataSerial because
		# syncedPenalties don't get serialized to JSON
	end

protected
	##
	# Parse HTTP request body JSON into a Ruby object
	def incoming_json
		unless params[:incoming_json]
			inp = environment['rack.input']
			inp.rewind
			params[:incoming_json] = JSON.parse inp.read
		end

		params[:incoming_json]
	end

	##
	# Save current team states to file. This does not yet save the clock
	# or any other settings.
	def save_data
		File.open(@DATAFILE_NAME, 'w') do |f|
			f.write @teams.to_json
		end
	end

	##
	# Load team state from file and merge with default state.
	def load_data
		json = File.open(@DATAFILE_NAME, 'r') do |f|
			JSON.parse f.read
		end

		@teams[0].merge!(json[0])
		@teams[1].merge!(json[1])
	end

	##
	# Get the view command queue.
	def command_queue
		@command_queue ||= []
		@command_queue
	end
end


