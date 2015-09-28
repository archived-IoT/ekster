# Tests if the backend of the component complies to
# https://xmpp.org/extensions/xep-0347.html
#
# Some test cases refer to paragraphs and / or examples from the spec.

{EventEmitter} = require 'events'

MongooseBackend = require '../src/mongoose-backend.coffee'
Thing = require '../src/thing.coffee'
Property = require '../src/property.coffee'
Filter = require '../src/filter.coffee'

Q = require 'q'
_ = require 'lodash'
mongoose = require 'mongoose'
mockgoose = require 'mockgoose'

mockgoose mongoose
target = undefined

exports.MongooseBackendTest =
    setUp: (cb) ->
        if target is undefined
            target = new MongooseBackend 'test', 0, {}, undefined, mongoose
            target.db.connection.on 'connected', () ->
                cb()
        else
            mockgoose.reset()
            cb()

    tearDown: (cb) ->
        cb()

    'test thing2mongo mongo2thing' : (test) ->
        thing = new Thing 'jid'
        thing.needsNotification = true
        thing.removed = true
        thing.properties = []
        thing.properties.push new Property('string', 'KEY', 'abc')
        thing.properties.push new Property('number', 'ABC', '1.234')
        thing.properties.push new Property('string', 'DEF', 'test')

        mongo = target.thingToMongoThing thing
        test.equal mongo.jid, 'jid'
        test.equal mongo.needsNotification, true
        test.equal mongo.removed, true
        test.equal mongo.public, true
        test.equal mongo.key, 'abc'
        test.equal mongo.properties.length, 2

        for prop in mongo.properties
            if prop.type is 'number'
                test.equal prop.numberValue, 1.234
                test.equal prop.name, 'ABC'
                test.equal prop.stringValue, undefined
            else
                test.equal prop.type, 'string'
                test.equal prop.name, 'DEF'
                test.equal prop.stringValue, 'test'
                test.equal prop.numberValue, undefined

        thing = target.mongoThingToThing mongo
        test.equal thing.needsNotification, true
        test.equal thing.removed, true
        test.equal thing.public, true

        for prop in thing.properties
            if prop.type is 'number'
                test.equal prop.name, 'ABC'
                test.equal prop.value, '1.234'
            else
                test.equal prop.type, 'string'

                if prop.name is 'KEY'
                    test.equal prop.value, 'abc'
                else
                    test.equal prop.name, 'DEF'
                    test.equal prop.value, 'test'

        test.expect 23
        test.done()

    'test register test if preconditions are not met': (test) ->
        test.expect 1

        properties = [ new Property('type', 'name', 'value') ]
        thing = new Thing('jid', properties)

        promise = target.register thing

        onSuccess = (thing) ->
            test.done()

        onFail = (err) ->
            test.equal err.message, 'Missing property: KEY'
            test.done()

        promise.then onSuccess, onFail

    'test thing already registered': (test) ->
        test.expect 1

        properties = [
            new Property 'string', 'KEY', 'value'
        ]

        thing = new Thing('jid', properties)

        mongoThing = target.thingToMongoThing thing
        mongoThing.save (err, obj) ->
            if err
                test.done()
                return

            promise = target.register thing

            onSuccess = (thing) ->
                test.equal thing.jid, 'jid'
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test thing already registered and owned': (test) ->
        test.expect 2

        properties = [
            new Property 'string', 'KEY', 'value'
        ]

        thing = new Thing('jid', properties)
        mongoThing = target.thingToMongoThing thing
        mongoThing.owner = 'owner'

        mongoThing.save (err, obj) ->
            if err
                test.done()
            else
                promise = target.register thing

                onSuccess = (thing) ->
                    test.done()

                onFail = (err) ->
                    test.equal err.message, 'claimed'
                    test.equal err.owner, 'owner'
                    test.done()

                promise.then onSuccess, onFail

    'test register thing: multiple matching things found in the registry': (test) ->
        test.expect 1

        properties = [
            new Property 'string', 'KEY', 'value'
        ]

        thing = new Thing('jid', properties)
        mongoThing = target.thingToMongoThing thing
        mongoThing.save (err, obj) ->
            if (err)
                test.done()
                return

            mongoThing2 = target.thingToMongoThing thing
            mongoThing2.save (err, obj) ->
                if (err)
                    test.done()
                    return

                promise = target.register thing

                onSuccess = (thing) ->
                    test.done()

                onFail = (err) ->
                    test.equal true, true
                    test.done()

                promise.then onSuccess, onFail

    'test claim ownership: success case' : (test) ->
        test.expect 2

        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'monkey', 'boy'
        ]

        thing = new Thing('jid', properties)
        mongoThing = target.thingToMongoThing thing

        mongoThing.save (err, obj) ->
            if err
                test.done()
                return

            thing.owner = 'owner'
            thing.needsNotification = true

            promise = target.claim thing

            onSuccess = (claimed) ->
                test.equal claimed.owner, 'owner'
                test.equal claimed.needsNotification, true
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test claim ownership: device not found' : (test) ->
        test.expect 1

        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'monkey', 'boy'
        ]

        thing = new Thing('jid', properties)
        thing.owner = 'owner'

        promise = target.claim thing

        onSuccess = (thing) ->
            test.done()

        onFail = (err) ->
            test.equal err.message, 'not-found'
            test.done()

        promise.then onSuccess, onFail

    'test claim ownership: device already owned' : (test) ->
        test.expect 1

        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'monkey', 'boy'
        ]

        thing = new Thing('jid', properties)
        thing.owner = 'owner'

        mongoThing =  target.thingToMongoThing thing
        mongoThing.save (err) ->
            if err
                test.done()
                return

            promise = target.claim thing

            onSuccess = (thing) ->
                test.done()

            onFail = (err) ->
                test.equal err.message, 'claimed'
                test.done()

            promise.then onSuccess, onFail

    'test claim ownership: not an exact match' : (test) ->
        test.expect 1

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'monkey', 'boy'
        ]

        properties2 = [
            new Property 'string', 'KEY', '123'
        ]

        thing = new Thing('jid', properties1)

        mongoThing = target.thingToMongoThing thing

        mongoThing.save (err) ->
            if err
                test.done()
                return

            promise = target.claim new Thing('jid', properties2)

            onSuccess = (thing) ->
                test.done()

            onFail = (err) ->
                test.equal err.message, 'not-found'
                test.done()

            promise.then onSuccess, onFail

    'test claim ownership: not an exact match 2' : (test) ->
        test.expect 1

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'monkey', 'boy'
            new Property 'string', 'ROOM', '101'
        ]

        properties2 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
        ]

        thing = new Thing('jid', properties1)

        mongoThing = target.thingToMongoThing thing

        mongoThing.save (err) ->
            if err
                test.done()
                return

            promise = target.claim new Thing('jid', properties2)

            onSuccess = (thing) ->
                test.done()

            onFail = (err) ->
                test.equal err.message, 'not-found'
                test.done()

            promise.then onSuccess, onFail

    'test claim ownership: multiple results' : (test) ->
        test.expect 1

        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'monkey', 'boy'
        ]

        thing = new Thing('jid', properties)
        thing.owner = 'owner'

        mongoThing1 = target.thingToMongoThing thing
        mongoThing2 = target.thingToMongoThing thing

        mongoThing1.save (err) ->
            if err
                test.done()
                return

            mongoThing2.save (err) ->
                if err
                    test.done()
                    return

                promise = target.claim thing

                onSuccess = (thing) ->
                    test.done()

                onFail = (err) ->
                    test.equal err.message, 'illegal state'
                    test.done()

                promise.then onSuccess, onFail

    'test search: multiple results' : (test) ->
        test.expect 4

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.owner = 'owner1'

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'island'
        ]

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        mongoThing1.save (err) ->
            if err
                test.done()
                return

            mongoThing2.save (err) ->
                if err
                    test.done()
                    return

                searchFilters = [
                    new Filter 'strEq', 'ROOM', '101'
                ]

                promise = target.search searchFilters

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
        test.expect 4

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.owner = 'owner1'
        thing1.nodeId = 'node1'
        thing1.sourceId = 'source1'
        thing1.cacheType = 'cacheType1'

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'island'
        ]

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'
        thing2.nodeId = 'node2'
        thing2.sourceId = 'source2'
        thing2.cacheType = 'cacheType2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        mongoThing1.save (err) ->
            if err
                test.done()
                return

            mongoThing2.save (err) ->
                if err
                    test.done()
                    return

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
                    test.done()

                onFail = (err) ->
                    test.done()

                promise.then onSuccess, onFail

    'test search: case insensitive keys' : (test) ->
        test.expect 1

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.owner = 'owner1'

        mongoThing1 = target.thingToMongoThing thing1

        mongoThing1.save (err) ->
            if err
                test.done()
                return

            searchFilters = [
                new Filter 'strEq', 'room', '101'
            ]

            promise = target.search searchFilters

            onSuccess = (result) ->
                things = result.things
                test.equal things.length, 1
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test search: strNEq' : (test) ->
        test.expect 2

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '102'
            new Property 'string', 'monkey', 'boy'
        ]

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'string', 'ROOM', '101'
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        Q.all([
            mongoThing1.save(),
            mongoThing2.save()]
        ).then () ->
            searchFilters = [
                new Filter 'strNEq', 'room', '101'
            ]

            promise = target.search searchFilters

            onSuccess = (result) ->
                things = result.things
                test.equal things.length, 1
                test.equal things[0].jid, 'jid1'
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test search: strGt' : (test) ->
        test.expect 2

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'string', 'ROOM', '100'
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        Q.all([
            mongoThing1.save(),
            mongoThing2.save()]
        ).then () ->
            searchFilters = [
                new Filter 'strGt', 'room', '100'
            ]

            promise = target.search searchFilters

            onSuccess = (result) ->
                things = result.things
                test.equal things.length, 1
                test.equal things[0].jid, 'jid1'
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test search: strGtEq' : (test) ->
        test.expect 2

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'string', 'ROOM', '100'
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        Q.all([
            mongoThing1.save(),
            mongoThing2.save()]
        ).then () ->
            searchFilters = [
                new Filter 'strGtEq', 'room', '101'
            ]

            promise = target.search searchFilters

            onSuccess = (result) ->
                things = result.things
                test.equal things.length, 1
                test.equal things[0].jid, 'jid1'
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test search: strLt' : (test) ->
        test.expect 2

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'string', 'ROOM', '102'
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        Q.all([
            mongoThing1.save(),
            mongoThing2.save()]
        ).then () ->
            searchFilters = [
                new Filter 'strLt', 'room', '102'
            ]

            promise = target.search searchFilters

            onSuccess = (result) ->
                things = result.things
                test.equal things.length, 1
                test.equal things[0].jid, 'jid1'
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test search: strLtEq' : (test) ->
        test.expect 2

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'string', 'ROOM', '102'
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        Q.all([
            mongoThing1.save(),
            mongoThing2.save()]
        ).then () ->
            searchFilters = [
                new Filter 'strLtEq', 'room', '101'
            ]

            promise = target.search searchFilters

            onSuccess = (result) ->
                things = result.things
                test.equal things.length, 1
                test.equal things[0].jid, 'jid1'
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

#    'test search: strRange' : (test) ->
#        test.expect 2
#
#        properties1 = [
#            new Property 'string', 'KEY', '123'
#            new Property 'string', 'ROOM', '101'
#            new Property 'string', 'monkey', 'boy'
#        ]
#
#        properties2 = [
#            new Property 'string', 'KEY', '456'
#            new Property 'string', 'ROOM', '102'
#        ]
#
#        thing1 = new Thing('jid1', properties1)
#        thing1.owner = 'owner1'
#
#        thing2 = new Thing('jid2', properties2)
#        thing2.owner = 'owner2'
#
#        mongoThing1 = target.thingToMongoThing thing1
#        mongoThing2 = target.thingToMongoThing thing2
#
#        Q.all([
#            mongoThing1.save(),
#            mongoThing2.save()]
#        ).then () ->
#            searchFilters = [
#                new Filter 'strRange', 'room'
#            ]
#
#            searchFilters[0].min = '100'
#            searchFilters[0].max = '102'
#            searchFilters[0].minIncluded = false
#            searchFilters[0].maxIncluded = false
#
#            promise = target.search searchFilters
#
#            onSuccess = (result) ->
#                things = result.things
#                test.equal things.length, 1
#                test.equal things[0].jid, 'jid1'
#                test.done()
#
#            onFail = (err) ->
#                test.done()
#
#            promise.then onSuccess, onFail

    'test search: numNEq' : (test) ->
        test.expect 2

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'number', 'ROOM', 102
            new Property 'string', 'monkey', 'boy'
        ]

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'number', 'ROOM', 101
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        Q.all([
            mongoThing1.save(),
            mongoThing2.save()]
        ).then () ->
            searchFilters = [
                new Filter 'numNEq', 'room', 101
            ]

            promise = target.search searchFilters

            onSuccess = (result) ->
                things = result.things
                test.equal things.length, 1
                test.equal things[0].jid, 'jid1'
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test search: numGt' : (test) ->
        test.expect 2

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'number', 'ROOM', 101
            new Property 'string', 'monkey', 'boy'
        ]

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'number', 'ROOM', 100
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        Q.all([
            mongoThing1.save(),
            mongoThing2.save()]
        ).then () ->
            searchFilters = [
                new Filter 'numGt', 'room', 100
            ]

            promise = target.search searchFilters

            onSuccess = (result) ->
                things = result.things
                test.equal things.length, 1
                test.equal things[0].jid, 'jid1'
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test search: numGtEq' : (test) ->
        test.expect 2

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'number', 'ROOM', 101
            new Property 'string', 'monkey', 'boy'
        ]

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'number', 'ROOM', 100
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        Q.all([
            mongoThing1.save(),
            mongoThing2.save()]
        ).then () ->
            searchFilters = [
                new Filter 'numGtEq', 'room', 101
            ]

            promise = target.search searchFilters

            onSuccess = (result) ->
                things = result.things
                test.equal things.length, 1
                test.equal things[0].jid, 'jid1'
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test search: numLt' : (test) ->
        test.expect 2

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'number', 'ROOM', 101
            new Property 'string', 'monkey', 'boy'
        ]

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'number', 'ROOM', 102
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        Q.all([
            mongoThing1.save(),
            mongoThing2.save()]
        ).then () ->
            searchFilters = [
                new Filter 'numLt', 'room', 102
            ]

            promise = target.search searchFilters

            onSuccess = (result) ->
                things = result.things
                test.equal things.length, 1
                test.equal things[0].jid, 'jid1'
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test search: numLtEq' : (test) ->
        test.expect 2

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'number', 'ROOM', 101
            new Property 'string', 'monkey', 'boy'
        ]

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'number', 'ROOM', 102
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        Q.all([
            mongoThing1.save(),
            mongoThing2.save()]
        ).then () ->
            searchFilters = [
                new Filter 'numLtEq', 'room', 101
            ]

            promise = target.search searchFilters

            onSuccess = (result) ->
                things = result.things
                test.equal things.length, 1
                test.equal things[0].jid, 'jid1'
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

#    'test search: numRange' : (test) ->
#        test.expect 2
#
#        properties1 = [
#            new Property 'string', 'KEY', '123'
#            new Property 'number', 'ROOM', 101
#            new Property 'string', 'monkey', 'boy'
#        ]
#
#        properties2 = [
#            new Property 'string', 'KEY', '456'
#            new Property 'number', 'ROOM', 102
#        ]
#
#        thing1 = new Thing('jid1', properties1)
#        thing1.owner = 'owner1'
#
#        thing2 = new Thing('jid2', properties2)
#        thing2.owner = 'owner2'
#
#        mongoThing1 = target.thingToMongoThing thing1
#        mongoThing2 = target.thingToMongoThing thing2
#
#        Q.all([
#            mongoThing1.save(),
#            mongoThing2.save()]
#        ).then () ->
#            searchFilters = [
#                new Filter 'numRange', 'room'
#            ]
#
#            searchFilters[0].min = 100
#            searchFilters[0].max = 102
#            searchFilters[0].minIncluded = false
#            searchFilters[0].maxIncluded = false
#
#            promise = target.search searchFilters
#
#            onSuccess = (result) ->
#                things = result.things
#                test.equal things.length, 1
#                test.equal things[0].jid, 'jid1'
#                test.done()
#
#            onFail = (err) ->
#                test.done()
#
#            promise.then onSuccess, onFail

    'test search: multiple search filters' : (test) ->
        test.expect 1

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
            new Property 'number', 'V', 1.2
        ]

        properties2 = [
            new Property 'string', 'ROOM', '101'
            new Property 'number', 'V', 1.3
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        Q.all([
            mongoThing1.save(),
            mongoThing2.save()]
        ).then () ->
            searchFilters = [
                new Filter 'strEq', 'room', '101'
                new Filter 'numEq', 'v', 1.2
            ]

            promise = target.search searchFilters

            onSuccess = (result) ->
                things = result.things
                test.equal things.length, 1
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail


    'test search: filter unowned from results' : (test) ->
        test.expect 2

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        thing1 = new Thing('jid1', properties1)

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'island'
        ]

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        mongoThing1.save (err) ->
            if err
                test.done()
                return

            mongoThing2.save (err) ->
                if err
                    test.done()
                    return

                searchFilters = [
                    new Filter 'strEq', 'ROOM', '101'
                ]

                promise = target.search searchFilters

                onSuccess = (result) ->
                    things = result.things

                    test.equal things.length, 1
                    test.equal things[0].jid, 'jid2'
                    test.done()

                onFail = (err) ->
                    test.done()

                promise.then onSuccess, onFail

    'test search: filter private things from results' : (test) ->
        test.expect 2

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.public = false

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'island'
        ]

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        mongoThing1.save (err) ->
            if err
                test.done()
                return

            mongoThing2.save (err) ->
                if err
                    test.done()
                    return

                searchFilters = [
                    new Filter 'strEq', 'ROOM', '101'
                ]

                promise = target.search searchFilters

                onSuccess = (result) ->
                    things = result.things

                    test.equal things.length, 1
                    test.equal things[0].jid, 'jid2'
                    test.done()

                onFail = (err) ->
                    test.done()

                promise.then onSuccess, onFail

    'test search: filter removed things from results' : (test) ->
        test.expect 2

        properties1 = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        thing1 = new Thing('jid1', properties1)
        thing1.removed = true

        properties2 = [
            new Property 'string', 'KEY', '456'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'island'
        ]

        thing2 = new Thing('jid2', properties2)
        thing2.owner = 'owner2'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        mongoThing1.save (err) ->
            if err
                test.done()
                return

            mongoThing2.save (err) ->
                if err
                    test.done()
                    return

                searchFilters = [
                    new Filter 'strEq', 'ROOM', '101'
                ]

                promise = target.search searchFilters

                onSuccess = (result) ->
                    things = result.things

                    test.equal things.length, 1
                    test.equal things[0].jid, 'jid2'
                    test.done()

                onFail = (err) ->
                    test.done()

                promise.then onSuccess, onFail

    'test search: testing offset' : (test) ->
        test.expect 5

        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        thing1 = new Thing('jid1', properties)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid2', properties)
        thing2.owner = 'owner2'

        thing3 = new Thing('jid3', properties)
        thing3.owner = 'owner3'

        thing4 = new Thing('jid4', properties)
        thing4.owner = 'owner4'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2
        mongoThing3 = target.thingToMongoThing thing3
        mongoThing4 = target.thingToMongoThing thing4

        Q.all([
            mongoThing1.save(),
            mongoThing2.save(),
            mongoThing3.save(),
            mongoThing4.save() ]
        ).then () ->
            searchFilters = [
                new Filter 'strEq', 'ROOM', '101'
            ]

            promise = target.search searchFilters, 1

            onSuccess = (result) ->
                things = result.things

                test.equal things.length, 3
                test.equal things[0].jid, 'jid2'
                test.equal things[1].jid, 'jid3'
                test.equal things[2].jid, 'jid4'
                test.equal result.more, false
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test search: testing maxcount' : (test) ->
        test.expect 4

        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        thing1 = new Thing('jid1', properties)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid2', properties)
        thing2.owner = 'owner2'

        thing3 = new Thing('jid3', properties)
        thing3.owner = 'owner3'

        thing4 = new Thing('jid4', properties)
        thing4.owner = 'owner4'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2
        mongoThing3 = target.thingToMongoThing thing3
        mongoThing4 = target.thingToMongoThing thing4

        Q.all([
            mongoThing1.save(),
            mongoThing2.save(),
            mongoThing3.save(),
            mongoThing4.save() ]
        ).then () ->
            searchFilters = [
                new Filter 'strEq', 'ROOM', '101'
            ]

            promise = target.search searchFilters, undefined, 2

            onSuccess = (result) ->
                things = result.things

                test.equal things.length, 2
                test.equal things[0].jid, 'jid1'
                test.equal things[1].jid, 'jid2'
                test.equal result.more, true
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test search: testing offset and maxcount' : (test) ->
        test.expect 4

        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        thing1 = new Thing('jid1', properties)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid2', properties)
        thing2.owner = 'owner2'

        thing3 = new Thing('jid3', properties)
        thing3.owner = 'owner3'

        thing4 = new Thing('jid4', properties)
        thing4.owner = 'owner4'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2
        mongoThing3 = target.thingToMongoThing thing3
        mongoThing4 = target.thingToMongoThing thing4

        Q.all([
            mongoThing1.save(),
            mongoThing2.save(),
            mongoThing3.save(),
            mongoThing4.save() ]
        ).then () ->
            searchFilters = [
                new Filter 'strEq', 'ROOM', '101'
            ]

            promise = target.search searchFilters, 1, 2

            onSuccess = (result) ->
                things = result.things

                test.equal things.length, 2
                test.equal things[0].jid, 'jid2'
                test.equal things[1].jid, 'jid3'
                test.equal result.more, true
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test update thing: multiple matching things found in the registry': (test) ->
        test.expect 1

        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        thing1 = new Thing('jid1', properties)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid1', properties)
        thing2.owner = 'owner1'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        Q.all([
            mongoThing1.save(),
            mongoThing2.save()
        ]).then () ->
            promise = target.update thing1

            onSuccess = (result) ->
                test.done()

            onFail = (err) ->
                test.equal err.message, ''
                test.done()

            promise.then onSuccess, onFail

    'test update thing: success case': (test) ->
        test.expect 7

        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'TEST', '456'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'BUILDING', 'ABC'
            new Property 'number', 'NUMBER', 123
            new Property 'string', 'NOT_A_NUMBER', '456'
        ]

        thing = new Thing('jid', properties)
        thing.owner = 'owner'

        mongoThing = target.thingToMongoThing thing

        mongoThing.save (err) ->
            if err
                test.done()
                return

            thing.properties = [
                new Property 'string', 'KEY', 'value'
                new Property 'string', 'TEST', '' #empty, should be removed
                new Property 'string', 'BUILDING', 'DEF'
                new Property 'string', 'number', '123'
                new Property 'number', 'NOT_A_NUMBER', 456
                new Property 'string', 'NEW', 'Hi!'
            ]

            promise = target.update thing

            onSuccess = (thing) ->
                test.equal thing.properties.length, 6

                for property in thing.properties
                    if property.name is 'KEY'
                        test.equal property.value, 'value'

                    if property.name is 'ROOM'
                        test.equal property.value, '101'

                    if property.name is 'BUILDING'
                        test.equal property.value, 'DEF'

                    if property.name is 'number'
                        test.equal property.value, '123'

                    if property.name is 'NOT_A_NUMBER'
                        test.equal property.value, 456

                    if property.name is 'NEW'
                        test.equal property.value, 'Hi!'

                    if property.name is 'TEST'
                        test.equal true, false

                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test update thing: not owned': (test) ->
        test.expect 1

        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'TEST', '456'
            new Property 'string', 'ROOM', '101'
        ]

        thing = new Thing('jid', properties)

        mongoThing = target.thingToMongoThing thing

        mongoThing.save (err) ->
            if err
                test.done()
                return

            promise = target.update thing

            onSuccess = (thing) ->
                test.done()

            onFail = (err) ->
                test.equal err.message, 'disowned'
                test.done()

            promise.then onSuccess, onFail

    'test remove thing: success case': (test) ->
        test.expect 1

        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'TEST', '456'
            new Property 'string', 'ROOM', '101'
        ]

        thing = new Thing('jid', properties)
        thing.owner = 'owner'

        mongoThing = target.thingToMongoThing thing

        mongoThing.save (err) ->
            if err
                test.done()
                return

            promise = target.remove thing

            onSuccess = () ->
                test.equal true, true
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test remove thing: not found': (test) ->
        test.expect 1
        thing = new Thing('jid')
        thing.owner = 'owner'

        promise = target.remove thing

        onSuccess = () ->
            test.done()

        onFail = (err) ->
            test.equal err.message, 'not-found'
            test.done()

        promise.then onSuccess, onFail

    'test remove thing: not owned': (test) ->
        test.expect 1

        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'TEST', '456'
            new Property 'string', 'ROOM', '101'
        ]

        thing = new Thing('jid', properties)

        mongoThing = target.thingToMongoThing thing

        mongoThing.save (err) ->
            if err
                test.done()
                return

            promise = target.remove thing

            onSuccess = () ->
                test.done()

            onFail = (err) ->
                test.equal err.message, 'not-owned'
                test.done()

            promise.then onSuccess, onFail

    'test remove thing: multiple results': (test) ->
        test.expect 1

        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'ROOM', '101'
            new Property 'string', 'monkey', 'boy'
        ]

        thing1 = new Thing('jid1', properties)
        thing1.owner = 'owner1'

        thing2 = new Thing('jid1', properties)
        thing2.owner = 'owner1'

        mongoThing1 = target.thingToMongoThing thing1
        mongoThing2 = target.thingToMongoThing thing2

        Q.all([
            mongoThing1.save(),
            mongoThing2.save()
        ]).then () ->
            promise = target.remove thing1

            onSuccess = () ->
                test.done()

            onFail = (err) ->
                test.equal err.message, ''
                test.done()

            promise.then onSuccess, onFail

    'test remove thing: not allowed (not the owner)': (test) ->
        test.expect 1

        properties = [
            new Property 'string', 'KEY', '123'
            new Property 'string', 'TEST', '456'
            new Property 'string', 'ROOM', '101'
        ]

        thing = new Thing('jid', properties)
        thing.owner = 'owner'

        mongoThing = target.thingToMongoThing thing

        mongoThing.save (err) ->
            if err
                test.done()
                return

            thing.owner = 'not the owner'
            promise = target.remove thing

            onSuccess = () ->
                test.done()

            onFail = (err) ->
                test.equal err.message, 'not-allowed'
                test.done()

            promise.then onSuccess, onFail

    'test unregister thing: success case': (test) ->
        test.expect 1

        thing = new Thing('jid')

        mongoThing = target.thingToMongoThing thing

        mongoThing.save (err) ->
            if err
                test.done()
                return

            promise = target.unregister thing

            onSuccess = () ->
                test.equal true, true
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test unregister thing: not found' : (test) ->
        test.expect 1
        thing = new Thing('jid')

        promise = target.unregister thing

        onSuccess = () ->
            test.done()

        onFail = (err) ->
            test.equal err.message, 'not-found'
            test.done()

        promise.then onSuccess, onFail

    'test get thing: success' : (test) ->
        test.expect 2

        thing = new Thing('jid')

        mongoThing = target.thingToMongoThing thing

        mongoThing.save (err) ->
            if err
                test.done()
                return

            promise = target.get thing

            onSuccess = (things) ->
                test.equal things.length, 1
                test.equal things[0].jid, 'jid'
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test get thing: not found because no owner' : (test) ->
        test.expect 1

        thing = new Thing('jid')

        mongoThing = target.thingToMongoThing thing

        mongoThing.save (err) ->
            if err
                test.done()
                return

            thing.owner = 'owner'
            promise = target.get thing

            onSuccess = (things) ->
                test.equal things.length, 0
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test get thing: multiple results found' : (test) ->
        test.expect 1

        mongoThing1 = target.thingToMongoThing(new Thing('jid'))
        mongoThing2 = target.thingToMongoThing(new Thing('jid'))

        Q.all([mongoThing1.save(), mongoThing2.save()]).then () ->
            promise = target.get new Thing('jid')

            onSuccess = (things) ->
                test.equal things.length, 2
                test.done()

            onFail = (err) ->
                test.done()

            promise.then onSuccess, onFail

    'test get thing: no results found' : (test) ->
        test.expect 1

        promise = target.get new Thing('jid')

        onSuccess = (things) ->
            test.equal things.length, 0
            test.done()

        onFail = (err) ->
            test.done()

        promise.then onSuccess, onFail

