_ = require 'underscore-plus'
ghClient = require './gh-client'


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
# elements in the DOM and adds a `has-comments` class on them (& their parents)
# when there is a comment on a file.

UPDATE_INTERVAL = 4 * 1000 # Update the tree view every 4 seconds

module.exports = new class TreeViewDecorator
  start: ->
    @interval = setInterval(@poll.bind(@), UPDATE_INTERVAL)

  stop: ->
    clearInterval(@interval)
    @interval = null

  poll: ->
    ghClient.getCommentsPromise()
    .then @updateTreeView

  updateTreeView: (comments) ->
    # Add a class to every visible file in tree-view to show the comment icon
    # First, clear all the comment markers
    allTreeViewFiles = document.querySelectorAll("[data-path].has-comment")
    if allTreeViewFiles
      _.each allTreeViewFiles, (el) ->
        el.classList.remove('has-comment')

    comments.forEach (comment) ->
      # Add a comment icon on the file and
      # mark all the directories up the tree so the files are easy to find
      # TODO: on Win32 convert '/' to backslash
      acc = ''
      comment.path.split('/').forEach (segment) ->
        if acc
          acc += "/#{segment}"
        else
          acc = segment

        el = document.querySelector("[data-path$='#{acc}']")
        if el
          el.classList.add('has-comment')
