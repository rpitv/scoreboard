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
# This class implements a sync facility using a dry contact closure.
# The dry contact is connected to CTS and DTR. CTS is pulled to RTS 
# by a 10k resistor. So CTS assumes the state of RTS when the contact
# is open, and the state of DTR when the contact is closed. The switch 
# on a Daktronics AllSport 5000 console closes when the clock is stopped.
# We will set up RTS and DTR so that we get a logic 1 when the clock is 
# running and a 0 when it is stopped.
class DrycontactSync

	include SerialSyncHelper

	##
	# Initialize the dry contact sync thread, which will 
	# report data back to +app+.
	def initialize(app, options)
		@app = app
		@stop_thread = false

		@sp = open_port(options, 9600)
		@thread = Thread.new { run_thread }
	end

	##
	# Shut down the dry contact sync thread and free the serial port.
	def shutdown
		STDERR.puts "Dry contact sync thread shutting down"
		@stop_thread = true
		@thread.join
		@sp.close
		STDERR.puts "Dry contact sync thread terminated"
	end

	##
	# Return the capabilities of the sync facility.
	def capabilities
		['clock']
	end

	##
	# Poll CTS line for changes and start/stop clock.
	def run_thread
		@sp.rts = 1
		@sp.dtr = 0
		last_cts = 1
		STDERR.puts "Dry contact sync thread starting"

		while not @stop_thread
			current_cts = @sp.cts
			if current_cts != last_cts
				if app.autosync_clock
					if current_cts == 1
						# start the clock
						app.sync_clock_start
					else
						# stop the clock
						app.sync_clock_stop
					end
				end
				# remember what the last state was
				last_cts = current_cts
				# delay briefly to allow signal to debounce
				sleep 0.1
			end
			sleep 0.01
		end
	end
end
