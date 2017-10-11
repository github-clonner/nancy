#!/bin/bash
# Copyright 2017 AT&T Intellectual Property, Inc
#  
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#  
# http://www.apache.org/licenses/LICENSE-2.0
#  
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#. What this is: Complete scripted deployment of an experimental Rancher-based
#. cloud-native application platform. When complete, Rancher and the following
#. will be installed:
#. - nginx and dokuwiki as demo applications
#. - prometheus + grafana for cluster monitoring/stats
#.   Prometheus dashboard: http://<master_public_ip>:9090
#.   Grafana dashboard: http://<master_public_ip>:3000
#. 
#. Prerequisites:
#. - Ubuntu server for Rancher cluster nodes (admin/master and agent nodes)
#. - MAAS server as cluster admin for Rancher master/agent nodes
#. - Password-less ssh key provided for node setup
#. Usage: on the MAAS server
#. $ git clone https://github.com/blsaws/nancy.git 
#. $ bash nancy/rancher/demo_deploy.sh <key> "<hosts>" <master_ip>
#.     "<agent ips>" [<extras>]
#. <key>: name of private key for cluster node ssh (in current folder)
#. <hosts>: space separated list of hostnames managed by MAAS
#. <master_ip>: IP of cluster admin node
#. <agent_ips>: space separated list of agent node IPs
#. <extras>: optional name of script for extra setup functions as needed

function wait_node_status() {
  status=$(maas opnfv machines read hostname=$1 | jq -r ".[0].status_name")
  while [[ "x$status" != "x$2" ]]; do
    echo "$1 status is $status ... waiting for it to be $2"
    sleep 30
    status=$(maas opnfv machines read hostname=$1 | jq -r ".[0].status_name")
  done
  echo "$1 status is $status"
}

function release_nodes() {
  nodes=$1
  for node in $nodes; do
    echo "Releasing node $node"
    id=$(maas opnfv machines read hostname=$node | jq -r '.[0].system_id')
    maas opnfv machines release machines=$id
  done
}

function deploy_nodes() {
  nodes=$1
  for node in $nodes; do
    echo "Deploying node $node"
    id=$(maas opnfv machines read hostname=$node | jq -r '.[0].system_id')
    maas opnfv machines allocate system_id=$id
    maas opnfv machine deploy $id
  done
}

function wait_nodes_status() {
  nodes=$1
  for node in $nodes; do
    wait_node_status $node $2
  done
}

key=$1
nodes="$2"
admin_ip=$3
agent_ips="$4"
extras=$5

release_nodes "$nodes"
wait_nodes_status "$nodes" Ready
deploy_nodes "$nodes"
wait_nodes_status "$nodes" Deployed
ssh-keygen -f ~/.ssh/known_hosts -R $admin_ip
eval `ssh-agent`
ssh-add $key
if [[ "x$extras" != "x" ]]; then source $extras; fi
scp -o StrictHostKeyChecking=no $key ubuntu@$admin_ip:/home/ubuntu/$key
echo "Setting up Rancher..."
ssh -x ubuntu@$admin_ip <<EOF
exec ssh-agent bash
ssh-add $key
echo "Cloning nancy..."
git clone https://github.com/blsaws/nancy.git
bash nancy/rancher/rancher-cluster.sh all "$agent_ips"
EOF
# TODO: Figure this out... Have to break the setup into two steps as something
# causes the ssh session to end before the prometheus setup, if both scripts 
# (k8s-cluster and prometheus-tools) are in the same ssh session
echo "Setting up Prometheus..."
ssh -x ubuntu@$admin_ip <<EOF
exec ssh-agent bash
ssh-add $key
bash nancy/prometheus/prometheus-tools.sh all "$agent_ips"
EOF
echo "All done!"