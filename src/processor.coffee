# XMPP message processor for the IoT registry.

# import 3rd party stuff
ltx = require('node-xmpp-core').ltx
{JID} = require 'node-xmpp-core'
shortId = require 'shortid'
_ = require 'lodash'
NodeCache = require 'node-cache'
Q = require 'q'

# import classes
Logger = require './logger.coffee'
Property = require './property.coffee'
Thing = require './thing.coffee'
PresenceHandler = require './presence-handler.coffee'
Filter = require './filter.coffee'

class Processor
    constructor: (@connection, @jid, @backend, @log) ->
        @connection.on 'stanza', @process
        @log = new Logger() if not @log
        @log.info 'The XMPP event processor is ready'
        @presenceHandler = new PresenceHandler(this, @log)

        # create cache for callbacks
        @queries = new NodeCache stdTTL: 60, checkperiod: 100
        @queries.on 'expired', (key, value) =>
            # when the waiting period for a message expires. Rejet the query.
            @log.info "Not getting a response for message #{ key }.
                Rejecting the promise for the result."
            value.reject()

    # Checks whether the request element has the correct namespace.
    #
    # @param [Object] The request part of the incomming message.
    checkNamespace = (request) ->
        if request.attrs.xmlns isnt 'urn:xmpp:iot:discovery'
            throw new Error "Unknown namespace in register
                message: #{ request.attrs.xmlns }"

    # Parses the properties in a request and returns them in an array.
    #
    # @param [Object] The request containing the properties
    # @returns [Array] The array with all properties.
    parseProperties = (request) ->
        properties = []

        for child in request.children
            if _.isObject(child)
                switch child.name
                    when 'str'
                        property = new Property 'string',
                            child.attrs.name,
                            child.attrs.value
                        properties.push property
                    when 'num'
                        property = new Property 'number',
                            child.attrs.name,
                            parseFloat child.attrs.value

                        if _.isNaN(property.value)
                            throw new Error "Received an illegal value
                            #{ child.attrs.value }, expected a
                            number value."

                        properties.push property
                    else
                        throw new Error "Unknown property type
                            received: #{ child.name }"

        return properties

    # Replies to a message with an error response.
    #
    # @param [Object] The message that needs a reply.
    # @param [Error] The error object.
    respondWithError: (stanza, error) ->
        @log.warn error.message
        result = new ltx.Element 'iq',
            to: stanza.attrs.from
            from: @jid
            type: 'error'
            id: stanza.attrs.id
        @connection.send result

    respondWithServiceUnavailable: (stanza) ->
        result = new ltx.Element 'iq',
            to: stanza.attrs.from
            from: @jid
            type: 'error'
            id: stanza.attrs.id

        result.children = stanza.children
        result.c('error', type: 'cancel')
            .c('service-unavailable', xmlns: 'urn:ietf:params:xml:ns:xmpp-stanzas')

        @connection.send result

    # Process an incoming message stanza
    #
    # @param [Object] The stanza that was received.
    process: (stanza) =>
        @log.trace stanza.toString()

        if stanza.name is 'presence'
            # ignore error stanza's
            if stanza.attrs.type isnt 'error'
                @presenceHandler.handle stanza, @connection, @backend
            return

        if stanza.name isnt 'iq'
            # do not respond on anything but <iq/> messages
            @log.warn 'I will only respond to <iq/> messages!'
            return

        children = 0
        request = undefined

        for child in stanza.children
            if _.isObject(child)
                request = child
                children++

        # handle responses of queries that were send by the processor
        if stanza.attrs.type is 'result' or stanza.attrs.type is 'error'
            item = @queries.get stanza.attrs.id

            if item[stanza.attrs.id]
                item[stanza.attrs.id].resolve stanza
                @queries.del stanza.attrs.id

            return

        if (not stanza.children) or (children isnt 1) or (
            stanza.attrs.type isnt 'get' and stanza.attrs.type isnt 'set')
            # Only respond to 'get' or 'set' messages.
            # This type of messages must have only child element
            # https://xmpp.org/rfcs/rfc6120.html#stanzas-semantics-iq
            result = new ltx.Element 'iq',
                to: stanza.attrs.from
                from: @jid
                type: 'error'
                id: stanza.attrs.id

            @connection.send result
            @log.warn "Got a message that cannot be processed: #{ stanza }"
            return

        # now we have a valid request that we should handle somehow.
        from = (new JID stanza.attrs.from).bare()

        try
            switch request.name
                when 'register'
                    @processRegister from, request, stanza
                when 'unregister'
                    @processUnregister from, request, stanza
                when 'disown'
                    @processDisown from, request, stanza
                when 'mine'
                    @processMine from, request, stanza
                when 'remove'
                    @processRemove from, request, stanza
                when 'update'
                    @processUpdate from, request, stanza
                when 'search'
                    @processSearch from, request, stanza
                when 'query'
                    @processQuery from, request, stanza
                when 'ping'
                    @processPing from, request, stanza
                else
                    @respondWithServiceUnavailable stanza
        catch error
            @respondWithError stanza, error

    # Process a 'ping' message
    processPing: (from, request, stanza) =>
        @log.trace 'Processing ping.'

        result = new ltx.Element 'iq',
            to: stanza.attrs.from
            from: @jid
            id: stanza.attrs.id
            type: 'result'

        @connection.send result

    # Process a 'query' message
    processQuery: (from, request, stanza) =>
        @log.trace 'Processing query.'

        result = new ltx.Element 'iq',
            to: stanza.attrs.from
            from: @jid
            id: stanza.attrs.id

        if request.attrs and request.attrs.xmlns is 'http://jabber.org/protocol/disco#info'
            # support the info query
            result.attrs.type = 'result'
            result.c('query', xmlns: 'http://jabber.org/protocol/disco#info')
                .c('feature', var: 'urn:xmpp:iot:discovery')
        else
            # do not support other query namespaces
            result.attrs.type = 'error'
            result.c('error', type: 'cancel')
                .c('feature-not-implemented',
                    xmlns: 'urn:ietf:params:xml:ns:xmpp-stanzas')

        @connection.send result

    # Process an 'search' message
    processSearch: (from, request, stanza) =>
        @log.trace 'Processing search.'

        checkNamespace request, stanza
        filters = []

        result = new ltx.Element 'iq',
            to: stanza.attrs.from
            from: @jid
            id: stanza.attrs.id

        offset = parseInt request.attrs.offset
        maxCount = parseInt request.attrs.maxCount

        if isNaN(offset) or isNaN(maxCount)
            @respondWithError stanza, new Error 'illegal value'
            return

        for operator in request.children
            if _.isObject operator
                if operator.attrs.name is 'KEY'
                    result.attrs.type = 'result'
                    result.c 'found',
                        xmlns: 'urn:xmpp:iot:discovery'
                        more: false

                    @connection.send result
                    return

                filter = new Filter(operator.name,
                    operator.attrs.name, operator.attrs.value)

                filter.max = operator.attrs.max
                filter.min = operator.attrs.min
                filter.wildcard = operator.attrs.wildcard

                if operator.attrs.minIncluded and operator.attrs.minIncluded is 'false'
                    filter.minIncluded = false

                if operator.attrs.maxIncluded and operator.attrs.maxIncluded is 'false'
                    filter.maxIncluded = false

                filters.push filter

        onSuccess = (answer) =>
            # on success send a response...
            result.attrs.type = 'result'
            found = result.c 'found',
                xmlns: 'urn:xmpp:iot:discovery'
                more: answer.more

            for thing in answer.things
                child = found.c 'thing',
                    owner: thing.owner
                    jid: thing.jid

                child.attrs.nodeId = thing.nodeId if thing.nodeId
                child.attrs.sourceId = thing.sourceId if thing.sourceId
                child.attrs.cacheType = thing.cacheType if thing.cacheType

                for property in thing.properties
                    if property.name isnt 'KEY'
                        switch property.type
                            when 'string'
                                child.c 'str',
                                    name: property.name
                                    value: property.value
                            when 'number'
                                child.c 'num',
                                    name: property.name
                                    value: property.value
                            else
                                @log.warn "Illigal propety type found
                                in thing: #{ JSON.stringify thing }"

            @connection.send result

        onError = (error) =>
            if error.message is 'feature-not-implemented'
                result.attrs.type ='error'
                result.c('error', type: 'cancel')
                    .c('feature-not-implemented',
                        xmlns: 'urn:ietf:params:xml:ns:xmpp-stanzas')
            else
                result.attrs.type = 'result'
                result.c 'found',
                    xmlns: 'urn:xmpp:iot:discovery'
                    more: false

            @connection.send result

        @log.trace 'Calling search on backend.'
        promise = @backend.search(filters, offset, maxCount)
        promise.then onSuccess, onError

    # Process an 'update' message
    processUpdate: (from, request, stanza) =>
        @log.trace 'Processing update.'

        checkNamespace request, stanza

        if request.attrs.jid
            thing = new Thing request.attrs.jid, parseProperties request
            thing.owner = from.toString()
        else
            thing = new Thing from.toString(), parseProperties request

        thing.nodeId = request.attrs.nodeId
        thing.sourceId = request.attrs.sourceId
        thing.cacheType = request.attrs.cacheType

        result = new ltx.Element 'iq',
            to: stanza.attrs.from
            from: @jid
            id: stanza.attrs.id

        onSuccess = (thing) =>
            # on success send a response...
            result.attrs.type = 'result'
            @connection.send result

        onError = (error) =>
            if error.message is 'not-found'
                result.attrs.type = 'error'
                result.c('error', type: 'cancel')
                    .c('item-not-found',
                        xmlns: 'urn:ietf:params:xml:ns:xmpp-stanzas')
                @connection.send result

            else if error.message is 'disowned'
                result.attrs.type = 'result'
                result.c('disowned',
                    xmlns: 'urn:xmpp:iot:discovery')
                @connection.send result

            else
                @respondWithError stanza, error

        promise = @backend.update(thing)
        promise.then onSuccess, onError

    # Process a 'unregister' message
    processUnregister: (from, request, stanza) =>
        @log.trace 'Processing unregister.'

        checkNamespace request, stanza
        thing = new Thing from.toString()
        thing.nodeId = request.attrs.nodeId
        thing.sourceId = request.attrs.sourceId
        thing.cacheType = request.attrs.cacheType

        result = new ltx.Element 'iq',
            to: stanza.attrs.from
            from: @jid
            type: 'result'
            id: stanza.attrs.id

        onSuccess = () =>
            @connection.send result

        onError = (error) =>
            # in case of an error we are logging here.
            # response is the same
            @log.info "Unregistering Thing failed: #{ thing }"
            @connection.send result

        promise = @backend.unregister(thing)
        promise.then onSuccess, onError

    # Sends a removed message to the JID and cancels the
    # presence subscription in case no Things are registered
    # with that JID.
    notifyRemoved: (jid, thing) =>
        message = new ltx.Element 'iq',
            to: jid,
            from: @jid,
            type: 'set',
            id: shortId.generate()

        attrs = {}
        attrs.xmlns = 'urn:xmpp:iot:discovery'

        # only add jid if the thing isnt behind a concentrator
        attrs.jid = thing.jid if thing.nodeId or
            thing.sourceId or thing.cacheType

        attrs.nodeId = thing.nodeId if thing.nodeId
        attrs.sourceId = thing.sourceId if thing.sourceId
        attrs.cacheType = thing.cacheType if thing.cacheType
        message.c 'removed', attrs

        defered = Q.defer()

        onResponse = (response) =>
            # when the Thing confirms the removal we can
            # remove and unsubscribe
            if response.attrs.type is 'result'
                onSuccess = () =>
                    @log.info 'Removed the Thing from the registry'

                onError = (thing) =>
                    @log.error 'Cannot remove the Thing from the registry'

                promise = @backend.remove(thing)
                promise.then onSuccess, onError

                # check if this was the last thing with this JID
                @presenceHandler.unfriendIfPossible thing.jid
            else
                @log.warn "Unexpected response on removed notifcation to #{ jid }"

        onTimeout = () =>
            @log.info "Thing #{ jid } did not confirm removal."

        defered.promise.then onResponse, onTimeout
        @queries.set message.attrs.id, defered
        @connection.send message

    # Process a 'remove' message
    processRemove: (from, request, stanza) =>
        @log.trace 'Processing remove.'

        checkNamespace request, stanza
        thing = new Thing request.attrs.jid
        thing.owner = from.bare().toString()
        thing.nodeId = request.attrs.nodeId
        thing.sourceId = request.attrs.sourceId
        thing.cacheType = request.attrs.cacheType
        thing.removed = true
        thing.needsNotification = true

        onSuccess = () =>
            # on success first send the response...
            result = new ltx.Element 'iq',
                to: stanza.attrs.from
                from: @jid
                type: 'result'
                id: stanza.attrs.id

            @connection.send result
            # probe to force notification if the thing in online now
            @presenceHandler.probe thing.jid

        onError = (error) =>
            if error.message is 'not-found'
                result = new ltx.Element 'iq',
                    to: stanza.attrs.from
                    from: @jid
                    id: stanza.attrs.id
                    type: 'error'

                result.c('error', type: 'cancel')
                    .c('item-not-found',
                        xmlns: 'urn:ietf:params:xml:ns:xmpp-stanzas')

                @connection.send result
            else
                @respondWithError stanza, error

        promise = @backend.update(thing)
        promise.then onSuccess, onError

    # Sends 'disowned' and processes the result.
    sendDisowned: (jid, thing, stanza) =>
        @log.trace "Sending disowned message to #{ thing.jid }"

        # notify the thing that it is being disowned
        message = new ltx.Element 'iq',
            to: jid,
            from: @jid,
            type: 'set',
            id: shortId.generate()

        attrs = {}
        attrs.xmlns = 'urn:xmpp:iot:discovery'

        attrs.nodeId = thing.nodeId if thing.nodeId
        attrs.sourceId = thing.sourceId if thing.sourceId
        attrs.cacheType = thing.cacheType if thing.cacheType

        message.c 'disowned', attrs

        defered = Q.defer()

        onResponse = (response) =>
            if response.attrs.type is 'result'
                # handle success situation
                # if the message has been received succesfully
                # then update the registry
                thing.owner = undefined
                thing.needsNotification = false
                addKey = true
                keyValue = shortId.generate() + shortId.generate() +
                    shortId.generate() + shortId.generate()

                for property in thing.properties
                    if property.name is 'KEY'
                        addKey = false
                        property.value = keyValue
                    else
                        property.type = 'string'
                        property.value = ''

                thing.properties.push new Property('string', 'KEY', keyValue) if addKey

                updateOk = () =>
                    @log.trace 'Update successful. Thing has been disowned'
                    result = new ltx.Element 'iq',
                        to: stanza.attrs.from
                        from: @jid
                        id: stanza.attrs.id
                        type: 'result'

                    @connection.send result

                updateNotOk = () =>
                    @respondWithError stanza, new Error("Update of Thing #{ thing.jid }
                        failed after successfully sending a disowned message")

                succesfullUpdate = @backend.update(thing, true)
                succesfullUpdate.then updateOk, updateNotOk
            else
                # handle error situation
                @respondWithError stanza, new Error("Received an error when sending the disowned
                    notifcation to #{ thing.jid }. Notifying the owner")

        onTimeout = () ->
            @respondWithError stanza, new Error("Disowned message to #{ thing.jid } timed out.")

        defered.promise.then onResponse, onTimeout
        @queries.set message.attrs.id, defered
        @connection.send message


    # Process a 'disown' message
    processDisown: (from, request, stanza) =>
        @log.trace 'Processing disown.'

        checkNamespace request, stanza
        proto = new Thing request.attrs.jid
        proto.owner = from.toString()
        proto.nodeId = request.attrs.nodeId
        proto.sourceId = request.attrs.sourceId
        proto.cacheType = request.attrs.cacheType

        onSuccess = (things) =>
            # if there is no matching thing let the caller know
            if things.length is 0
                result = new ltx.Element 'iq',
                    to: stanza.attrs.from
                    from: @jid
                    id: stanza.attrs.id
                    type: 'error'

                result.c('error', type: 'cancel')
                    .c('item-not-found',
                        xmlns: 'urn:ietf:params:xml:ns:xmpp-stanzas')

                @connection.send result
            else if things.length is 1
                thing = things[0]

                # lets check if the caller owns this thing,
                # we should not get in this situation if the backend
                # works correctly though...
                if thing.owner isnt proto.owner
                    @respondWithError stanza, new Error('The backend did not implement the get
                        method correctly. It does not filter on the owner property.')
                else
                    whenOnline = (jid) =>
                        @sendDisowned jid, thing, stanza

                    whenOffline = () =>
                        # when not online the thing can not be disowned
                        result = new ltx.Element 'iq',
                            to: stanza.attrs.from
                            from: @jid
                            id: stanza.attrs.id
                            type: 'error'

                        result.c('error', type: 'cancel')
                            .c('not-allowed',
                                xmlns: 'urn:ietf:params:xml:ns:xmpp-stanzas')

                        @connection.send result

                    isOnline = @presenceHandler.whenOnline thing.jid, 6000, @connection
                    isOnline.then whenOnline, whenOffline
            else
                # should not have multiple results
                @respondWithError stanza,
                    new Error( "Found multiple results for disown request: #{ proto.jid }")

        onError = (error) =>
            @respondWithError stanza, error

        promise = @backend.get proto
        promise.then onSuccess, onError

    # Sends 'claimed' notification is needed.
    notifyClaimed: (jid, thing) =>
        @log.trace "Sending claimed message to #{ thing.jid }"

        # notify the thing about its new owner
        message = new ltx.Element 'iq',
            to: jid,
            from: @jid,
            type: 'set',
            id: shortId.generate()

        attrs = {}
        attrs.jid = thing.owner
        attrs.xmlns = 'urn:xmpp:iot:discovery'

        attrs.nodeId = thing.nodeId if thing.nodeId
        attrs.sourceId = thing.sourceId if thing.sourceId
        attrs.cacheType = thing.cacheType if thing.cacheType
        # only include the public attribute when the thing isn't public
        attrs.public = 'false' if thing.public isnt true

        message.c 'claimed', attrs

        defered = Q.defer()

        onResponse = (response) =>
            if response.attrs.type is 'result'
                # handle succes situation
                # if the message has been received succesfully
                # then update the registry
                thing.needsNotification = false

                updateOk = () ->
                    @log.trace 'Update successful. Thing does not need updating anymore'

                updateNotOk = () ->
                    @log.error "Update of Thing #{ thing.jid } failed after successfully
                        sending a claimed message"

                succesfullUpdate = @backend.update(thing)
                succesfullUpdate.then updateOk, updateNotOk
            else
                # handle error situation
                @log.warn "Received an error when sending the claim notifcation to
                    #{ thing.jid }. Trying it again later..."

        onTimeout = () ->
            @log.info "Claimed message to #{ thing.jid } timed out. Not updating the
                registry, message will be send again..."

        defered.promise.then onResponse, onTimeout
        @queries.set message.attrs.id, defered
        @connection.send message

    # Process a 'mine' message
    processMine: (from, request, stanza) =>
        @log.trace 'Processing mine.'

        checkNamespace request, stanza
        thing = new Thing undefined, parseProperties request
        thing.owner = from.bare().toString()
        thing.needsNotification = true

        if request.attrs.public is 'false'
            thing.public = false

        onSuccess = (thing) =>
            # on success first send the response...
            result = new ltx.Element 'iq',
                to: stanza.attrs.from
                from: @jid
                type: 'result'
                id: stanza.attrs.id

            attrs = {}
            attrs.jid = thing.jid
            attrs.xmlns = 'urn:xmpp:iot:discovery'

            attrs.nodeId = thing.nodeId if thing.nodeId
            attrs.sourceId = thing.sourceId if thing.sourceId
            attrs.cacheType = thing.cacheType if thing.cacheType

            result.c 'claimed', attrs
            @connection.send result
            @presenceHandler.probe thing.jid

        onError = (error) =>
            if error.message is 'claimed' or error.message is 'not-found'
                result = new ltx.Element 'iq',
                    to: stanza.attrs.from
                    from: @jid
                    id: stanza.attrs.id
                    type: 'result'

                result.c('error', type: 'cancel')
                    .c('item-not-found',
                        xmlns: 'urn:ietf:params:xml:ns:xmpp-stanzas')

                @connection.send result
            else
                @respondWithError stanza, error


        promise = @backend.claim(thing)
        promise.then onSuccess, onError

    # Process a 'register' message
    processRegister: (from, request, stanza) =>
        @log.trace 'Processing register.'

        checkNamespace request, stanza

        thing = new Thing from.toString(), parseProperties request
        thing.nodeId = request.attrs.nodeId
        thing.sourceId = request.attrs.sourceId
        thing.cacheType = request.attrs.cacheType

        if request.attrs.selfOwned is 'true'
            thing.owner = from.bare().toString()

        onSuccess = =>
            result = new ltx.Element 'iq',
                to: stanza.attrs.from
                from: @jid
                type: 'result'
                id: stanza.attrs.id
            @connection.send result

        onError = (error) =>
            if error.message is 'claimed'
                result = new ltx.Element 'iq',
                    to: stanza.attrs.from
                    from: @jid
                    id: stanza.attrs.id
                    type: 'result'
                result.c 'claimed',
                    xmlns: 'urn:xmpp:iot:discovery'
                    jid: error.owner

                @connection.send result
            else
                @respondWithError stanza, error

        promise = @backend.register(thing)
        promise.then onSuccess, onError

module.exports = Processor
