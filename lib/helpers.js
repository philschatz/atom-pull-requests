"use babel";

function getNameWithOwner(repo) {
  url  = repo.getOriginURL()
  if (!url) {
    return [];
  }
  return /([^\/:]+)\/([^\/]+)$/.exec(url.replace(/\.git$/, ''))[0]
}

export function getRepoInfo() {
    const repo = atom.project.getRepositories()[0]
    if (!repo) {
      return {}
    }
    const [repoOwner, repoName] = getNameWithOwner(repo).split('/')
    const {branch} = repo

    let branchName;
    if(branch) {
      if (!/^refs\/heads\//.test(branch)) {
        throw new Error('unexpected branch prefix:' + branch)
      }
      branchName = repo.getShortHead(branch)
    }
    return {repoOwner, repoName, branchName}
}
