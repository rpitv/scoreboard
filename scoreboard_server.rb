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

require 'patchbay'
require 'json'
require 'erubis'
require 'thin'
require 'serialport'

require_relative './scoreboard_view'
require_relative './scoreboard_app'

app = ScoreboardApp.new
app.view = ScoreboardView.new('assets/rpitv_scoreboard.svg.erb')
Thin::Logging.silent = true
Thread.new { app.run(:Host => '::1', :Port => 3002) }

dirty_level = 1

while true
	# prepare next SVG frame
	data = app.view.render

	# build header with data length and global alpha
	header = [ data.bytesize, app.view.galpha, dirty_level ].pack('LCC')

	# wait for handshake byte from other end
	if STDIN.read(1).nil?
		break
	end

	# send SVG data with header
	STDOUT.write(header)
	STDOUT.write(data)
end
