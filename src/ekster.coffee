#!/usr/bin/env coffee

# XMPP connector for the IoT registry.

program = require 'commander'
pson = require '../package.json'
shortId = require 'shortid'
ltx = require('node-xmpp-core').ltx

Component = require 'node-xmpp-component'
Processor = require './processor.coffee'
{JID} = require 'node-xmpp-core'
Backend = require './backend.coffee'
MongooseBackend = require './mongoose-backend.coffee'

bunyan = require 'bunyan'

program.version pson.version
program.option '-j, --jid <jid>', 'jid for the registry'
program.option '-P, --password <password>', 'password for the component'
program.option '-H, --host <hostname>',
    'hostname of the XMPP server this component connects to'
program.option '-R, --no-reconnect',
    'disable reconnecting to the XMPP server when the connection is lost'
program.option '-p, --port [port]', 'the port to connect to [5347]',
    5347
program.option '-b, --backend [backend]', 'the backend to connect to [mongoose]',
    'mongoose'
program.option '-B, --backendHost [backendHost]', 'the host of the backend [localhost]',
    'localhost'
program.option '-s, --backendPort [backendPort]', 'the port where the backend is listening [27017]',
    3000
program.option '--backendOptions []', 'the configuration options for
    the backend []', '{}'

program.option '-v, --verbose', 'verbose logging'

program.on '--help', () ->
    console.log '  Examples:'
    console.log ''
    console.log '    $ registrar --help'
    console.log '    $ registrar --jid registry.yourcompany.com
      --password secret --host xmpp.yourcompany.com --backend mongoose
      --backendHost localhost --backendPort 27017
      --backendOptions \'{ "user": "mongouser", "pass": "mongopass", "db": "mongodb" }\''
    console.log ''

program.parse process.argv

if !program.jid or !program.password or !program.host
    program.help()

if program.verbose
    level = 'trace'
else
    level = 'info'

log = bunyan.createLogger
    name: 'registrar'
    level: level

log.trace "Creating component for #{ program.jid }"

component = new Component
    jid: program.jid
    password: program.password
    host: program.host
    port: program.port
    reconnect: program.reconnect

serverDomain = undefined

component.on 'online', () ->
    log.info 'IoT Registry component came online.'

    # Keep the connection going by sending a keep alive
    # every 5 minutes (5 minutes * 60 seconds * 1000 milliseconds)
    ping = new ltx.Element 'iq',
            to: program.jid
            type: 'get'
    ping.c 'ping', { 'xmlns': 'urn:xmpp:ping' }

    setInterval () ->
        log.trace 'Sending keep-alive to the server'
        ping.attrs.id = shortId.generate()
        component.send ping
    , 5*60*1000

component.on 'reconnect', () ->
    log.info 'The connection to the XMPP server is lost but Ekster tries to reconnect...'

component.on 'error', (e) ->
    log.warn 'Error in the connection to the XMPP server: ' + e

backend = undefined

if program.backend is 'octoblu'
    log.info "Going to use the octoblu backend on
        ws://#{ program.backendHost }:#{ program.backendPort }."
    log.trace 'Using these options: ' + program.backendOptions

    backend = new OctobluBackend "ws://#{program.backendHost}",
        program.backendPort, JSON.parse(program.backendOptions),
        bunyan.createLogger { name: 'octoblu', level: level }
else if program.backend is 'mongoose'
    log.info "Going to use the mongoose backend on
        mongo://#{ program.backendHost }:#{ program.backendPort }."
    log.trace "Using these options: #{ program.backendOptions }"
    backend = new MongooseBackend program.backendHost, program.backendPort,
        JSON.parse(program.backendOptions), bunyan.createLogger { name: 'mongoose', level: level }
else
    log.fatal 'Using the prototype backend. Do not use for production!'
    backend = new Backend

log.info 'Starting the event processor'

processor = new Processor component, backend, bunyan.createLogger(
    name: 'processor'
    level: level
)

