#!/usr/bin/env bash

set -euo pipefail

function die() { echo "$@" 1>&2 ; exit 1; }

function dieGracefully() { echo "$@" 1>&2 ; exit 0; }

function test_semver() {
  [[ $1 =~ ^${2}[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} ]] || die "Value '$1' does not match ${2}x.x.x."
}

function release_semver() {
  test_semver "$1" release-
}

function hotfix_semver() {
  test_semver "$1" hotfix-
}

function confirm () {
    # call with a prompt string or use a default
    local default_answer='Y'
    read -p ">>>>>>>> ${1:-Are you sure?} [Y/n]" default_answer_input
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
    GITVERSION_CMD="docker run --rm -v ${ROOT}:/repo gittools/gitversion:5.0.0-linux /repo"
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
  ${GITVERSION_CMD} $@
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
  branches=$(git ls-remote --quiet origin "$pattern" | sed 's:.*/::g')
  [ -n "$branches" ] || die "Remote branch(es) matching '$pattern' DOES NOT exist."
  (( $(grep -c . <<< "$branches") == 1 )) || { echo -e "Branches found:\n$branches"; die "Zero or multiple remote branches matching pattern '$pattern'. See above."; }
  [ -z "${2:-}" ] || echo $branches
}

function search_for_branch() {
  local pattern=$1
  local branches
  branches=$(git ls-remote --quiet origin "$pattern" | sed 's:.*/::g')
  (( $(grep -c . <<< "$branches") < 2 )) || { echo -e "Branches found:\n$branches"; die "Multiple remote branches matching pattern '$pattern'. See above."; }
  [ -z "${2:-}" ] || echo $branches
}

function ensure_no_branch() {
  local pattern=$1
  local branches
  branches=$(git ls-remote --quiet origin "$pattern" | sed 's:.*/::g')
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
    git push origin :$fromBr
  else
    echo "No remote found."
  fi
  echo "Rename $fromBr -> $toBr"
  git branch -m $fromBr $toBr
  echo "Checkout new $toBr"
  git checkout -q $toBr
  git branch --unset-upstream &> /dev/null || true
  echo "Push remote $toBr"
  git push --set-upstream origin $toBr
}

function rename_hotfix() {
  local workingBr targetBranch
  workingBr=$(ensure_single_branch "$GF_HOTFIX_PATTERN" true)
  read -p "New hotfix branch [$workingBr]: " targetBranch
  [[ "$workingBr" != "$targetBranch" ]] || die "source and target cannot be identical"
  hotfix_semver "$targetBranch"
  rename_branch "$workingBr" "$targetBranch"
}

function rename_release() {
  local workingBr targetBranch
  workingBr=$(ensure_single_branch "$GF_RELEASE_PATTERN" true)
  read -p "New release branch [$workingBr]: " targetBranch
  [[ "$workingBr" != "$targetBranch" ]] || die "source and target cannot be identical"
  release_semver "$targetBranch"
  rename_branch "$workingBr" "$targetBranch"
}


function create_branch() {
  local sourceBranch=$1
  local targetBranch=$2
  local regexPrefix=$3
  local branchPoint

  # get input vars
  read -p "Source branch [$sourceBranch]: " sourceBranchInput
  sourceBranch=${sourceBranchInput:-$sourceBranch}
  read -p "Target branch [$targetBranch]: " targetBranchInput
  targetBranch=${targetBranchInput:-$targetBranch}
  test_semver "$targetBranch" $regexPrefix
  confirm "Create branch '$targetBranch' from source '$sourceBranch'"

  # check for custom commit
  checkout_branch $sourceBranch
  branchPoint=$(git rev-parse --short HEAD)
  if [[ "$targetBranch" =~ release* ]]; then
    echo "Listing last 10 commits."
    git --no-pager log --oneline -n 10
    read -p "Commit to branch from [$branchPoint]: " branchPointInput
    if [[ "$branchPointInput" != "$branchPoint" ]]; then
      echo "Checking out from commit '$branchPointInput'"
      git checkout -b $targetBranch $branchPointInput
    else
      echo "Checking out from HEAD"
      git checkout -b $targetBranch
    fi
  else
    echo "Checking out from HEAD"
    git checkout -b $targetBranch
  fi
  git push --set-upstream origin $targetBranch
}

function merge_source_into_target() {
  local source=$1
  local target=$2
  confirm "Will merge release '$source' into '$target'"
  checkout_branch $source
  checkout_branch $target
  git merge --no-ff $source -m "Merge branch '$source'"
  git push origin $target
}

function delete_branch() {
  local branch=$1
  confirm "Will delete branch '$branch' both locally and remote."
  git branch -d $branch
  git push origin :$branch
}

function create_release() {
  local targetVersion
  ensure_single_branch "$GF_DEVELOP"
  ensure_no_branch "$GF_RELEASE_PATTERN"
  targetVersion=$(run_cmd /showvariable MajorMinorPatch)
  create_branch "$GF_DEVELOP" "release-${targetVersion}" release-
}

function create_hotfix() {
  local major minor patch targetVersion
  ensure_single_branch "$GF_MASTER"
  ensure_no_branch "$GF_HOTFIX_PATTERN"
  git checkout "$GF_MASTER" -q
  major=$(run_cmd /showvariable Major)
  minor=$(run_cmd /showvariable Minor)
  patch=$(run_cmd /showvariable Patch)
  targetVersion="${major}.${minor}.$(( $patch + 1 ))"
  create_branch "$GF_MASTER" "hotfix-${targetVersion}" hotfix-
}

function merge_release() {
  local masterBr developBr workingBr
  masterBr=$(ensure_single_branch "$GF_MASTER" true)
  developBr=$(ensure_single_branch "$GF_DEVELOP" true)
  workingBr=$(ensure_single_branch "$GF_RELEASE_PATTERN" true)
  merge_source_into_target $workingBr $developBr
  merge_source_into_target $workingBr $masterBr
  delete_branch $workingBr
  tag_branch "$GF_MASTER"
}

function status() {
  local masterBr developBr releaseBr hotfixBr
  for pattern in "$GF_DEVELOP" "$GF_RELEASE_PATTERN" "$GF_HOTFIX_PATTERN" "$GF_MASTER"; do
    workingBr=$(search_for_branch "$pattern" true)
    if [ -n "$workingBr" ]; then
      checkout_branch $workingBr '-q'
      printf "%-15s %-10s\n" "$workingBr" "$(run_cmd /showvariable FullSemVer)"
    else
      printf "%-15s %-10s\n" "$pattern" "does not exist"
    fi
  done
}

function merge_hotfix() {
  local masterBr workingBr
  masterBr=$(ensure_single_branch "$GF_MASTER" true)
  developBr=$(ensure_single_branch "$GF_DEVELOP" true)
  workingBr=$(ensure_single_branch "$GF_HOTFIX_PATTERN" true)
  releaseBr=$(search_for_branch "$GF_RELEASE_PATTERN" true)
  if [ -n "$releaseBr" ]; then
    merge_source_into_target $workingBr $releaseBr
  fi
  merge_source_into_target $workingBr $developBr
  merge_source_into_target $workingBr $masterBr
  delete_branch $workingBr
  tag_branch "$GF_MASTER"
}

function tag_branch() {
  local workingBr=$1
  local tag
  workingBr=$(ensure_single_branch "$workingBr" true)
  checkout_branch $workingBr
  tag="v$(run_cmd /showvariable SemVer)"
  read -p "New tag [$tag]: " tagInput
  tag=${tagInput:-$tag}
  test_semver "$tag" v
  confirm "Will tag branch '$workingBr' with '$tag'"
  git tag -am "Add tag '$tag' (performed by $USER)" $tag
  git push origin $tag
}

function empty_commit() {
  local currentBr dateStr
  currentBr=$(git symbolic-ref --short HEAD)
  dateStr=$(date '+%Y-%m-%d_%H:%M:%S')
  git commit --allow-empty -m "Empty commit at $dateStr to '$currentBr'"
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
GF_MASTER="master"
GF_DEVELOP='develop'
GF_RELEASE_PATTERN='release-*'
GF_HOTFIX_PATTERN='hotfix-*'

if [[ $ARG == 'prereqs' ]]; then
  prereqs
elif [[ $ARG == 'run' ]]; then
  run_cmd $@
elif [[ $ARG == 'f' ]]; then
  get_field ${1:-}
elif [[ $ARG == 'create_release' ]]; then
  ensure_pristine_workspace
  create_release $@
elif [[ $ARG == 'rename_release' ]]; then
  ensure_pristine_workspace
  rename_release $@
elif [[ $ARG == 'rename_hotfix' ]]; then
  ensure_pristine_workspace
  rename_hotfix $@
elif [[ $ARG == 'tag_release' ]]; then
  ensure_pristine_workspace
  tag_branch "$GF_RELEASE_PATTERN" $@
elif [[ $ARG == 'tag_master' ]]; then
  ensure_pristine_workspace
  tag_branch "$GF_MASTER" $@
elif [[ $ARG == 'create_hotfix' ]]; then
  ensure_pristine_workspace
  create_hotfix $@
elif [[ $ARG == 'merge_release' ]]; then
  ensure_pristine_workspace
  merge_release $@
elif [[ $ARG == 'merge_hotfix' ]]; then
  ensure_pristine_workspace
  merge_hotfix $@
elif [[ $ARG == 'status' ]]; then
  ensure_pristine_workspace
  status $@
elif [[ $ARG == 'empty_commit' ]]; then
  ensure_pristine_workspace_light
  empty_commit $@
else
  die "method '$ARG' not found"
fi
