node {
    def lastCommit, clusterSuffix // metadata
    def clusterName = params.cluster
    def naiscaperVersion = '5.1.3'

    if (!clusterName?.trim()){
        error "cluster is not defined, aborting"
    }

    try {
        stage("init") {
            git credentialsId: 'navikt-ci',  url: "https://github.com/navikt/nsync.git"

            sh("rm -rf naisible nais-inventory nais-tpa nais-platform-apps")

            dir("nais-inventory") {
                git credentialsId: 'navikt-ci', url: "https://github.com/navikt/nais-inventory.git"
            }

            dir("naisible") {
                git credentialsId: 'navikt-ci', url: "https://github.com/nais/naisible.git"
            }

            dir("nais-platform-apps") {
                git credentialsId: 'navikt-ci', url: "https://github.com/navikt/nais-platform-apps.git"
            }

            dir("nais-tpa") {
                git credentialsId: 'navikt-ci', url: "https://github.com/navikt/nais-tpa.git"
            }

            clusterSuffix = sh(script: "grep 'cluster_lb_suffix' ./nais-inventory/${clusterName} | cut -d'=' -f2", returnStdout: true).trim()
            lastCommit = sh(script: "/bin/sh ./echo_recent_git_log.sh", returnStdout: true).trim()
        }

        stage("run naisible") {
            sh("ansible-playbook -i ./nais-inventory/${clusterName} ./naisible/setup-playbook.yaml")
        }

        stage("test basic functionality") {
            sleep 15 // allow addons to start
            sh("ansible-playbook -i ./nais-inventory/${clusterName} ./naisible/test-playbook.yaml")
        }
          
        stage("update nais platform apps") {
            sh("ansible-playbook -i ./nais-inventory/${clusterName} ./fetch-kube-config.yaml")
            sh("sudo docker run -v `pwd`/nais-platform-apps:/root/nais-platform-apps -v `pwd`/${clusterName}:/root/.kube navikt/naiscaper:${naiscaperVersion} /bin/bash -c \"/usr/bin/helm repo update && naiscaper ${clusterName} nais /root/nais-platform-apps\"")
        }

        stage("update nais 3rd party apps") {
            sh """
                if [[ -d /root/nais-tpa/clusters/${clusterName} ]]; then
                    sudo docker run -v `pwd`/nais-tpa:/root/nais-tpa -v `pwd`/${clusterName}:/root/.kube navikt/naiscaper:${naiscaperVersion} /bin/bash -c \"/usr/bin/helm repo update && /usr/bin/landscaper -v --env ${clusterName} --context ${clusterName} --namespace tpa apply /root/nais-tpa/clusters/${clusterName}/*.yaml\"
                else
                    echo "No third party apps defined for ${clusterName}, skipping"
                fi
            """
        }

        stage("deploy nais-testapp") {
            // wait till naisd is up
            retry(15) {
                sleep 5
                httpRequest acceptType: 'APPLICATION_JSON',
                            consoleLogResponseBody: true,
                            ignoreSslErrors: true,
                            responseHandle: 'NONE',
                            url: 'https://daemon.' + clusterSuffix +'/isalive',
                            validResponseCodes: '200'
            }

            withEnv(['HTTPS_PROXY=http://webproxy-utvikler.nav.no:8088', 'NO_PROXY=adeo.no']) {
                sh "curl https://raw.githubusercontent.com/nais/nais-testapp/master/package.json > ./package.json"
            }

            def releaseVersion = sh(script: "node -pe 'require(\"./package.json\").version'", returnStdout: true).trim()

            withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'srvauraautodeploy', usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD']]) {
                sh "curl -k -d \'{\"application\": \"nais-testapp\", \"version\": \"${releaseVersion}\", \"environment\": \"ci\", \"zone\": \"fss\", \"username\": \"${env.USERNAME}\", \"password\": \"${env.PASSWORD}\", \"namespace\": \"default\", \"manifesturl\": \"https://raw.githubusercontent.com/nais/nais-testapp/master/nais.yaml\"}\' https://daemon.${clusterSuffix}/deploy"
            }
        }

        stage("verify resources") {
            retry(15) {
                sleep 5
                httpRequest acceptType: 'APPLICATION_JSON',
                            consoleLogResponseBody: true,
                            ignoreSslErrors: true,
                            responseHandle: 'NONE',
                            url: 'https://nais-testapp.' + clusterSuffix + '/healthcheck',
                            validResponseCodes: '200'
            }
        }

        wrap([$class: 'BuildUser']) {
            slackSend channel: '#nais-internal', message: ":nais: ${clusterName} successfully nsynced by Mr. ${env.BUILD_USER}. ${lastCommit} \nSee log for more info ${env.BUILD_URL}", teamDomain: 'nav-it', tokenCredentialId: 'slack_fasit_frontend'

            if (currentBuild.result == null) {
                currentBuild.result = "SUCCESS"
                currentBuild.description = "Mr. ${env.BUILD_USER} nsynced: ${clusterName} ok"
            }
        }
    } catch (e) {
        wrap([$class: 'BuildUser']) {
            if (currentBuild.result == null) {
                currentBuild.result = "FAILURE"
                currentBuild.description = "Mr. ${env.BUILD_USER} nsynced: ${clusterName} failed"
            }

            slackSend channel: '#nais-internal', message: ":shit: nsync of ${clusterName} by Mr. ${env.BUILD_USER} failed: ${e.getMessage()}. ${lastCommit}\nSee log for more info ${env.BUILD_URL}", teamDomain: 'nav-it', tokenCredentialId: 'slack_fasit_frontend'
        }

        throw e
    }
}
