# pull-requests package for Atom [![gh-board](https://img.shields.io/github/issues/philschatz/atom-pull-requests.svg?label=Issues%20%28gh-board%29)](http://philschatz.com/gh-board/#/r/philschatz:atom-pull-requests)

View/Edit comments on a Pull Request directly inside the Atom Editor.

![counts-and-icons-in-tab](https://cloud.githubusercontent.com/assets/253202/11326511/82360626-9139-11e5-8466-ed2d356cb0d8.png)

Annoyed when someone litters your elegant code with _"comments"_, and _"suggestions"_? and then you have to sift through all the files in your text editor to find the right place? Fear no more!

![in action](https://cloud.githubusercontent.com/assets/253202/11237087/a3568100-8dab-11e5-8d9d-3bc9cc3dc5af.gif)


# Setup

GitHub restricts talking to their API. You can view public repositories without having to authenticate against GitHub but will be limited to _60 requests per hour_.

If you want to look at **private repositories** or are requesting more than 60 times per hour, you can create a token at https://github.com/settings/tokens and set that in the plugin config. 

- Just leave all the scopes checkboxes _unchecked_ to give this plugin the minimal permissions necessary.


# TODO

- [x] work with private or enterprise repositories (see package settings)
- [x] show comment counts in tree view and in file tab
- [x] render all MarkDown in the comments
  - [ ] render emojis
- [ ] support forked Pull Requests
- [ ] do local diff of all commits since the one pushed to GitHub
  - [ ] let user know that they have unpushed commits
- [ ] support comments made to the entire Pull Request (not just lines in the code)

# Atom API Suggestions

- expose a `tree-view` file decorator that can add classes asynchronously
  - see [atom/tree-view#658](https://github.com/atom/tree-view/pull/658) for progress on this feature
- expose a `tabs` filename decorator so open tabs can have the # of comments in the file

# `atom-community/linter` suggestions

- provide icons in gutter markers

# Config

For private repositories you need to create a token @ github:
 1. Go to https://github.com/settings/tokens and create a new token
 2. Open your config.cson
 3. Add this snippet (replacing '*my-git-token*' with the token you created
```cson  
  "pull-requests":
    githubAuthorizationToken: "my-git-token"
```
