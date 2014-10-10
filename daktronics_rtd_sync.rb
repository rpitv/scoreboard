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
# This class implements a parser for the Daktronics RTD protocol.
#
# The RTD protocol transmits various data items in a packetized format.
# Each packet begins with a 0x16 byte and ends with a 2-byte checksum
# followed by a 0x17 byte. This data is transmitted serially, 19200 bps
# 8N1, over RS232 and current loop interfaces from the Daktronics console.
# The checksum is simply the modulo-256 sum of all bytes, starting with the 
# first byte following the 0x16 byte and ending with the last byte before
# the checksum itself. The checksum is transmitted as two ASCII hexadecimal
# digits instead of a single byte.
# 
# Bytes 9 through 18 of the payload are a string that uniquely identifies
# the data item being transmitted. This is typically 00421xxxxx
# where xxxxx is the "item number" listed in the All Sport 5000 Series
# Enhanced RTD Reference Manual published by Daktronics Inc., MINUS ONE.
# This document, Daktronics document number ED12483, may be found at 
# http://www.daktronics.com/Web%20Documents/Customer-Service-Manuals/ED-12483.pdf
#
# This parser operates in three stages. The top level breaks the serial stream
# apart into packets, which are processed by process_dak_packet(). 
# process_dak_packet() validates the checksum, then looks for a 
# +packet_xxxxxxxxxx_ method, where xxxxxxxxxx is the data item identifier 
# string from bytes 9-18 of the packet. These functions are responsible for 
# interpreting the packet payload and calling the appropriate sync function
# on app.
class DaktronicsRtdSync

    include SerialSyncHelper

    ##
    # Initialize the RTD parser, which will report data back to +app+.
    #
    # +options+ is a hash of options including the following:
    # [+'port'+']       serial port to use
    def initialize(app, options)
        @app = app
        @stop_thread = false

        @sp = open_port(options, 19200)
        @sp.read_timeout = 500
        @thread = Thread.new { run_thread }
    end

    ##
    # Shut down the RTD parser and free the serial port
    def shutdown
        STDERR.puts "Daktronics RTD sync thread shutting down"
        @stop_thread = true
        @thread.join
        @sp.close
        STDERR.puts "Daktronics RTD sync thread terminated"
    end

    ##
    # Return the types of data supplied by the parser
    def capabilities
        ['clock', 'score', 'downdist', 'playclock']
    end

    ##
    # Parse main game clock (item 1)
    def packet_0042100000(payload)
        tenths = -1

        # try to parse payload as time in minutes:seconds
        # or seconds.tenths
        if (payload =~ /^(([ \d]\d):(\d\d))/)
                tenths = $2.to_i * 600 + $3.to_i * 10
        elsif (payload =~ /^(([ \d]\d).(\d))/)
                tenths = $2.to_i * 10 + $3.to_i
        else
                puts "0042100000: don't understand clock format"
        end

        STDERR.puts "tenths: #{tenths}"

        if tenths >= 0 
            app.sync_clock_time_remaining(tenths)
        end
    end

    ##
    # Parse home team score (item 108)
    def packet_0042100107(payload)
        if (payload =~ /^\s*(\d+)$/)
            home_score = $1.to_i  
            @app.sync_hscore(home_score)
        end
    end

    ##
    # Parse visiting team score (item 112)
    def packet_0042100111(payload)
        if (payload =~ /^\s*(\d+)$/)
            guest_score = $1.to_i  
            @app.sync_vscore(guest_score)
        end
    end
    
    ##
    # Parse football down (item 222)
    def packet_0042100221(payload)
        if (payload =~ /(1st|2nd|3rd|4th)/i)
	    STDERR.puts "#{$1} down"
            @app.sync_down($1) 
        end
    end
    
    ##
    # Parse yards to go (item 225)
    def packet_0042100224(payload)
        if (payload =~ /(\d+)/)
	    STDERR.puts "#{$1} to go"
            @app.sync_distance($1.to_i)
        end
    end

    ##
    # Parse play clock (item 201)
    #
    # Daktronics documentation is not quite correct for this item.
    # The documentation indicates that the play clock is in mm:ss
    # format; however, the actual data transmitted appears to be
    # just a number of seconds.
    def packet_0042100200(payload)
        if (payload =~ /(\d+)/)
            STDERR.puts "play: #{$1}"
        end
    end

    ##
    # Parse home possession (item 209)
    #
    # Daktronics documentation appears to be incorrect for this item.
    # The documentation suggests that this item should contain a 
    # less-than sign to indicate home-team possession, and a blank
    # space otherwise. But it seems that it may contain a less-than or
    # greater-than sign depending on which team has possession.
    def packet_0042100209(payload)
        if payload =~ /([<>])/
            STDERR.puts "HOME team GAINED possession (#{$1})"
        else
            STDERR.puts "HOME team LOST possession"
        end
    end

    ##
    # Parse guest possession (item 215)
    # 
    # Daktronics documentation indicates that this field should contain
    # a greater-than sign to indicate guest-team possession, and a blank
    # space otherwise. However, testing with an actual console indicates
    # that this may not be correct.
    def packet_0042100214(payload)
        if payload =~ /([<>])/
            STDERR.puts "GUEST team GAINED possession (#{$1})"
        else
            STDERR.puts "GUEST team LOST possession"
        end
    end

    ##
    # Process Daktronics RTD packet.
    #
    # This routine receives in +buf+ the string of bytes between 0x16 and 
    # 0x17 bytes, not including those bytes. It validates the packet checksum,
    # then calls the appropriate packet parser with the payload. If the packet
    # is of unknown type, the item number field is printed.
    def process_dak_packet(buf)
        cksum_range = buf[0..-3]
        cksum = buf[-2..-1].hex
        our_cksum = 0

        cksum_range.each_byte do |byte|
            our_cksum += byte
        end

        if (cksum != our_cksum % 256)
            STDERR.puts "warning: invalid checksum on this packet (ours #{our_cksum}, theirs #{cksum})"
        end

        address = buf[9..18]

        if (address =~ /^(\d+)$/ && respond_to?("packet_#{$1}"))
            send("packet_#{$1}", buf[20..-4])
        else
            STDERR.puts ""
            STDERR.puts "--- UNKNOWN PACKET (#{address}) ENCOUNTERED ---"
            STDERR.puts ""
        end
    end

    ##
    # Main parser loop. 
    #
    # This routine attempts to read bytes from the serial port and reassemble
    # them into packets, looking for 0x16 and 0x17 delimiter bytes. When a 
    # complete packet is received, it is passed to +process_dak_packet+ for
    # further processing and parsing.
    def run_thread
        begin
            STDERR.puts "Daktronics RTD sync thread starting"
            logfile_name = Time.now.strftime("rs232_log_%Y%m%d_%H%M%S")
            logfile = File.open(logfile_name, "w")
            packet = ''

            while not @stop_thread
                byte = @sp.read(1)
                logfile.write(byte)

                if byte
                    if byte.ord == 0x16
                        packet = ''
                    elsif byte.ord == 0x17
                        process_dak_packet(app, packet)
                    else
                        packet << byte
                    end
                end
            end
        rescue Exception => e
            STDERR.puts e.inspect
        end
    end
end
