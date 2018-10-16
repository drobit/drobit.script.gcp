#!/bin/bash

gcloud container clusters create spinnaker-tutorial \
    --zone us-central1-f \
    --machine-type=n1-standard-2 \
    --disk-type=pd-ssd \
    --node-locations us-central1-a,us-central1-b,us-central1-f \
    --num-nodes 1 --enable-autoscaling --min-nodes 1 --max-nodes 5
	
gcloud iam service-accounts create  spinnaker-storage-account \
    --display-name spinnaker-storage-account

export SA_EMAIL=$(gcloud iam service-accounts list \
    --filter="displayName:spinnaker-storage-account" \
    --format='value(email)')
	
export PROJECT=$(gcloud info --format='value(config.project)')

gcloud projects add-iam-policy-binding \
    $PROJECT --role roles/storage.admin --member serviceAccount:$SA_EMAIL

gcloud iam service-accounts keys create spinnaker-sa.json --iam-account $SA_EMAIL

wget https://storage.googleapis.com/kubernetes-helm/helm-v2.11.0-linux-amd64.tar.gz

tar zxfv helm-v2.11.0-linux-amd64.tar.gz

cp linux-amd64/helm .

kubectl create clusterrolebinding user-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value account)
kubectl create serviceaccount tiller --namespace kube-system
kubectl create clusterrolebinding tiller-admin-binding --clusterrole=cluster-admin --serviceaccount=kube-system:tiller

kubectl create clusterrolebinding --clusterrole=cluster-admin --serviceaccount=default:default spinnaker-admin

./helm init --service-account=tiller

./helm repo update

sleep 15

./helm version

export PROJECT=$(gcloud info \
    --format='value(config.project)')
export BUCKET=$PROJECT-spinnaker-config
gsutil mb -c regional -l us-central1 gs://$BUCKET

export SA_JSON=$(cat spinnaker-sa.json)
export PROJECT=$(gcloud info --format='value(config.project)')
export BUCKET=$PROJECT-spinnaker-config
cat > spinnaker-config.yaml <<EOF
storageBucket: $BUCKET
gcs:
  enabled: true
  project: $PROJECT
  jsonKey: '$SA_JSON'

# Disable minio as the default
minio:
  enabled: false


# Configure your Docker registries here
accounts:
- name: gcr
  address: https://gcr.io
  username: _json_key
  password: '$SA_JSON'
  email: 1234@5678.com
EOF

./helm install -n cd stable/spinnaker -f spinnaker-config.yaml --timeout 600 \
    --version 0.3.1

export DECK_POD=$(kubectl get pods --namespace default -l "component=deck" \
    -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward --namespace default $DECK_POD 8080:9000 >> /dev/null &

wget https://gke-spinnaker.storage.googleapis.com/sample-app.tgz

tar xzfv sample-app.tgz

p="$HOME/sample-app" 
cd "$p" && git config --global user.email "drobotserg1983@gmail.com" && git config --global user.name "drobit" && git init && git add . && git commit -m "Initial commit" && gcloud source repos create sample-app && git config credential.helper gcloud.sh && export PROJECT=$(gcloud info --format='value(config.project)') && git remote add origin https://source.developers.google.com/p/$PROJECT/r/sample-app && git push origin master

d="$HOME"
cd "$d" 
./helm install stable/prometheus --version 6.7.4 --name my-prometheus

cat > values.yml <<EOF 
persistence:
  enabled: true
  accessModes:
    - ReadWriteOnce
  size: 5Gi

datasources: 
 datasources.yaml:
   apiVersion: 1
   datasources:
   - name: Prometheus
     type: prometheus
     url: http://my-prometheus-server
     access: proxy
     isDefault: true

dashboards:
    kube-dash:
      gnetId: 6663
      revision: 1
      datasource: Prometheus
    kube-official-dash:
      gnetId: 2
      revision: 1
      datasource: Prometheus

dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
    - name: 'default'
      orgId: 1
      folder: ''
      type: file
      disableDeletion: false
      editable: true
      options:
        path: /var/lib/grafana/dashboards
EOF

./helm install --name my-grafana stable/grafana --version 1.11.6 -f values.yml

kubectl get secret --namespace default my-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

sleep 65

export POD_NAME=$(kubectl get pods --namespace default -l "app=grafana" -o jsonpath="{.items[0].metadata.name}")

kubectl --namespace default port-forward $POD_NAME 3000 >> /dev/null &


cd "$p"

touch deploypipeline.sh

chmod +x deploypipeline.sh 

cat > deploypipeline.sh <<EOF 
#!/bin/bash

kubectl apply -f k8s/services

export PROJECT=$(gcloud info --format='value(config.project)')
sed s/PROJECT/$PROJECT/g spinnaker/pipeline-deploy.json | curl -d@- -X \
    POST --header "Content-Type: application/json" --header \
    "Accept: /" http://localhost:8080/gate/pipelines
EOF

cd $HOME
mkdir bin
PATH=$PATH:$HOME/bin/
sudo git clone https://github.com/ahmetb/kubectx $HOME/kubectx
sudo ln -s $HOME/kubectx/kubectx $HOME/bin/kubectx
sudo ln -s $HOME/kubectx/kubens $HOME/bin/kubens

git clone https://github.com/jonmosco/kube-ps1.git
echo 'source $HOME/kube-ps1/kube-ps1.sh' >> ~/.bashrc
export VAR="PS1='[\W \$(kube_ps1)]\$ '"
echo $VAR >> ~/.bashrc
source $HOME/.bashrc

export GCP_ZONE=us-central1-f
gcloud config set compute/zone $GCP_ZONE
gcloud container clusters get-credentials spinnaker-tutorial --zone $GCP_ZONE --project $(gcloud info --format='value(config.project)')
kubectx spinnaker-turotial="gke_"$(gcloud info --format='value(config.project)')"_"$GCP_ZONE"_spinnaker-tutorial"



