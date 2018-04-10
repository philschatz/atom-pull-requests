{CompositeDisposable, Emitter} = require 'atom'
_ = require 'underscore-plus'
Octokat = require 'octokat'
keytar = require 'keytar'
{getRepoInfo} = require './helpers'
Polling = require './polling'
Dialog = require './dialog'

CONFIG_POLLING_INTERVAL = 'pull-requests.githubPollingInterval'
CONFIG_ROOT_URL = 'pull-requests.githubRootUrl'
KEYTAR_SERVICE_NAME = 'atom-github'
KEYTAR_ACCOUNT_NAME = 'https://api.github.com'

TOKEN_RE = /^[a-f0-9]{40}/

getRepoNameWithOwner = (repo) ->
  url  = repo.getOriginURL()
  return [] unless url?
  repoNameAndOwner = /([^\/:]+)\/([^\/]+)$/.exec(url.replace(/\.git$/, ''))?[0]
  if repoNameAndOwner
    repoNameAndOwner.split('/') or []
  else
    # This may be the case when using BitBucket or a non-GitHub repo
    []


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
    token = keytar.findPassword(KEYTAR_SERVICE_NAME, KEYTAR_ACCOUNT_NAME) or null
    rootURL = atom.config.get(CONFIG_ROOT_URL) or null

    # Validate the token and URL before instantiating
    if token and not TOKEN_RE.test(token)
      keytar.deletePassword(KEYTAR_SERVICE_NAME, KEYTAR_ACCOUNT_NAME)
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

  # There are 4 cases for finding comments:
  # 1. This is a PR to the same repo (most common for development within an org)
  # 2. This is a PR to a parent repo (this repo is a fork) (common for contributing to popular libraries)
  # 3. This is just a branch so there are no PR comments
  # 4. This is not even in GitHub
  _fetchComments: ->
    unless @repoOwner and @repoName and @branchName
      # Case 4. This is not even in GitHub
      return Promise.resolve([])

    filterComments = (allComments) =>
      # Loop through the comments and see if this file matches
      # TODO: support paged results

      # Skip out-of-date comments
      comments = allComments.filter ({path, position}) ->
        position isnt null

      # Reset the hasShownConnectionError flag because we succeeded
      @hasShownConnectionError = false
      comments

    repo = @octo.repos(@repoOwner, @repoName)

    repo.pulls.fetch({head: "#{@repoOwner}:#{@branchName}"})
    .then (pulls) =>
      [pull] = pulls.items

      if pull
        # Case 1. This is a PR to the same repo
        # Grab all the comments on a Pull request (and filter by file)
        # pull.comments()
        repo.pulls(pull.number).comments.fetchAll()
        .then(filterComments)
      else
        # There may not be a Pull Request, or this may be a fork and the Pull Request is in the parent repo
        # Fetch the repo to see if it is a fork
        repo.fetch().then ({parent}) =>
          if parent
            # Case 2. This is a PR to a parent repo (this repo is a fork)
            parentRepo = @octo.repos(parent.owner.login, parent.name)
            # parentRepo = @octo.repos(parent.id)
            parentRepo.pulls.fetch({head: "#{@repoOwner}:#{@branchName}"})
            .then ([pull]) =>
              return [] unless pull
              parentRepo.pulls(pull.number).comments.fetch()
              .then(filterComments)
          else
            # Case 3. This is just a branch so there are no PR comments
            return []

  _tick: ->
    @updateRepoBranch() # Sometimes the branch name does not update

    if @repoOwner and @repoName and @branchName
      @_fetchComments()
      .then (comments) =>
        @emitter.emit('did-update', comments)
      .then undefined, (err) =>
        unless @hasShownConnectionError
          @hasShownConnectionError = true
          try
            # If the rate limit was exceeded show a specific Error message
            url = JSON.parse(err.message).documentation_url
            if url is 'https://developer.github.com/v3/#rate-limiting'
              atom.notifications.addError 'Rate limit exceeded for talking to GitHub API',
                dismissable: true
                detail: 'You have exceeded the rate limit for anonymous access to the GitHub API. You will need to wait an hour or create a token from https://github.com/settings/tokens and add it to the settings for the pull-requests plugin'

              tokenDialog = new Dialog({
                defaultValue: keytar.getPassword(KEYTAR_SERVICE_NAME, KEYTAR_ACCOUNT_NAME)
                title: 'Rate limit exceeded for talking to GitHub API'
                detail: 'You have exceeded the rate limit for anonymous access to the GitHub API. You will need to wait an hour or create a token using the instructions below.'})
              tokenDialog.toggle (err, token) =>
                unless err
                  if token
                    @hasShownConnectionError = false
                    if keytar.getPassword(KEYTAR_SERVICE_NAME, KEYTAR_ACCOUNT_NAME)
                      keytar.replacePassword(KEYTAR_SERVICE_NAME, KEYTAR_ACCOUNT_NAME, token)
                    else
                      keytar.addPassword(KEYTAR_SERVICE_NAME, KEYTAR_ACCOUNT_NAME, token)
                  @updateConfig()
              # yield [] so consumers still run
              return []
          catch error

          atom.notifications.addError 'Error fetching Pull Request data from GitHub',
            dismissable: true
            detail: 'Make sure you are connected to the internet and if this is a private repository then you will need to create a token from https://github.com/settings/tokens and provide it to the pull-requests plugin settings'

          # tokenDialog = new Dialog({
          #   defaultValue: keytar.getPassword(KEYTAR_SERVICE_NAME, KEYTAR_ACCOUNT_NAME)
          #   title: 'Unable to find repository on GitHub'
          #   detail: 'Make sure you are connected to the internet and if this is a private repository then you will need to create a token using the instructions below. If you already have a token entered then it may not have the correct scope. If this is a private repository then make sure the "repo" scope is selected.'})
          # tokenDialog.toggle (err, token) =>
          #   unless err
          #     if token
          #       @hasShownConnectionError = false
          #       if keytar.getPassword(KEYTAR_SERVICE_NAME, KEYTAR_ACCOUNT_NAME)
          #         keytar.replacePassword(KEYTAR_SERVICE_NAME, KEYTAR_ACCOUNT_NAME, token)
          #       else
          #         keytar.addPassword(KEYTAR_SERVICE_NAME, KEYTAR_ACCOUNT_NAME, token)
          #     @updateConfig()

        # yield [] so consumers still run
        []

    else
      # No repo info (not a GitHub Repo)
      @emitter.emit 'did-update', []
