node {
    def clusterSuffix
    def clusterName = params.cluster
    def naiscaperVersion = '6.0.0'
    def naisplaterVersion = '0.0.0'
    def kubectlImageTag = 'v1.10.0'

    if (!clusterName?.trim()){
        error "cluster is not defined, aborting"
    }

    try {
        stage("init") {
            git credentialsId: 'navikt-ci',  url: "https://github.com/navikt/nsync.git"

            sh("rm -rf naisible nais-inventory nais-tpa nais-platform-apps nais-yaml")

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

            dir("nais-yaml") {
                git credentialsId: 'navikt-ci', url: "https://github.com/navikt/nais-yaml.git"
            }

            clusterSuffix = sh(script: "grep 'cluster_lb_suffix' ./nais-inventory/${clusterName} | cut -d'=' -f2", returnStdout: true).trim()
        }

        stage("run naisible") {
            sh("ansible-playbook -i ./nais-inventory/${clusterName} ./naisible/setup-playbook.yaml")
        }

        stage("test basic functionality") {
            sleep 15 // allow addons to start
            sh("ansible-playbook -i ./nais-inventory/${clusterName} ./naisible/test-playbook.yaml")
        }

        stage("fetch kubeconfig for cluster"){
            sh("ansible-playbook -i ./nais-inventory/${clusterName} ./fetch-kube-config.yaml")
        }

        stage("run naisplater") {
            sh("rm -rf ./out && mkdir -p ./out")
            sh("sudo docker run -v `pwd`/nais-yaml/templates:/templates -v `pwd`/nais-yaml/vars:/vars -v `pwd`/out:/out navikt/naisplater:${naisplaterVersion} /bin/bash -c \"naisplater ${clusterName} /templates /vars /out\"")
            sh("sudo docker run -v `pwd`/out:/nais-yaml -v `pwd`/${clusterName}/config:/root/.kube/config lachlanevenson/k8s-kubectl:${kubectlImageTag} apply -f /nais-yaml")
        }
          
        stage("update nais platform apps") {
            sh("sudo docker run -v `pwd`/nais-platform-apps:/root/nais-platform-apps -v `pwd`/${clusterName}:/root/.kube navikt/naiscaper:${naiscaperVersion} /bin/bash -c \"/usr/bin/helm repo update && naiscaper ${clusterName} nais /root/nais-platform-apps\"")
        }

        stage("update nais 3rd party apps") {
            sh """
                if [[ -d ./nais-tpa/clusters/${clusterName} ]]; then
                    sudo docker run -v `pwd`/nais-tpa:/root/nais-tpa -v `pwd`/${clusterName}:/root/.kube navikt/naiscaper:${naiscaperVersion} /bin/bash -c \"/usr/bin/helm repo update && /usr/bin/landscaper -v --env ${clusterName} --context ${clusterName} --namespace tpa apply /root/nais-tpa/clusters/${clusterName}/*.yaml\"
                else
                    echo "No third party apps defined for ${clusterName}, skipping"
                fi
            """
        }

        /*
        stage("delete nais-testapp") {
            // wait till naisd is up
            retry(15) {
                sleep 5
                httpRequest acceptType: 'APPLICATION_JSON',
                            consoleLogResponseBody: true,
                            ignoreSslErrors: true,
                            responseHandle: 'NONE',
                            url: 'https://daemon.' + clusterSuffix + '/deploystatus/default/nais-testapp',
                            validResponseCodes: '200,404'
            }

            httpRequest consoleLogResponseBody: true,
                        ignoreSslErrors: true,
                        responseHandle: 'NONE',
                        httpMode: 'DELETE',
                        url: 'https://daemon.' + clusterSuffix + '/app/default/nais-testapp',
                        validResponseCodes: '200'
                        
	       //Hack to make sure delete finishes before we deploy again.
	       retry(15) {
                sleep 5
                httpRequest consoleLogResponseBody: true,
                            ignoreSslErrors: true,
                            responseHandle: 'NONE',
                            url: 'https://daemon.' + clusterSuffix + '/deploystatus/default/nais-testapp',
                            validResponseCodes: '404'

           }
        }
        */

        stage("deploy nais-testapp") {
            withEnv(['HTTPS_PROXY=http://webproxy-utvikler.nav.no:8088', 'NO_PROXY=adeo.no']) {
                sh "curl https://raw.githubusercontent.com/nais/nais-testapp/master/package.json > ./package.json"
            }

            def releaseVersion = sh(script: "node -pe 'require(\"./package.json\").version'", returnStdout: true).trim()

            withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'srvauraautodeploy', usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD']]) {
                sh "curl -k -d \'{\"application\": \"nais-testapp\", \"version\": \"${releaseVersion}\", \"fasitEnvironment\": \"ci\", \"zone\": \"fss\", \"fasitUsername\": \"${env.USERNAME}\", \"fasitPassword\": \"${env.PASSWORD}\", \"namespace\": \"default\", \"manifesturl\": \"https://raw.githubusercontent.com/nais/nais-testapp/master/nais.yaml\"}\' https://daemon.${clusterSuffix}/deploy"
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

        slackSend channel: '#nais-ci', color: "good", message: "${clusterName} successfully nsynced :nais: ${env.BUILD_URL}", teamDomain: 'nav-it', tokenCredentialId: 'slack_fasit_frontend'

        if (currentBuild.result == null) {
            currentBuild.result = "SUCCESS"
            currentBuild.description = "${clusterName} ok"
        }
    } catch (e) {
        if (currentBuild.result == null) {
            currentBuild.result = "FAILURE"
            currentBuild.description = "${clusterName} failed"
        }

        slackSend channel: '#nais-ci', color: "danger", message: ":shit: nsync of ${clusterName} failed: ${e.getMessage()}.\nSee log for more info ${env.BUILD_URL}", teamDomain: 'nav-it', tokenCredentialId: 'slack_fasit_frontend'

        throw e
    }
}
