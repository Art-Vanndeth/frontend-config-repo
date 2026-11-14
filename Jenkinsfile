// ==============================================================================
// Jenkins CD Pipeline - Frontend Configuration Repository
// Repo: https://github.com/Art-Vanndeth/frontend-config-repo.git
// Flow: Triggered by frontend-project-pipeline or Git Webhook ->
//       Update K8s/Helm Image Tag -> Push Git (ArgoCD Webhook) ->
//       Package & Push Helm Chart to Nexus -> Ansible Subdomain Config -> Telegram
// ==============================================================================

def sendTelegram(String message) {
    withCredentials([
        string(credentialsId: 'telegram-bot-token', variable: 'TG_BOT_TOKEN'),
        string(credentialsId: 'telegram-chat-id', variable: 'TG_CHAT_ID')
    ]) {
        sh """
            curl -s -X POST "https://api.telegram.org/bot\${TG_BOT_TOKEN}/sendMessage" \
              -d chat_id="\${TG_CHAT_ID}" \
              -d parse_mode="HTML" \
              --data-urlencode "text=${message}" > /dev/null
        """
    }
}

pipeline {
    agent any

    parameters {
        string(name: 'IMAGE_TAG', defaultValue: '', description: 'Docker image tag from frontend-project-pipeline (leave empty for direct config push)')
        choice(name: 'ENVIRONMENT', choices: ['prod', 'dev'], description: 'Target Helm environment values file')
    }

    triggers {
        GenericTrigger(
            genericVariables: [
                [key: 'GIT_BRANCH', value: '$.ref'],
                [key: 'COMMIT_MSG', value: '$.commits[0].message']
            ],
            regexpFilterText: '$COMMIT_MSG',
            regexpFilterExpression: '^(?!.*\\[skip ci\\]).*$',
            causeString: 'Triggered by Frontend Config Repo Push Webhook',
            token: 'frontend-config-token',
            printContributedVariables: true,
            printPostContent: false
        )
    }

    environment {
        CHART_NAME          = 'cstad-frontend'
        NEXUS_HELM_REPO_URL = 'https://nexus.devops.cstad.edu.kh/repository/nexus-helm/'
        HELM_VERSION        = "1.0.${BUILD_NUMBER}"
        FRONTEND_DOMAIN     = 'app.devops.cstad.edu.kh'
    }

    stages {
        stage('Notify Config CD Start') {
            steps {
                script {
                    sendTelegram("⚙️ <b>Frontend Config CD Started</b>\n<b>Build:</b> #${env.BUILD_NUMBER}\n<b>Env:</b> ${params.ENVIRONMENT}\n<b>Requested Tag:</b> <code>${params.IMAGE_TAG ?: 'manual-config-update'}</code>")
                }
            }
        }

        stage('Checkout Config Repository') {
            steps {
                checkout scm
                sh 'git checkout main || git checkout master'
            }
        }

        stage('Update K8s & Helm Image Tag') {
            when {
                expression { return params.IMAGE_TAG?.trim() }
            }
            steps {
                sh """
                    sed -i.bak -E "s|(docker\\.devops\\.cstad\\.edu\\.kh/cstad-frontend:).*|\\1${params.IMAGE_TAG}|g" k8s/deployment.yaml
                    sed -i.bak -E "s|^([[:space:]]*tag:[[:space:]]*).*|\\1\\"${params.IMAGE_TAG}\\"|g" helm-chart/values.yaml
                    sed -i.bak -E "s|^appVersion:.*|appVersion: \\"${params.IMAGE_TAG}\\"|g" helm-chart/Chart.yaml
                    rm -f k8s/*.bak helm-chart/*.bak
                """
            }
        }

        stage('Validate K8s & Helm Manifests') {
            steps {
                sh """
                    helm lint ./helm-chart -f ./helm-chart/values-${params.ENVIRONMENT}.yaml
                    helm template ${CHART_NAME} ./helm-chart -f ./helm-chart/values-${params.ENVIRONMENT}.yaml > /dev/null
                """
            }
        }

        stage('Push Updated Manifests to Private Git Repo') {
            when {
                expression { return params.IMAGE_TAG?.trim() }
            }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'git-private-creds',
                    usernameVariable: 'GIT_USER',
                    passwordVariable: 'GIT_PASS'
                )]) {
                    sh '''
                        git config user.name "Jenkins CI Bot"
                        git config user.email "jenkins@devops.cstad.edu.kh"
                        if ! git diff --quiet; then
                            git add k8s/deployment.yaml helm-chart/values.yaml helm-chart/Chart.yaml
                            git commit -m "chore(cd): update frontend image tag to ${IMAGE_TAG} [skip ci]"
                            REPO_URL=$(git config --get remote.origin.url | sed -E "s#https://#https://${GIT_USER}:${GIT_PASS}@#")
                            git push "${REPO_URL}" HEAD:main
                        else
                            echo "No manifest changes to commit."
                        fi
                    '''
                }
            }
        }

        stage('Package & Push Helm Chart to Nexus (Bonus)') {
            steps {
                script {
                    def appVer = params.IMAGE_TAG?.trim() ? params.IMAGE_TAG : 'v1.0.0'
                    sh """
                        sed -i.bak -E "s|^version:.*|version: ${HELM_VERSION}|g" helm-chart/Chart.yaml
                        rm -f helm-chart/*.bak
                        helm package ./helm-chart --version "${HELM_VERSION}" --app-version "${appVer}" -d /tmp/helm-pkg
                    """
                    withCredentials([usernamePassword(
                        credentialsId: 'nexus-creds',
                        usernameVariable: 'NEXUS_USER',
                        passwordVariable: 'NEXUS_PASS'
                    )]) {
                        sh """
                            curl --fail-with-body -u "\${NEXUS_USER}:\${NEXUS_PASS}" \
                              --upload-file "/tmp/helm-pkg/${CHART_NAME}-${HELM_VERSION}.tgz" \
                              "${NEXUS_HELM_REPO_URL}${CHART_NAME}-${HELM_VERSION}.tgz"
                            rm -rf /tmp/helm-pkg
                        """
                    }
                }
            }
        }

        stage('Configure Subdomain via Ansible') {
            steps {
                sh """
                    if [ -f /opt/ansible/playbooks/03-configure-nginx-subdomains.yml ]; then
                        ansible-playbook -i /opt/ansible/inventory.ini \
                          /opt/ansible/playbooks/03-configure-nginx-subdomains.yml \
                          --tags frontend
                    else
                        echo "Ansible controller playbook mounted at /opt/ansible; skipping local run if not present on agent."
                    fi
                """
            }
        }
    }

    post {
        success {
            script {
                sendTelegram("✅ <b>Frontend Config CD &amp; Helm Push Succeeded</b>\n<b>Chart:</b> <code>${env.CHART_NAME}-${env.HELM_VERSION}.tgz</code>\n<b>Image Tag:</b> <code>${params.IMAGE_TAG ?: 'unchanged'}</code>\n<b>Domain:</b> https://${env.FRONTEND_DOMAIN}\n<b>ArgoCD:</b> Sync triggered via Git/Helm\n<b>URL:</b> ${env.BUILD_URL}")
            }
        }
        failure {
            script {
                sendTelegram("❌ <b>Frontend Config CD Failed</b>\n<b>Build:</b> #${env.BUILD_NUMBER}\n<b>URL:</b> ${env.BUILD_URL}")
            }
        }
    }
}

