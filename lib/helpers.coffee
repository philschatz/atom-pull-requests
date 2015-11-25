getNameWithOwner = (repo) ->
  url  = repo.getOriginURL()
  return null unless url?
  return /([^\/:]+)\/([^\/]+)$/.exec(url.replace(/\.git$/, ''))[0]

module.exports =
  getRepoInfo: ->
    repo = atom.project.getRepositories()[0]
    return {} unless repo

    [repoOwner, repoName] = getNameWithOwner(repo).split('/')

    {branch} = repo
    # localSha = repo.getReferenceTarget(branch)

    unless /^refs\/heads\//.test(branch)
      throw new Error('unexpected branch prefix')
    branchName = repo.getShortHead(branch)

    {repoOwner, repoName, branchName}
