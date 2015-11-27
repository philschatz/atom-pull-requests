{Emitter} = require 'atom'

module.exports = class Polling
  initialize: ->
    @emitter = new Emitter

  destroy: ->
    clearTimeout(@_timeout)

  poll: ->
    @emitter.emit('did-tick')
    @_timeout = setTimeout(@poll.bind(@), @interval)

  start: ->
    @poll()

  stop: ->
    clearTimeout(@_timeout)
    @_timeout = null

  forceIfStarted: ->
    @poll() if @_timeout

  set: (@interval) ->
    if @_timeout
      @stop()
      @start()

  onDidTick: (cb) ->
    @emitter.on 'did-tick', cb
