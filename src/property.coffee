# Property that describes a single piece of meta information.

class Property
    # Constructs a new thing
    #
    # @param [String] The type of the Property. Should be one of the following:
    #   * string - for properties with a string value.
    #   * number - for properties with a numeric value.
    # @param [String] The name of the property.
    # @param [Object] The value of the property.
    constructor: (@type, @name, @value) ->

module.exports = Property

