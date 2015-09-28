# Tests if the server component complies to
# https://xmpp.org/extensions/xep-0347.html
#
# Some test cases refer to paragraphs and / or examples from the spec.

{EventEmitter} = require 'events'

Processor = require '../src/processor.coffee'
Backend = require '../src/backend.coffee'
Thing = require '../src/thing.coffee'
Property = require '../src/property.coffee'
Q = require 'q'
_ = require 'lodash'

ltx = require('node-xmpp-core').ltx

class Connection extends EventEmitter
    constructor: () ->
        @jid = 'class-under-test'

class TestBackend extends Backend
    constructor: (@callback) ->
        super 'test'

    register: (thing) ->
        return @callback('register', thing)

    claim: (thing) ->
        return @callback('claim', thing)

    remove: (thing) ->
        return @callback('remove', thing)

    update: (thing) ->
        return @callback('update', thing)

    search: (properties, offset, maxCount) ->
        return @callback('search', properties, offset, maxCount)

    unregister: (thing) ->
        return @callback('unregister', thing)

    disown: (thing) ->
        return @callback('disown', thing)

    get: (thing) ->
        return @callback('get', thing)

exports.ProcessorTest =
    'test do not response to non-iq type messages': (test) ->
        message = "<message from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='1'/>"

        connection = new Connection
        backend = new TestBackend
        processor = new Processor connection, backend

        connection.send = (stanza) ->
            test.ok false, 'do not call this'

        connection.emit 'stanza', ltx.parse(message)
        test.done()

    'test do not respond to result type messages': (test) ->
        message = "<iq type='result'
            from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='5'/>"

        connection = new Connection
        backend = new TestBackend
        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)
        test.done()

    'test respond with error when the message has no child elements': (test) ->
        message = "<iq type='set'
            from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='1'/>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.id, '1'
            test.equal stanza.attrs.from, 'class-under-test'
            test.done()

        processor = new Processor connection
        connection.emit 'stanza', ltx.parse(message)

    'test respond with error when the iq message is not of type
    get or set': (test) ->
        message = "<iq type='blaat'
            from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='1'/>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.id, '1'
            test.equal stanza.attrs.from, 'class-under-test'
            test.done()

        processor = new Processor connection
        connection.emit 'stanza', ltx.parse(message)

    'test respond with error when the iq message has to many
    children': (test) ->
        message = "<iq type='get'
            from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='1'>
                <register/>
                <register/>
            </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.id, '1'
            test.equal stanza.attrs.from, 'class-under-test'
            test.done()

        processor = new Processor connection
        connection.emit 'stanza', ltx.parse(message)

    'test respond with service-unavailable when the iq message has an unknown
    child': (test) ->
        test.expect 12
        message = "<iq type='get'
            from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='1'><unknown fruit='banana'><bla/></unknown></iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.id, '1'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children.length, 2

            for child in stanza.children
                if child.name is 'unknown'
                    test.equal child.children.length, 1
                    test.equal child.attrs.fruit, 'banana'
                if child.name is 'error'
                    test.equal child.attrs.type, 'cancel'
                    test.equal child.children.length, 1
                    test.equal child.children[0].name, 'service-unavailable'
                    test.equal child.children[0].attrs.xmlns, 'urn:ietf:params:xml:ns:xmpp-stanzas'

            test.done()

        processor = new Processor connection
        connection.emit 'stanza', ltx.parse(message)

    'test respond to ping': (test) ->
        test.expect 6
        message = "<iq type='get'
            from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='1'><ping xmlns='urn:xmpp:ping'/></iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '1'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children.length, 0
            test.done()

        processor = new Processor connection
        connection.emit 'stanza', ltx.parse(message)

    'test 3.6 register a thing': (test) ->
        message = "<iq type='set'
            from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='1'>
                <register xmlns='urn:xmpp:iot:discovery'>
                    <str name='SN' value='394872348732948723'/>
                    <str name='MAN' value='www.ktc.se'/>
                    <str name='MODEL' value='IMC'/>
                    <num name='V' value='1.2'/>
                    <str name='KEY' value='4857402340298342'/>
                </register>
            </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '1'
            test.equal stanza.attrs.from, 'class-under-test'
            test.expect 12
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'register'
            test.equal thing.jid, 'thing@clayster.com'
            test.equal thing.properties.length, 5

            for property in thing.properties
                switch property.name
                    when 'SN'
                        test.equal property.type, 'string'
                        test.equal property.value, '394872348732948723'
                    when 'V'
                        test.equal property.type, 'number'
                        test.equal property.value, 1.2

            return Q.fcall ->
                return

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.6 register a self owned thing': (test) ->
        message = "<iq type='set'
            from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='1'>
                <register xmlns='urn:xmpp:iot:discovery' selfOwned='true'>
                    <str name='SN' value='394872348732948723'/>
                    <str name='MAN' value='www.ktc.se'/>
                    <str name='MODEL' value='IMC'/>
                    <num name='V' value='1.2'/>
                    <str name='KEY' value='4857402340298342'/>
                </register>
            </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '1'
            test.equal stanza.attrs.from, 'class-under-test'
            test.expect 13
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'register'
            test.equal thing.jid, 'thing@clayster.com'
            test.equal thing.properties.length, 5
            test.equal thing.owner, 'thing@clayster.com'

            for property in thing.properties
                switch property.name
                    when 'SN'
                        test.equal property.type, 'string'
                        test.equal property.value, '394872348732948723'
                    when 'V'
                        test.equal property.type, 'number'
                        test.equal property.value, 1.2

            return Q.fcall ->
                return

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.6 registering a thing fails': (test) ->
        message = "<iq type='set'
            from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='2'>
                <register xmlns='urn:xmpp:iot:discovery'>
                    <str name='SN' value='394872348732948723'/>
                    <str name='MAN' value='www.ktc.se'/>
                    <str name='MODEL' value='IMC'/>
                    <num name='V' value='1.2'/>
                    <str name='KEY' value='4857402340298342'/>
                </register>
            </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.id, '2'
            test.equal stanza.attrs.from, 'class-under-test'
            test.expect 7
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'register'
            test.equal thing.jid, 'thing@clayster.com'
            return Q.fcall ->
                throw new Error('fails in this test case')

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.6 registering a thing fails because of illegal value': (test) ->
        message = "<iq type='set'
            from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='2'>
                <register xmlns='urn:xmpp:iot:discovery'>
                    <num name='V' value='banaan'/>
                </register>
            </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.id, '2'
            test.equal stanza.attrs.from, 'class-under-test'
            test.expect 5
            test.done()

        processor = new Processor connection
        connection.emit 'stanza', ltx.parse(message)

    'test 3.6 registering a thing fails because of unknown
    property type': (test) ->
        message = "<iq type='set'
            from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='2'>
                <register xmlns='urn:xmpp:iot:discovery'>
                    <banana name='V' value='monkey'/>
                </register>
            </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.id, '2'
            test.equal stanza.attrs.from, 'class-under-test'
            test.expect 5
            test.done()

        processor = new Processor connection
        connection.emit 'stanza', ltx.parse(message)

    'test 3.6 registering a thing fails because of illegal namespace': (test) ->
        message = "<iq type='set'
            from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='2'>
                <register xmlns='urn:xmpp:iot:bananas'>
                    <num name='V' value='1'/>
                </register>
            </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.id, '2'
            test.equal stanza.attrs.from, 'class-under-test'
            test.expect 5
            test.done()

        processor = new Processor connection
        connection.emit 'stanza', ltx.parse(message)

    'test 3.6 registering thing that already has been claimed': (test) ->
        message = "<iq type='set'
            from='thing@clayster.com/imc'
            to='discovery.clayster.com'
            id='1'>
                <register xmlns='urn:xmpp:iot:discovery'>
                    <str name='SN' value='394872348732948723'/>
                    <str name='MAN' value='www.ktc.se'/>
                    <str name='MODEL' value='IMC'/>
                    <num name='V' value='1.2'/>
                    <str name='KEY' value='4857402340298342'/>
                </register>
            </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '1'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children[0].name, 'claimed'
            test.equal stanza.children[0].attrs.xmlns, 'urn:xmpp:iot:discovery'
            test.equal stanza.children[0].attrs.jid, 'owner@clayster.com'
            test.expect 10
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'register'
            test.equal thing.jid, 'thing@clayster.com'
            return Q.fcall ->
                error = new Error('claimed')
                error.owner = 'owner@clayster.com'
                throw error

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.8 register thing behind concentrator': (test) ->
        message = "<iq type='set'
               from='rack@clayster.com/plcs'
               to='discovery.clayster.com'
               id='3'>
              <register xmlns='urn:xmpp:iot:discovery'
                nodeId='imc1'
                sourceId='MeteringTopology'
                cacheType='test'>
                  <str name='SN' value='394872348732948723'/>
                  <str name='MAN' value='www.ktc.se'/>
                  <str name='MODEL' value='IMC'/>
                  <num name='V' value='1.2'/>
                  <str name='KEY' value='4857402340298342'/>
              </register>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'rack@clayster.com/plcs'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '3'
            test.equal stanza.attrs.from, 'class-under-test'
            test.expect 11
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'register'
            test.equal thing.jid, 'rack@clayster.com'
            test.equal thing.nodeId, 'imc1'
            test.equal thing.sourceId, 'MeteringTopology'
            test.equal thing.cacheType, 'test'
            test.equal thing.properties.length, 5
            return Q.fcall ->
                return

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.8 register thing behind concentrator without cacheType': (test) ->
        message = "<iq type='set'
               from='rack@clayster.com/plcs'
               to='discovery.clayster.com'
               id='3'>
              <register xmlns='urn:xmpp:iot:discovery'
                nodeId='imc1'
                sourceId='MeteringTopology'>
                  <str name='SN' value='394872348732948723'/>
                  <str name='MAN' value='www.ktc.se'/>
                  <str name='MODEL' value='IMC'/>
                  <num name='V' value='1.2'/>
                  <str name='KEY' value='4857402340298342'/>
              </register>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'rack@clayster.com/plcs'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '3'
            test.equal stanza.attrs.from, 'class-under-test'
            test.expect 11
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'register'
            test.equal thing.jid, 'rack@clayster.com'
            test.equal thing.nodeId, 'imc1'
            test.equal thing.sourceId, 'MeteringTopology'
            test.equal thing.cacheType, undefined
            test.equal thing.properties.length, 5
            return Q.fcall ->
                return

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.9 - example 15 and 20 - claim ownership of public thing': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='4'>
              <mine xmlns='urn:xmpp:iot:discovery'>
                  <str name='SN' value='394872348732948723'/>
                  <str name='MAN' value='www.ktc.se'/>
                  <str name='MODEL' value='IMC'/>
                  <num name='V' value='1.2'/>
                  <str name='KEY' value='4857402340298342'/>
              </mine>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            if stanza.name is 'iq'
                test.equal stanza.name, 'iq'

                if stanza.attrs.type is 'result'
                    test.equal stanza.attrs.to, 'owner@clayster.com/phone'
                    test.equal stanza.attrs.type, 'result'
                    test.equal stanza.attrs.id, '4'
                    test.equal stanza.attrs.from, 'class-under-test'
                    test.equal stanza.children[0].name, 'claimed'
                    test.equal stanza.children[0].attrs.xmlns,
                        'urn:xmpp:iot:discovery'
                    test.equal stanza.children[0].attrs.jid, 'thing@clayster.com'
                else
                    test.equal stanza.attrs.to, 'thing@clayster.com/imc'
                    test.equal stanza.attrs.type, 'set'
                    test.equal _.has(stanza.attrs, 'id'), true
                    test.equal _.isString(stanza.attrs.id), true
                    test.equal stanza.children.length, 1
                    test.equal stanza.children[0].name, 'claimed'
                    test.equal stanza.children[0].attrs.xmlns,
                        'urn:xmpp:iot:discovery'
                    test.equal stanza.children[0].attrs.jid, 'owner@clayster.com'

                    response = "<iq type='result'
                        from='thing@clayster.com/imc'
                        to='discovery.clayster.com'
                        id='#{ stanza.attrs.id }'/>"

                    connection.emit 'stanza', ltx.parse(response)
            else
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.to, 'thing@clayster.com'
                test.equal stanza.attrs.from, 'class-under-test'
                test.equal stanza.attrs.type, 'probe'

                presence =  "<presence from='thing@clayster.com/imc'
                    to='class-under-test'
                    type='available'/>"

                connection.emit 'stanza', ltx.parse(presence)

        backend = new TestBackend (method, thing) ->
            if method is 'claim'
                test.equal thing.properties.length, 5
                test.equal thing.needsNotification, true

                return Q.fcall ->
                    thing.jid = 'thing@clayster.com'
                    thing.owner = 'owner@clayster.com'
                    return thing
            else if method is 'get'
                test.equal thing.jid, 'thing@clayster.com'
                return Q.fcall ->
                    thing.jid = 'thing@clayster.com'
                    thing.owner = 'owner@clayster.com'
                    thing.needsNotification = true
                    return [ thing ]
            else
                test.equal method, 'update'
                test.equal thing.needsNotification, false
                test.expect 26
                test.done()

                return Q.fcall ->
                    thing.jid = 'thing@clayster.com'
                    thing.needsNotification = undefined
                    return thing

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.9 - example 16 and 20 - claim ownership of a private thing': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='4'>
              <mine xmlns='urn:xmpp:iot:discovery' public='false'>
                  <str name='SN' value='394872348732948723'/>
                  <str name='MAN' value='www.ktc.se'/>
                  <str name='MODEL' value='IMC'/>
                  <num name='V' value='1.2'/>
                  <str name='KEY' value='4857402340298342'/>
              </mine>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            if stanza.name is 'iq'
                test.equal stanza.name, 'iq'

                if stanza.attrs.type is 'result'
                    test.equal stanza.attrs.to, 'owner@clayster.com/phone'
                    test.equal stanza.attrs.type, 'result'
                    test.equal stanza.attrs.id, '4'
                    test.equal stanza.attrs.from, 'class-under-test'
                    test.equal stanza.children[0].name, 'claimed'
                    test.equal stanza.children[0].attrs.xmlns,
                        'urn:xmpp:iot:discovery'
                    test.equal stanza.children[0].attrs.jid, 'thing@clayster.com'
                else
                    test.equal stanza.attrs.to, 'thing@clayster.com/imc'
                    test.equal stanza.attrs.type, 'set'
                    test.equal _.has(stanza.attrs, 'id'), true
                    test.equal _.isString(stanza.attrs.id), true
                    test.equal stanza.children.length, 1
                    test.equal stanza.children[0].name, 'claimed'
                    test.equal stanza.children[0].attrs.xmlns,
                        'urn:xmpp:iot:discovery'
                    test.equal stanza.children[0].attrs.jid, 'owner@clayster.com'
                    test.equal stanza.children[0].attrs.public, 'false'

                    response = "<iq type='result'
                        from='thing@clayster.com/imc'
                        to='discovery.clayster.com'
                        id='#{ stanza.attrs.id }'/>"

                    connection.emit 'stanza', ltx.parse(response)
            else
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.to, 'thing@clayster.com'
                test.equal stanza.attrs.from, 'class-under-test'
                test.equal stanza.attrs.type, 'probe'

                presence =  "<presence from='thing@clayster.com/imc'
                    to='class-under-test'
                    type='available'/>"

                connection.emit 'stanza', ltx.parse(presence)

        backend = new TestBackend (method, thing) ->
            if method is 'claim'
                test.equal thing.properties.length, 5
                test.equal thing.public, false
                return Q.fcall ->
                    thing.jid = 'thing@clayster.com'
                    thing.owner = 'owner@clayster.com'
                    return thing
            else if method is 'get'
                test.equal thing.jid, 'thing@clayster.com'
                return Q.fcall ->
                    thing.jid = 'thing@clayster.com'
                    thing.owner = 'owner@clayster.com'
                    thing.public = false
                    thing.needsNotification = true
                    return [ thing ]
            else
                test.equal method, 'update'
                test.equal thing.needsNotification, false
                test.equal thing.public, false
                test.expect 28
                test.done()

                return Q.fcall ->
                    thing.jid = 'thing@clayster.com'
                    thing.needsNotification = undefined
                    return thing

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.9 - example 16 and 20 - claim ownership of a public thing (attrib)': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='4'>
              <mine xmlns='urn:xmpp:iot:discovery' public='true'>
                  <str name='SN' value='394872348732948723'/>
                  <str name='MAN' value='www.ktc.se'/>
                  <str name='MODEL' value='IMC'/>
                  <num name='V' value='1.2'/>
                  <str name='KEY' value='4857402340298342'/>
              </mine>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            if stanza.name is 'iq'
                test.equal stanza.name, 'iq'

                if stanza.attrs.type is 'result'
                    test.equal stanza.attrs.to, 'owner@clayster.com/phone'
                    test.equal stanza.attrs.type, 'result'
                    test.equal stanza.attrs.id, '4'
                    test.equal stanza.attrs.from, 'class-under-test'
                    test.equal stanza.children[0].name, 'claimed'
                    test.equal stanza.children[0].attrs.xmlns,
                        'urn:xmpp:iot:discovery'
                    test.equal stanza.children[0].attrs.jid, 'thing@clayster.com'
                else
                    test.equal stanza.attrs.to, 'thing@clayster.com/imc'
                    test.equal stanza.attrs.type, 'set'
                    test.equal _.has(stanza.attrs, 'id'), true
                    test.equal _.isString(stanza.attrs.id), true
                    test.equal stanza.children.length, 1
                    test.equal stanza.children[0].name, 'claimed'
                    test.equal stanza.children[0].attrs.xmlns,
                        'urn:xmpp:iot:discovery'
                    test.equal stanza.children[0].attrs.jid, 'owner@clayster.com'
                    test.equal stanza.children[0].attrs.public, undefined

                    response = "<iq type='result'
                        from='thing@clayster.com/imc'
                        to='discovery.clayster.com'
                        id='#{ stanza.attrs.id }'/>"

                    connection.emit 'stanza', ltx.parse(response)
            else
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.to, 'thing@clayster.com'
                test.equal stanza.attrs.from, 'class-under-test'
                test.equal stanza.attrs.type, 'probe'

                presence =  "<presence from='thing@clayster.com/imc'
                    to='class-under-test'
                    type='available'/>"

                connection.emit 'stanza', ltx.parse(presence)

        backend = new TestBackend (method, thing) ->
            if method is 'claim'
                test.equal thing.properties.length, 5
                test.equal thing.public, true

                return Q.fcall ->
                    thing.jid = 'thing@clayster.com'
                    thing.owner = 'owner@clayster.com'
                    return thing
            else if method is 'get'
                test.equal thing.jid, 'thing@clayster.com'
                return Q.fcall ->
                    thing.jid = 'thing@clayster.com'
                    thing.owner = 'owner@clayster.com'
                    thing.public = true
                    thing.needsNotification = true
                    return [ thing ]
            else
                test.equal method, 'update'
                test.equal thing.needsNotification, false
                test.equal thing.public, true
                test.expect 28
                test.done()

                return Q.fcall ->
                    thing.jid = 'thing@clayster.com'
                    thing.needsNotification = undefined
                    return thing

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.9 - example 18 and 22 - claim ownership of public thing behind
    a concentrator': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='4'>
              <mine xmlns='urn:xmpp:iot:discovery'>
                  <str name='SN' value='394872348732948723'/>
                  <str name='MAN' value='www.ktc.se'/>
                  <str name='MODEL' value='IMC'/>
                  <num name='V' value='1.2'/>
                  <str name='KEY' value='4857402340298342'/>
              </mine>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            if stanza.name is 'iq'
                if stanza.attrs.type is 'result'
                    test.equal stanza.attrs.to, 'owner@clayster.com/phone'
                    test.equal stanza.attrs.type, 'result'
                    test.equal stanza.attrs.id, '4'
                    test.equal stanza.attrs.from, 'class-under-test'
                    test.equal stanza.children[0].name, 'claimed'
                    test.equal stanza.children[0].attrs.xmlns,
                        'urn:xmpp:iot:discovery'
                    test.equal stanza.children[0].attrs.jid,
                        'thing@clayster.com'
                    test.equal stanza.children[0].attrs.nodeId, 'imc1'
                    test.equal stanza.children[0].attrs.sourceId, 'MeteringTopology'
                    test.equal _.has(stanza.children[0].attrs, 'cacheType'), false
                else
                    test.equal stanza.attrs.to, 'thing@clayster.com/imc'
                    test.equal stanza.attrs.type, 'set'
                    test.equal _.has(stanza.attrs, 'id'), true
                    test.equal _.isString(stanza.attrs.id), true
                    test.equal stanza.children.length, 1
                    test.equal stanza.children[0].name, 'claimed'
                    test.equal stanza.children[0].attrs.xmlns,
                        'urn:xmpp:iot:discovery'
                    test.equal stanza.children[0].attrs.jid, 'owner@clayster.com'
                    test.equal stanza.children[0].attrs.nodeId, 'imc1'
                    test.equal stanza.children[0].attrs.sourceId, 'MeteringTopology'
                    test.equal _.has(stanza.children[0].attrs, 'cacheType'), false

                    response = "<iq type='result'
                        from='thing@clayster.com/imc'
                        to='discovery.clayster.com'
                        id='#{ stanza.attrs.id }'/>"

                    connection.emit 'stanza', ltx.parse(response)
            else
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.to, 'thing@clayster.com'
                test.equal stanza.attrs.from, 'class-under-test'
                test.equal stanza.attrs.type, 'probe'

                presence =  "<presence from='thing@clayster.com/imc'
                    to='class-under-test'
                    type='available'/>"

                connection.emit 'stanza', ltx.parse(presence)

        backend = new TestBackend (method, thing) ->
            if method is 'claim'
                test.equal thing.properties.length, 5
                return Q.fcall ->
                    thing.jid = 'thing@clayster.com'
                    thing.owner = 'owner@clayster.com'
                    thing.nodeId = 'imc1'
                    thing.sourceId = 'MeteringTopology'
                    return thing
            else if method is 'get'
                test.equal thing.jid, 'thing@clayster.com'
                return Q.fcall ->
                    thing.jid = 'thing@clayster.com'
                    thing.owner = 'owner@clayster.com'
                    thing.needsNotification = true
                    thing.nodeId = 'imc1'
                    thing.sourceId = 'MeteringTopology'
                    return [ thing ]
            else
                test.equal method, 'update'
                test.equal thing.needsNotification, false
                test.expect 29
                test.done()

                return Q.fcall ->
                    thing.jid = 'thing@clayster.com'
                    thing.needsNotification = undefined
                    return thing

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.9 - claim ownership of thing fails because thing was already
    claimed': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='4'>
              <mine xmlns='urn:xmpp:iot:discovery'>
                  <str name='SN' value='394872348732948723'/>
                  <str name='MAN' value='www.ktc.se'/>
                  <str name='MODEL' value='IMC'/>
                  <num name='V' value='1.2'/>
                  <str name='KEY' value='4857402340298342'/>
              </mine>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'owner@clayster.com/phone'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '4'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children[0].name, 'error'
            test.equal stanza.children[0].attrs.type, 'cancel'
            test.equal stanza.children[0].children[0].name, 'item-not-found'
            test.equal stanza.children[0].children[0].attrs.xmlns,
                'urn:ietf:params:xml:ns:xmpp-stanzas'
            test.expect 11
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'claim'
            test.equal thing.properties.length, 5
            return Q.fcall ->
                throw new Error 'claimed'

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.9 - claim ownership of thing fails because thing was
    not found': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='4'>
              <mine xmlns='urn:xmpp:iot:discovery'>
                  <str name='SN' value='394872348732948723'/>
                  <str name='MAN' value='www.ktc.se'/>
                  <str name='MODEL' value='IMC'/>
                  <num name='V' value='1.2'/>
                  <str name='KEY' value='4857402340298342'/>
              </mine>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'owner@clayster.com/phone'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '4'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children[0].name, 'error'
            test.equal stanza.children[0].attrs.type, 'cancel'
            test.equal stanza.children[0].children[0].name, 'item-not-found'
            test.equal stanza.children[0].children[0].attrs.xmlns,
                'urn:ietf:params:xml:ns:xmpp-stanzas'
            test.expect 11
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'claim'
            test.equal thing.properties.length, 5
            return Q.fcall ->
                throw new Error 'not-found'

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.9 - claim ownership of thing fails because of
    other reason': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='4'>
              <mine xmlns='urn:xmpp:iot:discovery'>
                  <str name='SN' value='394872348732948723'/>
                  <str name='MAN' value='www.ktc.se'/>
                  <str name='MODEL' value='IMC'/>
                  <num name='V' value='1.2'/>
                  <str name='KEY' value='4857402340298342'/>
              </mine>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'owner@clayster.com/phone'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.id, '4'
            test.equal stanza.attrs.from, 'class-under-test'
            test.expect 7
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'claim'
            test.equal thing.properties.length, 5
            return Q.fcall ->
                throw new Error 'banana'

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.10 - example 24 - removing a thing from the registry': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='6'>
              <remove xmlns='urn:xmpp:iot:discovery' jid='thing@clayster.com'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            if stanza.name is 'iq'
                if stanza.attrs.type is 'result'
                    test.equal stanza.attrs.to, 'owner@clayster.com/phone'
                    test.equal stanza.attrs.type, 'result'
                    test.equal stanza.attrs.from, 'class-under-test'
                    test.equal stanza.attrs.id, '6'
                else
                    test.equal stanza.attrs.to, 'thing@clayster.com/imc'
                    test.equal stanza.attrs.type, 'set'
                    test.equal _.has(stanza.attrs, 'id'), true
                    test.equal _.isString(stanza.attrs.id), true
                    test.equal stanza.children.length, 1
                    test.equal stanza.children[0].name, 'removed'
                    test.equal stanza.children[0].attrs.xmlns,
                        'urn:xmpp:iot:discovery'

                    response = "<iq type='result'
                       from='thing@clayster.com/imc'
                       to='discovery.clayster.com'
                       id='#{ stanza.attrs.id }'/>"

                    connection.emit 'stanza', ltx.parse(response)
            else
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.type, 'probe'
                test.equal stanza.attrs.to, 'thing@clayster.com'
                test.equal stanza.attrs.from, 'class-under-test'

                response = "<presence
                    from='thing@clayster.com/imc'
                    to='discovery.clayster.com'
                    id='#{ stanza.attrs.id }'
                    type='available'/>"

                connection.emit 'stanza', ltx.parse(response)

        getCalled = 0

        backend = new TestBackend (method, thing) ->
            if method is 'update'
                test.equal thing.jid, 'thing@clayster.com'
                test.equal thing.owner, 'owner@clayster.com'
                test.equal thing.removed, true
                test.equal thing.needsNotification, true
                return Q.fcall ->
                    return thing

            else if method is 'get'
                getCalled++

                test.equal thing.jid, 'thing@clayster.com'

                if getCalled is 2
                    test.expect 25
                    test.done()

                return Q.fcall ->
                    thing.removed = true
                    thing.owner = 'owner@clayster.com'
                    thing.needsNotification = true
                    return [ thing ]
            else
                test.equal method, 'remove'
                test.equal thing.jid, 'thing@clayster.com'
                test.equal thing.owner, 'owner@clayster.com'
                test.equal thing.nodeId, undefined
                return Q.fcall ->
                    return thing

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.10 - example 25 - removing a thing behind a concentrator
    from the registry': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='6'>
              <remove xmlns='urn:xmpp:iot:discovery'
                jid='rack@clayster.com'
                nodeId='imc1'
                sourceId='MeteringTopology'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            if stanza.name is 'iq'
                if stanza.attrs.type is 'result'
                    test.equal stanza.attrs.to, 'owner@clayster.com/phone'
                    test.equal stanza.attrs.type, 'result'
                    test.equal stanza.attrs.from, 'class-under-test'
                    test.equal stanza.attrs.id, '6'
                else
                    test.equal stanza.attrs.to, 'rack@clayster.com/imc'
                    test.equal stanza.attrs.type, 'set'
                    test.equal _.has(stanza.attrs, 'id'), true
                    test.equal _.isString(stanza.attrs.id), true
                    test.equal stanza.children.length, 1
                    test.equal stanza.children[0].name, 'removed'
                    test.equal stanza.children[0].attrs.xmlns,
                        'urn:xmpp:iot:discovery'
                    test.equal stanza.children[0].attrs.nodeId, 'imc1'
                    test.equal stanza.children[0].attrs.sourceId,
                        'MeteringTopology'
                    test.equal _.has(stanza.children[0].attrs.cacheType), false

                    response = "<iq type='result'
                       from='thing@clayster.com/imc'
                       to='discovery.clayster.com'
                       id='#{ stanza.attrs.id }'/>"

                    connection.emit 'stanza', ltx.parse(response)
            else
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.type, 'probe'
                test.equal stanza.attrs.to, 'rack@clayster.com'
                test.equal stanza.attrs.from, 'class-under-test'

                response = "<presence
                    from='rack@clayster.com/imc'
                    to='discovery.clayster.com'
                    id='#{ stanza.attrs.id }'
                    type='available'/>"

                connection.emit 'stanza', ltx.parse(response)

        getCalled = 0

        backend = new TestBackend (method, thing) ->
            if method is 'update'
                test.equal thing.jid, 'rack@clayster.com'
                test.equal thing.owner, 'owner@clayster.com'
                test.equal thing.removed, true
                test.equal thing.needsNotification, true
                return Q.fcall ->
                    return thing
            else if method is 'get'
                getCalled++

                test.equal thing.jid, 'rack@clayster.com'

                if getCalled is 2
                    test.expect 30
                    test.done()

                return Q.fcall ->
                    thing.removed = true
                    thing.owner = 'owner@clayster.com'
                    thing.needsNotification = true
                    thing.nodeId = 'imc1'
                    thing.sourceId = 'MeteringTopology'
                    return [ thing ]
            else
                test.equal method, 'remove'
                test.equal thing.jid, 'rack@clayster.com'
                test.equal thing.owner, 'owner@clayster.com'
                test.equal thing.nodeId, 'imc1'
                test.equal thing.sourceId, 'MeteringTopology'
                test.equal thing.cacheType, undefined
                return Q.fcall ->
                    return thing

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.10 - example 27 - removing a thing from the registry
    fails': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='6'>
              <remove xmlns='urn:xmpp:iot:discovery' jid='thing@clayster.com'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'owner@clayster.com/phone'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.attrs.id, '6'
            test.equal stanza.children.length, 1
            test.equal stanza.children[0].name, 'error'
            test.equal stanza.children[0].attrs.type, 'cancel'
            test.equal stanza.children[0].children.length, 1
            test.equal stanza.children[0].children[0].name, 'item-not-found'
            test.equal stanza.children[0].children[0].attrs.xmlns,
                'urn:ietf:params:xml:ns:xmpp-stanzas'
            test.expect 13
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'update'
            test.equal thing.jid, 'thing@clayster.com'
            return Q.fcall ->
                throw new Error 'not-found'

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.10 - example 27 - removing a thing from the registry
    fails with general error': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='6'>
              <remove xmlns='urn:xmpp:iot:discovery' jid='thing@clayster.com'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'owner@clayster.com/phone'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.attrs.id, '6'
            test.expect 7
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'update'
            test.equal thing.jid, 'thing@clayster.com'
            return Q.fcall ->
                throw new Error

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.13 - example 31 and 33 - update meta data request': (test) ->
        message = "<iq type='set'
               from='thing@clayster.com/imc'
               to='discovery.clayster.com'
               id='8'>
              <update xmlns='urn:xmpp:iot:discovery'>
                  <str name='KEY' value=''/>
                  <str name='CLASS' value='PLC'/>
                  <num name='LON' value='-71.519722'/>
                  <num name='LAT' value='-33.008055'/>
              </update>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '8'
            test.equal stanza.attrs.from, 'class-under-test'
            test.expect 12
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'update'
            test.equal thing.jid, 'thing@clayster.com'
            test.equal thing.properties.length, 4

            for property in thing.properties
                switch property.name
                    when 'KEY'
                        test.equal property.type, 'string'
                        test.equal property.value, ''
                    when 'LAT'
                        test.equal property.type, 'number'
                        test.equal property.value, -33.008055

            return Q.fcall ->
                return

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.13 - example 32 and 33 - update meta data request
        behind a concentrator': (test) ->
        message = "<iq type='set'
               from='rack@clayster.com/plcs'
               to='discovery.clayster.com'
               id='8'>
              <update xmlns='urn:xmpp:iot:discovery' nodeId='imc1'
                sourceId='MeteringTopology'>
                  <str name='KEY' value=''/>
                  <str name='CLASS' value='PLC'/>
                  <num name='LON' value='-71.519722'/>
                  <num name='LAT' value='-33.008055'/>
              </update>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'rack@clayster.com/plcs'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '8'
            test.equal stanza.attrs.from, 'class-under-test'
            test.expect 15
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'update'
            test.equal thing.jid, 'rack@clayster.com'
            test.equal thing.nodeId, 'imc1'
            test.equal thing.sourceId, 'MeteringTopology'
            test.equal _.has('cacheType'), false
            test.equal thing.properties.length, 4

            for property in thing.properties
                switch property.name
                    when 'KEY'
                        test.equal property.type, 'string'
                        test.equal property.value, ''
                    when 'LAT'
                        test.equal property.type, 'number'
                        test.equal property.value, -33.008055

            return Q.fcall ->
                return

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.13 - example 31 - update meta data request fails': (test) ->
        message = "<iq type='set'
               from='thing@clayster.com/imc'
               to='discovery.clayster.com'
               id='8'>
              <update xmlns='urn:xmpp:iot:discovery'>
                  <str name='KEY' value=''/>
                  <str name='CLASS' value='PLC'/>
                  <num name='LON' value='-71.519722'/>
                  <num name='LAT' value='-33.008055'/>
              </update>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.id, '8'
            test.equal stanza.attrs.from, 'class-under-test'
            test.expect 8
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'update'
            test.equal thing.jid, 'thing@clayster.com'
            test.equal thing.properties.length, 4

            return Q.fcall ->
                throw new Error

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.13 - example 31 and 34 - update meta data request fails': (test) ->
        message = "<iq type='set'
               from='thing@clayster.com/imc'
               to='discovery.clayster.com'
               id='8'>
              <update xmlns='urn:xmpp:iot:discovery'>
                  <str name='KEY' value=''/>
                  <str name='CLASS' value='PLC'/>
                  <num name='LON' value='-71.519722'/>
                  <num name='LAT' value='-33.008055'/>
              </update>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.id, '8'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children.length, 1
            test.equal stanza.children[0].name, 'error'
            test.equal stanza.children[0].attrs.type, 'cancel'
            test.equal stanza.children[0].children.length, 1
            test.equal stanza.children[0].children[0].name, 'item-not-found'
            test.equal stanza.children[0].children[0].attrs.xmlns,
                'urn:ietf:params:xml:ns:xmpp-stanzas'
            test.expect 14
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'update'
            test.equal thing.jid, 'thing@clayster.com'
            test.equal thing.properties.length, 4

            return Q.fcall ->
                throw new Error('not-found')

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.13 - example 31 and 35 - update meta data request fails
    because of disowned Thing': (test) ->
        message = "<iq type='set'
               from='thing@clayster.com/imc'
               to='discovery.clayster.com'
               id='8'>
              <update xmlns='urn:xmpp:iot:discovery'>
                  <str name='KEY' value=''/>
                  <str name='CLASS' value='PLC'/>
                  <num name='LON' value='-71.519722'/>
                  <num name='LAT' value='-33.008055'/>
              </update>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '8'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children.length, 1
            test.equal stanza.children[0].name, 'disowned'
            test.equal stanza.children[0].attrs.xmlns,
                'urn:xmpp:iot:discovery'
            test.expect 11
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'update'
            test.equal thing.jid, 'thing@clayster.com'
            test.equal thing.properties.length, 4

            return Q.fcall ->
                throw new Error('disowned')

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.13 - example 36 and 38 - update meta data request by the owner': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/imc'
               to='discovery.clayster.com'
               id='8'>
              <update xmlns='urn:xmpp:iot:discovery' jid='thing@clayster.com'>
                  <str name='KEY' value=''/>
                  <str name='CLASS' value='PLC'/>
                  <num name='LON' value='-71.519722'/>
                  <num name='LAT' value='-33.008055'/>
              </update>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'owner@clayster.com/imc'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '8'
            test.equal stanza.attrs.from, 'class-under-test'
            test.expect 13
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'update'
            test.equal thing.jid, 'thing@clayster.com'
            test.equal thing.properties.length, 4
            test.equal thing.owner, 'owner@clayster.com'

            for property in thing.properties
                switch property.name
                    when 'KEY'
                        test.equal property.type, 'string'
                        test.equal property.value, ''
                    when 'LAT'
                        test.equal property.type, 'number'
                        test.equal property.value, -33.008055

            return Q.fcall ->
                return

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)


    'test 3.14 - example 36 - searching for Things [strEq & numEq]': (test) ->
        message = "<iq type='get'
               from='curious@clayster.com/client'
               to='discovery.clayster.com'
               id='9'>
              <search xmlns='urn:xmpp:iot:discovery' offset='0' maxCount='20'>
                  <strEq name='MAN' value='www.ktc.se'/>
                  <strEq name='MODEL' value='IMC'/>
                  <numEq name='V' value='1'/>
              </search>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'curious@clayster.com/client'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '9'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children.length, 1
            test.equal stanza.children[0].name, 'found'
            test.equal stanza.children[0].attrs.xmlns, 'urn:xmpp:iot:discovery'
            test.equal stanza.children[0].attrs.more, false
            test.equal stanza.children[0].children.length, 1
            thing = stanza.children[0].children[0]
            test.equal thing.name, 'thing'
            test.equal thing.attrs.owner, 'owner@clayster.com'
            test.equal thing.attrs.jid, 'thing@clayster.com'
            test.equal thing.children.length, 3 # should not contain KEY
            test.equal thing.attrs.nodeId, undefined
            test.equal thing.attrs.sourceId, undefined
            test.equal thing.attrs.cacheType, undefined

            for child in thing.children
                test.equal child.attrs.name is 'KEY', false

            test.expect 24
            test.done()

        backend = new TestBackend (method, filters, offset, maxCount) ->
            test.equal method, 'search'
            test.equal filters.length, 3
            test.equal offset, 0
            test.equal maxCount, 20

            properties = []
            properties.push new Property('string', 'KEY', 'doesnottellthis')
            properties.push new Property('string', 'MAN', 'www.ktc.se')
            properties.push new Property('string', 'MODEL', 'IMC')
            properties.push new Property('string', 'V', 1)

            found = new Thing 'thing@clayster.com', properties
            found.owner = 'owner@clayster.com'

            result = {
                things: [ found ]
                more: false
            }

            return Q.fcall ->
                return result

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.14 - example 42 - searching for Things [strEq & numEq]': (test) ->
        message = "<iq type='get'
               from='curious@clayster.com/client'
               to='discovery.clayster.com'
               id='9'>
              <search xmlns='urn:xmpp:iot:discovery' offset='1' maxCount='10'>
                  <strEq name='MAN' value='www.ktc.se'/>
                  <strEq name='MODEL' value='IMC'/>
                  <numEq name='V' value='1'/>
              </search>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'curious@clayster.com/client'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '9'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children.length, 1
            test.equal stanza.children[0].name, 'found'
            test.equal stanza.children[0].attrs.xmlns, 'urn:xmpp:iot:discovery'
            test.equal stanza.children[0].attrs.more, true
            test.equal stanza.children[0].children.length, 1
            thing = stanza.children[0].children[0]
            test.equal thing.name, 'thing'
            test.equal thing.attrs.owner, 'owner@clayster.com'
            test.equal thing.attrs.jid, 'thing@clayster.com'
            test.equal thing.attrs.nodeId, 'imc1'
            test.equal thing.attrs.sourceId, 'MeteringTopology'
            test.equal thing.attrs.cacheType, 'typedCache'
            test.equal thing.children.length, 3 # should not contain KEY

            for child in thing.children
                test.equal child.attrs.name is 'KEY', false

            test.expect 24
            test.done()

        backend = new TestBackend (method, filters, offset, maxCount) ->
            test.equal method, 'search'
            test.equal filters.length, 3
            test.equal offset, 1
            test.equal maxCount, 10

            properties = []
            properties.push new Property('string', 'KEY', 'doesnottellthis')
            properties.push new Property('string', 'MAN', 'www.ktc.se')
            properties.push new Property('string', 'MODEL', 'IMC')
            properties.push new Property('string', 'V', 1)

            found = new Thing 'thing@clayster.com', properties
            found.owner = 'owner@clayster.com'
            found.nodeId = 'imc1'
            found.sourceId = 'MeteringTopology'
            found.cacheType = 'typedCache'

            result = {
                things: [ found ]
                more: true
            }

            return Q.fcall ->
                return result

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.14 - example 42 - searching for Things [strRange & strNRange & strMask & numRange & numNRange]': (test) ->
        message = "<iq type='get'
               from='curious@clayster.com/client'
               to='discovery.clayster.com'
               id='9'>
              <search xmlns='urn:xmpp:iot:discovery' offset='1' maxCount='10'>
                  <strRange name='MAN' minIncluded='false' maxIncluded='false' min='A' max='B'/>
                  <strNRange name='MAN' min='A' max='B'/>
                  <strMask name='MAN' value='bla*' wildcard='*'/>
                  <numRange name='V' min='1' max='2'/>
                  <numNRange name='V' min='1' max='2'/>
              </search>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'curious@clayster.com/client'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '9'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children.length, 1
            test.equal stanza.children[0].name, 'found'
            test.equal stanza.children[0].attrs.xmlns, 'urn:xmpp:iot:discovery'
            test.equal stanza.children[0].attrs.more, true
            test.equal stanza.children[0].children.length, 1
            thing = stanza.children[0].children[0]
            test.equal thing.name, 'thing'
            test.equal thing.attrs.owner, 'owner@clayster.com'
            test.equal thing.attrs.jid, 'thing@clayster.com'
            test.equal thing.attrs.nodeId, 'imc1'
            test.equal thing.attrs.sourceId, 'MeteringTopology'
            test.equal thing.attrs.cacheType, 'typedCache'
            test.equal thing.children.length, 3 # should not contain KEY

            for child in thing.children
                test.equal child.attrs.name is 'KEY', false

            test.expect 44
            test.done()

        backend = new TestBackend (method, filters, offset, maxCount) ->
            test.equal method, 'search'
            test.equal filters.length, 5
            test.equal offset, 1
            test.equal maxCount, 10

            for filter in filters
                if filter.type is 'strRange'
                    test.equal filter.name, 'MAN'
                    test.equal filter.min, 'A'
                    test.equal filter.max, 'B'
                    test.equal filter.minIncluded, false
                    test.equal filter.maxIncluded, false
                    test.equal filter.value, undefined

                if filter.type is 'strNRange'
                    test.equal filter.name, 'MAN'
                    test.equal filter.min, 'A'
                    test.equal filter.max, 'B'
                    test.equal filter.minIncluded, true
                    test.equal filter.maxIncluded, true

                if filter.type is 'strMask'
                    test.equal filter.name, 'MAN'
                    test.equal filter.value, 'bla*'
                    test.equal filter.wildcard, '*'

                if filter.type is 'numRange'
                    test.equal filter.name, 'V'
                    test.equal filter.min, '1'
                    test.equal filter.max, '2'

                if filter.type is 'numNRange'
                    test.equal filter.name, 'V'
                    test.equal filter.min, '1'
                    test.equal filter.max, '2'

            properties = []
            properties.push new Property('string', 'KEY', 'doesnottellthis')
            properties.push new Property('string', 'MAN', 'www.ktc.se')
            properties.push new Property('string', 'MODEL', 'IMC')
            properties.push new Property('string', 'V', 1)

            found = new Thing 'thing@clayster.com', properties
            found.owner = 'owner@clayster.com'
            found.nodeId = 'imc1'
            found.sourceId = 'MeteringTopology'
            found.cacheType = 'typedCache'

            result = {
                things: [ found ]
                more: true
            }

            return Q.fcall ->
                return result

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.14 - cannot search for KEY': (test) ->
        message = "<iq type='get'
               from='curious@clayster.com/client'
               to='discovery.clayster.com'
               id='9'>
              <search xmlns='urn:xmpp:iot:discovery' offset='0' maxCount='20'>
                  <strEq name='KEY' value='1234'/>
              </search>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'curious@clayster.com/client'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '9'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children.length, 1
            test.equal stanza.children[0].name, 'found'
            test.equal stanza.children[0].attrs.xmlns, 'urn:xmpp:iot:discovery'
            test.equal stanza.children[0].children.length, 0

            test.expect 9
            test.done()

        processor = new Processor connection
        connection.emit 'stanza', ltx.parse(message)

     'test 3.14 - cannot search with illegal offset': (test) ->
        message = "<iq type='get'
               from='curious@clayster.com/client'
               to='discovery.clayster.com'
               id='9'>
              <search xmlns='urn:xmpp:iot:discovery' offset='aap' maxCount='20'>
                  <strEq name='KEY' value='1234'/>
              </search>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'curious@clayster.com/client'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.id, '9'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children.length, 0

            test.expect 6
            test.done()

        processor = new Processor connection
        connection.emit 'stanza', ltx.parse(message)

     'test 3.14 - cannot search without offset': (test) ->
        message = "<iq type='get'
               from='curious@clayster.com/client'
               to='discovery.clayster.com'
               id='9'>
              <search xmlns='urn:xmpp:iot:discovery' maxCount='20'>
                  <strEq name='KEY' value='1234'/>
              </search>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'curious@clayster.com/client'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.id, '9'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children.length, 0

            test.expect 6
            test.done()

        processor = new Processor connection
        connection.emit 'stanza', ltx.parse(message)

    'test 3.14 - cannot search without maxCount': (test) ->
        message = "<iq type='get'
               from='curious@clayster.com/client'
               to='discovery.clayster.com'
               id='9'>
              <search xmlns='urn:xmpp:iot:discovery' offset='0'>
                  <strEq name='KEY' value='1234'/>
              </search>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'curious@clayster.com/client'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.id, '9'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children.length, 0

            test.expect 6
            test.done()

        processor = new Processor connection
        connection.emit 'stanza', ltx.parse(message)

     'test 3.14 - cannot search with illegal maxCount': (test) ->
        message = "<iq type='get'
               from='curious@clayster.com/client'
               to='discovery.clayster.com'
               id='9'>
              <search xmlns='urn:xmpp:iot:discovery' offset='0' maxCount='aap'>
                  <strEq name='KEY' value='1234'/>
              </search>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'curious@clayster.com/client'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.id, '9'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children.length, 0

            test.expect 6
            test.done()

        processor = new Processor connection
        connection.emit 'stanza', ltx.parse(message)


    'test 3.14 - cannot search for unsupported filter type': (test) ->
        message = "<iq type='get'
               from='curious@clayster.com/client'
               to='discovery.clayster.com'
               id='9'>
              <search xmlns='urn:xmpp:iot:discovery' offset='0' maxCount='20'>
                  <notAFilter name='MAN' value='1234'/>
              </search>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'curious@clayster.com/client'
            test.equal stanza.attrs.type, 'error'
            test.equal stanza.attrs.id, '9'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.children.length, 1
            test.equal stanza.children[0].name, 'error'
            test.equal stanza.children[0].attrs.type, 'cancel'
            test.equal stanza.children[0].children.length, 1
            test.equal stanza.children[0].children[0].name,
                'feature-not-implemented'
            test.equal stanza.children[0].children[0].attrs.xmlns,
                'urn:ietf:params:xml:ns:xmpp-stanzas'

            test.expect 14
            test.done()

        backend = new TestBackend (method, filters, offset, maxCount) ->
            test.equal method, 'search'
            test.equal filters.length, 1
            test.equal filters[0].type, 'notAFilter'

            return Q.fcall ->
                throw new Error 'feature-not-implemented'

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 4 - example 60 - determine support': (test) ->
        message = "<iq type='get'
               from='device@clayster.com/device'
               to='discovery.clayster.com'
               id='16'>
              <query xmlns='http://jabber.org/protocol/disco#info'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'device@clayster.com/device'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.attrs.id, '16'
            test.equal stanza.children.length, 1
            test.equal stanza.children[0].name, 'query'
            test.equal stanza.children[0].attrs.xmlns, 'http://jabber.org/protocol/disco#info'
            test.equal stanza.children[0].children.length, 1
            features = stanza.children[0].children
            test.equal features[0].name, 'feature'
            test.equal features[0].attrs.var, 'urn:xmpp:iot:discovery'
            test.expect 10
            test.done()

        processor = new Processor connection
        connection.emit 'stanza', ltx.parse(message)

    'test 3.16 - example 43 - unregister thing': (test) ->
        message = "<iq type='set'
               from='thing@clayster.com/imc'
               to='discovery.clayster.com'
               id='10'>
              <unregister xmlns='urn:xmpp:iot:discovery'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.attrs.id, '10'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.children.length, 0
            test.expect 8
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'unregister'
            test.equal thing.jid, 'thing@clayster.com'

            return Q.fcall ->
                return thing

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.16 - example 43 - unregister thing fails': (test) ->
        message = "<iq type='set'
               from='thing@clayster.com/imc'
               to='discovery.clayster.com'
               id='10'>
              <unregister xmlns='urn:xmpp:iot:discovery'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.attrs.id, '10'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.children.length, 0
            test.expect 8
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'unregister'
            test.equal thing.jid, 'thing@clayster.com'

            return Q.fcall ->
                return new Error

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.16 - example 44 - unregister thing behind a concentrator': (test) ->
        message = "<iq type='set'
               from='thing@clayster.com/imc'
               to='discovery.clayster.com'
               id='10'>
              <unregister xmlns='urn:xmpp:iot:discovery' nodeId='imc1' sourceId='MeteringTopology'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            test.equal stanza.name, 'iq'
            test.equal stanza.attrs.to, 'thing@clayster.com/imc'
            test.equal stanza.attrs.from, 'class-under-test'
            test.equal stanza.attrs.id, '10'
            test.equal stanza.attrs.type, 'result'
            test.equal stanza.children.length, 0
            test.expect 10
            test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'unregister'
            test.equal thing.jid, 'thing@clayster.com'
            test.equal thing.nodeId, 'imc1'
            test.equal thing.sourceId, 'MeteringTopology'

            return Q.fcall ->
                return thing

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.17 - example 46 / 48 - disowning thing fails: item not found': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='11'>
              <disown xmlns='urn:xmpp:iot:discovery' jid='thing@clayster.com'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            if stanza.name is 'iq'
                test.equal stanza.attrs.to, 'owner@clayster.com/phone'
                test.equal stanza.attrs.from, 'class-under-test'
                test.equal stanza.attrs.id, '11'
                test.equal stanza.attrs.type, 'error'
                test.equal stanza.children.length, 1

                error = stanza.children[0]
                test.equal error.name, 'error'
                test.equal error.attrs.type, 'cancel'
                test.equal error.children.length, 1
                test.equal error.children[0].name, 'item-not-found'
                test.equal error.children[0].attrs.xmlns, 'urn:ietf:params:xml:ns:xmpp-stanzas'

                test.expect 12
                test.done()

        backend = new TestBackend (method, thing) ->
            test.equal method, 'get'
            test.equal thing.jid, 'thing@clayster.com'

            return Q.fcall ->
                return [ ]

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.17 - example 46 / 48 - disowning thing fails: not the owner': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='11'>
              <disown xmlns='urn:xmpp:iot:discovery' jid='thing@clayster.com'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            if stanza.name is 'iq'
                # as the backend should not return items not owned
                # by the owner this test case validates what happens
                # if the backend is not implemented correctly and
                # accidently returns an item that is not owned by
                # the caller
                test.equal stanza.attrs.to, 'owner@clayster.com/phone'
                test.equal stanza.attrs.from, 'class-under-test'
                test.equal stanza.attrs.id, '11'
                test.equal stanza.attrs.type, 'error'
                test.equal stanza.children.length, 0

                test.expect 7
                test.done()
            else
                test.equal true, false, 'should not call this'

        backend = new TestBackend (method, thing) ->
            test.equal method, 'get'
            test.equal thing.jid, 'thing@clayster.com'

            result = new Thing thing.jid
            result.owner = 'not the owner'

            return Q.fcall ->
                return [ result ]

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.17 - example 46 / 49 - disowning thing fails: offline': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='11'>
              <disown xmlns='urn:xmpp:iot:discovery' jid='thing@clayster.com'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            if stanza.name is 'iq'
                test.equal stanza.attrs.to, 'owner@clayster.com/phone'
                test.equal stanza.attrs.from, 'class-under-test'
                test.equal stanza.attrs.id, '11'
                test.equal stanza.attrs.type, 'error'
                test.equal stanza.children.length, 1

                error = stanza.children[0]
                test.equal error.name, 'error'
                test.equal error.attrs.type, 'cancel'
                test.equal error.children.length, 1
                test.equal error.children[0].name, 'not-allowed'
                test.equal error.children[0].attrs.xmlns, 'urn:ietf:params:xml:ns:xmpp-stanzas'

                test.expect 17
                test.done()
            else
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.type, 'probe'
                test.equal stanza.attrs.to, 'thing@clayster.com'
                test.equal stanza.attrs.from, 'class-under-test'

                response = "<presence
                    from='thing@clayster.com/imc'
                    to='discovery.clayster.com'
                    id='123'
                    type='unavailable'/>"

                connection.emit 'stanza', ltx.parse(response)

        backend = new TestBackend (method, thing) ->
            test.equal method, 'get'
            test.equal thing.jid, 'thing@clayster.com'
            test.equal thing.owner, 'owner@clayster.com'

            return Q.fcall ->
                return [ thing ]

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.17 - example 46 / 50 / 52 / 53 - disowning thing successful': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='11'>
              <disown xmlns='urn:xmpp:iot:discovery' jid='thing@clayster.com'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            if stanza.name is 'iq'
                if stanza.attrs.to is 'thing@clayster.com/imc'
                    test.equal stanza.attrs.from, 'class-under-test'
                    test.equal stanza.attrs.type, 'set'
                    test.equal stanza.children.length, 1
                    test.equal stanza.children[0].name, 'disowned'
                    test.equal stanza.children[0].attrs.xmlns, 'urn:xmpp:iot:discovery'

                    response = "<iq type='result'
                        from='discovery.clayster.com'
                        to='discovery.clayster.com'
                        id='#{ stanza.attrs.id }'/>"

                    connection.emit 'stanza', ltx.parse(response)
                else
                    test.equal stanza.attrs.to, 'owner@clayster.com/phone'
                    test.equal stanza.attrs.from, 'class-under-test'
                    test.equal stanza.attrs.id, '11'
                    test.equal stanza.attrs.type, 'result'
                    test.expect 26
                    test.done()
            else
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.type, 'probe'
                test.equal stanza.attrs.to, 'thing@clayster.com'
                test.equal stanza.attrs.from, 'class-under-test'

                response = "<presence
                    from='thing@clayster.com/imc'
                    to='discovery.clayster.com'
                    id='#{ stanza.attrs.id }'
                    type='available'/>"

                connection.emit 'stanza', ltx.parse(response)

        backend = new TestBackend (method, thing) ->
            if method is 'get'
                test.equal thing.jid, 'thing@clayster.com'

                properties = []
                properties.push new Property('string', 'KEY', 'mysecret')
                properties.push new Property('string', 'MAN', 'www.ktc.se')
                properties.push new Property('string', 'MODEL', 'IMC')
                properties.push new Property('number', 'V', 1)

                thing.properties = properties
                thing.owner = 'owner@clayster.com'

                return Q.fcall ->
                    return [ thing ]
            else
                test.equal method, 'update'
                test.equal thing.jid, 'thing@clayster.com'
                test.equal thing.owner, undefined
                test.equal thing.properties.length, 4

                for property in thing.properties
                    if property.name is 'KEY'
                        test.notEqual property.value, 'mysecret'
                    else
                        test.equal property.type, 'string', 'changed in string
                            so it can be removed from the registry'
                        test.equal property.value, ''

                return Q.fcall ->
                    return [ thing ]

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.17 - example 46 / 50 / 52 / 53 - disowning thing successfully
            behind a concentrator': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='11'>
              <disown xmlns='urn:xmpp:iot:discovery'
                      jid='thing@clayster.com'
                      nodeId='imcl'
                      sourceId='MeteringTopology'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            if stanza.name is 'iq'
                if stanza.attrs.to is 'thing@clayster.com/imc'
                    test.equal stanza.attrs.from, 'class-under-test'
                    test.equal stanza.attrs.type, 'set'
                    test.equal stanza.children.length, 1
                    test.equal stanza.children[0].name, 'disowned'
                    test.equal stanza.children[0].attrs.nodeId, 'imcl'
                    test.equal stanza.children[0].attrs.sourceId, 'MeteringTopology'
                    test.equal stanza.children[0].attrs.xmlns, 'urn:xmpp:iot:discovery'

                    response = "<iq type='result'
                        from='discovery.clayster.com'
                        to='discovery.clayster.com'
                        id='#{ stanza.attrs.id }'/>"

                    connection.emit 'stanza', ltx.parse(response)
                else
                    test.equal stanza.attrs.to, 'owner@clayster.com/phone'
                    test.equal stanza.attrs.from, 'class-under-test'
                    test.equal stanza.attrs.id, '11'
                    test.equal stanza.attrs.type, 'result'
                    test.expect 21
                    test.done()
            else
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.type, 'probe'
                test.equal stanza.attrs.to, 'thing@clayster.com'
                test.equal stanza.attrs.from, 'class-under-test'

                response = "<presence
                    from='thing@clayster.com/imc'
                    to='discovery.clayster.com'
                    id='#{ stanza.attrs.id }'
                    type='available'/>"

                connection.emit 'stanza', ltx.parse(response)

        backend = new TestBackend (method, thing) ->
            if method is 'get'
                test.equal thing.jid, 'thing@clayster.com'

                properties = []
                properties.push new Property('string', 'KEY', 'mysecret')
                properties.push new Property('string', 'MAN', 'www.ktc.se')
                properties.push new Property('string', 'MODEL', 'IMC')
                properties.push new Property('string', 'V', 1)

                thing.properties = properties
                thing.owner = 'owner@clayster.com'
                thing.nodeId = 'imcl'
                thing.sourceId = 'MeteringTopology'

                return Q.fcall ->
                    return [ thing ]
            else
                test.equal method, 'update'
                test.equal thing.jid, 'thing@clayster.com'
                test.equal thing.owner, undefined
                test.equal thing.properties.length, 4

                return Q.fcall ->
                    return thing

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.17 - example 46 / 50 / 52 / 53 - disowning thing fails, unexpected response': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='11'>
              <disown xmlns='urn:xmpp:iot:discovery' jid='thing@clayster.com'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            if stanza.name is 'iq'
                if stanza.attrs.to is 'thing@clayster.com/imc'
                    test.equal stanza.attrs.from, 'class-under-test'
                    test.equal stanza.attrs.type, 'set'
                    test.equal stanza.children.length, 1
                    test.equal stanza.children[0].name, 'disowned'
                    test.equal stanza.children[0].attrs.xmlns, 'urn:xmpp:iot:discovery'

                    response = "<iq type='error'
                        from='discovery.clayster.com'
                        to='discovery.clayster.com'
                        id='#{ stanza.attrs.id }'/>"

                    connection.emit 'stanza', ltx.parse(response)
                else
                    test.equal stanza.attrs.to, 'owner@clayster.com/phone'
                    test.equal stanza.attrs.from, 'class-under-test'
                    test.equal stanza.attrs.id, '11'
                    test.equal stanza.attrs.type, 'error'
                    test.expect 15
                    test.done()
            else
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.type, 'probe'
                test.equal stanza.attrs.to, 'thing@clayster.com'
                test.equal stanza.attrs.from, 'class-under-test'

                response = "<presence
                    from='thing@clayster.com/imc'
                    to='discovery.clayster.com'
                    id='#{ stanza.attrs.id }'
                    type='available'/>"

                connection.emit 'stanza', ltx.parse(response)

        backend = new TestBackend (method, thing) ->
            if method is 'get'
                test.equal thing.jid, 'thing@clayster.com'

                properties = []
                properties.push new Property('string', 'KEY', 'mysecret')
                properties.push new Property('string', 'MAN', 'www.ktc.se')
                properties.push new Property('string', 'MODEL', 'IMC')
                properties.push new Property('string', 'V', 1)

                thing.properties = properties
                thing.owner = 'owner@clayster.com'

                return Q.fcall ->
                    return [ thing ]
            else
                test.equal true, false, 'should not update'
                test.done()

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

    'test 3.17 - example 46 / 50 / 52 / 53 - disowning thing fails because of backend': (test) ->
        message = "<iq type='set'
               from='owner@clayster.com/phone'
               to='discovery.clayster.com'
               id='11'>
              <disown xmlns='urn:xmpp:iot:discovery' jid='thing@clayster.com'/>
           </iq>"

        connection = new Connection
        connection.send = (stanza) ->
            if stanza.name is 'iq'
                if stanza.attrs.to is 'thing@clayster.com/imc'
                    test.equal stanza.attrs.from, 'class-under-test'
                    test.equal stanza.attrs.type, 'set'
                    test.equal stanza.children.length, 1
                    test.equal stanza.children[0].name, 'disowned'
                    test.equal stanza.children[0].attrs.xmlns, 'urn:xmpp:iot:discovery'

                    response = "<iq type='result'
                        from='discovery.clayster.com'
                        to='discovery.clayster.com'
                        id='#{ stanza.attrs.id }'/>"

                    connection.emit 'stanza', ltx.parse(response)
                else
                    test.equal stanza.attrs.to, 'owner@clayster.com/phone'
                    test.equal stanza.attrs.from, 'class-under-test'
                    test.equal stanza.attrs.id, '11'
                    test.equal stanza.attrs.type, 'error'
                    test.expect 16
                    test.done()
            else
                test.equal stanza.name, 'presence'
                test.equal stanza.attrs.type, 'probe'
                test.equal stanza.attrs.to, 'thing@clayster.com'
                test.equal stanza.attrs.from, 'class-under-test'

                response = "<presence
                    from='thing@clayster.com/imc'
                    to='discovery.clayster.com'
                    id='#{ stanza.attrs.id }'
                    type='available'/>"

                connection.emit 'stanza', ltx.parse(response)

        backend = new TestBackend (method, thing) ->
            if method is 'get'
                test.equal thing.jid, 'thing@clayster.com'

                properties = []
                properties.push new Property('string', 'KEY', 'mysecret')
                properties.push new Property('string', 'MAN', 'www.ktc.se')
                properties.push new Property('string', 'MODEL', 'IMC')
                properties.push new Property('number', 'V', 1)

                thing.properties = properties
                thing.owner = 'owner@clayster.com'

                return Q.fcall ->
                    return [ thing ]
            else
                test.equal method, 'update'

                return Q.fcall ->
                    throw new Error()

        processor = new Processor connection, backend
        connection.emit 'stanza', ltx.parse(message)

# more test cases:
# - test offset and maxcount
# - test logging for unknown property type

