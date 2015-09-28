# Default logger

class Logger
    info: console.log
    warn: console.log
    trace: () ->
    error: console.log
    debug: console.log
    fatal: console.log

module.exports = Logger

