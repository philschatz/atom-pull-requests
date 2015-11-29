"use babel";

import {CompositeDisposable} from 'atom';
import fs from 'fs-plus';
import path from 'path';

export default new class PullRequests {
  constructor() {
    this.treeViewDecorator = null; // Delayed instantiation
    // Atom config
    this.config = {
      githubPollingInterval: {
        title: 'GitHub API polling interval',
        description: 'How often (in seconds) should updated comments be retreived',
        type: 'number',
        default: 60,
        minimum: 20,
        order: 1
      },
      githubAuthorizationToken: {
        title: 'GitHub authorization token (optional)',
        description: 'Useful for retreiving private repositories',
        type: 'string',
        default: '',
        order: 2
      },
      githubRootUrl: {
        title: 'Enterprise GitHub Url (optional)',
        description: 'Specify the GitHub Enterprise root URL (ie https://example.com/api/v3)',
        type: 'string',
        default: 'https://api.github.com',
        order: 3
      }
    }
  }
  activate() {
    require('atom-package-deps').install('pull-requests')
    this.subscriptions = new CompositeDisposable
    this.ghClient = require('./gh-client')
    this.ghClient.initialize()

    this.treeViewDecorator = require('./tree-view-decorator')
    this.treeViewDecorator.initialize()

    this.pullRequestLinter = require('./pr-linter')
    this.pullRequestLinter.initialize()
  }
  deactivate() {
    if (this.ghClient) {
      this.ghClient.destroy()
    }
    if (this.treeViewDecorator) {
      this.treeViewDecorator.destroy()
    }

    this.pullRequestLinter.destroy()
    this.subscriptions.destroy()
  }
  consumeLinter(registry) {
    atom.packages.activate('linter').then(() => {
      registry = atom.packages.getLoadedPackage('linter').mainModule.provideIndie()

      // HACK because of bug in `linter` package
      registry.emit = registry.emitter.emit.bind(registry.emitter)

      linter = registry.register({name: 'Pull Request'})
      this.pullRequestLinter.setLinter(linter)
      this.subscriptions.add(linter)
    });
  }
}
