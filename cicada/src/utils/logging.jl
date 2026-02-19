"""
Logging utilities for PalimpsestCryptoIdentity
"""

using Logging
using Dates

"""
Configure logging with different verbosity levels
- 0: Errors only
- 1: Warnings and errors
- 2: Info, warnings, errors (default)
- 3: Debug, info, warnings, errors
"""
function configure_logging(verbosity::Int=2)
    level = if verbosity == 0
        Logging.Error
    elseif verbosity == 1
        Logging.Warn
    elseif verbosity == 2
        Logging.Info
    else
        Logging.Debug
    end

    logger = ConsoleLogger(stderr, level)
    global_logger(logger)

    return logger
end

"""
Log with timestamp
"""
function log_with_timestamp(level::LogLevel, msg::String)
    timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    @logmsg level "[$timestamp] $msg"
end

"""
Log security event (always logged regardless of verbosity)
"""
function log_security(msg::String)
    timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    println(stderr, "[SECURITY][$timestamp] $msg")
end

"""
Log key operation (always logged for audit trail)
"""
function log_key_operation(operation::String, details::String)
    timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    println(stderr, "[KEY_OP][$timestamp] $operation: $details")
end
