class DaktronicsRtdSync
    def initialize(app, options)
        @app = app
        @stop_thread = false

        # FIXME: we are passing potentially untrusted data to this constructor
        @sp = SerialPort.new(options['port'] || '/dev/ttyS0', 19200)
        @sp.read_timeout = 500
        @thread = Thread.new { run_thread }
    end

    def shutdown
        @stop_thread = true
        @thread.join
        @sp.close
    end

    def capabilities
        ['clock', 'score', 'downdist', 'playclock']
    end

    # 0042100000: main game clock for football and hockey
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

    # 0042100107: home team score for football and hockey
    def packet_0042100107(payload)
        if (payload =~ /^\s*(\d+)$/)
            home_score = $1.to_i  
            @app.sync_hscore(home_score)
        end
    end

    # 0042100111: guest team score for football and hockey
    def packet_0042100111(payload)
        if (payload =~ /^\s*(\d+)$/)
            guest_score = $1.to_i  
            @app.sync_vscore(guest_score)
        end
    end
    
    # 0042100221: down (1st, 2nd, 3rd, 4th)
    def packet_0042100221(payload)
        if (payload =~ /(1st|2nd|3rd|4th)/i)
	    STDERR.puts "#{$1} down"
            @app.sync_down($1) 
        end
    end
    
    # 0042100224: yards to go
    def packet_0042100224(payload)
        if (payload =~ /(\d+)/)
	    STDERR.puts "#{$1} to go"
            @app.sync_distance($1.to_i)
        end
    end

    # 0042100200: play clock
    def packet_0042100200(payload)
        if (payload =~ /(\d+):(\d+)/)
            STDERR.puts "play: #{$1}:#{$2}"
        else
            STDERR.puts "play clock payload: #{payload}"
        end
    end

    # 0042100209: home possession
    def packet_0042100209(payload)
        if payload =~ /([<>])/
            STDERR.puts "HOME team GAINED possession (#{$1})"
        else
            STDERR.puts "HOME team LOST possession"
        end
    end

    def packet_0042100215(payload)
        if payload =~ /([<>])/
            STDERR.puts "GUEST team GAINED possession (#{$1})"
        else
            STDERR.puts "GUEST team LOST possession"
        end
    end

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

    def run_thread
        begin
            logfile_name = Time.now.strftime("rs232_log_%Y%m%d_%H%M%S")
            logfile = File.open(logfile_name, "w")
            packet = ''

            while not @stop_thread
                byte = @sp.read(1)
                logfile.write(byte)

                if byte == ""
                    # do nothing, read timed out
                elsif byte.ord == 0x16
                    packet = ''
                elsif byte.ord == 0x17
                    process_dak_packet(app, packet)
                else
                    packet << byte
                end
            end
        rescue Exception => e
            STDERR.puts e.inspect
        end
    end
end
