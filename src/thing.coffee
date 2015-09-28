# Base class for a thing.

class Thing
    # Constructs a new thing
    #
    # @param [String] The jid of the thing
    # @param [Array] The meta data of the thing
    # @param [String] The id of the thing when it is behind
    # a concentrator.
    constructor: (@jid, @properties) ->
        @nodeId = undefined
        @sourceId = undefined
        @cacheType = undefined
        @owner = undefined
        @public = true
        @needsNotification = undefined
        @removed = undefined

module.exports = Thing

