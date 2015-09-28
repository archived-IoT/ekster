# Backend for Octoblu

Backend = require './backend.coffee'
Q = require 'q'
crypto = require 'crypto'
_ = require 'lodash'
Logger = require './logger.coffee'
Thing = require './thing.coffee'
Property = require './property.coffee'

class OctobluBackend extends Backend
    @RESERVED_KEYS = [
        # xmpp stuff
        'xmpp_jid',
        'xmpp_owner',
        'xmpp_public',
        'xmpp_nodeId',
        'xmpp_sourceId',
        'xmpp_cacheType',
        'xmpp_needsNotification',
        'xmpp_removed',
        # octoblu internals
        'owner',
        'token',
        'uuid',
        'socketid',
        'timestamp',
        'channel',
        'online',
        'geo',
        'ipAddress'
    ]

    constructor: (@host, @port, @opts, @log, @skynet) ->
        super @opts

        # to make this class testable
        @skynet = require 'skynet' if not @skynet
        @log = new Logger if not @log

        @connected = false

        @log.info 'Trying to connect to octoblu...'

        @conn = @skynet.createConnection
            uuid: @opts.uuid
            token: @opts.token
            server: @host
            port: @port

        @conn.on 'notReady', (data) =>
            # maybe we should register?
            @log.warn 'Connection is not ready. Trying to register...'
            @conn.register {
                uuid: @opts.uuid
                token: @opts.token
            }, (data) =>
                if not data.uuid or data.uuid isnt @opts.uuid
                    throw new Error "Cannot register uuid '#{ @opts.uuid }' in
                        Octoblu: #{ JSON.stringify data }"

                @connected = true
                @log.info 'Registered!'

                @conn = @skynet.createConnection
                    uuid: @opts.uuid
                    token: @opts.token
                    server: @host
                    port: @port

                @listen()

        @listen()

    listen: =>
        checkReady = () =>
            if not @connected
                @conn.emit 'unboundSocket'

        setTimeout checkReady, 5000

        @conn.on 'ready', (data) =>
            @connected = true
            @log.info 'Connected!'

        @conn.on 'unboundSocket', (data) =>
            @log.fatal 'Unable to connect to octoblu'
            #throw new Error 'Unable to connect to octoblu'

        @conn.on 'disconnect', (data) =>
            @log.warn 'Disconnected from octoblu!'
            @log.info data
            # throw new Error 'Disconnected from octoblu'

    # Registers a thing.
    #
    # Some properties are used by the XMPP implementation and are
    # reserved. See RESERVED_KEYS.
    register: (thing) =>
        @log.trace 'About to registering a new thing...'

        defered = Q.defer()

        try
            octoThing = @serialize thing
        catch err
            defered.reject err
            return defered.promise

        @log.trace 'Register message is ready:'
        @log.trace octoThing

        deferedNotPresent = Q.defer()

        # check first if a thing with this uuid is already present
        @conn.devices { uuid: octoThing.uuid }, (data) =>
            if _.has(data, 'devices')

                if data.devices.length is 1
                    # if the is present check if we need to remove it first
                    @log.info 'The thing is already registered in the
                        registry.'

                    if _.has(data.devices[0], 'xmpp_owner')
                        @log.info 'This thing is already owned.'
                        error = new Error('claimed')
                        error.owner = data.devices[0].xmpp_owner
                        deferedNotPresent.reject error
                    else
                        @log.info 'This thing is not owned. It can be
                            removed and re-registered.'
                        @conn.unregister { uuid: octoThing.uuid }, (data) =>
                            if _.has(data, 'name') and data.name is 'error'
                                deferedNotPresent.reject new Error('unregister failed')

                            @log.info 'Unregistered the thing from the registry'
                            deferedNotPresent.resolve()

                else if data.devices.length is 0
                    @log.info 'The thing has has not been registered before'
                    deferedNotPresent.resolve()

                else deferedNotPresent.reject(
                    new Error 'Only 1 device expected with uuid = ' + octoThing.uuid)

            else
                if _.has(data, 'error') and data.error.message is 'Devices not found'
                    # not found so we can still register
                    deferedNotPresent.resolve()
                else
                    deferedNotPresent.reject(new Error 'Unknown state: ' + JSON.stringify(data))

        onSuccess = () =>
            @log.trace 'Cool, we have green light for adding this thing to the registry!'
            @conn.register octoThing, (data) =>
                if _.has(data, 'name') and data.name is 'error' and data.value.code is 500
                    throw new Error(data.value)

                registeredThing = @deserialize data
                @log.trace 'Deserialized thing:'
                @log.trace registeredThing
                defered.resolve registeredThing

        onError = (err) ->
            throw defered.reject(err)

        deferedNotPresent.promise.then onSuccess, onError

        return defered.promise

    # Claims ownership of a thing. Basically updates the information about a thing with
    # information about the owner.
    claim: (thing) =>
        @log.trace 'About to claim ownership of a thing'

        defered = Q.defer()
        octoThing = @serialize thing

        # first lookup the thing without owner property or notification property
        delete octoThing.xmpp_owner
        delete octoThing.xmpp_needsNotification

        # check if the thing exsists and if it is already owned.
        @conn.devices octoThing, (data) =>
            if _.has(data, 'devices') and data.devices.length is 1

                if _.has(data.devices[0], 'xmpp_owner')
                    @log.info 'Cannot claim ownership, thing is already owned.'
                    defered.reject new Error('claimed')
                else
                    # if the thing is not owned update the information.
                    @log.info 'Claim ownership of the thing.'
                    data.devices[0].xmpp_owner = thing.owner
                    data.devices[0].xmpp_needsNotification = thing.needsNotification.toString()

                    @conn.update data.devices[0], (data) =>
                        if _.has(data, 'name') and data.name is 'error'
                            defered.reject new Error(data.value)

                        claimedThing = @deserialize data
                        defered.resolve claimedThing

            else if data.devices.length is 0
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

        template = {}
        for filter in filters
            if filter.type isnt 'strEq' and filter.type isnt 'numEq'
                defered.reject new Error('feature-not-implemented')
                return defered.promise

            template[filter.name] = filter.value

        @conn.devices template, (data) =>
            things = []

            if _.has(data, 'devices')
                for device in data.devices
                    if _.has(device, 'xmpp_owner')
                        found = @deserialize(device)
                        if found.removed isnt true and found.public
                            things.push found
                    else
                        @log.info 'Unowned device removed from search results.'

                # not we have the results: filter them using offset and maxCount
                more = false

                if maxCount isnt undefined
                    results = things.slice offset, offset + maxCount
                    more = things.length > (offset + maxCount)
                else if maxCount is undefined
                    results = things.slice offset
                else
                    results = things

                defered.resolve things: results, more: more
            else
                defered.reject new Error('error searching for things')

        return defered.promise

    # Updates a thing in the registry
    update: (thing, updateOwner) =>
        @log.trace 'About to update the properties of a thing'

        defered = Q.defer()

        # save the properties
        properties = thing.properties

        # lookup the thing without using the properties
        thing.properties = []
        octoThing = @serialize thing, false

        # first lookup the thing
        @conn.devices octoThing, (data) =>
            if _.has(data, 'devices') and data.devices.length is 1
                # found the thing to update
                if _.has(data.devices[0], 'xmpp_owner')
                    # if it is owned it can be updated
                    update = data.devices[0]

                    if updateOwner
                        update.xmpp_owner = thing.owner

                    for property in properties
                        if property.type is 'string' and property.value is ''
                            update[property.name] = undefined
                        else
                            update[property.name] = property.value

                    @conn.update update, (result) =>
                        if _.has(result, 'name') and result.name is 'error'
                            defered.reject new Error(result.value)

                        claimedThing = @deserialize result.devices[0]
                        defered.resolve claimedThing

                else
                    @log.info 'Cannot update the meta information, thing is not owned yet.'
                    defered.reject new Error('disowned')

            else if data.devices.length is 0
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
        octoThing = @serialize thing, false

        # lookup the thing
        @conn.devices octoThing, (data) =>
            if _.has(data, 'devices') and data.devices.length is 1
                # found the thing to remove
                if _.has(data.devices[0], 'xmpp_owner')
                    # if it is owned it can be removed by the owner
                    if data.devices[0].xmpp_owner is thing.owner
                        @conn.unregister { uuid: octoThing.uuid }, (data) =>
                            if _.has(data, 'name') and data.name is 'error'
                                defered.reject new Error('unregister failed')

                            @log.info 'Unregistered the thing from the registry'
                            defered.resolve()
                    else
                        @log.warn 'Only the owner can remove a thing.'
                        defered.reject new Error('not-allowed')
                else
                    @log.info 'Cannot remove the thing because it is not owned yet.'
                    defered.reject new Error('not-owned')
            else if data.devices.length is 0
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
        octoThing = @serialize thing, false

        # lookup the thing
        @conn.devices octoThing, (data) =>
            if _.has(data, 'devices') and data.devices.length is 1
                # found the thing to remove
                @conn.unregister { uuid: octoThing.uuid }, (data) =>
                    if _.has(data, 'name') and data.name is 'error'
                        defered.reject new Error('unregister failed')

                    @log.info 'Unregistered the thing from the registry'
                    defered.resolve()
            else if data.devices.length is 0
                @log.info 'no device found'
                defered.reject new Error('not-found')
            else
                @log.info 'other reason not to execute the remove'
                @log.trace data
                defered.reject new Error()

        return defered.promise

    # Gets thing from the registry
    get: (thing) =>
        @log.trace "About the get the thing: #{ thing.jid }"

        defered = Q.defer()

        thing.properties = []
        octoThing = @serialize thing, false

        # do not use the hash for getting thing based upon JID
        delete octoThing['uuid']

        # lookup the thing
        @conn.devices octoThing, (data) =>
            things = []

            if _.has(data, 'devices')
                for device in data.devices
                    things.push @deserialize(device)

                defered.resolve things
            else
                defered.reject new Error(data.error.message)

        return defered.promise

    # Deserialzes an octublu object to a thing
    #
    # @param Object object containing the octublu data.
    # @return The thing.
    deserialize: (data) ->
        properties = []

        for key in _.keys(data)
            if _.indexOf(OctobluBackend.RESERVED_KEYS, key) is -1
                properties.push new Property('string', key, data[key])

        thing = new Thing data.jid, properties
        thing.uuid = data.uuid
        thing.token = data.token
        thing.jid = data.xmpp_jid
        thing.owner = data.xmpp_owner
        thing.nodeId = data.xmpp_nodeId
        thing.sourceId = data.xmpp_sourceId
        thing.cacheType = data.xmpp_cacheType

        if data.xmpp_needsNotification
            thing.needsNotification = (data.xmpp_needsNotification is 'true')

        if data.xmpp_removed
            thing.removed = (data.xmpp_removed is 'true')

        if data.xmpp_public
            thing.public = (data.xmpp_public is 'true')
        else
            thing.public = true

        return thing

    # Serializes a Thing to an actoblu object
    #
    # @param Thing the Thing to serialize.
    # @return The octoblu object.
    # @throws Error when a thing contains illegal keys
    serialize: (thing, checkForKey) =>
        if checkForKey is undefined
            checkForKey = true

        octoThing = {}

        # check if the KEY is there
        for property in thing.properties
            if _.indexOf(OctobluBackend.RESERVED_KEYS,
                property.name) isnt -1
                throw new Error("Illegal property: #{ property.name }")

            if _.contains(octoThing, property.name)
                throw new Error("Duplicate property: #{ property.name }")

            if property.type is 'number'
                @log.warn 'Octoblu does not support numeric values.
                    Converting to string!'

            if property.name is 'KEY'
                octoThing.token = property.value
            else
                octoThing[property.name] = property.value

        if checkForKey is true and not octoThing.token
            throw new Error 'Missing property: KEY'

        # set the properties of the octoThing
        octoThing.owner = @opts.uuid

        if thing.jid
            octoThing.uuid = @createUUID thing
            octoThing.xmpp_jid = thing.jid
            octoThing.xmpp_owner = thing.owner
            octoThing.xmpp_nodeId = thing.nodeId if thing.nodeId
            octoThing.xmpp_sourceId = thing.sourceId if thing.sourceId
            octoThing.xmpp_cacheType = thing.cacheType if thing.cacheType
            octoThing.xmpp_needsNotification =
                thing.needsNotification.toString() if thing.needsNotification
            octoThing.xmpp_removed =
                thing.removed.toString() if thing.removed

            if thing.public is undefined or thing.public
                octoThing.xmpp_public = 'true'
            else
                octoThing.xmpp_public = 'false'

        for key in _.keys(octoThing)
            if octoThing[key] is undefined
                delete octoThing[key]

        return octoThing

    # Creates a UUID of the thing based upon the Thing's information
    #
    # @param Thing the Thing to calculate the uuid for.
    # returns The uuid of the Thing.
    createUUID: (thing) ->
        # determine UUID

        hash = crypto.createHash 'md5'
        hash.update thing.jid
        hash.update thing.nodeId if thing.nodeId
        hash.update thing.sourceId if thing.sourceId
        hash.update thing.cacheType if thing.cacheType
        return hash.digest 'hex'

module.exports = OctobluBackend
