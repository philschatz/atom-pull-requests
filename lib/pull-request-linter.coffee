_ = require 'underscore-plus'

ghClient = require './gh-client'

getNameWithOwner = (repo) ->
  url  = repo.getOriginURL()
  return null unless url?
  return /([^\/:]+)\/([^\/]+)$/.exec(url.replace(/\.git$/, ''))[0]


module.exports = new class # This only needs to be a class to bind lint()

  name: 'Pull Request'
  grammarScopes: ['*']
  scope: 'file'
  lintOnFly: true

  lint: (textEditor) ->
    filePath = textEditor.getPath()
    repo = atom.project.getRepositories()[0]
    return unless repo

    [repoOwner, repoName] = getNameWithOwner(repo).split('/')

    {branch} = repo
    # localSha = repo.getReferenceTarget(branch)

    unless /^refs\/heads\//.test(branch)
      throw new Error('unexpected branch prefix')
    branchName = repo.getShortHead(branch)

    # Get all the diffs since the last commit (TODO: Do not assume people push their commits immediately)
    # These are used to shift/remove comments in the gutter

    # Contains an {Array} of hunk {Object}s with the following keys:
    #   * `oldStart` The line {Number} of the old hunk.
    #   * `newStart` The line {Number} of the new hunk.
    #   * `oldLines` The {Number} of lines in the old hunk.
    #   * `newLines` The {Number} of lines in the new hunk
    diffs = repo.getLineDiffs(filePath, textEditor.getText())

    ghClient.setRepoInfo(repoOwner, repoName, branchName)
    # Return a promise with lines to add comments to (lint)
    ghClient.getCommentsPromise()
    .then (comments) ->
      # Filter out comments that are not on this file
      comments = comments.filter ({path}) ->
        filePath.endsWith(path)

      # Sort all the comments and combine multiple comments
      # that were made on the same line
      lineMap = {}
      _.forEach comments, (comment) ->
        {position, body, user} = comment
        lineMap[position] ?= []
        lineMap[position].push("#{user.login}: #{body}")

      # Collapse multiple comments on the same line
      # into 1 message with newlines
      editorBuffer = textEditor.getBuffer()
      lintWarningsOrNull = _.map lineMap, (commentsOnLine, position) ->

        # Adjust the line numbers for any diffs so they still line up
        diffs.forEach ({oldStart, newStart, oldLines, newLines}) ->
          return if position < oldStart
          # If the comment is in the range of edited text then do something (maybe hide it?)
          if oldStart <= position and position <= oldStart + oldLines
            position = -1
          else
            position = position - oldLines + newLines

        if position is -1
          return null

        # Put a squiggly across the entire line by finding the line length
        if editorBuffer.getLineCount() <= position - 1
          # TODO: Keep track of local diffs to adjust where the comments are
          lineLength = 1
        else
          lineLength = editorBuffer.lineLengthForRow(position - 1)

        {
          type: 'Info'
          text: commentsOnLine.join('\n')
          range: [[position - 1, 0], [position - 1, lineLength]]
          filePath
        }

      # Filter out all the comments that no longer apply since the source was changed
      lintWarningsOrNull.filter (lintWarning) -> !!lintWarning
