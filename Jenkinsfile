node {
    def clusterSuffix
    def monitorId
    def clusterName = params.cluster
    def naisibleBranch = params.branch
    def skipUptimed = params.skipUptimed
    def skipNaisible = params.skipNaisible
    def naiscaperVersion = '34.0.0'
    def bashscaperVersion = '15.0.2'
    def naisplaterVersion = '9.0.0'
    def kubectlImageTag = 'v1.12.3'
    //def uptimedVersionFromPod, uptimedVersionNaisYaml, doesMasterHaveApiServer

    if (!clusterName?.trim()){
        error "cluster is not defined, aborting"
    }

    try {
        stage("init") {
            git url: "https://github.com/navikt/nsync.git", changelog: false

            sh("rm -rf naisible nais-inventory nais-platform-apps nais-yaml ca-certificates")

            dir("nais-inventory") {
                git credentialsId: 'nais-inventory', url: "git@github.com:navikt/nais-inventory.git", changelog: false
            }

            dir("naisible") {
                if (naisibleBranch) {
                    git branch: naisibleBranch, url: "https://github.com/nais/naisible.git", changelog: false
                } else {
                    git url: "https://github.com/nais/naisible.git", changelog: false
                }
            }

            dir("nais-platform-apps") {
                git credentialsId: 'nais-platform-apps', url: "git@github.com:navikt/nais-platform-apps.git", changelog: false
            }

            dir("nais-yaml") {
                git credentialsId: 'nais-yaml', url: "git@github.com:navikt/nais-yaml.git", changelog: false
            }

            dir("ca-certificates") {
                git credentialsId: 'ca-certificates', url: "git@github.com:navikt/ca-certificates.git", changelog: false
            }

            def inventory_vars = readYaml file: "./nais-inventory/${clusterName}-vars.yaml"
            clusterSuffix = inventory_vars.cluster_lb_suffix
        }

        stage("pause reboots from reboot-coordinator") {
            if (fileExists("${clusterName}/config")) {
              sh("docker run --rm -v `pwd`/${clusterName}/config:/root/.kube/config lachlanevenson/k8s-kubectl:${kubectlImageTag} annotate nodes --all --overwrite flatcar-linux-update.v1.flatcar-linux.net/reboot-paused=true || true")
            } else {
              echo 'Skipping stage because no kubeconfig was found.'
            }
        }

        stage ("start monitoring of up") {
            if (skipUptimed) {
                echo '[SKIPPING] skipping monitoring of up'
            } else {
                sh("nohup sh -c '( ( ./uptime.sh https://up.${clusterSuffix}/ping 1500 ) & echo \$! > pid )' > `pwd`/nohup.out")
            }
        }

        stage("run naisible") {
            if (skipNaisible) {
              echo '[SKIPPING] naisible setup playbook'
            } else {
              def vsphere_secrets = [
                [$class: 'VaultSecret', path: "secret/aura/jenkins/vsphere", secretValues: [
                    [$class: 'VaultSecretValue', envVar: 'VSPHERE_USERNAME', vaultKey: 'USERNAME'],
                    [$class: 'VaultSecretValue', envVar: 'VSPHERE_PASSWORD', vaultKey: 'PASSWORD']
                  ]
                ]
              ]

              wrap([$class: 'VaultBuildWrapper', vaultSecrets: vsphere_secrets]) {
                sh("./ansible-playbook -f 20 --key-file=/home/jenkins/.ssh/id_rsa -i inventory/${clusterName} -e @inventory/${clusterName}-vars.yaml playbooks/setup-playbook.yaml")
              }
            }
        }

        stage("test basic functionality") {
            if (skipNaisible) {
              echo '[SKIPPING] naisible test playbook'
            } else {
              sleep 15 // allow addons to start
              sh("./ansible-playbook -f 20 --key-file=/home/jenkins/.ssh/id_rsa -i inventory/${clusterName} -e @inventory/${clusterName}-vars.yaml playbooks/test-playbook.yaml")
            }
        }

        stage("fetch kubeconfig for cluster") {
            sh("ansible-playbook -i nais-inventory/${clusterName} -e @nais-inventory/${clusterName}-vars.yaml ./fetch-kube-config.yaml")
        }

        stage("run naisplater") {
            withCredentials([string(credentialsId: 'encryption_key', variable: 'ENC_KEY')]) {
                sh("rm -rf ./out && mkdir -p ./out")
                sh("docker run --rm -v `pwd`/nais-yaml/templates:/templates -v `pwd`/nais-yaml/vars:/vars -v `pwd`/out:/out navikt/naisplater:${naisplaterVersion} /bin/bash -c \"naisplater ${clusterName} /templates /vars /out ${ENC_KEY}\"")
                sh("""
                  mkdir -p `pwd`/out/raw
                  cp `pwd`/nais-yaml/raw/*.yaml `pwd`/out/raw || true
                  cp `pwd`/nais-yaml/raw/${clusterName}/*.yaml `pwd`/out/raw || true
                """)
                sh("docker run --rm -v `pwd`/out:/nais-yaml -v `pwd`/${clusterName}/config:/root/.kube/config lachlanevenson/k8s-kubectl:${kubectlImageTag} apply --recursive=true -f /nais-yaml")
            }
        }

        stage("update nais platform apps") {
            sh """
                docker volume create "naiscaper-output-${clusterName}-${env.BUILD_NUMBER}"
                docker run --rm \
                  -v naiscaper-output-${clusterName}-${env.BUILD_NUMBER}:/naiscaper/output \
                  -v `pwd`/nais-platform-apps/base:/naiscaper/input/base:ro \
                  -v `pwd`/nais-platform-apps/clusters/${clusterName}:/naiscaper/input/overrides:ro \
                  navikt/naiscaper:${naiscaperVersion} \
                  /bin/bash -c \"naiscaper /naiscaper/input/base /naiscaper/input/overrides /naiscaper/output\"
            """

            sh """
                docker run --rm \
                  -v naiscaper-output-${clusterName}-${env.BUILD_NUMBER}:/apply \
                  -v `pwd`/${clusterName}:/root/.kube \
                  navikt/bashscaper:${bashscaperVersion} \
                  /bin/bash -c \"/usr/bin/helm repo update && bashscaper nais ${clusterName} /apply/*.yaml\"
                docker volume rm "naiscaper-output-${clusterName}-${env.BUILD_NUMBER}"
            """
        }
        stage("check status of monitoring and kill script") {
            if (skipUptimed) {
                echo '[SKIPPING] skip checking uptime'
            } else {
                sh("sh ./check_uptime.sh")
            }
        }

        stage("resume reboots from reboot-coordinator") {
            sh("docker run --rm -v `pwd`/${clusterName}/config:/root/.kube/config lachlanevenson/k8s-kubectl:${kubectlImageTag} annotate nodes --all --overwrite flatcar-linux-update.v1.flatcar-linux.net/reboot-paused=false")
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

        sh """
          echo If this next step fails, it just means that the pipeline failed before the volume was created.
          docker volume rm \"naiscaper-output-${clusterName}-${env.BUILD_NUMBER}\" || true
        """
        throw e
    }
}
