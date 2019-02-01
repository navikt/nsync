node {
    def clusterSuffix
    def monitorId
    def clusterName = params.cluster
    def naisibleBranch = params.branch
    def skipUptimed = params.skipUptimed
    def skipNaisible = params.skipNaisible
    def naiscaperVersion = '31.0.0'
    def naisplaterVersion = '6.0.0'
    def kubectlImageTag = 'v1.12.3'
    def uptimedVersionFromPod, uptimedVersionNaisYaml, doesMasterHaveApiServer

    if (!clusterName?.trim()){
        error "cluster is not defined, aborting"
    }

    try {
        stage("init") {
            git url: "https://github.com/navikt/nsync.git"

            sh("rm -rf naisible nais-inventory nais-tpa nais-platform-apps nais-yaml ca-certificates")

            dir("nais-inventory") {
                git credentialsId: 'nais-inventory', url: "git@github.com:navikt/nais-inventory.git"
            }

            dir("naisible") {
                if (naisibleBranch) {
                    git branch: naisibleBranch, url: "https://github.com/nais/naisible.git"
                } else {
                    git url: "https://github.com/nais/naisible.git"
                }
            }

            dir("nais-platform-apps") {
                git credentialsId: 'nais-platform-apps', url: "git@github.com:navikt/nais-platform-apps.git"
            }

            dir("nais-tpa") {
                git credentialsId: 'nais-tpa', url: "git@github.com:navikt/nais-tpa.git"
            }

            dir("nais-yaml") {
                git credentialsId: 'nais-yaml', url: "git@github.com:navikt/nais-yaml.git"
            }

            dir("ca-certificates") {
                git credentialsId: 'ca-certificates', url: "git@github.com:navikt/ca-certificates.git"
            }

            clusterSuffix = sh(script: "grep 'cluster_lb_suffix' ./nais-inventory/${clusterName} | cut -d'=' -f2", returnStdout: true).trim()
        }

        stage("start monitoring of nais-testapp") {
            if (skipUptimed) {
                echo '[SKIPPING] skipping monitoring of nais-testapp'
            } else {
                sh("rm -rf ./out && mkdir -p ./out")
                uptimedVersionFromPod = sh(script: "sudo docker run -v `pwd`/out:/nais-yaml -v `pwd`/${clusterName}/config:/root/.kube/config lachlanevenson/k8s-kubectl:${kubectlImageTag} get pods -n nais -l app=uptimed -o jsonpath=\"{..image}\" |tr -s '[[:space:]]' '\\n' |uniq -c | cut -d: -f2", returnStdout: true).trim()
                if (uptimedVersionFromPod.isInteger()) {
                    uptimedVersionFromPod = uptimedVersionFromPod.toInteger()
                }
                uptimedVersionNaisYaml = sh(script: "cat nais-yaml/vars/uptimed.yaml | cut -d: -f2", returnStdout: true).trim().toInteger()
                masterNode = sh(script: "cat nais-inventory/${clusterName} | awk '/masters/{getline;print}'", returnStdout: true).trim()
                doesMasterHaveApiServer = sh(script: "nc -w 2 ${masterNode} 6443 </dev/null; echo \$?", returnStdout: true).trim().toInteger()
                if (uptimedVersionNaisYaml <= uptimedVersionFromPod && doesMasterHaveApiServer == 0) {
                    monitorId = sh(script: "curl -s -X POST https://uptimed.${clusterSuffix}/start?endpoint=https://nais-testapp.${clusterSuffix}/isalive&interval=1&timeout=900", returnStdout: true).trim()
                    sh """
                        if [[ "${monitorId}" == "" ]]; then
                            echo "No monitoring will be done for nais-testapp, could not start monitor"
			    exit 1
                        fi
                    """
                }
            }
        }

        stage("run naisible") {
            if (skipNaisible) {
              echo '[SKIPPING] naisible setup playbook'
            } else {
              def vcenter_secrets = [
                [$class: 'VaultSecret', path: "secret/aura/jenkins/vcenter", secretValues: [
                    [$class: 'VaultSecretValue', envVar: 'VCENTER_USERNAME', vaultKey: 'USERNAME'],
                    [$class: 'VaultSecretValue', envVar: 'VCENTER_PASSWORD', vaultKey: 'PASSWORD']
                  ]
                ]
              ]

              wrap([$class: 'VaultBuildWrapper', vaultSecrets: vcenter_secrets]) {
                sh("sudo -E ./ansible-playbook -f 20 --key-file=/home/jenkins/.ssh/id_rsa -i inventory/${clusterName} playbooks/setup-playbook.yaml")
              }
            }
        }

        stage("test basic functionality") {
            if (skipNaisible) {
              echo '[SKIPPING] naisible test playbook'
            } else {
              sleep 15 // allow addons to start
              sh("sudo -E ./ansible-playbook -f 20 --key-file=/home/jenkins/.ssh/id_rsa -i inventory/${clusterName} playbooks/test-playbook.yaml")
            }
        }

        stage("fetch kubeconfig for cluster") {
            sh("ansible-playbook -i ./nais-inventory/${clusterName} ./fetch-kube-config.yaml")
        }

        stage("run naisplater") {
            withCredentials([string(credentialsId: 'encryption_key', variable: 'ENC_KEY')]) {
                sh("rm -rf ./out && mkdir -p ./out")
                sh("sudo docker run -v `pwd`/nais-yaml/templates:/templates -v `pwd`/nais-yaml/vars:/vars -v `pwd`/out:/out navikt/naisplater:${naisplaterVersion} /bin/bash -c \"naisplater ${clusterName} /templates /vars /out ${ENC_KEY}\"")
                sh("sudo docker run -v `pwd`/out:/nais-yaml -v `pwd`/${clusterName}/config:/root/.kube/config lachlanevenson/k8s-kubectl:${kubectlImageTag} apply -f /nais-yaml")
            }
        }

        stage("update nais platform apps") {
            sh("sudo docker run -v `pwd`/nais-platform-apps:/root/nais-platform-apps -v `pwd`/${clusterName}:/root/.kube navikt/naiscaper:${naiscaperVersion} /bin/bash -c \"/usr/bin/helm repo update && naiscaper ${clusterName} nais /root/nais-platform-apps\"")
        }

        stage("update nais 3rd party apps") {
            sh """
                if [[ -d ./nais-tpa/clusters/${clusterName} ]]; then
                    sudo docker run -v `pwd`/nais-tpa:/root/nais-tpa -v `pwd`/${clusterName}:/root/.kube navikt/naiscaper:${naiscaperVersion} /bin/bash -c \"/usr/bin/helm repo update && /usr/bin/landscaper -v --env ${clusterName} --context ${clusterName} --namespace tpa apply --wait --wait-timeout 10m /root/nais-tpa/clusters/${clusterName}/*.yaml\"
                else
                    echo "No third party apps defined for ${clusterName}, skipping"
                fi
            """
        }

        stage("deploy nais-testapp") {
            // wait until naisd is up
            retry(15) {
                sleep 5
                httpRequest acceptType: 'APPLICATION_JSON',
                            consoleLogResponseBody: true,
                            ignoreSslErrors: true,
                            responseHandle: 'NONE',
                            url: 'https://daemon.' + clusterSuffix + '/deploystatus/default/nais-testapp',
                            validResponseCodes: '200,404'
            }

            withEnv(['HTTPS_PROXY=http://webproxy-utvikler.nav.no:8088', 'NO_PROXY=adeo.no']) {
                sh "curl --ipv4 --fail https://raw.githubusercontent.com/nais/nais-testapp/master/package.json > ./package.json"
            }

            def releaseVersion = sh(script: "node -pe 'require(\"./package.json\").version'", returnStdout: true).trim()

            withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'srvauraautodeploy', usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD']]) {
                sh "curl --ipv4 --fail -k -d \'{\"application\": \"nais-testapp\", \"version\": \"${releaseVersion}\", \"fasitEnvironment\": \"ci\", \"zone\": \"fss\", \"fasitUsername\": \"${env.USERNAME}\", \"fasitPassword\": \"${env.PASSWORD}\", \"namespace\": \"default\", \"manifesturl\": \"https://raw.githubusercontent.com/nais/nais-testapp/master/nais.yaml\"}\' https://daemon.${clusterSuffix}/deploy"
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

        stage("stop monitoring and get results of nais-testapp monitoring") {
            if (skipUptimed) {
                echo '[SKIPPING] skipping monitoring of nais-testapp'
            } else {
                if (uptimedVersionNaisYaml <= uptimedVersionFromPod && doesMasterHaveApiServer == 0) {
                    result = sh(script: "curl -s -X POST https://uptimed.${clusterSuffix}/stop/${monitorId}", returnStdout: true)
                    if ("100.00" != result) {
                        error("nais-testapp did not respond all ok during nsync of ${clusterName}. Response from uptimed was: ${result}")
                    }
                }
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
