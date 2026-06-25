// Jenkinsfile - Pipeline CI/CD SentimentAI - 11 stages
pipeline {
    agent any

    environment {
        IMAGE_NAME = 'sentiment-ai'
        REGISTRY   = 'ghcr.io/samuelgoure'
        IMAGE_TAG  = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                echo "Branche : ${env.GIT_BRANCH}"
                echo "Commit  : ${env.GIT_COMMIT}"
                sh 'git log --oneline -5'
            }
        }

        stage('Lint') {
            steps {
                sh '''
                    docker run --rm \
                        --volumes-from jenkins \
                        -w $WORKSPACE \
                        python:3.12-slim \
                        sh -c "pip install flake8 -q && flake8 src/ --max-line-length=100"
                '''
            }
        }

        stage('IaC Validate') {
            steps {
                dir('infra') {
                    sh 'terraform init -backend=false -input=false'
                    sh 'terraform fmt -check'
                    sh 'terraform validate'
                }
            }
        }

        stage('Build & Test') {
            steps {
                sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
                sh """
                    docker run --rm \
                        --volumes-from jenkins \
                        -w \$WORKSPACE \
                        ${IMAGE_NAME}:${IMAGE_TAG} \
                        pytest tests/ -v \
                        --cov=src \
                        --cov-report=xml:coverage.xml \
                        --cov-report=term-missing \
                        --cov-fail-under=70
                """
            }
            post {
                failure {
                    echo 'Tests échoués ou coverage insuffisant (< 70%)'
                }
            }
        }

        stage('SonarQube Analysis') {
            environment {
                SONARQUBE_TOKEN = credentials('sonar-token')
            }
            steps {
                withSonarQubeEnv('sonarqube') {
                    sh '''
                        docker run --rm \
                            --network sentiment-ai_cicd-network \
                            --volumes-from jenkins \
                            -w "$WORKSPACE" \
                            -e SONAR_HOST_URL="$SONAR_HOST_URL" \
                            -e SONAR_TOKEN="$SONARQUBE_TOKEN" \
                            sonarsource/sonar-scanner-cli:latest \
                            sonar-scanner \
                                -Dsonar.projectKey=sentiment-ai \
                                -Dsonar.projectName=SentimentAI \
                                -Dsonar.projectBaseDir="$WORKSPACE" \
                                -Dsonar.sources=src \
                                -Dsonar.python.version=3.11 \
                                -Dsonar.python.coverage.reportPaths=coverage.xml \
                                -Dsonar.sourceEncoding=UTF-8 \
                                -Dsonar.scanner.metadataFilePath="$WORKSPACE/report-task.txt"
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Security Scan') {
            steps {
                sh """
                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v trivy-cache:/root/.cache/trivy \
                        aquasec/trivy:latest image \
                        --severity HIGH,CRITICAL \
                        --exit-code 0 \
                        --format table \
                        ${IMAGE_NAME}:${IMAGE_TAG}
                """
            }
            post {
                failure {
                    echo 'Vulnérabilités CRITICAL ou HIGH détectées !'
                    echo 'Corrigez les dépendances avant de déployer.'
                }
            }
        }

        stage('Push') {
            when { expression { env.GIT_BRANCH == 'main' || env.GIT_BRANCH == 'origin/main' } }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'github-token',
                    usernameVariable: 'REGISTRY_USER',
                    passwordVariable: 'REGISTRY_PASS'
                )]) {
                    sh """
                        echo \$REGISTRY_PASS | docker login ghcr.io \
                            -u \$REGISTRY_USER --password-stdin
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:latest
                        docker push ${REGISTRY}/${IMAGE_NAME}:latest
                    """
                }
            }
        }

        // IaC Apply -- main seulement, apres Push
        stage('IaC Apply') {
            when { expression { env.GIT_BRANCH == 'main' || env.GIT_BRANCH == 'origin/main' } }
            steps {
                dir('infra') {
                    sh 'terraform init -input=false'
                    sh '''
                        # Importer le reseau s'il existe mais n'est pas dans le state
                        NETWORK_ID=$(docker network inspect cicd-network --format '{{.Id}}' 2>/dev/null || true)
                        if [ -n "$NETWORK_ID" ]; then
                            terraform import docker_network.cicd "$NETWORK_ID" 2>/dev/null || true
                        fi
                        # Supprimer le conteneur staging s'il existe (Terraform le recrée)
                        docker stop sentiment-staging 2>/dev/null || true
                        docker rm sentiment-staging 2>/dev/null || true
                    '''
                    sh """
                        terraform apply -auto-approve \
                            -var='image_tag=${IMAGE_TAG}'
                    """
                }
            }
        }

        stage('Deploy Staging') {
            when { expression { env.GIT_BRANCH == 'main' || env.GIT_BRANCH == 'origin/main' } }
            steps {
                sh 'docker exec sentiment-staging curl -sf http://localhost:8000/health || exit 1'
            }
        }

        stage('Smoke Test') {
            when { expression { env.GIT_BRANCH == 'main' || env.GIT_BRANCH == 'origin/main' } }
            steps {
                // Verifier que /metrics expose bien nos metriques personnalisees
                sh '''
                    docker exec sentiment-staging curl -sf http://localhost:8000/health
                    docker exec sentiment-staging curl -s http://localhost:8000/metrics \
                        | grep -q "sentiment_predictions_total" \
                        || (echo "ERREUR: metrique sentiment_predictions_total absente" && exit 1)
                    echo "Metriques Prometheus OK"
                '''
                // Verifier Prometheus et Grafana s'ils tournent (non bloquant)
                sh '''
                    docker exec prometheus curl -sf \
                        "http://localhost:9090/api/v1/query?query=up" \
                        > /dev/null 2>&1 && echo "Prometheus OK" \
                        || echo "Prometheus non disponible (ignoré)"
                    docker exec grafana curl -sf http://localhost:3000/api/health \
                        > /dev/null 2>&1 && echo "Grafana OK" \
                        || echo "Grafana non disponible (ignoré)"
                '''
            }
        }
    }

    post {
        always {
            sh 'docker compose down -v 2>/dev/null || true'
        }
        success {
            echo "Pipeline réussi ! Image : ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        }
        failure {
            echo 'Pipeline échoué. Consultez les logs ci-dessus.'
        }
    }
}
