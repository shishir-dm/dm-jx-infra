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
                sh 'echo hello'
            }
        }
    }
    post {
        cleanup {
            cleanWs()
        }
    }
}

