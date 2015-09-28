# Base class for all backends.
#
# @example How to subsclass an backend
#   class MyBackend extends Backend
#       register: (thing) ->

class Backend
    # Constructs a new backend
    #
    # @param [Object] Options for initializing the backend
    constructor: (opts) ->

    # Registers a new Thing in the backend.
    #
    # @param [Thing] The thing to register.
    # @return [Promise] A promise that will be successfull if the registration
    # succeeds or not not successfull if something goes wrong. When the promise
    # is rejected one of these error objects should be passed:
    # * new Error() - general error
    # * new Error("claimed") - when ownership of a device has already been
    #   claimed.
    #   - In this case the property `owner` should be set with the JID of
    #       the owner of the Thing.
    register: (thing) ->
        throw new Error('Backend.register is not implemented.')

    # Unregisters a new Thing from the backend.
    #
    # @param [Thing] The thing to unregister.
    # @return [Promise] A promise that will be successfull if the unregistration
    # succeeds or not not successfull if something goes wrong.
    # * new Error() - general error
    unregister: (thing) ->
        throw new Error('Backend.unregister is not implemented.')

    # Claims a Thing from the backend.
    #
    # @param [Thing] The thing to claim.
    # @return [Promise] A promise that will succeed with a reference to the
    #   Thing when the claim has been made or rejected when something went
    #   wrong. When the promise is rejected one of these error objects should
    #   be passed:
    #   * new Error() - general error
    #   * new Error("claimed") - when ownership of a device has already been
    #       claimed.
    #   * new Error("claimed-by-claimer") - when ownership of a device has already
    #       been claimed by the claimer.
    #   * new Error("not-found") - when the thing is not found in the registry.
    claim: (thing) ->
        throw new Error('Backend.claim is not implemented.')

    # Removes a Thing from the backend
    #
    # @param [Thing] The thing to remove. At least the `jid` and `owner`
    #   properties should be set.
    # @return [Promise] A promise that will succeed when the thing was removed.
    #   Or the promise will be rejected when something went wrong. In the latter
    #   case one of these error object are passed to the failure function:
    #   * new Error() - general error
    #   * new Error("not-found") - when the thing is not found in the
    #       registry or the entitiy requesting the removal is not the owner.
    remove: (thing) ->
        throw new Error('Backend.remove is not implemented.')

    # Update a Thing in the backend
    #
    # @param [Thing] A thing that should be updated. If a property contains
    #   an empty string value and are of string type then that property
    #   should be removed from the database (3.13 from spec).
    # @param [updateOwner] True if the owner field should be updated as well.
    # @return [Promise] A promise that will succeed with a reference to the
    #   updated Thing when the update was successful. When the promise is
    #   rejected one of these error objects should be passed:
    #   * new Error() - general error
    #   * new Error("not-found") - when the thing could not be found in the
    #       registry.
    #   * new Error("disowned") - when the thing is not owned by anyone.
    update: (thing, updateOwner) ->
        throw new Error('Backend.update is not implemented.')

    # Searches for Things in the backend
    #
    # @param [Array] Array of Properties that the things should match.
    # @param [Number] The number of responses to skip.
    # @param [Number] The desired maximum number of things to return.
    # @return [Promise] A promise that will succeed with an object that
    #   has a 'things' property with an array of things that match the properties.
    #   And a 'more' property indicating if there are more results that match the
    #   query.
    search: (properties, offset, maxCount) ->
        throw new Error('Backend.search is not implemented.')

    # Gets a specific Thing from the backend
    # @param [thing] A prototype identifing the thing
    # @return [Promise] A promise that will succeed with a reference to an
    #   array of Things. The array will the things registered with the JID.
    #   The list can be empty, contain a single Thing or multiple JIDs in
    #   case the JID belongs to a concentrator.
    #
    #   When the promise is rejected one of these error object should
    #   be passed:
    #   * new Error() - general error
    get: (thing) ->
        throw new Error('Backend.get is not implemented.')

module.exports = Backend
