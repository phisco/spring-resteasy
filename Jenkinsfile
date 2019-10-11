podTemplate(yaml: """
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: jenkins-builder
spec:
  containers:
  - name: maven
    image: maven:3.3.9-jdk-8-alpine
    command:
    - cat
    tty: true
    volumeMounts:
    - name: maven-repo
      mountPath: "/root/.m2"
  - name: hadolint
    image: hadolint/hadolint:v1.17.2-debian
    tty: true
  - name: opa
    image: quay.io/sighup/opa:3.1_1.31.0_0.15.0-dev
    command:
    - cat
    tty: true
    volumeMounts:
    - name: policy
      mountPath: /policy
  - name: dind
    image: docker:dind
    securityContext:
      privileged: true
    volumeMounts:
    #- name: dockersock
      #mountPath: "/var/run/docker.sock"
    - name: gnupg
      subPath: gnupg.tgz
      mountPath: /conf/gnupg.tgz
    tty: true
    env:
    - name: MY_POD_IP
      valueFrom:
        fieldRef:
            fieldPath: status.podIP
    args: ["--insecure-registry=nexus:8082", "--storage-driver=overlay2"]
  volumes:
  - name: policy
    configMap:
      name: policy
  - name: gnupg
    configMap:
      name: gnupg
  - name: dockersock
    hostPath:
      path: /var/run/docker.sock
  - name: maven-repo
    persistentVolumeClaim:
      claimName: "maven-repo-claim"
""") {
  node(POD_LABEL) {
    def gitvars
      stage('checkout') {
        gitvars = checkout scm
        sh 'mkdir reports'
      }
    stage('Application Specific Stage - Maven') {
      container('maven') {
        withMaven(globalMavenSettingsConfig: 'MavenGlobalSIGHUP') {
          // sh "mvn -B -DskipTests clean package"
          // sh 'mvn clean install'
          // sh 'mvn test'
          //We simulate the war generation to save time:
          sh 'mkdir target ; echo "delete me" > target/spring-resteasy.war'
        }
      }
    }
    stage('Dockerfile linting (Hadolint)'){
      container('hadolint') {
        // This step is going to be replaced by OPA in the feature. They're integrating Dockerfile validation into `conftest`.
        sh 'hadolint Dockerfile'
      }
    }
    stage('Manifests linting (OPA)') {
      container('opa') {
        // We should be pushing/pulling the policies from/to the Registry, 
        // can't use this approach due to us using an insecure registry for testing and this is not supported by conftest.
        sh "conftest test --policy=/policy deployment.yaml"
          //echo 'PASS'
      }
    }
    container('dind'){
      stage('Docker image Build') {
        // We can use also the docker plugin. Like this:
        // app = docker.build("nexus:8082/registry/unicredit/myapp:1.0")
        // TODO: analyze if it's more convenient.
        docker.withRegistry('http://nexus:8082/', 'nexus-admin') {
          // TODO: replace the hard-coded image name by a variable:
          // sh "docker pull nexus:8082/registry/unicredit/$JOB_NAME:latest"
          sh "docker build --network host --cache-from nexus:8082/unicredit/apps/$JOB_NAME:latest --tag nexus:8082/unicredit/apps/$JOB_NAME:latest --tag nexus:8082/unicredit/apps/$JOB_NAME:$gitvars.GIT_COMMIT ."
          // The following snippet was used to pull from dockerhub and push to nexus to speed up the process:
          //sh 'docker pull jboss/wildfly:17.0.1.Final'
          //sh 'docker tag jboss/wildfly:17.0.1.Final nexus:8082/unicredit/apps/wildfly:17.0.1.Final'
          //sh 'docker push nexus:8082/unicredit/apps/wildfly:17.0.1.Final'
          // sh 'docker pull vladgh/gpg'
          // sh 'docker tag vladgh/gpg nexus:8082/registry/unicredit/gpg'
          // sh 'docker push nexus:8082/registry/unicredit/gpg'
          // sh 'docker pull curlimages/curl:7.66.0'
          // sh 'docker tag curlimages/curl:7.66.0 nexus:8082/registry/unicredit/curl:7.66.0'
          // sh 'docker push nexus:8082/registry/unicredit/curl:7.66.0'
          // sh 'docker pull ralgozino/clair-scanner'
          // sh 'docker tag ralgozino/clair-scanner nexus:8082/registry/unicredit/clair-scanner'
          // sh 'docker push nexus:8082/registry/unicredit/clair-scanner'
          // We pull the images prior to using `docker run`:
          sh 'docker pull nexus:8082/registry/unicredit/gpg'
          sh 'docker pull nexus:8082/registry/unicredit/curl:7.66.0'
          sh 'docker pull nexus:8082/registry/unicredit/clair-scanner'
        }
      }
      stage('Docker image Static Analysis'){
        sh "docker run -v /var/run/docker.sock:/var/run/docker.sock:ro -v \${PWD}/reports:/reports --network=host nexus:8082/registry/unicredit/clair-scanner --clair=http://clair:6060 --ip=\${MY_POD_IP} --report=/reports/security-report.json -t Critical nexus:8082/unicredit/apps/$JOB_NAME:$gitvars.GIT_COMMIT"
      }
      stage('Docker image signing'){
        sh 'tar xzvf /conf/gnupg.tgz -C /'
          sh 'docker inspect nexus:8082/unicredit/apps/$JOB_NAME:$gitvars.GIT_COMMIT --format "{{.Id}}" > reports/image_id.txt'
          sh 'docker run -v "${PWD}/reports:/reports" -v /gnupg:/root/.gnupg nexus:8082/registry/unicredit/gpg -u image.signer@example.com \
          --armor \
          --clearsign \
          --output=reports/signature.gpg \
          reports/image_id.txt'
          // The following lines are for saving variables in files. This probably could be done better.
          // I tried to use ENV VARS but it seems that Jenkins doesn't save them to ENV, so when you want
          // to use them they are empty.
          // sh 'docker run -v /gnupg:/root/.gnupg nexus:8082/registry/unicredit/gpg --armor --export image.signer@example.com > "$(cat GPG_KEY_ID).pub"'
          sh 'docker run -v /gnupg:/root/.gnupg nexus:8082/registry/unicredit/gpg --list-keys --keyid-format short|egrep "expires"|cut -d " " -f 4 | cut -d / -f 2 > GPG_KEY_ID'
          sh 'cat reports/signature.gpg | base64 > GPG_SIGNATURE'
          sh 'echo "http://nexus:8082/registry/unicredit/myapp@$(cat reports/image_id.txt)" > RESOURCE_URL'

          // The note datatype should be created only once. Is the "general definition of the occurrences".
          // It shouldn't be part of the "application pipeline", but I'm leaving it here as reminder until we decide how to do it.
          def note = readJSON text: '{"name": "projects/image-signing/notes/cienv","shortDescription": "CI Env image signer","longDescription": "CI Env image signer","attestationAuthority": {"hint": {"humanReadableName": "CI Environment"}}}'
          writeJSON file: 'note.json', json: note
          sh 'docker run  --network host -v "${PWD}/note.json:/note.json" nexus:8082/registry/unicredit/curl:7.66.0 -X POST \
          "http://grafeas:8080/v1beta1/projects/image-signing/notes?noteId=cienv" \
          -d @/note.json'
          // In the previous command we run `curl` WITHOUT the `--fail` flag, in case the note already exists, we don't want the pipeline to fail.

          sh 'echo {\\\"resource\\\": { \\\"uri\\\": \\\"$(cat RESOURCE_URL)\\\" }, \\\"noteName\\\": \\\"projects/image-signing/notes/cienv\\\",\\\"attestation\\\": {\\\"attestation\\\": { \\\"pgpSignedAttestation\\\": {\\\"signature\\\": \\\"$(cat GPG_SIGNATURE)\\\",\\\"pgpKeyId\\\": \\\"$(cat GPG_KEY_ID)\\\"}}}} > occurrence.json'
          sh 'docker run --network host -v "${PWD}/occurrence.json:/occurrence.json" nexus:8082/registry/unicredit/curl:7.66.0 --fail --show-error -X POST \
          "http://grafeas:8080/v1beta1/projects/image-signing/occurrences" \
          -d @/occurrence.json'
      }
      stage('Docker image Push'){
        docker.withRegistry('http://nexus:8082/registry/unicredit', 'nexus-admin') {
          // app.push("nexus:8082/unicredit/apps/$JOB_NAME:$gitvars.GIT_COMMIT")
          sh "docker push nexus:8082/unicredit/apps/$JOB_NAME:$gitvars.GIT_COMMIT"
        }
      }
    }
    // TODO: make the collection always, eventhough the pipeline fails, so we can have the security reports for analysis for example.
    stage('Collect Artifacts'){
      archiveArtifacts artifacts: 'reports/*', fingerprint: true
                                            }
    }
  }

