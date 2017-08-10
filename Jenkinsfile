node {
    def committer, committerEmail // metadata

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
            sh("sudo docker run -v `pwd`/nais-platform-apps:/root/nais-platform-apps -v `pwd`/kube:/root/.kube navikt/naiscaper:latest /usr/bin/landscaper --dir /root/nais-platform-apps/clusters/${params.cluster} --context ${params.cluster} apply")
        }

        stage("run integration tests") {
            sh("echo 'testing all night long'")
        }

        stage("fetch and copy kubeconfigs") {
            sh('cd /kubeconfigs; ./fetch-kube-config.sh')
        }

    } catch (e) {
        currentBuild.result = "FAILED"
        throw e

        mail body: message, from: "jenkins@aura.adeo.no", subject: "FAILED to complete ${env.JOB_NAME}", to: committerEmail
        def errormessage = "see jenkins for more info ${env.BUILD_URL}"
    }
}

