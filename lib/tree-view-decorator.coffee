_ = require 'underscore-plus'
ghClient = require './gh-client'
Polling = require './polling'

# This is a terrible implementation.
# HACK: Unfortunately, while `tree-view` exposes a provider (`atom.file-icons`)
# for decorating files and directories, it only allows you to set a class name
# based on the path of the file.
#
# Since comments on files in a Pull Request change while the files have not
# this endpoint is not sufficient.
#
# I tried monkey-patching the TreeView File prototype (and GitRepository)
# but GitHub has (correctly) hidden it; only the FileView is exposed
# (as a custom element).
#
# So, for now, I'm left with this terrible code that selects all the filename
# elements in the DOM and adds a `data-comment-count` attribute on them (& their parents)
# when there is a comment on a file.

UPDATE_INTERVAL = 4 * 1000 # Update the tree view every 4 seconds

COMMENT_COUNT_CLASSES = [
  'pr-comment-count-1'
  'pr-comment-count-2'
  'pr-comment-count-3'
  'pr-comment-count-4'
  'pr-comment-count-5'
  'pr-comment-count-6'
  'pr-comment-count-7'
  'pr-comment-count-8'
  'pr-comment-count-9'
]

module.exports = new class TreeViewDecorator
  initialize: ->
    @fileCache = new Set
    @polling = new Polling
    @polling.initialize()
    @polling.set(UPDATE_INTERVAL)
    @polling.onDidTick () => @_tick()
    @polling.start()
    ghClient.onDidUpdate (comments) => @updateTreeView(comments)

  destroy: ->
    @fileCache = null
    @polling.destroy()

  _tick: ->
    @updateTreeView(@cachedComments) if @cachedComments

  updateTreeView: (comments) ->
    @cachedComments = comments
    # Add a class to every visible file in tree-view to show the comment icon

    # First, clear all the comment markers
    # See "above" for why these ugly lines are in here
    COMMENT_COUNT_CLASSES.forEach (cls) ->
      nodesWithComments = document.querySelectorAll(".js-hack-added-manually.#{cls}")
      if nodesWithComments
        _.each nodesWithComments, (el) ->
          el.classList.remove('js-hack-added-manually')
          el.classList.remove(cls)

    # reset all the previously-marked files and directories
    @fileCache.forEach (file) ->
      unless file.destroyed
        file.updateIconStatus?(null)

    # Build a map of all the paths and how many comments are in them
    @pathsAndCommentCount = {}
    comments.forEach (comment) =>
      # Add a comment icon on the file and
      # mark all the directories up the tree so the files are easy to find
      # TODO: on Win32 convert '/' to backslash
      acc = ''
      comment.path.split('/').forEach (segment) =>
        if acc
          acc += "/#{segment}"
        else
          acc = segment

        @pathsAndCommentCount[acc] ?= 0
        @pathsAndCommentCount[acc] += 1

    @markTreeFiles()

  findPath: (projectRootDir, path) ->
    currentDir = projectRootDir
    for segment in path.split('/')
      currentDir = currentDir?.entries[segment]
      break unless currentDir
    currentDir

  markTreeFiles: ->
    treeView = atom.workspace.getLeftPanels()[0] # TODO: ugly assumption. Should test for right too
    if treeView
      projectRootDir = treeView.item.roots[0].directory

    # Now that we have iterated over all the comments to get the counts,
    # Update all the dirs/files in the tree view and all the open tabs
    for path of @pathsAndCommentCount
      commentCount = @pathsAndCommentCount[path]
      count = Math.min(commentCount, 9)

      # Find the correct File/Directory object
      currentDir = @findPath(projectRootDir, path)

      if currentDir
        # Try to call `.updateIconStatus` first (see `tree-view` PR)
        if currentDir?.updateIconStatus
          currentDir.updateIconStatus("pr-comment-count-#{count}")
          unless @fileCache.has(currentDir)
            @fileCache.add(currentDir)
            # Directory has this method but File does not
            currentDir.onDidAddEntries? =>
              @markTreeFiles()
        else
          # Fall back to using Selectors to update
          # Directory and File need the class to be added in slightly different places
          if typeof currentDir.getEntries is 'function'
            # This is a Directory
            el = document.querySelector("[is='tree-view-directory'] > .header > [data-path$='#{path}']")
            el?.parentNode.parentNode.classList.add("pr-comment-count-#{count}")
            el?.parentNode.parentNode.classList.add('js-hack-added-manually')
          else
            # This is a File
            el = document.querySelector("[is='tree-view-file'] > [data-path$='#{path}']")
            el?.parentNode.classList.add("pr-comment-count-#{count}")
            el?.parentNode.classList.add('js-hack-added-manually')

      # HACK: Show the comment count in the file tab too
      el = document.querySelector("[is='tabs-tab'] > [data-path$='#{path}']")
      if el
        el.parentNode.classList.add("pr-comment-count-#{count}")
        el.parentNode.classList.add('js-hack-added-manually')
