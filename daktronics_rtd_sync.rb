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
require 'hexdump'

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
# Bytes 9 through 18 of the payload are a string that identifies the address
# of the first byte transmitted. This is typically 00421xxxxx where xxxxx
# is the "item number" listed in the All Sport 5000 Series Enhanced RTD
# Reference Manual published by Daktronics Inc., MINUS ONE. This document,
# Daktronics document number ED12483, may be found at
# http://www.daktronics.com/Web%20Documents/Customer-Service-Manuals/ED-12483.pdf.
#
# This parser operates in three stages. The top level breaks the serial stream
# apart into packets, which are processed by process_dak_packet().
# process_dak_packet() validates the checksum, then beginning at the start
# address in the packet, calls the handler for each address. The handlers
# are defined in a hash in process_dak_packet. These functions are responsible
# for interpreting each portion of the payload and calling the appropriate
# sync functions in @app.
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
	def sync_game_clock(payload)
		tenths = -1

		# try to parse payload as time in minutes:seconds
		# or seconds.tenths
		if (payload =~ /^(([ \d]\d):(\d\d))/)
			tenths = $2.to_i * 600 + $3.to_i * 10
		elsif (payload =~ /^(([ \d]\d).(\d))/)
			tenths = $2.to_i * 10 + $3.to_i
		else
			puts "DaktronicsRtdSync: unrecognized clock format"
		end

		if tenths >= 0
			@app.sync_clock_time_remaining(tenths)
		end
	end

	##
	# This is used for all fields that are plain integer values, including
	# home team score (item 108) (method = :sync_hscore)
	# visiting team score (item 112) (method = :sync_vscore)
	# home and visiting team shots on goal (422 and 468)
	# (method = :sync_hshots, :sync_vshots)
	# period (142) (method = :sync_clock_period)
	def sync_integer(payload, method)
		if (payload =~ /^\s*(\d+)/)
			value = $1.to_i
			@app.send(method, value)
		end
	end

	def sync_string(payload, method)
		@app.send(method, payload)
	end

	def sync_possession(payload, team)
		if payload =~ /([<>])/
			@app.sync_possession(team, true)
		else
			@app.sync_possession(team, false)
		end
	end

	def dump_payload(payload, comment)
		puts "#{comment} payload:"
		Hexdump.dump(payload, :width => 16)
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

		payload = buf[20..-4]
		start_address = buf[9..18]

		# Map addresses to handlers.
		# Each address maps to an array. First item is the number of
		# bytes needed. Second is the handler function to call.
		# Rest of array is additional args to pass to the handler.
		handler_map = {
			42100000 => [ 5, :sync_game_clock ],
			42100107 => [ 4, :sync_integer, :sync_hscore ],
			42100111 => [ 4, :sync_integer, :sync_vscore ],
			42100421 => [ 3, :sync_integer, :sync_hshots ],
			42100467 => [ 3, :sync_integer, :sync_vshots ],
			42100141 => [ 2, :sync_integer, :sync_clock_period ],
			42100200 => [ 8, :sync_integer, :sync_play_clock_seconds ],
			#42100200 => [ 8, :dump_payload, "play clock" ],
			42100209 => [ 1, :sync_possession, 1 ],
			42100214 => [ 1, :sync_possession, 0 ],
			42100219 => [ 2, :sync_integer, :sync_ball_position ],
			42100221 => [ 3, :sync_string, :sync_down ],
			42100224 => [ 2, :sync_integer, :sync_distance ],
		}

		if (start_address =~ /^(\d+)$/)
			start_address = start_address.to_i
			end_address = start_address + payload.length - 1

			(start_address..end_address).each do |pos|
				bytes_left = end_address - pos + 1
				handler = handler_map[pos]
				if handler
					#STDERR.puts "this packet has address #{pos}"
				else
					#STDERR.puts "this packet has UNHANDLED address #{pos}"
				end
				if (handler && bytes_left >= handler[0])
					s = pos - start_address
					e = s + handler[0] - 1
					send(
						handler[1], payload[s..e],
						*handler[2..-1]
					)
				end
			end
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
						process_dak_packet(packet)
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
