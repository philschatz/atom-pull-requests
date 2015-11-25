_ = require 'underscore-plus'
Octokat = require 'octokat'
{getRepoInfo} = require './helpers'

module.exports = new class GitHubClient

  cachedPromise: null
  lastPolled: null
  octo: null

  setRepoInfo: ({repoOwner, repoName, branchName}) ->
    if @branchName isnt branchName or @repoOwner  isnt repoOwner or @repoName   isnt repoName

      lastPolled = null
      cachedPromise = null

      {@repoOwner, @repoName, @branchName} = {repoOwner, repoName, branchName}

      token = atom.config.get('pull-requests.githubAuthorizationToken') or null
      rootURL = atom.config.get('pull-requests.githubRootUrl') or null
      @octo = new Octokat({token, rootURL})

  _fetchComments: ->
    repo = @octo.repos(@repoOwner, @repoName)

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


  getCommentsPromise: ->
    @setRepoInfo(getRepoInfo())
    now = Date.now()
    pollingInterval = atom.config.get('pull-requests.githubPollingInterval')
    if @cachedPromise and @lastPolled + pollingInterval * 1000 > now
      return @cachedPromise
    @lastPolled = now

    unless @repoOwner and @repoName and @branchName
      return Promise.resolve([])

    # Return a promise
    return @cachedPromise = @_fetchComments()
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
