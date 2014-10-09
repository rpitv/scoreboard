class EversanSerialSync
    def initialize(app, options)
        @app = app
        @stop_thread = false

        # FIXME: we are passing potentially untrusted data to this constructor
        @sp = SerialPort.new(options['port'] || '/dev/ttyS0', 115200)
        @sp.read_timeout = 500
        @thread = Thread.new { run_thread }
    end

    def shutdown
        @stop_thread = true
        @thread.join
        @sp.close
    end

    def capabilities
        ['clock', 'score']
    end

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

    def run_thread
        begin
            digit_string = ''
            digits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']
            while not @stop_thread
                ch = sp.read(1)
                if ch == ""
                    # do nothing, read timed out
                elsif digits.include?(ch)
                    digit_string += ch
                else
                    parse_digit_string(digit_string, app)
                    digit_string = ''
                end
            end
        rescue Exception => e
            STDERR.puts e.inspect
        end
    end
end
