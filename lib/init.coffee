fs = require 'fs-plus'
path = require 'path'

treeViewDecorator = null # Delayed instantiation

module.exports =
  config:
    githubPollingInterval:
      title: 'GitHub API polling interval'
      description: 'How often (in seconds) should updated comments be retreived'
      type: 'number'
      default: 60
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

  activate: ->
    require('atom-package-deps').install('pull-requests')
    treeViewDecorator ?= require('./tree-view-decorator')
    treeViewDecorator.start()

  deactivate: ->
    treeViewDecorator?.stop()

  provideLinter: ->
    return require('./pull-request-linter')
