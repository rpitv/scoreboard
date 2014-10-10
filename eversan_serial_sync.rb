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

require_relative './serial_sync_helper'

##
# Parser for Eversan serial data stream
#
# This class implements a parser for the serial data stream available from
# some Eversan scoreboard consoles. This data stream is transmitted as RS-422
# at a non-standard baud rate, so some external hardware is needed to make 
# the data useful. Some consoles have the RS-422 port installed but are
# missing the driver chip. For these units, jumper wires may be installed 
# in place of the driver chip, making the port into a TTL-level serial output.
# An AVR C program is provided in hw_interface/eversan.c; this program
# translates the Eversan serial output to standard 115200bps 8N1 serial
# when run on appropriate hardware.
#
# The Eversan protocol is fairly simple: a string of digits is periodically
# transmitted. These digits correspond to the digits displayed in various
# locations on the scoreboard. The Eversan scoreboard that this code was 
# developed for was a simple model, displaying time, period, and score,
# so that's all it's able to sync. Given the protocol's simplicity, it 
# shouldn't be too difficult to extend this to work with more complex models.
class EversanSerialSync

    include SerialSyncHelper

    ##
    # Initialize the Eversan serial stream parser.
    #
    # The parser will report its data to +app+. +options+ is a hash
    # of options, including:
    #
    # [+'port'+]        serial port to use
    def initialize(app, options)
        @app = app
        @stop_thread = false

        @sp = open_port(options, 115200)
        @sp.read_timeout = 500
        @thread = Thread.new { run_thread }
    end

    ##
    # Shut down the Eversan parser and free the serial port.
    def shutdown
        STDERR.puts "Eversan serial sync thread shutting down"
        @stop_thread = true
        @thread.join
        @sp.close
        STDERR.puts "Eversan serial sync thread terminated"
    end

    ##
    # Return the types of data that can be supplied by the parser.
    def capabilities
        ['clock', 'score']
    end

    ##
    # Parse the string of digits sent by the scoreboard, and send the data
    # to the app.
    def parse_digit_string(string)
        if string =~ /(\d{2})(\d{2})(\d)(\d{2})(\d{2})(\d)$/
            minutes = $1.to_i
            seconds = $2.to_i
            tenths = $3.to_i
            hscore = $4.to_i
            vscore = $5.to_i
            period = $6.to_i

            clock_value = minutes * 600 + seconds * 10 + tenths
            @app.sync_clock_time_remaining(clock_value)
            @app.sync_clock_period(period)

            @app.sync_hscore(hscore)
            @app.sync_vscore(vscore)
        end
    end

    ##
    # Read from the serial port, building a string of digits until a delimiter
    # is received. Then call +parse_digit_string+ to extract game data from
    # the received string.
    def run_thread
        begin
            STDERR.puts "Eversan serial sync thread starting"
            digit_string = ''
            digits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']
            while not @stop_thread
                ch = @sp.read(1)
                if ch
                    if digits.include?(ch)
                        digit_string += ch
                    else
                        parse_digit_string(digit_string, app)
                        digit_string = ''
                    end
                end
            end
        rescue Exception => e
            STDERR.puts e.inspect
        end
    end
end
