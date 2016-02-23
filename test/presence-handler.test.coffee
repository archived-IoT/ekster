# Tests if the server component complies to
# https://xmpp.org/extensions/xep-0347.html
#
# Some test cases refer to paragraphs and / or examples from the spec.

{EventEmitter} = require 'events'

PresenceHandler = require '../src/presence-handler.coffee'
Backend = require '../src/backend.coffee'
Processor = require '../src/processor.coffee'
Thing = require '../src/thing.coffee'

ltx = require('node-xmpp-core').ltx
Q = require 'q'

class Connection extends EventEmitter
    constructor: () ->

class TestBackend extends Backend
    constructor: (@callback) ->
        super 'test'

    get: (jid) ->
        return @callback('get', jid)

    update: (thing) ->
        return @callback('update', thing)

exports.PresenceHandlerTest =
    'test subscribe' : (test) ->
        message = "<presence from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='0'
            type='subscribe'/>"

        connection = new Connection
        processor = new Processor(connection, 'discovery.clayster.com')
        handler = new PresenceHandler(processor)

        connection.send = (stanza) ->
            test.notEqual stanza.attrs.id, '0', 'should generate a new id'
            test.equal stanza.name, 'presence'
            test.equal stanza.attrs.to, 'thing@clayster.com'
            test.equal stanza.attrs.from, 'discovery.clayster.com'
            test.equal stanza.attrs.type, 'subscribe'
            test.expect 5
            test.done()

        handler.handle ltx.parse(message)

    'test unsubscribe' : (test) ->
        test.expect 9

        message = "<presence from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='0'
            type='unsubscribe'/>"

        connection = new Connection
        processor = new Processor(connection, 'discovery.clayster.com')
        handler = new PresenceHandler(processor)

        connection.send = (stanza) ->
            test.equal stanza.name, 'presence'
            test.notEqual stanza.attrs.id, '0', 'should generate a new id'
            test.equal stanza.attrs.to, 'thing@clayster.com'
            test.equal stanza.attrs.from, 'discovery.clayster.com'

            if stanza.attrs.type isnt 'unsubscribed'
                test.equal stanza.attrs.type, 'unsubscribe'
                test.done()

        handler.handle ltx.parse(message)

    'test subscribed' : (test) ->
        message = "<presence from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='0'
            type='subscribed'/>"

        connection = new Connection
        processor = new Processor(connection, 'discovery.clayster.com')
        handler = new PresenceHandler(processor)

        connection.send = (stanza) ->
            test.notEqual stanza.attrs.id, '0', 'should generate a new id'
            test.equal stanza.name, 'presence'
            test.equal stanza.attrs.to, 'thing@clayster.com'
            test.equal stanza.attrs.from, 'discovery.clayster.com'
            test.equal stanza.attrs.type, 'subscribed'
            test.expect 5
            test.done()

        handler.handle ltx.parse(message)

    'test unfriend' : (test) ->
        connection = new Connection
        processor = new Processor(connection, 'discovery.clayster.com')
        handler = new PresenceHandler(processor)

        received = 0

        connection.send = (stanza) ->
            received++

            if stanza.attrs.type is 'unsubscribe'
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.to, 'thing@clayster.com'
                test.equal stanza.attrs.from, 'discovery.clayster.com'
                test.equal stanza.attrs.type, 'unsubscribe'

            if stanza.attrs.type is 'unsubscribed'
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.to, 'thing@clayster.com'
                test.equal stanza.attrs.from, 'discovery.clayster.com'
                test.equal stanza.attrs.type, 'unsubscribed'

            if received is 2
                test.expect 8
                test.done()

        handler.unfriend 'thing@clayster.com'

    'test online - user is offline' : (test) ->
        connection = new Connection
        processor = new Processor(connection, 'discovery.clayster.com')
        handler = new PresenceHandler(processor)

        connection.send = (stanza) ->
            test.equal stanza.name, 'presence'
            test.equal stanza.attrs.to, 'thing@clayster.com'
            test.equal stanza.attrs.from, 'discovery.clayster.com'
            test.equal stanza.attrs.type, 'probe'

        onSuccess = () ->
            test.equal true, false, 'do not call this'
            test.done()

        onFailure = () ->
            test.expect 4
            test.done()

        promise = handler.whenOnline 'thing@clayster.com', 100
        promise.then onSuccess, onFailure

    'test online - user is online' : (test) ->
        connection = new Connection
        processor = new Processor(connection, 'discovery.clayster.com')
        handler = new PresenceHandler(processor)

        processor.backend = new TestBackend (method, thing) ->
            if method is 'get'
                return Q.fcall ->
                    return [ thing ]

        connection.send = (stanza) ->
            test.equal stanza.name, 'presence'
            test.equal stanza.attrs.to, 'thing@clayster.com'
            test.equal stanza.attrs.from, 'discovery.clayster.com'
            test.equal stanza.attrs.type, 'probe'

        onSuccess = (jid) ->
            test.equal jid, 'thing@clayster.com/imc'
            test.expect 5
            test.done()

        onFailure = () ->
            test.equal true, false, 'do not call this'
            test.done()

        promise = handler.whenOnline 'thing@clayster.com', 1000
        promise.then onSuccess, onFailure

        presence =  "<presence from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='1' type='available'/>"

        handler.handlePresence 'thing@clayster.com', ltx.parse(presence)

    'test online - user is online - no status' : (test) ->
        connection = new Connection
        processor = new Processor(connection, 'discovery.clayster.com')
        handler = new PresenceHandler(processor)

        processor.backend = new TestBackend (method, thing) ->
            if method is 'get'
                return Q.fcall ->
                    return [ thing ]

        connection.send = (stanza) ->
            test.equal stanza.name, 'presence'
            test.equal stanza.attrs.to, 'thing@clayster.com'
            test.equal stanza.attrs.from, 'discovery.clayster.com'
            test.equal stanza.attrs.type, 'probe'

        onSuccess = (jid) ->
            test.equal jid, 'thing@clayster.com/imc'
            test.expect 5
            test.done()

        onFailure = () ->
            test.equal true, false, 'do not call this'
            test.done()

        promise = handler.whenOnline 'thing@clayster.com', 1000
        promise.then onSuccess, onFailure

        presence =  "<presence from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='1'/>"

        handler.handlePresence 'thing@clayster.com', ltx.parse(presence)

    'test online - multiple request for same user' : (test) ->
        connection = new Connection
        processor = new Processor(connection, 'discovery.clayster.com')
        handler = new PresenceHandler(processor)

        processor.backend = new TestBackend (method, thing) ->
            if method is 'get'
                return Q.fcall ->
                    return [ thing ]

        connection.send = (stanza) ->
            test.equal stanza.name, 'presence'
            test.equal stanza.attrs.to, 'thing@clayster.com'
            test.equal stanza.attrs.from, 'discovery.clayster.com'
            test.equal stanza.attrs.type, 'probe'

        count = 0

        onSuccess = () ->
            count++

            if count > 1
                test.expect 4
                test.done()

        onFailure = () ->
            test.equal true, false, 'do not call this'
            test.done()

        promise1 = handler.whenOnline 'thing@clayster.com', 1000
        promise1.then onSuccess, onFailure

        promise2 = handler.whenOnline 'thing@clayster.com', 1000
        promise2.then onSuccess, onFailure

        presence =  "<presence from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='1' type='available'/>"

        handler.handlePresence 'thing@clayster.com', ltx.parse(presence)

    'test online - unavailable' : (test) ->
        connection = new Connection
        processor = new Processor(connection, 'discovery.clayster.com')
        handler = new PresenceHandler(processor)

        connection.send = (stanza) ->
            test.equal stanza.name, 'presence'
            test.equal stanza.attrs.to, 'thing@clayster.com'
            test.equal stanza.attrs.from, 'discovery.clayster.com'
            test.equal stanza.attrs.type, 'probe'

        onSuccess = () ->
            test.equal true, false, 'do not call this'
            test.done()

        onFailure = () ->
            test.expect 4
            test.done()

        promise = handler.whenOnline 'thing@clayster.com', 100
        promise.then onSuccess, onFailure

        presence =  "<presence from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='1' type='unavailable'/>"

        handler.handlePresence 'thing@clayster.com', ltx.parse(presence)

    'test came online - has messages' : (test) ->
        message = "<presence from='thing@clayster.com/imc'
            to='discovery.clayster.com'/>"

        connection = new Connection
        processor = new Processor(connection, 'discovery.clayster.com')
        handler = new PresenceHandler(processor)

        connection.send = (stanza) ->
            test.notEqual stanza.attrs.id, undefined
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.from, 'discovery.clayster.com'
            test.equal stanza.attrs.type, 'set'
            test.equal stanza.children.length, 1
            test.equal stanza.children[0].name, 'claimed'
            test.equal stanza.children[0].attrs.jid, 'owner@clayster.com'

            response = "<iq type='result'
                from='thing@clayster.com/imc'
                to='discovery.clayster.com'
                id='#{ stanza.attrs.id }'/>"

            connection.emit 'stanza', ltx.parse(response)

        processor.backend = new TestBackend (method, thing) ->
            if method is 'get'
                test.equal thing.jid, 'thing@clayster.com'

                return Q.fcall ->
                    thing.owner = 'owner@clayster.com'
                    thing.needsNotification = true

                    thing2 = new Thing thing.jid
                    thing2.owner = 'owner@clayster.com'
                    thing2.needsNotification = false

                    return [ thing, thing2 ]

            else if method is 'update'
                test.equal thing.jid, 'thing@clayster.com'
                test.equal thing.needsNotification, ''

                thing.needsNofication = undefined

                test.expect 11
                test.done()

                return Q.fcall ->
                    return thing

        handler.handle ltx.parse(message)

    'test came online - no messages' : (test) ->
        message = "<presence from='thing@clayster.com/imc'
            to='discovery.clayster.com'/>"

        connection = new Connection
        processor = new Processor(connection, 'discovery.clayster.com')
        handler = new PresenceHandler(processor)

        processor.backend = new TestBackend (method, thing) ->
            if method is 'get'
                test.equal thing.jid, 'thing@clayster.com'
                test.expect 1
                test.done()

                return Q.fcall ->
                    thing.owner = 'owner@clayster.com'
                    thing.needsNotification = false
                    return [ thing1, thing2 ]

            test.equal true, false, 'do not get here'
            test.done()

        handler.handle ltx.parse(message)

    'test unfriend if possible - it is possible' : (test) ->
        connection = new Connection
        processor = new Processor(connection, 'discovery.clayster.com')
        handler = new PresenceHandler(processor)
        received = 0

        connection.send = (stanza) ->
            received++

            if stanza.attrs.type is 'unsubscribe'
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.to, 'thing@clayster.com'
                test.equal stanza.attrs.from, 'discovery.clayster.com'
                test.equal stanza.attrs.type, 'unsubscribe'

            if stanza.attrs.type is 'unsubscribed'
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.to, 'thing@clayster.com'
                test.equal stanza.attrs.from, 'discovery.clayster.com'
                test.equal stanza.attrs.type, 'unsubscribed'

            if received is 2
                test.expect 9
                test.done()


        processor.backend = new TestBackend (method, thing) ->
            if method is 'get'
                test.equal thing.jid, 'thing@clayster.com'

                return Q.fcall ->
                    return [ ]

            test.equal true, false, 'do not get here'
            test.done()

        handler.unfriendIfPossible 'thing@clayster.com'

    'test unfriend if possible - it is not possible' : (test) ->
        connection = new Connection
        processor = new Processor(connection, 'discovery.clayster.com')
        handler = new PresenceHandler(processor)
        received = 0

        connection.send = (stanza) ->
            test.equal true, false, 'should not be called'

        processor.backend = new TestBackend (method, thing) ->
            if method is 'get'
                test.equal thing.jid, 'thing@clayster.com'
                test.expect 1
                test.done()

                return Q.fcall ->
                    return [ thing ]

        handler.unfriendIfPossible 'thing@clayster.com'

