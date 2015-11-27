{CompositeDisposable} = require 'atom'

fs = require 'fs-plus'
path = require 'path'

module.exports = new class PullRequests
  config:
    githubPollingInterval:
      title: 'GitHub API polling interval'
      description: 'How often (in seconds) should updated comments be retreived'
      type: 'number'
      default: 60
      minimum: 20
      order: 1
    githubAuthorizationToken:
      title: 'GitHub authorization token (optional)'
      description: 'Useful for retreiving private repositories'
      type: 'string'
      default: ''
      order: 2
    githubRootUrl:
      title: 'Enterprise GitHub Url (optional)'
      description: 'Specify the GitHub Enterprise root URL (ie https://example.com/api/v3)'
      type: 'string'
      default: 'https://api.github.com'
      order: 3

  treeViewDecorator: null # Delayed instantiation

  activate: ->
    require('atom-package-deps').install('pull-requests')
    @subscriptions = new CompositeDisposable
    @ghClient ?= require('./gh-client')
    @ghClient.initialize()

    @treeViewDecorator ?= require('./tree-view-decorator')
    @treeViewDecorator.initialize()

    @pullRequestLinter ?= require('./pr-linter')
    @pullRequestLinter.initialize()

  deactivate: ->
    @ghClient?.destroy()
    @treeViewDecorator?.destroy()
    @pullRequestLinter.destroy()
    @subscriptions.destroy()

  consumeLinter: (registry) ->
    atom.packages.activate('linter').then =>

      registry = atom.packages.getLoadedPackage('linter').mainModule.provideIndie()

      # HACK because of bug in `linter` package
      registry.emit = registry.emitter.emit.bind(registry.emitter)

      linter = registry.register {name: 'Pull Request'}
      @pullRequestLinter.setLinter(linter)
      @subscriptions.add(linter)
