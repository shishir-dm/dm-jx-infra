pipeline {
    parameters {
        choice choices: [
          'status',
          'help',
          'release_create',
          'release_tag',
          'release_finalise',
          'release_close',
          'release_rename',
          'hotfix_create',
          'hotfix_tag',
          'hotfix_finalise',
          'hotfix_close',
          'hotfix_rename',
          'develop_tag'],
          description: 'Makefile target to use. Use "help" first to see options.',
          name: 'MAKE_TARGET'
        string defaultValue: '',
          description: 'TARGET_VERSION referenced by the Makefile targets',
          name: 'TARGET_VERSION',
          trim: true
        string defaultValue: '',
          description: 'TARGET_SHA referenced by the Makefile targets',
          name: 'TARGET_SHA',
          trim: true
        booleanParam defaultValue: true,
          description: '''All commands will be run initially with "DRY_RUN=1" followed by a manual confirmation step before executing the command.
Uncheck this parameter to run commands without manual confirmation (to be used at a later date in automated deployments)''',
          name: 'MANUAL_CONFIRMATION'
    }
    options {
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr:'30'))
        skipStagesAfterUnstable()
        timeout(time: 15, unit: 'MINUTES')
    }

    agent {
        kubernetes {
            label 'jenkins-nodejs'
            defaultContainer 'nodejs'
        }
    }
    stages {
        stage('Setup') {
            steps {
                processGitVersion()
            }
        }
        stage('Dry Run') {
            steps {
                container('gitversion') {
                    script {
                        env.DRY_RUN_OUTPUT = sh(returnStdout: true, script: '''
                        unset JENKINS_URL
                        make $MAKE_TARGET DRY_RUN=1 BATCH_MODE=1
                        ''')
                    }
                    echo "${env.DRY_RUN_OUTPUT}"
                }
            }
        }
        stage('Verify') {
            when {
                expression { params.MANUAL_CONFIRMATION }
            }
            steps {
                input """
-------------------------
Running: make $MAKE_TARGET DRY_RUN=1 BATCH_MODE=1
-------------------------

${env.DRY_RUN_OUTPUT}
-------------------------

Please see the DRY_RUN output above.

- If you need to change any parameters, click "Abort" run again with the corrected parameters.

- If the output looks correct, click "Proceed" to perform the step.

                    """
            }
        }
        stage('Execute') {
            environment {
                GITHUB_CREDS = credentials('jx-pipeline-git-github-github')
            }
            steps {
                // if NOTHING_TO_MERGE found in the env.DRY_RUN_OUTPUT it means
                //  - release_close or hotfix_close was passed as a make target
                //  - there is nothing to merge so no pull request can be created
                // In this case, we can offer to delete the branch
                script {
                  if ("${env.DRY_RUN_OUTPUT}".contains('NOTHING_TO_MERGE')) {
                      echo """
-------------------------
It looks like there is nothing to merge back to the development branch.

!!! NOTE: Will not attempt to create a pull request

!!! NOTE: You need to delete the branch manually

-------------------------
                    """
                  } else {
                      container('gitversion') {
                          writeFile file: 'hub', text: """github.com:
      - user: $GITHUB_CREDS_USR
        oauth_token: $GITHUB_CREDS_PSW"""
                          sh 'mkdir ~/.config && mv hub /home/jenkins/hub'
                          sh '''
                          unset JENKINS_URL
                          make $MAKE_TARGET BATCH_MODE=1
                          '''
                      }
                  }
                }
            }
        }
        stage('Final Status') {
            steps {
                container('gitversion') {
                    sh '''
                    unset JENKINS_URL
                    make status
                    '''
                }
            }
        }
    }
    post {
        cleanup {
            cleanWs()
        }
    }
}

def processGitCreds() {
    // Set git auths
    sh "git config --global credential.helper store"
    sh "jx step git credentials"

    script {
      // copy gitCreds over to the default location on gitversion
      // (the gitversion container doesn't like them where they are at the moment)
      sh "cp /home/jenkins/git/credentials gitCreds"
      container('gitversion') {
          sh 'git config --global credential.helper store'
          sh 'git config --global push.default simple'
          sh 'cp gitCreds ~/.git-credentials'
          sh 'rm gitCreds'
      }
    }
}

def specialCaseGitHeadMove() {
    // special case if (a) it's a PR and (b) Merge commit
    // then we need to allow IGNORE_NORMALISATION_GIT_HEAD_MOVE = 1
    env.IGNORE_NORMALISATION_GIT_HEAD_MOVE = sh(
            returnStdout: true,
            script: '''
      # if on a PR
      if git config --local --get-all remote.origin.fetch | grep -q refs\\/pull; then
        # if is merge commit (i.e. has more than 1 parent)
        if [ $(git show -s --pretty=%p HEAD | wc -w) -gt 1 ]; then
          echo -n 1
        else
          echo -n 0
        fi
      else
        echo -n 0
      fi
    '''
    )
}

def determineOriginalCheckout() {
    // Determine the current checkout (branch vs merge commit with detached head)
    env.ORIGINAL_CHECKOUT = sh(
            returnStdout: true,
            script: 'git symbolic-ref HEAD &> /dev/null && echo -n "$(git symbolic-ref --short HEAD)" || echo -n $(git rev-parse --verify HEAD)'
    )
}
def fetchMandatoryRefs() {
    // fetch the tags since the current checkout doesn't have them.
    sh 'git fetch --tags -q'

    // Fetch CHANGE_TARGET and CHANGE_BRANCH if env vars exist (They are set on PR builds)
    sh '[ -z $CHANGE_BRANCH ] || git fetch origin $CHANGE_BRANCH:$CHANGE_BRANCH'
    sh '[ -z $CHANGE_TARGET ] || git fetch origin $CHANGE_TARGET:$CHANGE_TARGET'

    // Fetch default default branches needed for gitversion using gitflow.
    // These are things like master or stable, develop or dev, release-* etc
    sh '''
    for b in $(git ls-remote --quiet --heads origin stable master dev develop release-* hotfix-* | sed "s:.*/::g"); do
        git rev-parse -q --verify $b > /dev/null && echo "Branch $b exists locally" || git fetch origin $b:$b
    done
    '''

    // Checkout aforementioned branches adding any previously existing branches to the EXISTING_BRANCHES file.
    sh '''
  touch EXISTING_BRANCHES
  for r in $(git branch -a | grep -E "remotes/origin/(stable|master|dev|develop|release-.*|hotfix-*|PR-.*)"); do
    echo "Remote branch: $r"
    rr="$(echo $r | cut -d/ -f 3)";
    {
      git checkout $rr 2>/dev/null && echo $rr >> EXISTING_BRANCHES || git checkout -f -b "$rr" $r
    }
  done
  cat EXISTING_BRANCHES
  '''
}

def revertAnyChanges() {
    sh "git checkout $ORIGINAL_CHECKOUT"
    // git reset hard to revert any changes
    sh 'git clean -dfx'
    sh 'git reset --hard'
}

def processGitVersion() {
    processGitCreds()
    specialCaseGitHeadMove()
    determineOriginalCheckout()
    fetchMandatoryRefs()
    revertAnyChanges()
}

