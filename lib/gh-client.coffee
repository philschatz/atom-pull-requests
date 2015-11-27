{CompositeDisposable, Emitter} = require 'atom'
_ = require 'underscore-plus'
Octokat = require 'octokat'
{getRepoInfo} = require './helpers'
Polling = require './polling'

CONFIG_POLLING_INTERVAL = 'pull-requests.githubPollingInterval'
CONFIG_AUTHORIZATION_TOKEN = 'pull-requests.githubAuthorizationToken'
CONFIG_ROOT_URL = 'pull-requests.githubRootUrl'

TOKEN_RE = /^[a-f0-9]{40}/

getRepoNameWithOwner = (repo) ->
  url  = repo.getOriginURL()
  return [] unless url?
  repoNameAndOwner = /([^\/:]+)\/([^\/]+)$/.exec(url.replace(/\.git$/, ''))[0]
  repoNameAndOwner.split('/') or []


module.exports = new class GitHubClient

  octo: null

  initialize: ->
    @emitter = new Emitter
    @polling = new Polling
    @polling.initialize()
    
    @URL_TEST_NODE ?= document.createElement('a')

    @activeItemSubscription = atom.workspace.onDidChangeActivePaneItem =>
      @subscribeToActiveItem()
    @projectPathSubscription = atom.project.onDidChangePaths =>
      @subscribeToRepositories()
    @subscribeToRepositories()
    @subscribeToActiveItem()
    @subscribeToConfigChanges()

    @updateConfig()
    @polling.onDidTick => @_tick()
    @updatePollingInterval()
    @polling.start()

  destroy: ->
    @URL_TEST_NODE = null

    @activeItemSubscription?.dispose()
    @projectPathSubscription?.dispose()

  subscribeToActiveItem: ->
    activeItem = @getActiveItem()

    @savedSubscription?.dispose()
    @savedSubscription = activeItem?.onDidSave? => @updateRepoBranch()

    @updateRepoBranch()

  subscribeToConfigChanges: ->
    @configSubscriptions?.dispose()
    @configSubscriptions = new CompositeDisposable

    @_subscribeConfig CONFIG_POLLING_INTERVAL, => @updatePollingInterval()
    @_subscribeConfig CONFIG_AUTHORIZATION_TOKEN, => @updateConfig()
    @_subscribeConfig CONFIG_ROOT_URL, => @updateConfig()

  _subscribeConfig: (configKey, cb) ->
    @configSubscriptions.add atom.config.onDidChange configKey, cb

  subscribeToRepositories: ->
    @repositorySubscriptions?.dispose()
    @repositorySubscriptions = new CompositeDisposable

    for repo in atom.project.getRepositories() when repo?
      @repositorySubscriptions.add repo.onDidChangeStatus ({path, status}) =>
        @updateRepoBranch() if path is @getActiveItemPath()
      @repositorySubscriptions.add repo.onDidChangeStatuses =>
        @updateRepoBranch()

  getActiveItem: ->
    atom.workspace.getActivePaneItem()

  getActiveItemPath: ->
    @getActiveItem()?.getPath?()

  getRepositoryForActiveItem: ->
    [rootDir] = atom.project.relativizePath(@getActiveItemPath())
    rootDirIndex = atom.project.getPaths().indexOf(rootDir)
    if rootDirIndex >= 0
      atom.project.getRepositories()[rootDirIndex]
    else
      for repo in atom.project.getRepositories() when repo
        return repo

  updateConfig: ->
    token = atom.config.get(CONFIG_AUTHORIZATION_TOKEN) or null
    rootURL = atom.config.get(CONFIG_ROOT_URL) or null

    # Validate the token and URL before instantiating
    if token and not TOKEN_RE.test(token)
      atom.notifications.addError 'Token format is invalid',
        dismissable: true
        detail: 'You can create a token from https://github.com/settings/tokens and then use it here. It should be a string of 40 hex characters'
      token = null

    @URL_TEST_NODE.href = rootURL
    unless @URL_TEST_NODE.protocol is 'https:' and @URL_TEST_NODE.hostname
      rootURL = null

    @octo = new Octokat({token, rootURL})
    @polling.forceIfStarted()

  updatePollingInterval: ->
    interval = atom.config.get(CONFIG_POLLING_INTERVAL)
    @polling.set(interval * 1000)

  updateRepoBranch: ->
    repo = @getRepositoryForActiveItem()
    branchName = repo?.getShortHead(@getActiveItemPath()) or ''
    [repoOwner, repoName] = getRepoNameWithOwner(repo) if repo?
    if branchName isnt @branchName or repoOwner isnt @repoOwner or repoName isnt @repoName
      @branchName = branchName
      @repoOwner = repoOwner
      @repoName = repoName
      @polling.forceIfStarted()

  onDidUpdate: (cb) ->
    @emitter.on('did-update', cb)

  _fetchComments: ->
    repo = @octo.repos(@repoOwner, @repoName)

    unless @repoOwner and @repoName and @branchName
      Promise.resolve([])

    repo.pulls.fetch({head: "#{@repoOwner}:#{@branchName}"})
    .then (pulls) =>
      [pull] = pulls
      return [] unless pull # There may not be a pull request

      # Grab all the comments on a Pull request (and filter by file)
      # pull.comments()
      repo.pulls(pull.number).comments.fetch()
      .then (allComments) =>
        # Loop through the comments and see if this file matches
        # TODO: support paged results

        # Skip out-of-date comments
        comments = allComments.filter ({path, position}) ->
          position isnt null

        # Reset the hasShownConnectionError flag because we succeeded
        @hasShownConnectionError = false
        comments


  _tick: ->
    @updateRepoBranch() # Sometimes the branch name does not update

    unless @repoOwner and @repoName and @branchName
      @emit 'did-update', []

    @_fetchComments()
    .then (comments) =>
      @emitter.emit('did-update', comments)
    .then undefined, (err) ->
      unless @hasShownConnectionError
        @hasShownConnectionError = true
        try
          # If the rate limit was exceeded show a specific Error message
          url = JSON.parse(err.message).documentation_url
          if url is 'https://developer.github.com/v3/#rate-limiting'
            atom.notifications.addError 'Rate limit exceeded for talking to GitHub API',
              dismissable: true
              detail: 'You have exceeded the rate limit for anonymous access to the GitHub API. You will need to wait an hour or create a token from https://github.com/settings/tokens and add it to the settings for this plugin'
            # yield [] so consumers still run
            return []
        catch error

        atom.notifications.addError 'Error fetching Pull Request data from GitHub',
          dismissable: true
          detail: 'Make sure you are connected to the internet and if this is a private repository then you will need to create a token from https://github.com/settings/tokens'

      # yield [] so consumers still run
      []
