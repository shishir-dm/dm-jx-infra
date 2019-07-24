.DEFAULT_GOAL:=help
SHELL:=/bin/bash
ROOT=$(shell git rev-parse --show-toplevel)
.PHONY: all

help:

	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-19s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

empty_commit:  ## Adds a empty commit to the current branch

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

semver:  ## Outputs FullSemVer of the current branch according to gitversion

	@$(ROOT)/scripts/version_util.sh f FullSemVer

create_release:  ## Bumps minor version and creates a release branch

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

rename_release:  ## Renames the current release branch

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

merge_release:  ## Merges release branch to develop and master

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

tag_release:  ## Tags the HEAD of the release branch with the SemVer

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

create_hotfix:  ## Bumps hotfix version and creates a hotfix branch

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

rename_hotfix:  ## Renames the current hotfix branch

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

merge_hotfix:  ## Merges hotfix branch to master

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

tag_master:  ## Tags the HEAD of the release branch with the SemVer

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

status:  ## Get the status of all current gitflow branches

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)
