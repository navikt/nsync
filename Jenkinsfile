node {
    def cluster, committer, committerEmail // metadata

    try {
        stage("init") {
            git url: "ssh://git@stash.devillo.no:7999/aura/${cluster}-pipeline.git"

            dir("nais-inventory") {
                git url: "ssh://git@stash.devillo.no:7999/aura/nais-inventory.git"
            }

            dir("naisible") {
                git url: "https://github.com/nais/naisible.git"
            }

            dir("naiscaper") {
                git url: "ssh://git@stash.devillo.no:7999/aura/nais-platform-apps.git"
            }

            committer = sh(script: "git log -1 --pretty=format:'%ae (%an)'", returnStdout: true).trim()
            committerEmail = sh(script: "git log -1 --pretty=format:'%ae'", returnStdout: true).trim()
        }

        stage("run naisible") {
            sh('̈́ansible-playbook -i ./nais-inventory/${cluster} ./naisible/setup-playbook.yaml")
        }

        stage("test basic functionality") {
            sleep 15 // allow addons to start
            sh("ansible-playbook -i ./nais-inventory/${cluster} ./naisible/test-playbook.yaml")
        }

        stage("fetch kube-config from master") {
            sh("ansible-playbook -i ./nais-inventory/${cluster} ./fetch-kube-config.yaml")
        }

        stage("update nais platform apps") {
            sh("sudo docker run -v `pwd`/naiscaper:/root/naiscaper -v `pwd`/kube:/root/.kube navikt/naiscaper:latest /usr/bin/landscaper --dir /root/naiscaper/clusters/${cluster} --context ${cluster} apply")
        }

        stage("run integration tests") {
            sh("echo "testing all night long"")
        }

    } catch (e) {
        currentBuild.result = "FAILED"
        throw e

        mail body: message, from: "jenkins@aura.adeo.no", subject: "FAILED to complete ${env.JOB_NAME}", to: committerEmail
        def errormessage = "see jenkins for more info ${env.BUILD_URL}"
    }
}

