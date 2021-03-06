##
# Module dependencies.
markdown = require 'marked'
{escape} = require './utils'

##
# Parse comments in the given string of `js`.
#
# @param {String} js
# @param {Object} options
# @return {Array}
# @see exports.parseComment
# @api public
exports.parseComments = (js, options = {}) ->
  js = js.replace /\r\n/gm, '\n'

  comments = []
  raw = options.raw
  buf = ''
  withinMultiline = false
  withinSingle = false

  i = 0
  len = js.length
  while i < len
    # start comment
    if not withinMultiline and not withinSingle and '/' is js[i] and '*' is js[i+1]
      # code following previous comment
      if buf.trim().length
        comment = comments[comments.length - 1]
        if comment
          comment.code = code = buf.trim()
          comment.ctx = exports.parseCodeContext code
        buf = ''
      i += 2
      withinMultiline = true
      ignore = '!' is js[i]
    # end comment
    else if withinMultiline and not withinSingle and '*' is js[i] and '/' is js[i+1]
      i += 2
      buf = buf.replace /^[ \t]*\* ?/gm, ''
      comment = exports.parseComment buf, options
      comment.ignore = ignore
      comments.push comment
      withinMultiline = ignore = false
      buf = ''
    else if not withinSingle and not withinMultiline and '/' is js[i] and '/' is js[i+1]
      withinSingle = true
      buf += js[i]
    else if withinSingle and not withinMultiline and '\n' is js[i]
      withinSingle = false
      buf += js[i]
    # buffer comment or code
    else
      buf += js[i]

    i++

  if comments.length is 0
    comments.push
      tags: []
      description: full: '', summary: '', body: ''
      isPrivate: false

  # trailing code
  if buf.trim().length
    comment = comments[comments.length - 1]
    code = buf.trim()
    comment.code = code
    comment.ctx = exports.parseCodeContext code

  return comments

##
# Parse the given comment `str`.
#
# The comment object returned contains the following
#
#  - `tags`  array of tag objects
#  - `description` the first line of the comment
#  - `body` lines following the description
#  - `content` both the description and the body
#  - `isPrivate` true when "@api private" is used
#
# @param {String} str
# @param {Object} options
# @return {Object}
# @see exports.parseTag
# @api public
exports.parseComment = (str, options = {}) ->
  str = str.trim()

  comment = tags: []
  raw = options.raw
  description = {}

  if str[0] is '@'
    str = '\n' + str

  # parse comment body
  description.full = str.split('\n@')[0]
  description.summary = description.full.split('\n\n')[0]
  description.body = description.full.split('\n\n').slice(1).join('\n\n')
  comment.description = description

  # parse tags
  if ~str.indexOf('\n@')
    tags = '@' + str.split('\n@').slice(1).join('\n@')
    comment.tags = tags.split('\n').map(exports.parseTag)
    comment.isPrivate = comment.tags.some (tag) ->
      return 'api' is tag.type and 'private' is tag.visibility

  # markdown
  if not raw
    description.full = markdown description.full
    description.summary = markdown description.summary
    description.body = markdown description.body

  return comment

##
# Parse tag string "@param {Array} name description" etc.
#
# @param {String}
# @return {Object}
# @api public
exports.parseTag = (str) ->
  tag = {}
  parts = str.split /\ +/
  type = tag.type = parts.shift().replace('@', '').toLowerCase()

  switch type
    when 'param'
      tag.types = if /{.*}/.test(parts[0]) then exports.parseTagTypes(parts.shift()) else []
      tag.name = parts.shift() or ''
      tag.description = parts.join(' ')
    when 'return'
      tag.types = if /{.*}/.test(parts[0]) then exports.parseTagTypes(parts.shift()) else []
      tag.description = parts.join(' ')
    when 'see'
      if ~str.indexOf('http')
        tag.title = if parts.length > 1 then parts.shift() else ''
        tag.url = parts.join(' ')
      else
        tag.local = parts.join(' ')
    when 'api'
      tag.visibility = parts.shift()
    when 'type'
      tag.types = exports.parseTagTypes(parts.shift())
    when 'memberof'
      tag.parent = parts.shift()
    when 'augments'
      tag.otherClass = parts.shift()
    when 'borrows'
      tag.otherMemberName = parts.join(' ').split(' as ')[0]
      tag.thisMemberName = parts.join(' ').split(' as ')[1]
    when 'throws'
      tag.string = parts.join(' ')
    else
      tag.string = parts.join(' ')

  return tag

##
# Parse tag type string "{Array|Object}" etc.
#
# @param {String} str
# @return {Array}
# @api public
exports.parseTagTypes = (str) ->
  return str
    .replace /[{}]/g, ''
    .split /\ *[|,\/] */

##
# Parse the context from the given `str` of js.
#
# This method attempts to discover the context
# for the comment based on it's code. Currently
# supports:
#
#   - function statements
#   - function expressions
#   - prototype methods
#   - prototype properties
#   - methods
#   - properties
#   - declarations
#
# @param {String} str
# @return {Object}
# @api public
exports.parseCodeContext = (str) ->
  str = str.split('\n')[0]

  # function statement
  if /^function (\w+) *\(/.exec(str)
    return {
      type: 'function'
      name: RegExp.$1
      string: RegExp.$1 + '()'
    }
  # function expression
  else if /^var *(\w+)[ \t]*=[ \t]*function/.exec(str)
    return {
      type: 'function'
      name: RegExp.$1
      string: RegExp.$1 + '()'
    }
  # prototype method
  else if /^(\w+)\.prototype\.(\w+)[ \t]*=[ \t]*function/.exec(str)
    return {
      type: 'method'
      constructor: RegExp.$1
      cons: RegExp.$1
      name: RegExp.$2
      string: RegExp.$1 + '.prototype.' + RegExp.$2 + '()'
    }
  # prototype property
  else if /^(\w+)\.prototype\.(\w+)[ \t]*=[ \t]*([^\n;]+)/.exec(str)
    return {
      type: 'property'
      constructor: RegExp.$1
      cons: RegExp.$1
      name: RegExp.$2
      value: RegExp.$3
      string: RegExp.$1 + '.prototype.' + RegExp.$2
    }
  # method
  else if /^([\w.]+)\.(\w+)[ \t]*=[ \t]*function/.exec(str)
    return {
      type: 'method'
      receiver: RegExp.$1
      name: RegExp.$2
      string: RegExp.$1 + '.' + RegExp.$2 + '()'
    }
  # property
  else if /^(\w+)\.(\w+)[ \t]*=[ \t]*([^\n;]+)/.exec(str)
    return {
      type: 'property'
      receiver: RegExp.$1
      name: RegExp.$2
      value: RegExp.$3
      string: RegExp.$1 + '.' + RegExp.$2
    }
  # declaration
  else if /^var +(\w+)[ \t]*=[ \t]*([^\n;]+)/.exec(str)
    return {
      type: 'declaration'
      name: RegExp.$1
      value: RegExp.$2
      string: RegExp.$1
    }
  # method
  else if /^(\w+) *: *function/.exec(str)
    return {
      type: 'method'
      name: RegExp.$1
      string: RegExp.$1 + '()'
    }
  # property
  else if /^(\w+) *: *([^\n;]+)/.exec(str)
    return {
      type: 'property'
      name: RegExp.$1
      value: RegExp.$2
      string: RegExp.$1
    }
