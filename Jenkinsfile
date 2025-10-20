// Jenkins Pipeline for Network Policy Tests
// Supports parallel testing across multiple Kubernetes providers

pipeline {
    agent {
        label 'docker'
    }

    parameters {
        choice(
            name: 'PROVIDER',
            choices: ['kind', 'minikube', 'gke', 'eks', 'aks'],
            description: 'Kubernetes provider to test on'
        )
        choice(
            name: 'CNI',
            choices: ['calico', 'cilium', 'weave'],
            description: 'CNI plugin to use'
        )
        booleanParam(
            name: 'SKIP_UNSUPPORTED',
            defaultValue: true,
            description: 'Skip tests unsupported by CNI'
        )
        booleanParam(
            name: 'RUN_ON_GKE',
            defaultValue: false,
            description: 'Run tests on GKE (costs money!)'
        )
    }

    environment {
        RESULTS_DIR = 'test-framework/results'
        KUBECONFIG = "${WORKSPACE}/.kubeconfig"
        PATH = "${env.PATH}:/usr/local/bin"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '30'))
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
        ansiColor('xterm')
    }

    stages {
        stage('Pre-commit Checks') {
            steps {
                sh '''
                    # Install Python and pre-commit
                    if ! command -v python3 &>/dev/null; then
                        sudo apt-get update
                        sudo apt-get install -y python3 python3-pip
                    fi

                    pip3 install pre-commit

                    # Run pre-commit hooks
                    pre-commit run --all-files --show-diff-on-failure
                '''
            }
        }

        stage('BATS Unit Tests') {
            agent {
                label 'docker'
            }

            steps {
                sh '''
                    # Install dependencies
                    sudo apt-get update
                    sudo apt-get install -y parallel jq bc curl

                    # Install kubectl
                    if ! command -v kubectl &>/dev/null; then
                        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                        chmod +x kubectl
                        sudo mv kubectl /usr/local/bin/
                    fi

                    # Install kind
                    if ! command -v kind &>/dev/null; then
                        curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
                        chmod +x ./kind
                        sudo mv ./kind /usr/local/bin/kind
                    fi

                    # Create kind cluster
                    kind create cluster --wait 300s

                    # Run BATS tests
                    cd test-framework
                    ./run-all-bats-tests.sh --output both
                '''
            }

            post {
                always {
                    junit 'test-framework/results/bats/junit/*.xml'
                    archiveArtifacts artifacts: 'test-framework/results/bats/**/*', allowEmptyArchive: true
                }
                cleanup {
                    sh 'kind delete cluster || true'
                }
            }
        }

        stage('Preparation') {
            steps {
                script {
                    echo "=== Network Policy Tests ==="
                    echo "Provider: ${params.PROVIDER}"
                    echo "CNI: ${params.CNI}"
                    echo "Skip Unsupported: ${params.SKIP_UNSUPPORTED}"
                }
            }
        }

        stage('Install Dependencies') {
            steps {
                sh '''
                    # Install kubectl
                    if ! command -v kubectl &>/dev/null; then
                        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                        chmod +x kubectl
                        sudo mv kubectl /usr/local/bin/
                    fi

                    # Install dependencies
                    sudo apt-get update
                    sudo apt-get install -y parallel jq bc

                    # Verify installations
                    kubectl version --client
                    parallel --version
                    jq --version
                '''
            }
        }

        stage('Setup Cluster') {
            parallel {
                stage('Setup kind') {
                    when {
                        expression { params.PROVIDER == 'kind' }
                    }
                    steps {
                        sh '''
                            # Install kind
                            if ! command -v kind &>/dev/null; then
                                curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
                                chmod +x kind
                                sudo mv kind /usr/local/bin/
                            fi

                            # Create cluster
                            cd test-framework
                            ./provision-cluster.sh \
                                --provider kind \
                                --name np-test-jenkins \
                                --cni ${CNI} \
                                --workers 2

                            # Verify
                            kubectl get nodes
                            kubectl get pods -A
                        '''
                    }
                }

                stage('Setup minikube') {
                    when {
                        expression { params.PROVIDER == 'minikube' }
                    }
                    steps {
                        sh '''
                            # Install minikube
                            if ! command -v minikube &>/dev/null; then
                                curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
                                chmod +x minikube-linux-amd64
                                sudo mv minikube-linux-amd64 /usr/local/bin/minikube
                            fi

                            # Create cluster
                            cd test-framework
                            ./provision-cluster.sh \
                                --provider minikube \
                                --name np-test-jenkins \
                                --cni ${CNI}

                            # Verify
                            kubectl get nodes
                        '''
                    }
                }

                stage('Setup GKE') {
                    when {
                        expression { params.PROVIDER == 'gke' && params.RUN_ON_GKE }
                    }
                    steps {
                        withCredentials([file(credentialsId: 'gcp-service-account', variable: 'GCP_KEY')]) {
                            sh '''
                                # Authenticate with GCP
                                gcloud auth activate-service-account --key-file=$GCP_KEY
                                gcloud config set project ${GCP_PROJECT_ID}

                                # Create cluster
                                cd test-framework
                                export GKE_REGION=us-central1
                                export GKE_MACHINE_TYPE=e2-standard-2
                                ./provision-cluster.sh \
                                    --provider gke \
                                    --name np-test-jenkins-${BUILD_NUMBER} \
                                    --workers 2
                            '''
                        }
                    }
                }
            }
        }

        stage('Detect Environment') {
            steps {
                sh '''
                    cd test-framework
                    echo "=== Environment Detection ==="
                    ./parallel-test-runner.sh --detect
                '''
            }
        }

        stage('Run Tests') {
            steps {
                sh '''
                    cd test-framework

                    # Prepare arguments
                    ARGS=""
                    if [[ "${SKIP_UNSUPPORTED}" == "true" ]]; then
                        ARGS="$ARGS --skip-unsupported"
                    fi

                    # Run tests
                    ./parallel-test-runner.sh $ARGS || EXIT_CODE=$?

                    # Generate JUnit XML
                    ./lib/ci-helpers.sh junit-xml results/aggregate-*.json junit.xml

                    exit ${EXIT_CODE:-0}
                '''
            }
        }

        stage('Generate Reports') {
            steps {
                sh '''
                    cd test-framework

                    # Generate badge
                    ./lib/ci-helpers.sh badge results/aggregate-*.json badge.json || true

                    # Create summary
                    RESULT_FILE=$(ls -t results/aggregate-*.json | head -1)
                    if [[ -f "$RESULT_FILE" ]]; then
                        TOTAL=$(jq -r '.summary.total' "$RESULT_FILE")
                        PASSED=$(jq -r '.summary.passed' "$RESULT_FILE")
                        FAILED=$(jq -r '.summary.failed' "$RESULT_FILE")
                        TIMEOUT=$(jq -r '.summary.timeout' "$RESULT_FILE")
                        PASS_RATE=$(jq -r '.summary.pass_rate' "$RESULT_FILE")

                        cat > summary.txt <<EOF
Network Policy Test Summary
============================

Total Tests:    $TOTAL
Passed:         $PASSED
Failed:         $FAILED
Timeout:        $TIMEOUT
Pass Rate:      ${PASS_RATE}%

Provider:       ${PROVIDER}
CNI:            ${CNI}
EOF
                        cat summary.txt
                    fi
                '''
            }
        }
    }

    post {
        always {
            // Archive test results
            archiveArtifacts artifacts: 'test-framework/results/**/*.json', allowEmptyArchive: true
            archiveArtifacts artifacts: 'test-framework/results/**/*.html', allowEmptyArchive: true
            archiveArtifacts artifacts: 'test-framework/summary.txt', allowEmptyArchive: true
            archiveArtifacts artifacts: 'test-framework/badge.json', allowEmptyArchive: true

            // Publish JUnit results
            junit testResults: 'test-framework/junit.xml', allowEmptyResults: true

            // Publish HTML reports
            publishHTML([
                allowMissing: true,
                alwaysLinkToLastBuild: true,
                keepAll: true,
                reportDir: 'test-framework/results/html',
                reportFiles: 'report-*.html',
                reportName: 'Network Policy Test Report'
            ])

            // Cleanup cluster
            script {
                if (params.PROVIDER == 'kind') {
                    sh '''
                        cd test-framework
                        ./provision-cluster.sh --delete --provider kind --name np-test-jenkins || true
                    '''
                } else if (params.PROVIDER == 'minikube') {
                    sh '''
                        cd test-framework
                        ./provision-cluster.sh --delete --provider minikube --name np-test-jenkins || true
                    '''
                } else if (params.PROVIDER == 'gke' && params.RUN_ON_GKE) {
                    withCredentials([file(credentialsId: 'gcp-service-account', variable: 'GCP_KEY')]) {
                        sh '''
                            gcloud auth activate-service-account --key-file=$GCP_KEY
                            cd test-framework
                            export GKE_REGION=us-central1
                            ./provision-cluster.sh --delete --provider gke --name np-test-jenkins-${BUILD_NUMBER} || true
                        '''
                    }
                }

                // Cleanup leftover namespaces
                sh '''
                    kubectl delete namespaces -l test-runner=parallel --wait=false || true
                '''
            }
        }

        success {
            echo '✅ Network Policy tests passed!'

            script {
                // Send Slack notification on success (optional)
                if (env.SLACK_WEBHOOK_URL) {
                    sh '''
                        curl -X POST -H 'Content-type: application/json' \
                            --data "{\\"text\\":\\"✅ Network Policy tests passed on ${PROVIDER} with ${CNI}. Build: ${BUILD_URL}\\"}" \
                            ${SLACK_WEBHOOK_URL} || true
                    '''
                }
            }
        }

        failure {
            echo '❌ Network Policy tests failed!'

            script {
                // Send Slack notification on failure
                if (env.SLACK_WEBHOOK_URL) {
                    sh '''
                        curl -X POST -H 'Content-type: application/json' \
                            --data "{\\"text\\":\\"❌ Network Policy tests FAILED on ${PROVIDER} with ${CNI}. Build: ${BUILD_URL}\\"}" \
                            ${SLACK_WEBHOOK_URL} || true
                    '''
                }

                // Email notification
                if (env.EMAIL_RECIPIENTS) {
                    emailext(
                        subject: "❌ Network Policy Tests Failed - ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                        body: """
                            Network Policy tests failed.

                            Provider: ${params.PROVIDER}
                            CNI: ${params.CNI}

                            See build details: ${env.BUILD_URL}
                        """,
                        to: "${env.EMAIL_RECIPIENTS}",
                        attachLog: true
                    )
                }
            }
        }

        unstable {
            echo '⚠️ Network Policy tests are unstable!'
        }

        cleanup {
            // Cleanup workspace
            cleanWs()
        }
    }
}
