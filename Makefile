.DEFAULT_GOAL:=help
SHELL:=/bin/bash
ROOT=$(shell git rev-parse --show-toplevel)
.PHONY: all

help:

	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target> [BATCH_MODE=1] [DRY_RUN=1] [OPTS...]\033[0m\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-19s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

empty_commit:  ## Adds a empty commit to the current branch

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

semver:  ## Outputs FullSemVer of the current branch according to gitversion

	@$(ROOT)/scripts/version_util.sh f FullSemVer

release_create:  ## Bumps minor version and creates a release branch --> (OPTS: TARGET_VERSION=x.x.x, TARGET_SHA=...)

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

release_rename:  ## Renames the current release branch

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

release_close:  ## Creates PR from release branch to develop

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

release_tag:  ## Tags the release branch with the SemVer          --> (OPTS: TARGET_SHA=...)

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

hotfix_create:  ## Bumps minor version and creates a hotfix branch --> (OPTS: TARGET_VERSION=x.x.x, TARGET_SHA=...)

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

hotfix_rename:  ## Renames the current hotfix branch

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

hotfix_close:  ## Creates PR from hotfix branch to develop

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

hotfix_tag:  ## Tags the hotfix branch with the SemVer          --> (OPTS: TARGET_SHA=...)

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

develop_tag:  ## Tags the develop branch with the SemVer          --> (OPTS: TARGET_SHA=...)

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

status:  ## Get the status of all current gitflow branches

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)
