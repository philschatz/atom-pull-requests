"use babel";

import _ from 'underscore-plus';
import ghClient from './gh-client';
import Polling from './polling';

// This is a terrible implementation.
// HACK: Unfortunately, while `tree-view` exposes a provider (`atom.file-icons`)
// for decorating files and directories, it only allows you to set a class name
// based on the path of the file.
//
// Since comments on files in a Pull Request change while the files have not
// this endpoint is not sufficient.
//
// I tried monkey-patching the TreeView File prototype (and GitRepository)
// but GitHub has (correctly) hidden it; only the FileView is exposed
// (as a custom element).
//
// So, for now, I'm left with this terrible code that selects all the filename
// elements in the DOM and adds a `data-comment-count` attribute on them (& their parents)
// when there is a comment on a file.

const UPDATE_INTERVAL = 4 * 1000;

const COMMENT_COUNT_CLASSES = [
  'pr-comment-count-1',
  'pr-comment-count-2',
  'pr-comment-count-3',
  'pr-comment-count-4',
  'pr-comment-count-5',
  'pr-comment-count-6',
  'pr-comment-count-7',
  'pr-comment-count-8',
  'pr-comment-count-9'
];


export default new class TreeViewDecorator {
  initialize() {
    this.fileCache = new Set;
    this.polling = new Polling;
    this.polling.initialize();
    this.polling.set(UPDATE_INTERVAL);
    this.polling.onDidTick(() => this._tick())
    this.polling.start();
    return ghClient.onDidUpdate((comments) => this.updateTreeView(comments))
  }

  destroy() {
    this.fileCache = null;
    this.polling.destroy();
  }

  _tick() {
    if (this.cachedComments) {
      return this.updateTreeView(this.cachedComments);
    }
  }

  updateTreeView(comments) {
    this.cachedComments = comments;
    // Add a class to every visible file in tree-view to show the comment icon

    // First, clear all the comment markers
    // See "above" for why these ugly lines are in here
    COMMENT_COUNT_CLASSES.forEach((cls) => {
      const nodesWithComments = document.querySelectorAll(".js-hack-added-manually." + cls);
      if (nodesWithComments) {
        _.each(nodesWithComments, function(el) {
          el.classList.remove('js-hack-added-manually');
          el.classList.remove(cls);
        });
      }
    })
    // reset all the previously-marked files and directories
    this.fileCache.forEach((file) => {
      if (!file.destroyed) {
        typeof file.updateIconStatus === "function" ? file.updateIconStatus(null) : void 0;
      }
    })
    // Build a map of all the paths and how many comments are in them
    this.pathsAndCommentCount = {};
    comments.forEach((comment) => {
      // Add a comment icon on the file and
      // mark all the directories up the tree so the files are easy to find
      // TODO: on Win32 convert '/' to backslash
      let acc = '';
      return comment.path.split('/').forEach((segment) => {
        var base;
        if (acc) {
          acc += "/" + segment;
        } else {
          acc = segment;
        }
        if ((base = this.pathsAndCommentCount)[acc] == null) {
          base[acc] = 0;
        }
        this.pathsAndCommentCount[acc] += 1;
      });
    });
    this.markTreeFiles();
  }

  findPath(projectRootDir, path) {
    let currentDir = projectRootDir;
    const ref = path.split('/');
    let segment;
    for (let i = 0, len = ref.length; i < len; i++) {
      segment = ref[i];
      currentDir = currentDir != null ? currentDir.entries[segment] : void 0;
      if (!currentDir) {
        break;
      }
    }
    return currentDir;
  }

  isNewTreeView(currentDir) {
    return currentDir && typeof currentDir.updateIconStatus === 'function';
  }
  isDirectory(currentDir) {
    return typeof currentDir.onDidAddEntries === "function";
  }

  markTreeFiles() {
    // TODO: ugly assumption. Should test for right too
    const treeView = atom.workspace.getLeftPanels()[0];
    let projectRootDir = null;
    if (treeView) {
      projectRootDir = treeView.item.roots[0].directory;
    }
    // Now that we have iterated over all the comments to get the counts,
    // Update all the dirs/files in the tree view and all the open tabs
    for (const path in this.pathsAndCommentCount) {
      const commentCount = this.pathsAndCommentCount[path];
      const count = Math.min(commentCount, 9);
      // Find the correct File/Directory object
      const currentDir = this.findPath(projectRootDir, path);
      if (currentDir) {
        // Try to call `.updateIconStatus` first (see `tree-view` PR)
        if (this.isNewTreeView(currentDir)) {
          currentDir.updateIconStatus("pr-comment-count-" + count);
          if (!this.fileCache.has(currentDir)) {
            this.fileCache.add(currentDir);
            if (this.isDirectory(currentDir)) {
              // Directory has this method but File does not
              currentDir.onDidAddEntries(() => this.markTreeFiles());
            }
          }
        } else {
          // Fall back to using Selectors to update
          // Directory and File need the class to be added in slightly different places
          if (typeof currentDir.getEntries === 'function') {
            // This is a Directory. TODO: use this.isDirectory() to determine if it is a Directory
            const el = document.querySelector("[is='tree-view-directory'] > .header > [data-path$='" + path + "']");
            if (el != null) {
              el.parentNode.parentNode.classList.add("pr-comment-count-" + count);
              el.parentNode.parentNode.classList.add('js-hack-added-manually');
            }
          } else {
            // This is a File
            const el = document.querySelector("[is='tree-view-file'] > [data-path$='" + path + "']");
            if (el != null) {
              el.parentNode.classList.add("pr-comment-count-" + count);
              el.parentNode.classList.add('js-hack-added-manually');
            }
          }
        }
      }
      // HACK: Show the comment count in the file tab too
      const el = document.querySelector("[is='tabs-tab'] > [data-path$='" + path + "']");
      if (el) {
        el.parentNode.classList.add("pr-comment-count-" + count);
        el.parentNode.classList.add('js-hack-added-manually');
      }
    }
  }

}
