# Backend implementation for mongoose/mongodb

# Backend for Octoblu

Backend = require './backend.coffee'
Q = require 'q'
_ = require 'lodash'
Logger = require './logger.coffee'
Thing = require './thing.coffee'
Property = require './property.coffee'

MongoThing = undefined
MongoProperty = undefined

class MongooseBackend extends Backend
    # Creates the backend and connects to the mongo database
    # @param [String] The hostname to connect to
    # @param [Number] The port the mongod instance is running on
    # @param [Object] The mongoose options (see: http://mongoosejs.com/docs/connections.html)
    # @param [Object] The logger that should be used for logging
    # @param [Object] Optionally a mongoose object (for testing)
    constructor: (@host, @port, @opts, @log, @mongoose) ->
        super @opts

        @log = new Logger if not @log
        @mongoose = require 'mongoose' if not @mongoose

        # If we do not have a schema yet, create it...
        if MongoThing is undefined
            # creating the object model
            propertySchema = new @mongoose.Schema (
                type: String
                name: String
                stringValue: String
                numberValue: Number
            )

            registrySchema = new @mongoose.Schema (
                jid: String
                nodeId: String
                sourceId: String
                cacheType: String
                key: String
                properties: [ propertySchema ]
                owner: String
                public: Boolean
                needsNotification: Boolean
                removed: Boolean
            )

            # setting the index
            registrySchema.index (
                jid: 1
                nodeId: 1
                sourceId: 1
                cacheType: 1
            )

            MongoThing = @mongoose.model 'MongoThing', registrySchema
            MongoProperty = @mongoose.model 'MongoProperty', propertySchema

        @log.info 'Trying to connect to the database...'

        if @opts.server is undefined
            @opts.server = { }

        if @opts.replset is undefined
            @opts.replset = { }

        @opts.server.socketOptions = @opts.replset.socketOptions = { keepAlive: 1 }
        @db = @mongoose.connect "mongodb://#{ @host }:#{ @port }/#{ @opts.db }", @opts

        if @db.connection.on isnt undefined
            @db.connection.on 'connected', () =>
                @log.info 'Connected to the database.'

            @db.connection.on 'disconnected', (data) =>
                @log.warn 'Disconnected from the database!'

    # Registers a thing.
    register: (thing) =>
        @log.trace 'About to registering a new thing...'

        defered = Q.defer()

        proto = @thingToPrototype thing

        if proto.key is undefined
            defered.reject new Error 'Missing property: KEY'
            return defered.promise

        @log.trace 'Register message is ready:'
        @log.trace proto

        conditions =
            jid: proto.jid
            nodeId: proto.nodeId
            sourceId: proto.sourceId
            cacheType: proto.cacheType

        # check first if a thing with this uuid is already present
        MongoThing.find conditions, (err, things) =>
            if err
                defered.reject(err)
                return

            if things.length > 1
                defered.reject new Error "Only 1 device expected with for: #{ proto.toString() }"
            else
                mongoThing = @thingToMongoThing thing

                if things.length is 1 and things[0].owner is undefined
                    MongoThing.remove conditions, (err) =>
                        if err
                            defered.reject(err)
                            return

                        mongoThing.save (err) =>
                            if err
                                defered.reject(err)
                            else
                                defered.resolve @mongoThingToThing(mongoThing)
                else if things.length is 1 and things[0].owner isnt undefined
                    @log.info 'This thing is already owned.'
                    error = new Error('claimed')
                    error.owner = things[0].owner
                    defered.reject error
                else
                    mongoThing.save (err) =>
                        if err
                            defered.reject(err)
                        else
                            defered.resolve @mongoThingToThing(mongoThing)

        return defered.promise

    # Claims ownership of a thing. Basically updates the information about a thing with
    # information about the owner.
    claim: (thing) =>
        @log.trace 'About to claim ownership of a thing'

        defered = Q.defer()
        proto = @thingToPrototype thing

        # first lookup the thing without owner property or notification property
        delete proto.owner
        delete proto.needsNotification

        prop = proto.properties
        delete proto['properties']

        if prop is undefined
            prop = []

        # check if the thing exsists and if it is already owned.
        MongoThing.find(proto).populate('properties', null, prop).exec (err, things) =>
            if err
                defered.reject(err)
                return

            if things.length is 1
                if things[0].owner isnt undefined
                    @log.info 'Cannot claim ownership, thing is already owned.'
                    defered.reject new Error('claimed')
                else if things[0].properties.length isnt prop.length
                    @log.info 'Not an exact match.'
                    defered.reject new Error('not-found')
                else
                    # if the thing is not owned update the information.
                    @log.info 'Claim ownership of the thing.'
                    things[0].owner = thing.owner
                    things[0].needsNotification = thing.needsNotification

                    things[0].save (err) =>
                        if err
                            defered.reject err
                        else
                            defered.resolve @mongoThingToThing(things[0])

            else if things.length is 0
                defered.reject new Error('not-found')
            else
                defered.reject new Error('illegal state')

        return defered.promise

    # Searches for things that have properties with their corresponding values
    search: (filters, offset, maxCount) =>
        @log.trace 'Searching for things...'

        if offset is undefined
            offset = 0

        defered = Q.defer()

        #proto = new Thing(undefined, properties)
        #query = (@thingToPrototype proto).properties

        # looking for public things
        query = MongoThing.find { public: true }

        #@log.trace 'Using filters:'
        #@log.trace filters

        for filter in filters
            switch filter.type
                when 'numEq'
                    query.elemMatch 'properties',
                        name: { $regex : new RegExp(filter.name, "i") }
                        numberValue: filter.value
                when 'numNEq'
                    query.where { properties: { $not: { $elemMatch: {
                        name: { $regex: filter.name, $options: 'i' }
                        numberValue: filter.value
                    } } } }
                when 'numGt'
                    query.where { properties: { $elemMatch:
                        name: { $regex: new RegExp(filter.name, "i") }
                        numberValue: { $gt: filter.value }
                    } }
                when 'numGtEq'
                    query.where { properties: { $elemMatch:
                        name: { $regex: new RegExp(filter.name, "i") }
                        numberValue: { $gte: filter.value }
                    } }
                when 'numLt'
                    query.where { properties: { $elemMatch:
                        name: { $regex: new RegExp(filter.name, "i") }
                        numberValue: { $lt: filter.value }
                    } }
                when 'numLtEq'
                    query.where { properties: { $elemMatch:
                        name: { $regex: new RegExp(filter.name, "i") }
                        numberValue: { $lte: filter.value }
                    } }
                when 'numRange'
                    expression = {}

                    if filter.minIncluded
                        expression['$gte'] = filter.min
                    else
                        expression['$gt'] = filter.min

                    if filter.maxIncluded
                        expression['$lte'] = filter.max
                    else
                        expression['$lt'] = filter.max

                    query.where { properties: { $elemMatch:
                        name: { $regex: new RegExp(filter.name, "i") }
                        numberValue: expression
                    } }
                when 'numNRange'
                    expressions = []

                    if filter.minIncluded
                        expressions.push { '$lt': filter.min }
                    else
                        expressions.push { '$lte': filter.min }

                    if filter.maxIncluded
                        expressions.push { '$gt': filter.max }
                    else
                        expressions.push { '$gte': filter.max }

                    query.where { properties: { $elemMatch:
                        name: { $regex: new RegExp(filter.name, "i") }
                        $or: [
                            { numberValue: expressions[0] }
                            { numberValue: expressions[1] }
                        ]
                    } }
                when 'strEq'
                    query.where { properties: { $elemMatch:
                        name: { $regex: new RegExp(filter.name, "i") }
                        stringValue: filter.value
                    } }
                when 'strNEq'
                    query.where { properties: { $not: { $elemMatch: {
                        name: { $regex: filter.name, $options: 'i' }
                        stringValue: filter.value
                    } } } }
                when 'strGt'
                    query.where { properties: { $elemMatch:
                        name: { $regex: new RegExp(filter.name, "i") }
                        stringValue: { $gt: filter.value }
                    } }
                when 'strGtEq'
                    query.where { properties: { $elemMatch:
                        name: { $regex: new RegExp(filter.name, "i") }
                        stringValue: { $gte: filter.value }
                    } }
                when 'strLt'
                    query.where { properties: { $elemMatch:
                        name: { $regex: new RegExp(filter.name, "i") }
                        stringValue: { $lt: filter.value }
                    } }
                when 'strLtEq'
                    query.where { properties: { $elemMatch:
                        name: { $regex: new RegExp(filter.name, "i") }
                        stringValue: { $lte: filter.value }
                    } }
                when 'strRange'
                    expression = {}

                    if filter.minIncluded
                        expression['$gte'] = filter.min
                    else
                        expression['$gt'] = filter.min

                    if filter.maxIncluded
                        expression['$lte'] = filter.max
                    else
                        expression['$lt'] = filter.max

                    query.where { properties: { $elemMatch:
                        name: { $regex: new RegExp(filter.name, "i") }
                        stringValue: expression
                    } }
                when 'strNRange'
                    expressions = []

                    if filter.minIncluded
                        expressions.push { '$lt': filter.min }
                    else
                        expressions.push { '$lte': filter.min }

                    if filter.maxIncluded
                        expressions.push { '$gt': filter.max }
                    else
                        expressions.push { '$gte': filter.max }

                    query.where { properties: { $elemMatch:
                        name: { $regex: new RegExp(filter.name, "i") }
                        $or: [
                            { stringValue: expressions[0] }
                            { stringValue: expressions[1] }
                        ]
                    } }
                when 'strMask'
                    expression = _.escapeRegExp(filter.value.replace(filter.wildcard, '.*'))
                        .replace('\\.\\*', '.*')

                    query.where { properties: { $elemMatch:
                        name: { $regex: new RegExp(filter.name, "i") }
                        stringValue: { $regex: new RegExp(expression, "g") }
                    } }
                else
                    defered.reject new Error('feature-not-implemented')
                    return defered.promise

        query.exec (err, mongoThings) =>
            if err
                defered.reject(err)
                return

            things = []

            for mongoThing in mongoThings
                if mongoThing.owner isnt undefined and mongoThing.removed isnt true
                    things.push @mongoThingToThing(mongoThing)

            # now we have the results: filter them using offset and maxCount
            more = false

            @log.trace "Found #{ things.length } results."

            if maxCount isnt undefined
                results = things.slice offset, offset + maxCount
                more = things.length > (offset + maxCount)
            else if maxCount is undefined
                results = things.slice offset
            else
                results = things

            defered.resolve things: results, more: more

        return defered.promise

    # Updates a thing in the registry
    update: (thing, updateOwner) =>
        @log.trace 'About to update the properties of a thing'

        defered = Q.defer()

        # save the properties
        updatedProperties = []
        updatedProperties = thing.properties if thing.properties

        # lookup the thing without using the properties
        thing.properties = []
        query = @thingToPrototype thing

        if thing.owner is undefined
            delete query['owner']

        # first lookup the thing
        MongoThing.find(query).exec (err, mongoThings) =>
            if err
                defered.reject err
                return

            if mongoThings.length is 1
                mongoThing = mongoThings[0]

                if mongoThing.owner is undefined
                    @log.info 'Cannot update the meta information, thing is not owned yet.'
                    defered.reject new Error('disowned')
                    return

                if updateOwner
                    mongoThing.owner = thing.owner

                mongoThing.removed = thing.removed if thing.removed
                mongoThing.needsNotification = thing.needsNotification if thing.needsNotification
                mongoThing.public = thing.public

                for property in updatedProperties
                    updated = false

                    # update this property...
                    if property.name.toUpperCase() is 'KEY'
                        mongoThing.key = property.value
                        updated = true
                    else
                        for persistentProperty in mongoThing.properties.slice()
                            if (persistentProperty.name.toUpperCase() is
                            property.name.toUpperCase())
                                if property.type is 'string' and property.value is ''
                                    mongoThing.properties = _.without mongoThing.properties,
                                        persistentProperty
                                    updated = true
                                    break
                                else
                                    persistentProperty.name = property.name
                                    persistentProperty.type = property.type

                                    if persistentProperty.type is 'number'
                                        persistentProperty.stringValue = undefined
                                        persistentProperty.numberValue = property.value
                                    else
                                        persistentProperty.numberValue = undefined
                                        persistentProperty.stringValue = property.value

                                    persistentProperty.value = property.value
                                    updated = true
                                    break

                    if not updated
                        mongoThing.properties.push @propertyToMongoProperty property

                mongoThing.save (err) =>
                    if err
                        defered.reject err

                    defered.resolve @mongoThingToThing mongoThing

            else if mongoThings.length is 0
                defered.reject new Error('not-found')
            else
                defered.reject new Error()

        return defered.promise

    # Removes a thing from the registry
    remove: (thing) =>
        @log.trace "About to remove a thing with jid: #{ thing.jid }"

        defered = Q.defer()

        # remove properties if any...
        thing.properties = []
        query = @thingToPrototype thing
        delete query['owner']

        # first lookup the thing
        MongoThing.find(query).exec (err, mongoThings) =>
            if err
                defered.reject err
                return

            if mongoThings.length is 1
                mongoThing = mongoThings[0]

                # found the thing to remove
                if mongoThing.owner isnt undefined
                    # if it is owned it can be removed by the owner
                    if mongoThing.owner is thing.owner
                        mongoThing.remove (err) =>
                            if err
                                defered.reject new Error('unregister failed')
                                return

                            @log.info 'Removed the thing from the registry'
                            defered.resolve()
                    else
                        @log.warn 'Only the owner can remove a thing.'
                        defered.reject new Error('not-allowed')
                else
                    @log.info 'Cannot remove the thing because it is not owned yet.'
                    defered.reject new Error('not-owned')
            else if mongoThings.length is 0
                @log.info 'Not found'
                defered.reject new Error('not-found')
            else
                @log.info 'Multiple results found.'
                defered.reject new Error()

        return defered.promise

    # Unregisters a thing from the registry
    unregister: (thing) =>
        @log.trace "About to unregister the thing: #{ thing.jid }"

        defered = Q.defer()

        # remove properties if any...
        thing.properties = []

        query = @thingToPrototype thing

        # first lookup the thing
        MongoThing.find(query).exec (err, mongoThings) =>
            if err
                defered.reject err
                return

            if mongoThings.length is 1
                # found the thing to unregister
                mongoThings[0].remove (err) =>
                    if err
                        defered.reject new Error('unregister failed')
                        return

                    @log.info 'Unregistered the thing from the registry'
                    defered.resolve()
            else if mongoThings.length is 0
                @log.info 'no device found'
                defered.reject new Error('not-found')
            else
                @log.info 'other reason not to execute the remove'
                @log.trace mongoThings
                defered.reject new Error()

        return defered.promise

    # Gets thing from the registry
    get: (thing) =>
        @log.trace "About the get the thing: #{ thing.jid }"

        defered = Q.defer()

        thing.properties = []
        query = @thingToPrototype thing

        # first lookup the thing
        MongoThing.find(query).exec (err, mongoThings) =>
            if err
                defered.reject err
                return

            things = []

            for mongoThing in mongoThings
                things.push @mongoThingToThing mongoThing

            defered.resolve things

        return defered.promise

    # Deserialzes an serialized object to a thing
    #
    # @param Object object containing the serialized data.
    # @return The thing.
    mongoThingToThing: (serialized) ->
        properties = []

        for property in serialized.properties
            if property.type is 'number'
                properties.push new Property('number', property.name, String(property.numberValue))
            else
                properties.push new Property('string', property.name, property.stringValue)

        thing = new Thing serialized.jid, properties
        thing.owner = serialized.owner
        thing.nodeId = serialized.nodeId
        thing.sourceId = serialized.sourceId
        thing.cacheType = serialized.cacheType
        thing.needsNotification = serialized.needsNotification
        thing.removed = serialized.removed
        thing.public = serialized.public

        if (serialized.key)
            properties.push new Property('string', 'KEY', serialized.key)

        return thing

    # Converts a Thing to a prototype that can be used in a query
    # @param [Thing] The Thing to convert.
    # @return The prototype
    thingToPrototype: (thing) ->
        serialized = { }
        serialized.properties = []

        # check if the KEY is there
        for property in thing.properties
            if property.name is 'KEY'
                serialized.key = property.value
            else
                prop =
                    name: property.name
                    type: property.type

                if property.type is 'number'
                    prop.numberValue = Number(property.value)
                else
                    prop.stringValue = property.value


                serialized.properties.push prop

        # cleanup if the array is empty
        if serialized.properties.length is 0
            delete serialized['properties']

        serialized.jid = thing.jid if thing.jid
        serialized.owner = thing.owner if thing.owner
        serialized.nodeId = thing.nodeId if thing.nodeId
        serialized.sourceId = thing.sourceId if thing.sourceId
        serialized.cacheType = thing.cacheType if thing.cacheType

        return serialized

    # Converts a Thing to a MongoThing object
    #
    # @param Thing the Thing to serialize.
    # @return The serializable object.
    thingToMongoThing: (thing) ->
        serialized = new MongoThing()

        # check if the KEY is there
        if thing.properties
            for property in thing.properties
                if property.name is 'KEY'
                    serialized.key = property.value
                else
                    serialized.properties.push @propertyToMongoProperty property

        if thing.jid
            serialized.jid = thing.jid
            serialized.owner = thing.owner
            serialized.nodeId = thing.nodeId if thing.nodeId
            serialized.sourceId = thing.sourceId if thing.sourceId
            serialized.cacheType = thing.cacheType if thing.cacheType
            serialized.needsNotification = thing.needsNotification
            serialized.removed = thing.removed
            serialized.public = thing.public

        return serialized

    # Converts a property into a MongoProperty
    propertyToMongoProperty: (property) ->
        prop = new MongoProperty()
        prop.name = property.name
        prop.type = property.type
        prop.numberValue = undefined
        prop.stringValue = undefined

        if property.type is 'number'
            prop.numberValue = Number(property.value)
        else
            prop.stringValue = property.value

        return prop

module.exports = MongooseBackend

