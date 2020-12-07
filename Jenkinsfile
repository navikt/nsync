node {
    def clusterSuffix
    def monitorId
    def clusterName = params.cluster
    def naisibleBranch = params.branch
    def skipUptimed = params.skipUptimed
    def skipNaisible = params.skipNaisible
    def naisplaterVersion = '9.0.0'
    def kubectlImageTag = 'v1.12.3'
    //def uptimedVersionFromPod, uptimedVersionNaisYaml, doesMasterHaveApiServer

    if (!clusterName?.trim()){
        error "cluster is not defined, aborting"
    }

    try {
        stage("init") {
            git url: "https://github.com/navikt/nsync.git", changelog: false

            sh("rm -rf naisible nais-inventory")

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

            def inventory_vars = readYaml file: "./nais-inventory/${clusterName}-vars.yaml"
            clusterSuffix = inventory_vars.cluster_lb_suffix
        }

//        stage("pause reboots from reboot-coordinator") {
//            if (fileExists("${clusterName}/config")) {
//              sh("docker run --rm -v `pwd`/${clusterName}/config:/root/.kube/config lachlanevenson/k8s-kubectl:${kubectlImageTag} annotate nodes --all --overwrite flatcar-linux-update.v1.flatcar-linux.net/reboot-paused=true || true")
//            } else {
//              echo 'Skipping stage because no kubeconfig was found.'
//            }
//        }

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
                sh("./ansible-playbook -f 20 --key-file=/home/jenkins/.ssh/id_rsa -i inventory/${clusterName} -e @inventory/${clusterName}-vars.yaml playbooks/setup-playbook.yaml")
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

        stage("check status of monitoring and kill script") {
            if (skipUptimed) {
                echo '[SKIPPING] skip checking uptime'
            } else {
                sh("sh ./check_uptime.sh")
            }
        }

//        stage("resume reboots from reboot-coordinator") {
//            sh("docker run --rm -v `pwd`/${clusterName}/config:/root/.kube/config lachlanevenson/k8s-kubectl:${kubectlImageTag} annotate nodes --all --overwrite flatcar-linux-update.v1.flatcar-linux.net/reboot-paused=false")
//        }

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
