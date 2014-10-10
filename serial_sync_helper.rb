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
        baud = options['baud'] || default_baud

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
