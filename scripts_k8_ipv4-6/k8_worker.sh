#!/bin/bash

hostnamectl set-hostname k8-worker01

echo "2001:db8:85a3::1 k8-master" >> /etc/hosts
echo "2001:db8:85a3::2 k8-worker01" >> /etc/hosts

swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux

swapon
getenforce

firewall-cmd --permanent --add-port={179,10250,30000-32767}/tcp
firewall-cmd --permanent --add-port=4789/udp
firewall-cmd --reload
firewall-cmd --list-all

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

sudo sysctl -w net.ipv6.conf.all.forwarding=1 

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

sysctl -w net.ipv6.conf.all.forwarding=1
echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
sudo sysctl -p

yum install -y yum-utils

yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install containerd.io -y

cp -r /etc/containerd /etc/containerd_resp
mv /etc/containerd/config.toml /etc/containerd/config.toml.bkp
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

systemctl enable --now containerd

cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF

yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

systemctl enable --now kubelet
source <(kubectl completion bash)
kubectl completion bash > /etc/bash_completion.d/kubectl

reboot

-----------------------------------------------------------------------------------------

dnf install nfs-utils
systemctl enable --now nfs-server rpcbind
firewall-cmd --add-service={nfs,nfs3,mountd,rpc-bind} --permanent
