fs = require 'fs'
path = require 'path'
{TextBuffer} = require 'atom'
_ = require 'underscore-plus'
ultramarked = require 'ultramarked'
linkify = require 'gfm-linkify'

ghClient = require './gh-client'
{getRepoInfo} = require './helpers'

simplifyHtml = (html) ->
  DIV = document.createElement('div')
  DIV.innerHTML = html
  first = DIV.firstElementChild
  if first and first is DIV.lastElementChild and first.tagName.toLowerCase() is 'p'
    DIV.firstElementChild.innerHTML
  else
    DIV.innerHTML

getNameWithOwner = (repo) ->
  url  = repo.getOriginURL()
  return null unless url?
  return /([^\/:]+)\/([^\/]+)$/.exec(url.replace(/\.git$/, ''))[0]


# GitHub comments do not directly contain the line number of the comment.
# Instead, it needs to be calculated from the `.diffHunk`.
# This determines the line number by parsing the `diffHunk` and then adding
# or subtracting the line number depending on if the diff line has a `-`, ` `, or `+`.

# As an example:
# The following should end up with position=98
#
# ```
# @@ -90,6 +91,26 @@ DashboardChapter = React.createClass
#  someCode += 1;
#  someCode += 1;
#
# +
# +moreCode += 1;
# +
# +
# +thisIsTheLineWithTheComment = true;
# ```
parseHunkToGetPosition = (diffHunk) ->
  LINE_RE = /^@@\ -\d+,\d+\ \+(\d+)/  # Use the start line number in the new file

  diffLines = diffHunk.split('\n')

  throw new Error('weird hunk format') unless diffLines[0].startsWith('@@ -')

  # oldPosition = parseInt(diffLines[0].substring('@@ -'.length, diffLines[0].indexOf(',')))
  position = parseInt(LINE_RE.exec(diffLines[0])?[1])
  position -= 1 # because diff line numbers are 1-based

  diffLines.shift() # skip the 1st line
  _.each diffLines, (line) ->
    if line[0] isnt '-'
      position += 1
  position


module.exports = new class # This only needs to be a class to bind lint()

  initialize: ->
    ghClient.onDidUpdate (comments) => @poll(comments)

  destroy: ->

  setLinter: (@linter) ->

  poll: (allComments) ->
    if allComments.length is 0
      @linter?.deleteMessages()
      return
    repo = atom.project.getRepositories()[0]

    rootPath = path.join(repo.getPath(), '..')

    # Combine the comments by file
    filesMap = {}
    allComments.forEach (comment) ->
      filesMap[comment.path] ?= []
      filesMap[comment.path].push(comment)

    allMessages = []

    for filePath, comments of filesMap
      do (filePath, comments) =>

        fileAbsolutePath = path.join(rootPath, filePath)

        # Get all the diffs since the last commit (TODO: Do not assume people push their commits immediately)
        # These are used to shift/remove comments in the gutter

        fileText = fs.readFileSync(fileAbsolutePath, 'utf-8') # HACK: Assumes the file is utf-8

        # Contains an {Array} of hunk {Object}s with the following keys:
        #   * `oldStart` The line {Number} of the old hunk.
        #   * `newStart` The line {Number} of the new hunk.
        #   * `oldLines` The {Number} of lines in the old hunk.
        #   * `newLines` The {Number} of lines in the new hunk
        diffs = repo.getLineDiffs(filePath, fileText)
        {ahead, behind} = repo.getCachedUpstreamAheadBehindCount(filePath)

        if ahead or behind
          outOfDateText = 'marker line number may be off\n'
        else
          outOfDateText = ''


        # Sort all the comments and combine multiple comments
        # that were made on the same line
        lineMap = {}
        _.forEach comments, (comment) ->
          {diffHunk, body, user, htmlUrl} = comment
          position = parseHunkToGetPosition(diffHunk)
          lineMap[position] ?= []
          lineMap[position].push("[#{user.login}](#{htmlUrl}): #{body}")

        # Collapse multiple comments on the same line
        # into 1 message with newlines
        editorBuffer = new TextBuffer {text: fileText}
        lintWarningsOrNull = _.map lineMap, (commentsOnLine, position) =>

          position = parseInt(position)

          # Adjust the line numbers for any diffs so they still line up
          diffs.forEach ({oldStart, newStart, oldLines, newLines}) ->
            return if position < oldStart
            # If the comment is in the range of edited text then do something (maybe hide it?)
            if oldStart <= position and position <= oldStart + oldLines
              position = -1
            else
              position = position - oldLines + newLines

          # HACK: figure out why position can be -1
          if position is 0
            position = 1

          if position is -1
            return null

          # Put a squiggly across the entire line by finding the line length
          if editorBuffer.getLineCount() <= position - 1
            # TODO: Keep track of local diffs to adjust where the comments are
            lineLength = 1
          else
            lineLength = editorBuffer.lineLengthForRow(position - 1)

          text = outOfDateText + commentsOnLine.join('\n\n')
          context = ghClient.repoOwner + '/' + ghClient.repoName
          textStripped = text.replace(/<!--[\s\S]*?-->/g, '')
          # textEmojis = this.replaceEmojis(textStripped)
          textEmojis = textStripped
          html = ultramarked(linkify(textEmojis, context))

          {
            type: 'Info'
            html: simplifyHtml(html)
            range: [[position - 1, 0], [position - 1, lineLength]]
            filePath: fileAbsolutePath
          }

        # Filter out all the comments that no longer apply since the source was changed
        allMessages = allMessages.concat(lintWarningsOrNull.filter (lintWarning) -> !!lintWarning)
    @linter.setMessages(allMessages)
