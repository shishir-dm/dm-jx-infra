pipeline {
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
        stage('Test') {
            steps {
                processGitVersion()
                container('gitversion') {
                    sh "unset JENKINS_URL && make status"
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
    // copy over to the default location
    // (for some reason the gitversion container doesn't like them where they are at the moment)
    sh "cp ~/git/credentials ~/.git-credentials || true"
    sh "cp /home/jenkins/git/credentials ~/.git-credentials || true"
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

