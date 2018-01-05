node {
    def committer, committerEmail, clusterSuffix // metadata
    def clusterName = ${params.cluster}

    try {
        stage("init") {
            git url: "ssh://git@stash.devillo.no:7999/aura/nsync.git"

			sh("rm -rf naisible nais-inventory nais-platform-apps")

            dir("nais-inventory") {
                git url: "ssh://git@stash.devillo.no:7999/aura/nais-inventory.git"
            }

            dir("naisible") {
                git url: "https://github.com/nais/naisible.git"
            }

            dir("nais-platform-apps") {
                git url: "ssh://git@stash.devillo.no:7999/aura/nais-platform-apps.git"
            }

            dir("nais-tpa") {
                git url: "ssh://git@stash.devillo.no:7999/aura/nais-tpa.git"
            }

            committer = sh(script: "git log -1 --pretty=format:'%ae (%an)'", returnStdout: true).trim()
            committerEmail = sh(script: "git log -1 --pretty=format:'%ae'", returnStdout: true).trim()
            clusterSuffix = sh(script: "grep 'cluster_lb_suffix' ./nais-inventory/${clusterName} | cut -d'=' -f2", returnStdout: true).trim()
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
            sh("sudo docker run -v `pwd`/nais-platform-apps:/root/nais-platform-apps -v `pwd`/${clusterName}:/root/.kube navikt/naiscaper:latest /bin/bash -c \"/usr/bin/helm repo update && /usr/bin/landscaper -v --dir /root/nais-platform-apps/clusters/${clusterName} --context ${clusterName} --namespace nais apply\"")
        }

        stage("update nais 3rd party apps") {
            sh("sudo docker run -v `pwd`/nais-tpa:/root/nais-tpa -v `pwd`/${clusterName}:/root/.kube navikt/naiscaper:latest /bin/bash -c \"/usr/bin/helm repo update && /usr/bin/landscaper -v --dir /root/nais-tpa/clusters/${clusterName} --context ${clusterName} --namespace tpa apply\"")
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
                 sh "curl -k -d \'{\"application\": \"nais-testapp\", \"version\": \"${releaseVersion}\", \"environment\": \"ci\", \"zone\": \"fss\", \"username\": \"${env.USERNAME}\", \"password\": \"${env.PASSWORD}\", \"namespace\": \"default\", \"appconfigurl\": \"https://raw.githubusercontent.com/nais/nais-testapp/master/nais.yaml\"}\' https://daemon.${clusterSuffix}/deploy"
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

        slackSend channel: '#nais-internal', message: ":nais: ${clusterName} successfully nsynced. See log for more info ${env.BUILD_URL}", teamDomain: 'nav-it', tokenCredentialId: 'slack_fasit_frontend'


        if (currentBuild.result == null) {
            currentBuild.result = "SUCCESS"
        }
    } catch (e) {
        if (currentBuild.result == null) {
            currentBuild.result = "FAILURE"
        }

        slackSend channel: '#nais-internal', message: ":shit: nsync of ${clusterName} failed: ${e.getMessage()}. See log for more info ${env.BUILD_URL}", teamDomain: 'nav-it', tokenCredentialId: 'slack_fasit_frontend'

        throw e
    }
}

