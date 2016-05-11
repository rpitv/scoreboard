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
# Helper functions for serial sync classes.
module SerialSyncHelper
	##
	# Open a serial port, first checking if it's really a valid port.
	#
	# +options+ is a hash that can include +'port'+ and +'baud'+.
	# +default_baud+ is the default baud rate to use if not specified
	# in the options.
	def open_port(options, default_baud)
		port = options['port'] || '/dev/ttyS0'
		baud = options['baud'].to_i || default_baud

		# check if we really have (something resembling) a serial port
		isatty = false
		File.open(port, "r") do |f|
			if f.isatty
				isatty = true
			end
		end

		if isatty
			SerialPort.new(port, baud)
		else
			fail "#{port} is not a serial port"
		end
	end
end
