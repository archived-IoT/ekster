# Filter that can be used for filtering search results

class Filter
    # Constructs a new filter.
    #
    # @param [String] The type of the filter. Should be one of the elements
    #   from the table in XEP-0347 (table 2):
    #   * strEq     - Searches for string values tags with values
    #                   equal to a provided constant value.
    #   * strNEq    - Searches for string values tags with values
    #                   not equal to a provided constant value.
    #   * strGt     - Searches for string values tags with values
    #                   greater than a provided constant value.
    #   * strGtEq   - Searches for string values tags with values
    #                   greater than or equal to a provided constant value.
    #   * strLt     - Searches for string values tags with values
    #                   lesser than a provided constant value.
    #   * strLtEq   - Searches for string values tags with values
    #                   lesser than or equal to a provided constant value.
    #   * strRange  - Searches for string values tags with values
    #                   within a specified range of values. The endpoints can be
    #                   included or excluded in the search.
    #   * strNRange - Searches for string values tags with values
    #                   outside of a specified range of values. The endpoints can be
    #                   included or excluded in the range (and therefore correspondingly
    #                   excluded or included in the search).
    #   * strMask   - Searches for string values tags with values
    #                   similar to a provided constant value including wildcards.
    #   * numEq     - Searches for numerical values tags with values
    #                   equal to a provided constant value.
    #   * numNEq    - Searches for numerical values tags with values
    #                   not equal to a provided constant value.
    #   * numGt     - Searches for numerical values tags with values
    #                   greater than a provided constant value.
    #   * numGtEq   - Searches for numerical values tags with values
    #                   greater than or equal to a provided constant value.
    #   * numLt     - Searches for numerical values tags with values
    #                   lesser than a provided constant value.
    #   * numLtEq   - Searches for numerical values tags with values
    #                   lesser than or equal to a provided constant value.
    #   * numRange  - Searches for numerical values tags with values
    #                   within a specified range of values. The endpoints can be included
    #                   or excluded in the search.
    #   * numNRange - Searches for numerical values tags with values outside of a specified
    #                   range of values. The endpoints can be included or excluded in the range
    #                   (and therefore correspondingly excluded or included in the search).
    # @param [String] The name of the property to filter.
    # @param [Object] The value to filter.
    constructor: (@type, @name, @value) ->
        # The above properties are used for strEq, strNEq, strGt, strGtEq, strLt, strLtEq,
        # numEq, numNEq, numGt, numGtEq, numLt, numLtEq.
        #
        # For some filters there are extra properties that can be set.
        #   * for strRange, strNRange, numRange and numNRange these are:
        @min = undefined
        @minIncluded = true
        @max = undefined
        @maxIncluded = true
        #   * for strMask the extra properie is:
        @wildcard = undefined

module.exports = Filter


