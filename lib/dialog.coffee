# From https://github.com/sveale/remote-edit
{$, $$, View, TextEditorView} = require 'atom-space-pen-views'
{CompositeDisposable} = require 'atom'

TOKEN_RE = /^[a-f0-9]{40}/
NEW_TOKEN_URL = 'https://github.com/settings/tokens'

module.exports =
class Dialog extends View
  @content: ({title, detail} = {}) ->
    @div class: 'dialog', =>
      @h1 title
      @p detail
      @hr()
      @p 'You can create a token from the following link and then enter it below. The token will be saved in your keychain/keyring (using https://github.com/atom/node-keytar).'
      @div =>
        @a NEW_TOKEN_URL, href: NEW_TOKEN_URL
      @hr()
      @label 'Enter Token (or leave blank) and press Enter', class: 'icon', outlet: 'promptText'
      @subview 'miniEditor', new TextEditorView(mini: true)
      @div class: 'error-message', outlet: 'errorMessage'

  initialize: ({iconClass, defaultValue} = {}) ->
    @promptText.addClass(iconClass) if iconClass

    @disposables = new CompositeDisposable
    @disposables.add atom.commands.add 'atom-workspace',
      'core:confirm': => @onConfirm(@miniEditor.getText())
      'core:cancel': (event) =>
        @cancel()
        event.stopPropagation()

    if defaultValue
      @miniEditor.setText(defaultValue)
    @miniEditor.getModel().onDidChange => @validate()
    # @miniEditor.on 'blur', => @cancel()

  onConfirm: (value) ->
    @callback?(undefined, value)
    @cancel()
    value

  validate: () ->
    token = @miniEditor.getText()
    if token and not TOKEN_RE.test(token)
      @showError('Invalid format. Token must be a string of 40 hex characters')
    else
      @showError() # Clear the error message

  showError: (message='') ->
    @errorMessage.text(message)
    @flashError() if message

  destroy: ->
    @disposables.dispose()

  cancel: ->
    @cancelled()
    @restoreFocus()
    @destroy()

  cancelled: ->
    @hide()

  toggle: (@callback) ->
    if @panel?.isVisible()
      @cancel()
    else
      @show()

  show: () ->
    @panel ?= atom.workspace.addModalPanel(item: this)
    @panel.show()
    @storeFocusedElement()
    @miniEditor.focus()

  hide: ->
    @panel?.hide()

  storeFocusedElement: ->
    @previouslyFocusedElement = $(document.activeElement)

  restoreFocus: ->
    @previouslyFocusedElement?.focus()
