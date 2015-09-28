# Tests if the server component complies to
# https://xmpp.org/extensions/xep-0347.html
#
# Some test cases refer to paragraphs and / or examples from the spec.

{EventEmitter} = require 'events'

OctobluBackend = require '../src/octoblu-backend.coffee'
Thing = require '../src/thing.coffee'
Property = require '../src/property.coffee'
Filter = require '../src/filter.coffee'

Q = require 'q'
_ = require 'lodash'

class OctobluStub
    constructor: (@connection) ->

    createConnection: (opts) ->
        return @connection

exports.OctobluBackendTest =
    'test register test if preconditions are not met': (test) ->
        properties = [ new Property('type', 'name', 'value') ]
        thing = new Thing('jid', properties)

        class ConnectionStub extends EventEmitter
            constructor: ->

        class OptionTestStub extends OctobluStub
            createConnection: (opts) ->
                test.equal opts.server, 'test'
                test.equal opts.port, 666
                test.equal opts.uuid, 'user'
                test.equal opts.token, 'pass'
                super opts

        opts = {
            uuid: 'user'
            token: 'pass'
        }

        connection = new ConnectionStub()

        target = new OctobluBackend 'test', 666,
            opts,
            undefined,
            new OptionTestStub(connection)

        promise = target.register thing

        onSuccess = (thing) ->
            test.equal true, false

        onFail = (err) ->
            test.equal err.message, 'Missing property: KEY'
            test.expect 5
            test.done()

        promise.then onSuccess, onFail

    'test register test if reserved words are used': (test) ->
        properties = [
            new Property 'type', 'KEY', 'value'
            new Property 'type', 'xmpp_nodeId', 'value'
        ]

        thing = new Thing('jid', properties)

        class ConnectionStub extends EventEmitter
            constructor: ->

        connection = new ConnectionStub()

        target = new OctobluBackend undefined, undefined, {},
            undefined,
            new OctobluStub(connection)

        promise = target.register thing

        onSuccess = (thing) ->
            test.equal true, false

        onFail = (err) ->
            test.equal err.message, 'Illegal property: xmpp_nodeId'
            test.expect 1
            test.done()

        promise.then onSuccess, onFail

    'test register hash value': (test) ->
        properties = [
            new Property 'string', 'KEY', 'value'
        ]

        thing = new Thing('jid', properties)
        thing.nodeId = 'nodeId'
        thing.sourceId = 'sourceId'
        thing.cacheType = 'cacheType'

        class ConnectionStub extends EventEmitter
            constructor: ->

            register: (data, cb) ->
                test.equal data.uuid, '582b91b44e49a038a607f09e0d12cc61'
                test.equal data.token, 'value'

                result = {
                    xmpp_jid: thing.jid
                    xmpp_nodeId: thing.nodeId
                    xmpp_sourceId: thing.sourceId
                    xmpp_cacheType: thing.cacheType
                    uuid: data.uuid
                    token: data.token
                }

                cb result

            devices: (data, cb) ->
                test.equal data.uuid, '582b91b44e49a038a607f09e0d12cc61'
                cb { devices: [] }

        connection = new ConnectionStub()

        target = new OctobluBackend undefined, undefined, {},
            undefined,
            new OctobluStub(connection)

        promise = target.register thing

        onSuccess = (thing) ->
            test.equal thing.uuid, '582b91b44e49a038a607f09e0d12cc61'
            test.equal thing.token, 'value'
            test.expect 5
            test.done()

        onFail = (err) ->
            test.expect false, true

        promise.then onSuccess, onFail

    'test no backend account': (test) ->
        properties = [
            new Property 'string', 'KEY', 'value'
        ]

        thing = new Thing('jid', properties)

        class ConnectionStub extends EventEmitter
            constructor: ->

            register: (data, cb) ->
                if data.uuid is 'user'
                    test.equal data.token, 'pass'
                else
                    test.equal data.token, 'value'

                cb data

            devices: (data, cb) ->
                cb { devices: [] }

        connection = new ConnectionStub()

        opts = {
            uuid: 'user'
            token: 'pass'
        }

        target = new OctobluBackend 'test', 666, opts,
            undefined,
            new OctobluStub(connection)

        connection.emit 'notReady'

        promise = target.register thing

        onSuccess = (thing) ->
            test.equal thing.token, 'value'
            test.equal thing.uuid, '3d4478eb8cae476e97eacd52aa1cca16'
            test.expect 4
            test.done()

        onFail = (err) ->
            test.expect false, true

        promise.then onSuccess, onFail

    'test registration of the backend account failed': (test) ->
        properties = [
            new Property 'string', 'KEY', 'value'
        ]

        thing = new Thing('jid', properties)

        class ConnectionStub extends EventEmitter
            constructor: ->

            register: (data, cb) ->
                test.equal data.uuid, 'user'
                test.equal data.token, 'pass'
                test.throws () ->
                    cb { }

                test.done()

            devices: (data, cb) ->
                cb []

        connection = new ConnectionStub()

        opts = {
            uuid: 'user'
            token: 'pass'
        }

        target = new OctobluBackend 'test', 666, opts,
            undefined,
            new OctobluStub(connection)

        connection.emit 'notReady'

    'test thing already registered': (test) ->
        properties = [
            new Property 'string', 'KEY', 'value'
        ]

        thing = new Thing('jid', properties)

        class ConnectionStub extends EventEmitter
            constructor: ->

            register: (data, cb) ->
                cb data

            devices: (data, cb) ->
                result = {
                    devices: [ { uuid: data.uuid } ]
                }

                cb result

            unregister: (data, cb) ->
                test.equal data.uuid, '3d4478eb8cae476e97eacd52aa1cca16'
                cb data

        connection = new ConnectionStub()

        opts = {
            uuid: 'user'
            token: 'pass'
        }

        target = new OctobluBackend 'test', 666, opts,
            undefined,
            new OctobluStub(connection)

        connection.emit 'notReady'

        promise = target.register thing

        onSuccess = (thing) ->
            test.equal thing.token, 'value'
            test.equal thing.uuid, '3d4478eb8cae476e97eacd52aa1cca16'
            test.expect 3
            test.done()

        onFail = (err) ->
            test.expect false, true

        promise.then onSuccess, onFail

    'test thing already registered and owned': (test) ->
        properties = [
            new Property 'string', 'KEY', 'value'
        ]

        thing = new Thing('jid', properties)

        class ConnectionStub extends EventEmitter
            constructor: ->

            register: (data, cb) ->
                cb data

            devices: (data, cb) ->
                result = {
                    devices: [ { uuid: data.uuid, xmpp_owner: 'owner' } ]
                }

                cb result

        connection = new ConnectionStub()

        target = new OctobluBackend undefined, undefined, {},
            undefined,
            new OctobluStub(connection)

        connection.emit 'ready'

        promise = target.register thing

        onSuccess = (thing) ->
            test.equal true, false, 'should not hit this line'

        onFail = (err) ->
            test.equal err.message, 'claimed'
            test.equal err.owner, 'owner'
            test.expect 2
            test.done()

        promise.then onSuccess, onFail

    'test thing unregister fails': (test) ->
        properties = [
            new Property 'string', 'KEY', 'value'
        ]

        thing = new Thing('jid', properties)

        class ConnectionStub extends EventEmitter
            constructor: ->

            register: (data, cb) ->
                cb data

            devices: (data, cb) ->
                result = {
                    devices: [ { uuid: data.uuid } ]
                }

                cb result

            unregister: (data, cb) ->
                cb { name: 'error' }

        connection = new ConnectionStub()

        target = new OctobluBackend undefined, undefined, {},
            undefined,
            new OctobluStub(connection)

        connection.emit 'ready'

        promise = target.register thing

        onSuccess = (thing) ->
            test.equal true, false, 'should not hit this line'

        onFail = (err) ->
            test.equal err.message, 'unregister failed'
            test.expect 1
            test.done()

        promise.then onSuccess, onFail

    'test register thing: multiple matching things found in the registry': (test) ->
        properties = [
            new Property 'string', 'KEY', 'value'
        ]

        thing = new Thing('jid', properties)

        class ConnectionStub extends EventEmitter
            constructor: ->

            register: (data, cb) ->
                cb data

            devices: (data, cb) ->
                result = {
                    devices: [ {}, {} ]
                }

                cb result

        connection = new ConnectionStub()

        target = new OctobluBackend undefined, undefined, {},
            undefined,
            new OctobluStub(connection)

        connection.emit 'ready'

        promise = target.register thing

        onSuccess = (thing) ->
            test.equal true, false, 'should not hit this line'

        onFail = (err) ->
            test.done()

        promise.then onSuccess, onFail

    'test claim ownership: success case' : (test) ->
        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'monkey', 'boy'
        ]

        thing = new Thing('jid', properties)
        thing.owner = 'owner'
        thing.needsNotification = true

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal _.has(data, 'xmpp_owner'), false

                result = {
                    devices: [ data ]
                }

                cb result

            update: (data, cb) ->
                test.equal data.xmpp_owner, 'owner'
                cb data

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        promise = target.claim thing

        onSuccess = (thing) ->
            test.equal thing.owner, 'owner'
            test.expect 3
            test.done()

        onFail = (err) ->
            test.equal true, false, 'should not get here'

        promise.then onSuccess, onFail

    'test claim ownership: device not found' : (test) ->
        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'monkey', 'boy'
        ]

        thing = new Thing('jid', properties)
        thing.owner = 'owner'

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal _.has(data, 'xmpp_owner'), false

                result = {
                    devices: [ ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 1, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        promise = target.claim thing

        onSuccess = (thing) ->
            test.equal true, false, 'should not get here'

        onFail = (err) ->
            test.equal err.message, 'not-found'
            test.expect 2
            test.done()

        promise.then onSuccess, onFail

    'test claim ownership: device already owned' : (test) ->
        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'monkey', 'boy'
        ]

        thing = new Thing('jid', properties)
        thing.owner = 'owner'

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal _.has(data, 'xmpp_owner'), false
                data.xmpp_owner = 'taken'
                result = {
                    devices: [ data ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        promise = target.claim thing

        onSuccess = (thing) ->
            test.equal true, false, 'should not get here'

        onFail = (err) ->
            test.equal err.message, 'claimed'
            test.expect 2
            test.done()

        promise.then onSuccess, onFail

    'test claim ownership: multiple results' : (test) ->
        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'monkey', 'boy'
        ]

        thing = new Thing('jid', properties)
        thing.owner = 'owner'

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal _.has(data, 'xmpp_owner'), false
                result = {
                    devices: [ {}, {} ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        promise = target.claim thing

        onSuccess = (thing) ->
            test.equal true, false, 'should not get here'

        onFail = (err) ->
            test.equal err.message, 'illegal state'
            test.expect 2
            test.done()

        promise.then onSuccess, onFail

    'test search: multiple results' : (test) ->
        thing1 = {
            KEY: '123'
            monkey: 'boy'
            ROOM: '101'
            xmpp_jid: 'jid1'
            xmpp_owner: 'owner1'
        }

        thing2 = {
            KEY: '456'
            monkey: 'island'
            ROOM: '101'
            xmpp_jid: 'jid2'
            xmpp_owner: 'owner2'
        }

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal _.has(data, 'ROOM'), true
                test.equal data.ROOM, '101'
                result = {
                    devices: [ thing1, thing2 ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        searchFilters = [
            new Filter 'strEq', 'ROOM', '101'
        ]

        promise = target.search searchFilters

        test.expect 6

        onSuccess = (result) ->
            things = result.things

            test.equal things.length, 2
            test.equal things[0].nodeId, undefined
            test.equal things[0].sourceId, undefined
            test.equal things[0].cacheType, undefined
            test.done()

        onFail = (err) ->
            test.done()

        promise.then onSuccess, onFail

    'test search: multiple results behing concentrator' : (test) ->
        thing1 = {
            KEY: '123'
            monkey: 'boy'
            ROOM: '101'
            xmpp_jid: 'jid1'
            xmpp_owner: 'owner1'
            xmpp_nodeId: 'node1'
            xmpp_sourceId: 'source1'
            xmpp_cacheType: 'cacheType1'
        }

        thing2 = {
            KEY: '456'
            monkey: 'island'
            ROOM: '101'
            xmpp_jid: 'jid2'
            xmpp_owner: 'owner2'
            xmpp_nodeId: 'node2'
            xmpp_sourceId: 'source2'
            xmpp_cacheType: 'cacheType2'
        }

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal _.has(data, 'ROOM'), true
                test.equal data.ROOM, '101'
                result = {
                    devices: [ thing1, thing2 ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        searchFilters = [
            new Filter 'strEq', 'ROOM', '101'
        ]

        promise = target.search searchFilters

        onSuccess = (result) ->
            things = result.things

            test.equal things.length, 2
            test.equal things[0].nodeId, 'node1'
            test.equal things[0].sourceId, 'source1'
            test.equal things[0].cacheType, 'cacheType1'
            test.expect 6
            test.done()

        onFail = (err) ->
            test.equal true, false, 'should not get here'

        promise.then onSuccess, onFail


    'test search: filter unowned from results' : (test) ->
        thing1 = {
            KEY: '123'
            monkey: 'boy'
            ROOM: '101'
            xmpp_jid: 'jid1'
        }

        thing2 = {
            KEY: '456'
            monkey: 'island'
            ROOM: '101'
            xmpp_jid: 'jid2'
            xmpp_owner: 'owner2'
        }

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal _.has(data, 'ROOM'), true
                test.equal data.ROOM, '101'
                result = {
                    devices: [ thing1, thing2 ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        searchFilters = [
            new Filter 'strEq', 'ROOM', '101'
        ]

        promise = target.search searchFilters

        onSuccess = (result) ->
            things = result.things

            test.equal things.length, 1
            test.expect 3
            test.done()

        onFail = (err) ->
            test.equal true, false, 'should not get here'

        promise.then onSuccess, onFail

    'test search: filter private things from results' : (test) ->
        thing1 = {
            KEY: '123'
            monkey: 'boy'
            ROOM: '101'
            xmpp_jid: 'jid1'
            xmpp_owner: 'owner1'
            xmpp_public: 'true'
        }

        thing2 = {
            KEY: '456'
            monkey: 'island'
            ROOM: '101'
            xmpp_jid: 'jid2'
            xmpp_owner: 'owner2'
            xmpp_public: 'false'
        }

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal _.has(data, 'ROOM'), true
                test.equal data.ROOM, '101'
                result = {
                    devices: [ thing1, thing2 ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        searchFilters = [
            new Filter 'strEq', 'ROOM', '101'
        ]

        promise = target.search searchFilters

        onSuccess = (result) ->
            things = result.things

            test.equal things.length, 1
            test.equal things[0].jid, 'jid1'
            test.expect 4
            test.done()

        onFail = (err) ->
            test.equal true, false, 'should not get here'

        promise.then onSuccess, onFail

    'test search: filter removed things from results' : (test) ->
        thing1 = {
            KEY: '123'
            monkey: 'boy'
            ROOM: '101'
            xmpp_jid: 'jid1'
            xmpp_owner: 'owner1'
            xmpp_removed: 'true'
        }

        thing2 = {
            KEY: '456'
            monkey: 'island'
            ROOM: '101'
            xmpp_jid: 'jid2'
            xmpp_owner: 'owner2'
        }

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal _.has(data, 'ROOM'), true
                test.equal data.ROOM, '101'
                result = {
                    devices: [ thing1, thing2 ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        searchFilters = [
            new Filter 'strEq', 'ROOM', '101'
        ]

        promise = target.search searchFilters

        onSuccess = (result) ->
            things = result.things
            test.equal things.length, 1
            test.equal things[0].jid, 'jid2'
            test.expect 4
            test.done()

        onFail = (err) ->
            test.equal true, false, 'should not get here'

        promise.then onSuccess, onFail

    'test search: testing offset and maxcount' : (test) ->
        thing1 = {
            KEY: '123'
            monkey: 'boy'
            ROOM: '101'
            xmpp_jid: 'jid1'
            xmpp_owner: 'owner1'
        }

        thing2 = {
            KEY: '456'
            monkey: 'island'
            ROOM: '101'
            xmpp_jid: 'jid2'
            xmpp_owner: 'owner2'
        }

        thing3 = {
            KEY: '789'
            monkey: 'island'
            ROOM: '101'
            xmpp_jid: 'jid3'
            xmpp_owner: 'owner3'
        }

        thing4 = {
            KEY: '012'
            monkey: 'island'
            ROOM: '101'
            xmpp_jid: 'jid4'
            xmpp_owner: 'owner4'
        }

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal _.has(data, 'ROOM'), true
                test.equal data.ROOM, '101'
                result = {
                    devices: [ thing1, thing2, thing3, thing4 ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        searchFilters = [
            new Filter 'strEq', 'ROOM', '101'
        ]

        promise = target.search searchFilters, 1

        onSuccess = (result) ->
            things = result.things
            more = result.more

            test.equal things.length, 3
            test.equal things[0].jid, 'jid2'
            test.equal things[1].jid, 'jid3'
            test.equal things[2].jid, 'jid4'
            test.equal more, false
            test.expect 7
            test.done()

        onFail = (err) ->
            test.equal true, false, 'should not get here'

        promise.then onSuccess, onFail

    'test search: testing maxcount' : (test) ->
        thing1 = {
            KEY: '123'
            monkey: 'boy'
            ROOM: '101'
            xmpp_jid: 'jid1'
            xmpp_owner: 'owner1'
        }

        thing2 = {
            KEY: '456'
            monkey: 'island'
            ROOM: '101'
            xmpp_jid: 'jid2'
            xmpp_owner: 'owner2'
        }

        thing3 = {
            KEY: '789'
            monkey: 'island'
            ROOM: '101'
            xmpp_jid: 'jid3'
            xmpp_owner: 'owner3'
        }

        thing4 = {
            KEY: '012'
            monkey: 'island'
            ROOM: '101'
            xmpp_jid: 'jid4'
            xmpp_owner: 'owner4'
        }

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal _.has(data, 'ROOM'), true
                test.equal data.ROOM, '101'
                result = {
                    devices: [ thing1, thing2, thing3, thing4 ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        searchFilters = [
            new Filter 'strEq', 'ROOM', '101'
        ]

        promise = target.search searchFilters, undefined, 2

        onSuccess = (result) ->
            things = result.things
            more = result.more

            test.equal things.length, 2
            test.equal things[0].jid, 'jid1'
            test.equal things[1].jid, 'jid2'
            test.equal more, true
            test.expect 6
            test.done()

        onFail = (err) ->
            test.equal true, false, 'should not get here'

        promise.then onSuccess, onFail

    'test search: testing offset and maxcount' : (test) ->
        thing1 = {
            KEY: '123'
            monkey: 'boy'
            ROOM: '101'
            xmpp_jid: 'jid1'
            xmpp_owner: 'owner1'
        }

        thing2 = {
            KEY: '456'
            monkey: 'island'
            ROOM: '101'
            xmpp_jid: 'jid2'
            xmpp_owner: 'owner2'
        }

        thing3 = {
            KEY: '789'
            monkey: 'island'
            ROOM: '101'
            xmpp_jid: 'jid3'
            xmpp_owner: 'owner3'
        }

        thing4 = {
            KEY: '012'
            monkey: 'island'
            ROOM: '101'
            xmpp_jid: 'jid4'
            xmpp_owner: 'owner4'
        }

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal _.has(data, 'ROOM'), true
                test.equal data.ROOM, '101'
                result = {
                    devices: [ thing1, thing2, thing3, thing4 ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        searchFilters = [
            new Filter 'strEq', 'ROOM', '101'
        ]

        promise = target.search searchFilters, 1, 2

        onSuccess = (result) ->
            things = result.things
            more = result.more

            test.equal things.length, 2
            test.equal things[0].jid, 'jid2'
            test.equal things[1].jid, 'jid3'
            test.equal more, true
            test.expect 6
            test.done()

        onFail = (err) ->
            test.equal true, false, 'should not get here'

        promise.then onSuccess, onFail

    'test update thing: multiple matching things found in the registry': (test) ->
        properties = [
            new Property 'string', 'KEY', 'value'
        ]

        thing = new Thing('jid', properties)

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                result = {
                    devices: [ {}, {} ]
                }

                cb result

        connection = new ConnectionStub()

        target = new OctobluBackend '', 0, {},
            undefined,
            new OctobluStub(connection)

        connection.emit 'ready'

        promise = target.update thing

        onSuccess = (thing) ->
            test.equal true, false, 'should not hit this line'

        onFail = (err) ->
            test.done()

        promise.then onSuccess, onFail

    'test update thing: success case': (test) ->
        properties = [
            new Property 'string', 'KEY', 'value'
            new Property 'string', 'TEST', '' #empty, should be removed
        ]

        thing = new Thing('jid', properties)
        thing.owner = 'owner'

        storedDevice =
            xmpp_owner: 'owner'
            KEY: '123'
            TEST: '456'
            ROOM: '101'


        class ConnectionStub extends EventEmitter
            constructor: ->

            update: (data, cb) ->
                test.equal data.KEY, 'value'
                test.equal data.TEST, undefined
                test.equal data.ROOM, '101'

                delete data.TEST

                result = {
                    devices: [ data ]
                }

                cb result

            devices: (data, cb) ->
                result = {
                    devices: [ storedDevice ]
                }

                cb result

        connection = new ConnectionStub()

        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)

        connection.emit 'ready'

        promise = target.update thing

        onSuccess = (thing) ->
            test.equal thing.properties.length, 2

            for property in thing.properties
                if property.name is 'KEY'
                    test.equal property.value, 'value'

                if property.name is 'ROOM'
                    test.equal property.value, '101'

                if property.name is 'TEST'
                    test.done()

            test.expect 6
            test.done()

        onFail = (err) ->
            test.equal true, false, 'should not hit this line'
            test.done()

        promise.then onSuccess, onFail


    'test update thing: not owned': (test) ->
        properties = [
            new Property 'string', 'KEY', 'value'
            new Property 'string', 'TEST', '' #empty, should be removed
        ]

        thing = new Thing('jid', properties)

        storedDevice = {
            KEY: '123'
            TEST: '456'
            ROOM: '101'
        }

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                result = {
                    devices: [ storedDevice ]
                }

                cb result

        connection = new ConnectionStub()

        target = new OctobluBackend '', 0, {},
            undefined,
            new OctobluStub(connection)

        connection.emit 'ready'

        promise = target.update thing

        onSuccess = (thing) ->
            test.equal true, false, 'should not hit this line'

        onFail = (err) ->
            test.equal err.message, 'disowned'
            test.expect 1
            test.done()

        promise.then onSuccess, onFail

    'test remove thing: success case': (test) ->
        thing = new Thing('jid')
        thing.owner = 'owner'

        storedDevice =
            xmpp_jid: 'jid'
            xmpp_owner: 'owner'
            TEST: '456'

        class ConnectionStub extends EventEmitter
            constructor: ->

            unregister: (data, cb) ->
                test.notEqual data.uuid, undefined

                result = {
                }

                cb result

            devices: (data, cb) ->
                result = {
                    devices: [ storedDevice ]
                }

                cb result

        connection = new ConnectionStub()

        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)

        connection.emit 'ready'

        promise = target.remove thing

        onSuccess = (thing) ->
            test.expect 1
            test.done()

        onFail = (err) ->
            test.equal true, false, 'should not hit this line'
            test.done()

        promise.then onSuccess, onFail

    'test remove thing: not found': (test) ->
        thing = new Thing('jid')
        thing.owner = 'owner'

        class ConnectionStub extends EventEmitter
            constructor: ->

            unregister: (data, cb) ->
                test.equal true, false, 'should not get here'

                result = {
                    devices: [ ]
                }

                cb result

            devices: (data, cb) ->
                result = {
                    devices: [ ]
                }

                cb result

        connection = new ConnectionStub()

        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)

        connection.emit 'ready'

        promise = target.remove thing

        onSuccess = (thing) ->
            test.equal true, false, 'should not hit this line'
            test.done()

        onFail = (err) ->
            test.equal err.message, 'not-found'
            test.expect 1
            test.done()

        promise.then onSuccess, onFail

    'test remove thing: not owned': (test) ->
        thing = new Thing('jid')

        storedDevice =
            xmpp_jid: 'jid'

        class ConnectionStub extends EventEmitter
            constructor: ->

            unregister: (data, cb) ->
                test.equal true, false, 'should not get here'

                result = {
                    devices: [ ]
                }

                cb result

            devices: (data, cb) ->
                result = {
                    devices: [ storedDevice ]
                }

                cb result

        connection = new ConnectionStub()

        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)

        connection.emit 'ready'

        promise = target.remove thing

        onSuccess = (thing) ->
            test.equal true, false, 'should not hit this line'
            test.done()

        onFail = (err) ->
            test.equal err.message, 'not-owned'
            test.expect 1
            test.done()

        promise.then onSuccess, onFail

    'test remove thing: multiple results': (test) ->
        thing = new Thing('jid')
        thing.owner = 'not-owner'

        storedDevice =
            xmpp_jid: 'jid'
            xmpp_owner: 'owner'

        class ConnectionStub extends EventEmitter
            constructor: ->

            unregister: (data, cb) ->
                test.equal true, false, 'should not get here'

                result = {
                    devices: [ ]
                }

                cb result

            devices: (data, cb) ->
                result = {
                    devices: [ storedDevice, storedDevice ]
                }

                cb result

        connection = new ConnectionStub()

        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)

        connection.emit 'ready'

        promise = target.remove thing

        onSuccess = (thing) ->
            test.equal true, false, 'should not hit this line'
            test.done()

        onFail = (err) ->
            test.equal err.message, ''
            test.expect 1
            test.done()

        promise.then onSuccess, onFail

    'test remove thing: not allowed (not the owner)': (test) ->
        thing = new Thing('jid')
        thing.owner = 'not-owner'

        storedDevice =
            xmpp_jid: 'jid'
            xmpp_owner: 'owner'

        class ConnectionStub extends EventEmitter
            constructor: ->

            unregister: (data, cb) ->
                test.equal true, false, 'should not get here'

                result = {
                    devices: [ ]
                }

                cb result

            devices: (data, cb) ->
                result = {
                    devices: [ storedDevice ]
                }

                cb result

        connection = new ConnectionStub()

        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)

        connection.emit 'ready'

        promise = target.remove thing

        onSuccess = (thing) ->
            test.equal true, false, 'should not hit this line'
            test.done()

        onFail = (err) ->
            test.equal err.message, 'not-allowed'
            test.expect 1
            test.done()

        promise.then onSuccess, onFail

    'test unregister thing: success case': (test) ->
        thing = new Thing('jid')

        storedDevice =
            xmpp_jid: 'jid'

        class ConnectionStub extends EventEmitter
            constructor: ->

            unregister: (data, cb) ->
                test.notEqual data.uuid, undefined

                result = {
                }

                cb result

            devices: (data, cb) ->
                result = {
                    devices: [ storedDevice ]
                }

                cb result

        connection = new ConnectionStub()

        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)

        connection.emit 'ready'

        promise = target.unregister thing

        onSuccess = () ->
            test.expect 1
            test.done()

        onFail = (err) ->
            test.equal true, false, 'should not hit this line'
            test.done()

        promise.then onSuccess, onFail

    'test unregister thing: not found' : (test) ->
        thing = new Thing('jid')

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                result = {
                    devices: [ ]
                }

                cb result

        connection = new ConnectionStub()

        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)

        connection.emit 'ready'

        promise = target.unregister thing

        onSuccess = (thing) ->
            test.equal true, false, 'should not hit this line'
            test.done()

        onFail = (err) ->
            test.equal err.message, 'not-found'
            test.expect 1
            test.done()

        promise.then onSuccess, onFail

    'test get thing: success' : (test) ->
        storedDevice =
            xmpp_jid: 'jid'

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal data.xmpp_jid, 'jid'

                result = {
                    devices: [ storedDevice ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        proto = new Thing 'jid'
        promise = target.get proto

        onSuccess = (things) ->
            test.equal things.length, 1
            test.equal things[0].jid, 'jid'
            test.expect 3
            test.done()

        onFail = (err) ->
            test.equal true, false, 'should not hit this line'
            test.done()

        promise.then onSuccess, onFail

    'test get thing: error' : (test) ->
        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal data.xmpp_jid, 'jid'

                result = {
                    error: [ ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        proto = new Thing 'jid'
        promise = target.get proto

        onSuccess = (things) ->
            test.equal true, false, 'should not hit this line'
            test.done()

        onFail = (err) ->
            test.equal err.message, ''
            test.expect 2
            test.done()

        promise.then onSuccess, onFail

    'test get thing: multiple results found' : (test) ->
        storedDevice =
            xmpp_jid: 'jid'

        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal data.xmpp_jid, 'jid'

                result = {
                    devices: [ storedDevice, storedDevice ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        promise = target.get new Thing('jid')

        onSuccess = (things) ->
            test.equal things.length, 2
            test.expect 2
            test.done()

        onFail = (err) ->
            test.equal true, false, 'should not hit this line'
            test.done()

        promise.then onSuccess, onFail

    'test get thing: no results found' : (test) ->
        class ConnectionStub extends EventEmitter
            constructor: ->

            devices: (data, cb) ->
                test.equal data.xmpp_jid, 'jid'

                result = {
                    devices: [ ]
                }

                cb result

        connection = new ConnectionStub()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        promise = target.get new Thing('jid')

        onSuccess = (things) ->
            test.equal things.length, 0
            test.expect 2
            test.done()

        onFail = (err) ->
            test.equal true, false, 'should not hit this line'
            test.done()

        promise.then onSuccess, onFail

    'test serialization' : (test) ->
        thing = new Thing 'jid'
        thing.needsNotification = true
        thing.removed = true
        thing.properties = []

        connection = new EventEmitter()
        target = new OctobluBackend '', 0, {}, undefined, new OctobluStub(connection)
        connection.emit 'ready'

        serialized = target.serialize thing, false
        test.equal serialized.xmpp_jid, 'jid'
        test.equal serialized.xmpp_needsNotification, 'true'
        test.equal serialized.xmpp_removed, 'true'
        test.equal serialized.xmpp_public, 'true'

        thing = target.deserialize serialized
        test.equal thing.needsNotification, true
        test.equal thing.removed, true
        test.equal thing.public, true

        thing.removed = false
        thing.needsNotification = false
        thing.public = false

        serialized = target.serialize thing, false
        test.equal serialized.xmpp_jid, 'jid'
        test.equal serialized.xmpp_needsNotification, undefined
        test.equal serialized.xmpp_removed, undefined
        test.equal serialized.xmpp_public, 'false'

        thing = target.deserialize serialized
        test.equal thing.needsNotification, undefined
        test.equal thing.removed, undefined
        test.equal thing.public, false

        thing.needsNotification = undefined
        thing.removed = undefined
        thing.public = undefined

        serialized = target.serialize thing, false
        test.equal serialized.xmpp_jid, 'jid'
        test.equal serialized.xmpp_needsNotification, undefined
        test.equal serialized.xmpp_removed, undefined
        test.equal serialized.xmpp_public, 'true'

        thing = target.deserialize serialized
        test.equal thing.needsNotification, undefined
        test.equal thing.removed, undefined
        test.equal thing.public, true

        test.expect 21
        test.done()

