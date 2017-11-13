node {
    def committer, committerEmail, clusterSuffix // metadata

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

            dir("kubeconfigs") {
                git url: "ssh://git@stash.devillo.no:7999/aura/kubeconfigs.git"
            }

            committer = sh(script: "git log -1 --pretty=format:'%ae (%an)'", returnStdout: true).trim()
            committerEmail = sh(script: "git log -1 --pretty=format:'%ae'", returnStdout: true).trim()
            clusterSuffix = sh(script: "grep 'cluster_lb_suffix' ./nais-inventory/${params.cluster} | cut -d'=' -f2", returnStdout: true).trim()
        }

        stage("run naisible") {
            sh("ansible-playbook -i ./nais-inventory/${params.cluster} ./naisible/setup-playbook.yaml")
        }

        stage("test basic functionality") {
            sleep 15 // allow addons to start
            sh("ansible-playbook -i ./nais-inventory/${params.cluster} ./naisible/test-playbook.yaml")
        }

        stage("update nais platform apps") {
            sh("ansible-playbook -i ./nais-inventory/${params.cluster} ./fetch-kube-config.yaml")
            sh("sudo docker run -v `pwd`/nais-platform-apps:/root/nais-platform-apps -v `pwd`/${params.cluster}:/root/.kube navikt/naiscaper:latest /bin/bash -c \"/usr/bin/helm repo update && /usr/bin/landscaper -v --dir /root/nais-platform-apps/clusters/${params.cluster} --context ${params.cluster} --namespace nais apply\"")
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

        stage("fetch and copy kubeconfigs") {
            sh('cd ./kubeconfigs; ./fetch-kube-config.sh')
        }

    } catch (e) {
        currentBuild.result = "FAILED"
        throw e

        mail body: message, from: "jenkins@aura.adeo.no", subject: "FAILED to complete ${env.JOB_NAME}", to: committerEmail
        def errormessage = "see jenkins for more info ${env.BUILD_URL}"
    }
}

