.DEFAULT_GOAL:=help
SHELL:=/bin/bash
ROOT=$(shell git rev-parse --show-toplevel)
.PHONY: all

help:

	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target> [BATCH_MODE=1] [DRY_RUN=1] [OPTS...]\033[0m\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-19s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

empty_commit:  ## Adds a empty commit to the current branch

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

semver:  ## Outputs FullSemVer according to gitversion

	@$(ROOT)/scripts/version_util.sh f FullSemVer

release_create:  ## Creates a release branch                       --> (OPTS: TARGET_VERSION=x.x.x, TARGET_SHA=...)

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

release_tag:  ## Tags branch with the SemVer                    --> (OPTS: TARGET_SHA=...)

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

release_finalise:  ## Tags branch with official 3 digit SemVer version

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

release_close:  ## Merge develop into branch and create a PR if necessary

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

release_rename:  ## Rename the current release branch (for corrections)

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

hotfix_create:  ## Bump patch version and create hotfix branch   --> (OPTS: TARGET_VERSION=x.x.x, TARGET_SHA=...)

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

hotfix_tag:  ## Tags the branch with the SemVer                --> (OPTS: TARGET_SHA=...)

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

hotfix_finalise:  ## Tags branch with official 3 digit SemVer version

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

hotfix_close:  ## Merge develop into branch and create a PR if necessary

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

hotfix_rename:  ## Rename the current hotfix branch

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

develop_tag:  ## Tags the develop branch with the SemVer        --> (OPTS: TARGET_SHA=...)

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)

status:  ## Get the status of all current github flow branches

	@$(ROOT)/scripts/version_util.sh $@ $(PWD)
