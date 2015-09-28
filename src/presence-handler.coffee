# XMPP presence processor for the IoT registry.

# import 3rd party stuff
ltx = require('node-xmpp-core').ltx
shortId = require 'shortid'
NodeCache = require 'node-cache'
EventEmitter = require('events').EventEmitter
{JID} = require 'node-xmpp-core'
_ = require 'lodash'
Q = require 'q'

# import classes
Logger = require './logger.coffee'
Thing = require './thing.coffee'

class PresenceHandler
    constructor: (@processor, @log) ->
        @log = new Logger() if not @log
        @log.info 'The XMPP presence handler is ready'

        # create cache for callbacks
        @watchers = new NodeCache( { stdTTL: 60, checkperiod: 100 } )

    # Handles a presence message
    handle: (stanza) =>
        @log.trace "Processing presence: #{ stanza.toString() }"
        jid = new JID stanza.attrs.from
        from = jid.bare().toString()

        switch stanza.attrs.type
            when 'subscribe'
                # handle presence subscription
                @handleSubscribe from, stanza
            when 'unsubscribe'
                # handle presence unsubscription
                @handleUnsubscribe from, stanza
            when 'subscribed'
                # handle presence subscription confirmation
                @handleSubscribed from, stanza
            when 'unsubscribed'
                # handle presence cancelation
                @handleUnsubscribed from, stanza
            when 'probe'
                @log.trace 'Ignoring probe type presence messages'
            else
                @handlePresence from, stanza

    # Handles a subscription request by sending a request
    # back to the sender.
    # @param [JID] The bare JID of the sender.
    # @param [presence] The presence message.
    handleSubscribe: (from, stanza) =>
        request = new ltx.Element 'presence',
            to: from
            from: @processor.connection.jid
            id: shortId.generate()
            type: 'subscribe'

        @log.trace "Sending: #{ request.toString() }"
        @processor.connection.send request

    # Handles a subscribed notification by allowing
    # the subscription of the sender
    # @param [JID] The bare JID of the sender.
    # @param [presence] The presence message.
    handleSubscribed: (from, stanza) =>
        response = new ltx.Element 'presence',
            to: from
            from: @processor.connection.jid
            id: shortId.generate()
            type: 'subscribed'

        @log.trace "Sending: #{ response.toString() }"
        @processor.connection.send response

    # Handles a unsubscribe request by canceling
    # the subscription on the callers presence
    # @param [JID] The bare JID of the sender.
    # @param [presence] The presence message.
    handleUnsubscribe: (from, stanza) =>
        request = new ltx.Element 'presence',
            to: from
            from: @processor.connection.jid
            id: shortId.generate()
            type: 'unsubscribed'

        @log.trace "Sending: #{ request.toString() }"
        @processor.connection.send request

        request = new ltx.Element 'presence',
            to: from
            from: @processor.connection.jid
            id: shortId.generate()
            type: 'unsubscribe'

        @log.trace "Sending: #{ request.toString() }"
        @processor.connection.send request

    # Handles a unsubscribed request by canceling
    # the subscription of the caller
    # @param [JID] The bare JID of the sender.
    # @param [presence] The presence message.
    handleUnsubscribed: (from, stanza) ->

    # Unfriends a jid
    # @param [JID] The bare JID to unfriend.
    unfriend: (jid) =>
        @log.trace "Going to unfriend #{jid}"

        # cancel the subscription ...
        cancel = new ltx.Element 'presence',
            to: jid
            from: @processor.connection.jid
            id: shortId.generate()
            type: 'unsubscribed'

        @log.trace "Sending: #{ cancel.toString() }"
        @processor.connection.send cancel

        # ... unsubscribe from the other parties presence
        unsubscribe = new ltx.Element 'presence',
            to: jid
            from: @processor.connection.jid
            id: shortId.generate()
            type: 'unsubscribe'

        @log.trace "Sending: #{ unsubscribe.toString() }"
        @processor.connection.send unsubscribe

    # Unfriends a jid when there are no Things for it
    # in the registry
    unfriendIfPossible: (jid) =>
        onFound = (things) =>
            if things.length is 0
                # There were no Things. Why are we receiving
                # presence messages from this Thing? Cancel the subscription!
                @log.info "No Things in the registry for #{ jid }. Cancelling subscription."
                @unfriend jid

        onError = (error) ->
            @log.warn "Error received is: #{ error.message }"

        isDone = @processor.backend.get new Thing(jid)
        isDone.then onFound, onError

    # Sends a probe for a jid
    # @param [JID] The bare jid to probe.
    probe: (jid) =>
        probe = new ltx.Element 'presence',
            to: jid
            from: @processor.connection.jid
            id: shortId.generate()
            type: 'probe'

        @log.trace "Probing thing with jid #{ jid }"
        @processor.connection.send probe

    # Checks a jid if it is online.
    # @param [JID] The bare jid to probe.
    # @param [timeout] Timeout in milliseconds to wait for the probe result
    #   should be less or equal to 60 seconds.
    whenOnline: (jid, timeout) =>
        defered = Q.defer()
        entry = @watchers.get jid

        if _.isEmpty(entry)
            watch = new EventEmitter()
            @watchers.set jid, watch
            @probe jid
        else
            watch = entry[jid]

        watch.once 'found', (fullJID) ->
            defered.resolve fullJID

        watch.once 'notfound', () ->
            defered.reject()

        return defered.promise.timeout(timeout)

    # Presence handler. Handles all other presence messages.
    # @param [JID] The bare jid of the sender
    # @param [stanza] The XMPP presence stanza.
    handlePresence: (jid, stanza) =>
        # Check if someone is watching this jid
        entry = @watchers.get jid
        watch = entry[jid]

        if not _.isEmpty(watch)
            @log.trace "The thing #{ jid } is #{ stanza.attrs.type }"

            if stanza.attrs.type is undefined or stanza.attrs.type isnt 'unavailable'
                process.nextTick () ->
                    watch.emit 'found', stanza.attrs.from
            else
                process.nextTick () ->
                    watch.emit 'notfound'

            @watchers.del jid

        if stanza.attrs.type is undefined or stanza.attrs.type isnt 'unavailable'
            #            # use the replies to probes which will be delayed notifications
            #            delayed = false
            #
            #            for child in stanza.children
            #                if child.name is 'delay'
            #                    delayed = true
            #
            #            # if a thing comes online check if we need to send
            #            # it a message
            #            if delayed
            @handleThingBecameAvailable jid, stanza.attrs.from

    # A thing that has a friendship relation with the registry
    # just became available. Lets check if it is claimed while
    # being offline. In that case it still needs a 'claimed' notification.
    # @param [JID] The bare jid of the sender
    handleThingBecameAvailable: (bare, full) =>
        whenFound = (things) =>
            for thing in things
                if thing.needsNotification
                    if thing.removed
                        @processor.notifyRemoved full, thing
                    else
                        @processor.notifyClaimed full, thing

            if things.length is 0
                # There were no Things. Why are we receiving
                # presence messages from this Thing? Cancel the subscription!
                @log.warn "Received presence message from Thing that is
                    not correctly registered: #{ bare }"
                # @unfriend bare
                #TODO add a timer to check if the presence subscription is still
                #     in progress. In that case, after checking again, the thing
                #     with this jid should be in the database, otherwise we can
                #     unfriend the jid

        whenNotFound = (error) =>
            @log.warn "Error received is: #{ error }"

        proto = new Thing(bare)
        proto.public = undefined
        isDone = @processor.backend.get proto
        isDone.then whenFound, whenNotFound

module.exports = PresenceHandler
