# Copyright 2011 Exavideo LLC.
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


require 'patchbay'
require 'json'
require 'erubis'
require 'thin'
require 'serialport'

require_relative './daktronics_rtd_sync'
require_relative './eversan_serial_sync'
require_relative './scoreboard_helpers'
require_relative './game_clock'

class ScoreboardApp < Patchbay
    def initialize
        super

        @DATAFILE_NAME='scoreboard_state.dat'
        @clock = GameClock.new
        if File.exists?(@DATAFILE_NAME)
            begin
                @teams = load_data
            rescue
                STDERR.puts "failed to load config, initializing it..."
                @teams = initialize_team_config
                save_data
            end
        else
            @teams = initialize_team_config
            save_data
        end
        @announces = []
        @status = ''
        @status_color = 'white'
        @downdist = ''
        # use reasonable defaults here so we don't end up getting
        # 1st and <blank>
        @down = '1st'
        @distance = 10
        @autosync_clock = false
        @autosync_score = false
        @autosync_other = false
        @sync_thread = nil
    end

    attr_reader :status, :status_color

    def initialize_team_config
        # construct a JSON-ish data structure
        [
            {
                # Team name
                'name' => 'UNION',
                # color value to be used for team name display.
                'fgcolor' => '#ffffff',
                'bgcolor' => '#800000',
                # number of points scored by this team
                'score' => 0,

                # shots on goal count (for hockey)
                'shotsOnGoal' => 0,

                # number 
                # timeouts "left" don't include the one currently in use, if any
                'timeoutsLeft' => 3,
                'timeoutNowInUse' => false,

                # penalty queues (for hockey)
                # A penalty consists of player, penalty, length.
                'penalties' => {
                    # Only two players may serve penalties at a time. These arrays
                    # represent the "stacks" of penalties thus formed.
                    'activeQueues' => [ [], [] ],
                    
                    # These numbers represent the start time of each penalty "stack".
                    # 0 = start of game.
                    'activeQueueStarts' => [ 0, 0 ]
                },

                # roster autocompletion list
                'autocompletePlayers' => [
                ],

                'emptyNet' => false,
                'possession' => false,
                'fontWidth' => 0,
                'status' => '',
                'statusColor' => ''
            },
            {
                'name' => 'RPI',
                'fgcolor' => '#ffffff',
                'bgcolor' => '#d40000',
                'score' => 0,
                'shotsOnGoal' => 0,
                'timeoutsLeft' => 3,
                'timeoutNowInUse' => false,
                'penalties' => {
                    'announcedQueue' => [],
                    'activeQueues' => [ [], [] ],
                    'activeQueueStarts' => [ 0, 0 ]
                },
                'autocompletePlayers' => [
                ],
                'emptyNet' => false,
                'possession' => false,
                'fontWidth' => 0,
                'status' => '',
                'statusColor' => ''
            }
        ]
    end

    put '/team/:id' do
        id = params[:id].to_i

        if id == 0 or id == 1
            Thread.exclusive { @teams[id].merge!(incoming_json) }
            save_data
            render :json => ''
        else
            render :json => '', :status => 404
        end
    end

    get '/team/:id' do
        id = params[:id].to_i
        if id == 0 or id == 1
            render :json => @teams[id].to_json
        else
            render :json => '', :status => 404
        end
    end

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

    put '/clock/running' do
        if incoming_json['run']
            @clock.start
        else
            @clock.stop
        end

        render :json => ''
    end

    put '/clock/toggle' do
        if @clock.running?
            @clock.stop
        else
            @clock.start
        end

        render :json => ''
    end

    put '/clock/adjust' do
        time_offset = incoming_json['time'].to_i / 100
        time = @clock.period_remaining + time_offset;
        time = 0 if time < 0
        @clock.reset_time(time, @clock.period)

        render :json => ''
    end

    put '/clock/advance' do
        @clock.period_advance

        render :json => ''
    end

    get '/clock' do
        render :json => {
            'running' => @clock.running?,
            'period_remaining' => @clock.period_remaining,
            'period' => @clock.period,
            'time_elapsed' => @clock.time_elapsed
        }.to_json
    end

    get '/autosync' do
        render :json => {
            'clock' => @autosync_clock,
            'score' => @autosync_score,
            'other' => @autosync_other
        }.to_json
    end

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

    post '/announce' do
        if incoming_json.has_key? 'messages'
            @announces.concat(incoming_json['messages'])
        else
            @announces << incoming_json['message']
        end

        render :json => ''
    end

    put '/status' do
        @status = incoming_json['message']
        @status_color = incoming_json['color'] || 'white'
        render :json => ''
    end
    
    put '/scoreboardSettings' do
        @gameSettings = incoming_json
        STDERR.puts @gameSettings.inspect
        
        number_of_periods = @gameSettings['periodQty'].to_i
        begin
            period_length = GameClock.parse_clock(@gameSettings['periodLength'])
            overtime_length = GameClock.parse_clock(@gameSettings['otPeriodLength'])
        rescue
            render :status => 400
            return
        end
        
        new_clock_settings = GameClock::Settings.new(period_length, overtime_length, number_of_periods)
        @clock.load_settings(new_clock_settings)
        
        STDERR.puts "number_of_periods=#{number_of_periods}"
        render :json => ''
    end
    
    put '/downdist' do 
        @downdist = incoming_json['message']
        @status = @downdist
        @status_color = (@status == 'FLAG') ? 'yellow' : 'white'
        STDERR.puts @downdist
        render :json => ''
    end

    put '/view_command' do
        command_queue << incoming_json
        render :json => ''
    end

    get '/preview' do
        render :svg => @view.render_template
    end

    get '/view_status' do
        render :json => { :is_up => @view.is_up? }.to_json
    end

	##
	# Set sync feed parsing mode.
    put '/sync_mode' do
		# we will match the requested mode against this list
        allowed_sync_types = {
            'DaktronicsRtdSync' => DaktronicsRtdSync,
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
        @view.away_team = TeamHelper.new(@teams[0], @clock)
        @view.home_team = TeamHelper.new(@teams[1], @clock)
        @view.clock = ClockHelper.new(@clock)
        @view.command_queue = command_queue
    end

	##
	# Get the current template.
    def view
        @view
    end

    self.files_dir = 'public_html'

    attr_reader :clock, :autosync_clock, :autosync_score, :autosync_other

	##
	# Set the current home team score. Typically used by sync feed parsers.
    def sync_hscore(hscore)
        if @sync_score
            if hscore > @teams[1]['score'].to_i
                command_queue << { "goal_scored_by" => "/teams/1" }
            end
            @teams[1]['score'] = hscore
        end
    end

	##
	# Set the current guest team score. Typically used by sync feed parsers.
    def sync_vscore(vscore)
        if @sync_score
            if vscore > @teams[0]['score'].to_i
                command_queue << { "goal_scored_by" => "/teams/0" }
            end

            @teams[0]['score'] = vscore
        end
    end

	##
	# Set the current down (football). Typically used by sync feed parsers.
    def sync_down(down)
        if @autosync_other
            @down = down
            @downdist = "#{@down} & #{@distance}"
        end
    end

	##
	# Set the current distance to go (football). 
	# Typically used by sync feed parsers.
    def sync_distance(distance)
        if @autosync_other
            @distance = distance
            @downdist = "#{@down} & #{@distance}"
        end
    end

	##
	# Set the current time remaining. Typically used by sync feed parsers.
    def sync_clock_time_remaining(tenths)
        if @autosync_clock
            @clock.period_remaining = tenths
        end
    end

	##
	# Set the current time period. Typically used by sync feed parsers.
    def sync_clock_period(period)
        if @autosync_clock
            @clock.reset_time(@clock.period_remaining, period)
        end
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
	# Load team state from file.
	# This simply reads the file and returns the data. It does not 
	# alter the current state.
    def load_data
        File.open(@DATAFILE_NAME, 'r') do |f|
            JSON.parse f.read
        end
    end

	##
	# Get the view command queue.
    def command_queue
        @command_queue ||= []
        @command_queue
    end
end


class LinearAnimation
    IN = 0
    OUT = 1
    def initialize
        @value = 0
        @total_frames = 0
        @frame = 0
        @direction = IN
        @transition_done_block = nil
    end

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

    def cut_in
        @value = 1.0
    end

    def cut_out
        @value = 0.0
    end

    attr_reader :value
end

class ScoreboardView
    include ViewHelpers

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

    def render
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

        @animations.each do |ani|
            ani.frame_advance
        end

        announce.frames += 1

        if announce.frames == 90
            announce.next
        end

        render_template
    end

    def render_template
        @template.result(binding)
    end

    def is_up?
        @global_dissolve.value > 0.01
    end

    def galpha
        (255 * @global_dissolve.value).to_i
    end

    def announce_text_opacity
        @announce_text_dissolve.value
    end

    def away_blink_opacity
        @away_goal_flasher.value
    end

    def home_blink_opacity
        @home_goal_flasher.value
    end

    attr_accessor :announce, :status, :away_team, :home_team, :clock
    attr_accessor :command_queue
end

app = ScoreboardApp.new
app.view = ScoreboardView.new('assets/rpitv_scoreboard.svg.erb')
Thin::Logging.silent = true
Thread.new { app.run(:Host => '::1', :Port => 3002) }

def start_drycontact_sync_thread(app)
    # The dry contact is connected to CTS and DTR.
    # CTS is pulled to RTS by a 10k resistor. 
    # So CTS assumes the state of RTS when the contact
    # is open, and the state of DTR when the contact
    # is closed. The switch on a Daktronics AllSport
    # 5000 console closes when the clock is stopped.
    # We will set up RTS and DTR so that we get
    # a logic 1 when the clock is to run and a 0
    # when it is stopped.
    Thread.new do
        sp = SerialPort.new('/dev/ttyS0', 9600)
        sp.rts = 1
        sp.dtr = 0
        last_cts = 1

        while true
            if sp.cts != last_cts
                if app.autosync_clock
                    if sp.cts == 1
                        # start the clock
                        app.clock.start
                    else
                        # stop the clock
                        app.clock.stop
                    end
                end
                # remember what the last state was
                last_cts = sp.cts
                # delay briefly to allow signal to debounce
                sleep 0.1
            end
            sleep 0.01
        end
    end
end

dirty_level = 1

while true
    # prepare next SVG frame
    data = app.view.render

    # build header with data length and global alpha
    header = [ data.length, app.view.galpha, dirty_level ].pack('LCC')

    # wait for handshake byte from other end
    if STDIN.read(1).nil?
        break
    end

    # send SVG data with header
    STDOUT.write(header)
    STDOUT.write(data)
end
