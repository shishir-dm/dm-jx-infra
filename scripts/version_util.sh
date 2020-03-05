#!/usr/bin/env bash

set -euo pipefail

function die() { echo "$@" 1>&2 ; exit 1; }

function dieGracefully() { echo "$@" 1>&2 ; exit 0; }

function test_final_semver() {
  [[ $1 =~ ^${2:-}[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || die "Value '$1' does not match ${2:-}x.x.x."
}

function test_semver() {
  [[ $1 =~ ^${2:-}[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(-(alpha|beta|rc)\.[0-9]{1,3})*$ ]] || die "Value '$1' does not match ${2:-}x.x.x."
}

function release_semver() {
  test_semver "$1" release-
}

function hotfix_semver() {
  test_semver "$1" hotfix-
}

function version_gt() {
  local v1=$1
  local v2=$2
  local eq=${3:-}
  if [[ "$eq" == "eq" ]] && [[ "$v1" == "$v2" ]]; then
    return
  else
    # tricking the sort -V by adding an extra '_' to the end of the version
    # see: https://stackoverflow.com/a/40391207/1838659
    printf '%s\n%s\n' "${v1}" "${v2}" | $SED '/-/!{s/$/_/}' > /dev/null || die "The sed command failed. You may be on MacOS and have either not installed gnu-sed, or the gsed binary is not on the PATH."
    test "$(printf '%s\n%s\n' "${v1}" "${v2}" | $SED '/-/!{s/$/_/}' | sort -V | head -n 1)" != "${v1}"
  fi
}

# for testing purposes
# version_gt v3.22.0-alpha.1 v3.22.0-beta.1 && echo y || echo n
# version_gt v3.22.0-beta.1 v3.22.0-beta.1 && echo y || echo n
# version_gt v3.22.0-beta.1 v3.22.0-beta.1 eq && echo y || echo n
# version_gt v3.23.0-alpha.1 v3.22.0-beta.1 eq && echo y || echo n
# version_gt v3.22.0 v3.22.0-beta.1 eq && echo y || echo n
# exit

function confirm () {
    local msg="${1:-Are you sure?} [Y/n]"
    # call with a prompt string or use a default
    local default_answer='Y'
    if (( $BATCH_MODE )); then
      echo "[BATCH_MODE] $msg" >&2
    else
      read -p "$msg" default_answer_input
    fi
    default_answer=${default_answer_input:-$default_answer}
    #[ -n "$REPLY" ] && echo    # (optional) move to a new line
    if [[ $default_answer =~ ^[Nn]$ ]]; then
        dieGracefully "Received '${default_answer:-N}'. ${2:-Exiting gracefully}."
    elif [[ ! $default_answer =~ ^[Yy]$ ]]; then
        die "Did not recognise answer '${default_answer:-N}'."
    fi
}

# This method will look for in order of priority
#
#  - a "version.json" file (created by another container in the CI build scenario)
#  - the necessary binaries
#  - a running docker process to replace the binaries
#
function prereqs() {
  ROOT="$(git rev-parse --show-toplevel)"
  OS=$(uname | tr '[:upper:]' '[:lower:]')
  if [ -r "${ROOT}/version.json" ]; then
    GITVERSION_CMD="cat ${ROOT}/version.json"
  elif gitversion -h &> /dev/null; then
    GITVERSION_CMD="gitversion"
  elif docker info &> /dev/null; then
    GITVERSION_CMD="docker run --rm -v ${ROOT}:/repo:z gittools/gitversion:4.0.1-beta1-65-linux-debian-net472 /repo"
  else
    die "No gitversion and no docker "
  fi
  if jq -h &> /dev/null; then
    JQ_CMD="jq"
  elif docker info &> /dev/null; then
    JQ_CMD="docker run -i --rm diversario/eks-tools:0.0.3 jq"
  else
    die "No gitversion and no docker "
  fi
}

function run_cmd() {
  prereqs
  ${GITVERSION_CMD} "$@"
}

# use it method to get a particular field from the returned JSON string
function get_field() {
  prereqs
  if [ -n "${1:-}" ]; then
    ${GITVERSION_CMD} | ${JQ_CMD} -r .${1}
  else
    ${GITVERSION_CMD}
  fi
}

function ensure_pristine_workspace() {
  local git_status unpushed_commits
  [ -z "${NO_PRISTINE_CHECK:-}" ] || return 0
  # delete all local tags
  git tag -l | xargs git tag -d > /dev/null
  # fetch all and prune any deleted tag refs from your repository
  git fetch --all --prune --tags -q
  git_status=$(git status -s)
  original_branch=$(git symbolic-ref --short HEAD)
  [ -z "$git_status" ] || { echo -e "Changes found:\n$git_status\n"; die "Workspace must be free of changes. See above and please correct."; }
  if [ -z ${1:-} ]; then
    unpushed_commits=$(git log --branches --not --remotes)
    [ -z "$unpushed_commits" ] || { echo -e "Unpushed commits found (use 'git log --branches --not --remotes'):\n$unpushed_commits\n"; die "Workspace must be free of changes. See above and please correct."; }
  fi
}

function ensure_pristine_workspace_light() {
  ensure_pristine_workspace "true"
}

function ensure_single_branch() {
  local pattern=$1
  local branches
  branches=$(git ls-remote --quiet origin "$pattern" | $SED 's:.*/::g')
  [ -n "$branches" ] || die "Remote branch(es) matching '$pattern' DOES NOT exist."
  (( $(grep -c . <<< "$branches") == 1 )) || { echo -e "Branches found:\n$branches"; die "Zero or multiple remote branches matching pattern '$pattern'. See above."; }
  [ -z "${2:-}" ] || echo $branches
}

function search_for_branch() {
  local pattern=$1
  local branches
  branches=$(git ls-remote --quiet origin "$pattern" | $SED 's:.*/::g')
  (( $(grep -c . <<< "$branches") < 2 )) || { echo -e "Branches found:\n$branches"; die "Multiple remote branches matching pattern '$pattern'. See above."; }
  [ -z "${2:-}" ] || echo $branches
}

function ensure_no_branch() {
  local pattern=$1
  local branches
  branches=$(git ls-remote --quiet origin "$pattern" | $SED 's:.*/::g')
  [ -z "$branches" ] || { echo -e "Branches found:\n$branches"; die "Remote branch(es) matching '$pattern' ALREADY exist. See above."; }
}

function checkout_branch() {
  local branch=$1
  git checkout ${2:-} $branch
  git pull ${2:-} origin $branch
}

function rename_branch() {
  local fromBr=$1
  local toBr=$2
  echo "Start from $GF_DEVELOP"
  checkout_branch $GF_DEVELOP -q
  if git ls-remote -q --exit-code --heads . $fromBr &> /dev/null; then
    echo "Delete remote $fromBr"
    gitCmd push origin :$fromBr
  else
    echo "No remote found."
  fi
  echo "Rename $fromBr -> $toBr"
  gitCmd branch -m $fromBr $toBr
  echo "Checkout new $toBr"
  gitCmd checkout -q $toBr
  gitCmd branch --unset-upstream &> /dev/null || true
  echo "Push remote $toBr"
  gitCmd push --set-upstream origin $toBr
}

function hotfix_rename() {
  local workingBr targetBranch latestReleaseTag
  workingBr=$(ensure_single_branch "$GF_HOTFIX_PATTERN" true)
  [ -n "${TARGET_VERSION:-}" ] && targetBranch="hotfix-$TARGET_VERSION" || targetBranch="$workingBr"
  targetBranch=$(readValue "New hotfix branch [$targetBranch]: " "$targetBranch")
  [[ "$workingBr" != "$targetBranch" ]] || die "source and target cannot be identical"
  hotfix_semver "$targetBranch"
  latestReleaseTag=$(find_latest_release_tag)
  ensure_first_gt_second "${targetBranch//hotfix-/}" "${latestReleaseTag//v/}"
  rename_branch "$workingBr" "$targetBranch"
}

function release_rename() {
  local workingBr targetBranch latestReleaseTag
  workingBr=$(ensure_single_branch "$GF_RELEASE_PATTERN" true)
  [ -n "${TARGET_VERSION:-}" ] && targetBranch="release-$TARGET_VERSION" || targetBranch="$workingBr"
  targetBranch=$(readValue "New release branch [$targetBranch]: " "$targetBranch")
  [[ "$workingBr" != "$targetBranch" ]] || die "source and target cannot be identical"
  release_semver "$targetBranch"
  latestReleaseTag=$(find_latest_release_tag)
  ensure_first_gt_second "${targetBranch//release-/}" "${latestReleaseTag//v/}"
  rename_branch "$workingBr" "$targetBranch"
}

function gitCmd() {
  if (( $DRY_RUN )); then
    echo "[DRY_RUN] git $@"
  else
    git "$@"
  fi
}

function hubCmd() {
  if (( $DRY_RUN )); then
    echo "[DRY_RUN] hub $@"
  else
    hub "$@"
  fi
}

function readValue() {
  local msg=$1
  local defaultVal=$2
  if (( $BATCH_MODE )); then
    echo "[BATCH_MODE] $msg" >&2
  else
    read -p "$msg" returnVal
  fi
  echo -n "${returnVal:-$defaultVal}"
}

function determine_branch_or_tag_point() {
  local targetBranch=$1
  local branchOrTagPointInput latestKnownTagOnBranch
  # check for custom sha from TARGET_SHA
  if [ -n "${TARGET_SHA}" ]; then
    echo "TARGET_SHA found. Replacing default branch/tag point."
    branchOrTagPoint=$(git rev-parse --short "$TARGET_SHA")
  else
    branchOrTagPoint=$(git rev-parse --short HEAD)
    # check for custom sha from user input
    if [[ "$targetBranch" =~ ${GF_RELEASE_PATTERN} ]]; then
      echo "Listing last 10 commits."
      git --no-pager log --oneline -n 10
      branchOrTagPointInput=$(readValue "Commit to branch from [$branchOrTagPoint]: " "$branchOrTagPoint")
      branchOrTagPoint=${branchOrTagPointInput:-$branchOrTagPoint}
    fi
  fi
  # finally ensure the sha is after the latest tag (if the branch has a tag)
  if git describe --abbrev=0 --tags &> /dev/null; then
    latestKnownTagOnBranch=$(git describe --abbrev=0 --tags)
    git merge-base --is-ancestor $latestKnownTagOnBranch $branchOrTagPoint \
      || die "Something strange going on: branch/tag point '$branchOrTagPoint' is older than the latest known tag '$latestKnownTagOnBranch'."
  else
    echo "No tags found on this branch so far. Continuing..."
  fi
}

function create_branch() {
  local sourceBranch=$1
  local targetBranch=$2
  local regexPrefix=$3
  local sourceBranchInput targetBranchInput branchOrTagPoint

  # get input vars
  sourceBranchInput=$(readValue "Source branch [$sourceBranch]: " "$sourceBranch")
  sourceBranch=${sourceBranchInput:-$sourceBranch}
  targetBranchInput=$(readValue "Target branch [$targetBranch]: " "$targetBranch")
  targetBranch=${targetBranchInput:-$targetBranch}
  test_semver "$targetBranch" $regexPrefix
  confirm "Create branch '$targetBranch' from source '$sourceBranch'"
  checkout_branch $sourceBranch
  determine_branch_or_tag_point $targetBranch
  echo "Checking out from commit '$branchOrTagPoint'"
  gitCmd checkout -b $targetBranch $branchOrTagPoint
  gitCmd push --set-upstream origin $targetBranch
}

function delete_branch() {
  local branch=$1
  confirm "Will delete branch '$branch' both locally and remote."
  gitCmd branch -D $branch
  gitCmd push origin :$branch
}

function all_delete() {
  local workingBr branchPattern=$1
  workingBr=$(ensure_single_branch "$branchPattern" true)
  delete_branch "${workingBr}"
}

function release_create() {
  local eq=${1:-}
  local targetVersion latestReleaseTag
  ensure_single_branch "$GF_DEVELOP"
  ensure_no_branch "$GF_RELEASE_PATTERN"
  checkout_branch "$GF_DEVELOP" '-q'
  latestReleaseTag=$(find_latest_release_tag)
  targetVersion=$(run_cmd /showvariable MajorMinorPatch)
  targetVersion=${TARGET_VERSION:-$targetVersion}
  ensure_first_gt_second $targetVersion "${latestReleaseTag//v/}"
  create_branch "$GF_DEVELOP" "release-${targetVersion}" release-
}

function find_latest_release_tag() {
  git tag -l --sort=-version:refname "v*" | grep -E "^v[0-9]+\.[0-9]+\.[0-9]+$" | head -n 1 | xargs
}

function hotfix_create() {
  local major minor patch latestReleaseTag targetVersion
  ensure_no_branch "$GF_HOTFIX_PATTERN"
  latestReleaseTag=$(find_latest_release_tag)
  major=$(cut -d . -f 1 <<< ${latestReleaseTag/v/})
  minor=$(cut -d . -f 2 <<< ${latestReleaseTag/v/})
  patch=$(cut -d . -f 3 <<< ${latestReleaseTag/v/})
  targetVersion="${major}.${minor}.$(( $patch + 1 ))"
  targetVersion=${TARGET_VERSION:-$targetVersion}
  ensure_first_gt_second $targetVersion "${latestReleaseTag//v/}"
  create_branch "$latestReleaseTag" "hotfix-${targetVersion}" hotfix-
}

function create_pull_request() {
  local baseBranch=$1
  local headBranch=$2
  local msg=${3:-"Merging '${headBranch}' into '${baseBranch}'."}
  local commitCnt prURL
  # number of commits to be merged between headBranch and baseBranch
  commitCnt=$(git rev-list origin/${headBranch} ^origin/${baseBranch} --count)
  if [ "${commitCnt}" -ne "${commitCnt}" ] 2>/dev/null; then
    die "The returned commitCnt '${commitCnt}' is not an integer."
  elif (( $commitCnt )); then
    # Create the pull request
    echo "Commits found between origin/${headBranch} and origin/${baseBranch}. Creating pull request..."
    hub --version &> /dev/null || die "The hub binary is not installed (see: https://hub.github.com/)"
    hubCmd pull-request -b "${baseBranch}" -h "${headBranch}" -m "${msg}"
    #prURL=$(hubCmd pr list -b "${baseBranch}" -h "${headBranch}" --format='%U%n')
  else
    # NOTHING_TO_MERGE will be referenced in the Jenkinsfile. Do not change!
    echo "NOTHING_TO_MERGE: No commits to merge found between origin/${headBranch} and origin/${baseBranch}. Will not create pull request."
  fi
}

function all_close() {
  local developBr workingBr branchPattern=$1
  developBr=$(ensure_single_branch "$GF_DEVELOP" true)
  workingBr=$(ensure_single_branch "$branchPattern" true)
  gitCmd fetch origin $developBr
  checkout_branch $workingBr -q
  gitCmd merge origin/$developBr -m "Merge remote-tracking branch 'origin/$developBr' into $workingBr"
  gitCmd push --set-upstream origin $workingBr
  create_pull_request $developBr $workingBr
}

function ensure_target_version_gt_branch_version() {
  local targetVersion=$1
  local branch=$2
  local eq=${3:-}
  local branchVersion
  test_semver $targetVersion
  checkout_branch $branch -q
  branchVersion=$(run_cmd /showvariable SemVer)
  ensure_first_gt_second "$targetVersion" "$branchVersion" "$eq"
}

function ensure_first_gt_second() {
  local targetVersion=$1
  local branchVersion=$2
  local eq=${3:-}
  local branchSupplement
  [ -z "${branch:-}" ] || branchSupplement=" on '${branch:-}'"
  version_gt "$targetVersion" "$branchVersion" "$eq" || die "Target version supplied is lower than the version$branchSupplement:
  $branchVersion <- branch ($branch)
  vs
  $targetVersion <- target
  "
}

function status() {
  local latestReleaseTag
  for pattern in "$GF_DEVELOP" "$GF_RELEASE_PATTERN" "$GF_HOTFIX_PATTERN"; do
    workingBr=$(search_for_branch "$pattern" true)
    if [ -n "$workingBr" ]; then
      checkout_branch $workingBr '-q'
      printf "%-15s %-10s\n" "$workingBr" "$(run_cmd /showvariable FullSemVer)"
    else
      printf "%-15s %-10s\n" "$pattern" "does not exist"
    fi
  done
  latestReleaseTag=$(find_latest_release_tag)
  printf "%-15s %-10s\n" "latest" "$latestReleaseTag -> $(git --no-pager log --oneline --no-walk $latestReleaseTag)"
}

function exact_tag_exists() {
  if git show-ref --tags --quiet --verify -- "refs/tags/$tag"; then
    local tagCommit targetSha
    tagCommit=$(git rev-list -n 1 "$tag")
    targetSha=$(git rev-parse "$branchOrTagPoint")
    if [[ "$tagCommit" == "$targetSha" ]]; then
      return 0
    else
      die "Tag '$tag' exists and points to a different commit:
      current tag sha = $tagCommit
      target tag sha  = $targetSha
      "
    fi
  fi
  return 1
}

function release_quick() {
  local tagVersion
  # sanity checks
  [ -n "${TARGET_SHA:-}" ] || die "TARGET_SHA must be set manually when running 'release_quick'."

  # 1. tag the SHA with a final release
  if [ -z "${TARGET_VERSION:-}" ]; then
    checkout_branch "$GF_DEVELOP" -q
    TARGET_VERSION="$(run_cmd /showvariable MajorMinorPatch)"
  else
    test_final_semver "${TARGET_VERSION}"
  fi
  develop_tag

  # 2. create the branch from said SHA and version above
  # add the 'eq' arg because we have already tagged develop
  release_create 'eq'
}

function tag_branch() {
  local workingBr=$1
  local tag tagInput tagVersion
  workingBr=$(ensure_single_branch "$workingBr" true)
  checkout_branch $workingBr
  determine_branch_or_tag_point $workingBr
  tagVersion="$(run_cmd /showvariable SemVer)"
  tag="v${TARGET_VERSION:-$tagVersion}"
  tagInput=$(readValue "New tag [$tag]: " "$tag")
  tag=${tagInput:-$tag}
  test_semver "$tag" v
  # ${tag:1} to remove the prefixing 'v'
  # Add 'eq' because the SemVer could be equal even if tag doesn't exist yet.
  # ensure_target_version_gt_branch_version "${tag:1}" "$workingBr" "eq"
  # if tag exists and points to the same commit, ignore...
  if exact_tag_exists; then
    echo "Tag exists AND points to the same commit. No need to add the tag. Ignoring..."
  else
    confirm "Will tag branch '$workingBr' with '$tag' at commit '$branchOrTagPoint'"
    gitCmd tag -am "Add tag '$tag' (performed by ${USER:-${USERNAME:-n/a}})" $tag $branchOrTagPoint
    gitCmd push origin $tag
  fi
}

function develop_tag() {
  tag_branch "$GF_DEVELOP"
}

function tag_merge_base_on_develop_if_necessary() {
  local workingBr=$1
  local mergeBaseSha commitCnt
  workingBr=$(ensure_single_branch "$workingBr" true)
  # NOTE:
  #  - the TARGET_SHA has been set by 'set_final_target_version' below and is
  #    the HEAD of the release-branch.
  #  - the mergeBaseSha is the base of the release branch.
  #  - we will compare the number of commits between the two SHAs
  #  - if we find extra commits on the release branch we need to tag the develop
  #    branch at the original branching point sha.
  if [[ "${workingBr}" =~ ${GF_RELEASE_PATTERN} ]]; then
    mergeBaseSha=$(git merge-base "${TARGET_SHA}" "${GF_DEVELOP}")
    commitCnt=$(git rev-list ${TARGET_SHA} ^${mergeBaseSha} --count)
    if [ "${commitCnt}" -ne "${commitCnt}" ] 2>/dev/null; then
      die "The returned commitCnt '${commitCnt}' is not an integer."
    elif (( $commitCnt )); then
      echo "Additional commits found on release branch."

      # Check that there has been a commit on develop since creating the release
      # branch.
      checkout_branch "${GF_DEVELOP}"
      commitCnt=$(git rev-list HEAD ^${mergeBaseSha} --count)
      if [ "${commitCnt}" -ne "${commitCnt}" ] 2>/dev/null; then
        die "The returned commitCnt '${commitCnt}' is not an integer."
      elif (( $commitCnt )); then
        echo "Additional commits found on '${GF_DEVELOP}'. We can simply determine the TARGET_VERSION."
      else
        echo "SPECIAL CASE: No additional commits found on '${GF_DEVELOP}' so far.
We need to create an empty commit to tag because:
    - if we tag on the merge-base directly the release/hotfix branches will see it
    - if gitversion sees a higher (semver style) version it will use it
    - this leads to an incorrect version being detected

So, nothing else for it - we'll have to create an empty commit!!!
"
        gitCmd commit --no-gpg-sign --allow-empty -m "Commit needed by gitversion - see scripts/version_util.sh"
        gitCmd push
      fi
      # set new TARGET_SHA before tagging
      # the target has to be one commit after the merge-base commit
      # the following command does this
      # BTW: this is why we might have needed to add an empty commit above
      TARGET_SHA=$(git --no-pager log --reverse --ancestry-path --format="%H" -n 1 "${mergeBaseSha}".."${GF_DEVELOP}")

      TARGET_VERSION=$(run_cmd /showvariable SemVer)
      echo "Tagging '${GF_DEVELOP}' with '${TARGET_VERSION}' at the merge-base commit + 1: ${TARGET_SHA}"
      develop_tag
    else
      echo "No commits found between release branch and the merge base. Will not tag '${GF_DEVELOP}' branch."
      echo "No need to tag the '${GF_DEVELOP}' branch since the same commit has been tagged on the '${workingBr}'."
    fi
  else
    echo "Branch '${workingBr}' not a release branch. Not tagging ${GF_DEVELOP}."
  fi
}

function set_final_target_version() {
  local versionStr shaStr workingBr=$1
  [ -z "${TARGET_VERSION:-}" ] || die "TARGET_VERSION is not allowed to be set manually when finalizing."
  workingBr=$(ensure_single_branch "$workingBr" true)
  versionStr=$(echo "${workingBr}" | cut -d '-' -f 2)
  test_semver "${versionStr}"
  TARGET_VERSION="${versionStr}"
  [ -z "${TARGET_SHA:-}" ] || die "TARGET_SHA is not allowed to be set manually when finalizing."
  checkout_branch $workingBr '-q'
  TARGET_SHA=$(git rev-parse --short HEAD)
}

function empty_commit() {
  local currentBr dateStr
  currentBr=$(git symbolic-ref --short HEAD)
  dateStr=$(date '+%Y-%m-%d_%H:%M:%S')
  gitCmd commit --no-gpg-sign --allow-empty -m "Empty commit at $dateStr to '$currentBr'"
}

function finish {
  if [ -n "${original_branch:-}" ]; then
    if git rev-parse --verify "$original_branch" &> /dev/null; then
        echo "Returning to original branch '$original_branch'."
        git checkout $original_branch -q
    else
        echo "Returning to '$GF_DEVELOP' (branch '$original_branch' no longer exists)."
        git checkout $GF_DEVELOP -q
    fi
  fi
}
trap finish EXIT

ARG=${1:-}; shift || true

# some default vars - need to change them for europa.
GF_DEVELOP='develop'
GF_RELEASE_PATTERN='release-*'
GF_HOTFIX_PATTERN='hotfix-*'
BATCH_MODE=${BATCH_MODE:-0}
DRY_RUN=${DRY_RUN:-0}
TARGET_VERSION=${TARGET_VERSION:-}
TARGET_SHA=${TARGET_SHA:-}
DEBUG=${DEBUG:-0}
(( $DEBUG )) && { echo "DEBUG activated. Using 'set -x'..."; set -x; }

# Add the possibility to use this script externally for other projects
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel)}"
[ -r "${PROJECT_ROOT}/.version_util.overrides" ] && . "${PROJECT_ROOT}/.version_util.overrides"
cd $PROJECT_ROOT

# make sed alias gsed if available
SED=sed
if gsed --help &> /dev/null; then
  SED=gsed
fi

if [[ $ARG == 'prereqs' ]]; then
  prereqs
elif [[ $ARG == 'run' ]]; then
  run_cmd "$@"
elif [[ $ARG == 'f' ]]; then
  get_field ${1:-}
elif [[ $ARG == 'develop_tag' ]]; then
  ensure_pristine_workspace
  develop_tag "$@"
elif [[ $ARG == 'release_create' ]]; then
  ensure_pristine_workspace
  release_create
elif [[ $ARG == 'release_tag' ]]; then
  ensure_pristine_workspace
  tag_branch "$GF_RELEASE_PATTERN" "$@"
elif [[ $ARG == 'release_finalise' ]]; then
  ensure_pristine_workspace
  set_final_target_version "$GF_RELEASE_PATTERN"
  tag_branch "$GF_RELEASE_PATTERN" "$@"
  tag_merge_base_on_develop_if_necessary "$GF_RELEASE_PATTERN"
elif [[ $ARG == 'release_quick' ]]; then
  ensure_pristine_workspace
  release_quick
elif [[ $ARG == 'release_close' ]]; then
  ensure_pristine_workspace
  all_close "${GF_RELEASE_PATTERN}"
elif [[ $ARG == 'release_rename' ]]; then
  ensure_pristine_workspace
  release_rename "$@"
elif [[ $ARG == 'release_delete' ]]; then
  ensure_pristine_workspace
  all_delete "${GF_RELEASE_PATTERN}"
elif [[ $ARG == 'hotfix_create' ]]; then
  ensure_pristine_workspace
  hotfix_create "$@"
elif [[ $ARG == 'hotfix_tag' ]]; then
  ensure_pristine_workspace
  tag_branch "$GF_HOTFIX_PATTERN" "$@"
elif [[ $ARG == 'hotfix_finalise' ]]; then
  ensure_pristine_workspace
  set_final_target_version "$GF_HOTFIX_PATTERN"
  tag_branch "$GF_HOTFIX_PATTERN" "$@"
elif [[ $ARG == 'hotfix_close' ]]; then
  ensure_pristine_workspace
  all_close "${GF_HOTFIX_PATTERN}"
elif [[ $ARG == 'hotfix_rename' ]]; then
  ensure_pristine_workspace
  hotfix_rename
elif [[ $ARG == 'hotfix_delete' ]]; then
  ensure_pristine_workspace
  all_delete "${GF_HOTFIX_PATTERN}"
elif [[ $ARG == 'status' ]]; then
  ensure_pristine_workspace
  status "$@"
elif [[ $ARG == 'empty_commit' ]]; then
  ensure_pristine_workspace_light
  empty_commit "$@"
else
  die "method '$ARG' not found"
fi
