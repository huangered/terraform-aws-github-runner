#!/bin/bash -x
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

${pre_install}

# Install AWS CLI
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y awscli jq curl wget git uidmap

USER_NAME=runners
useradd -m -s /bin/bash $USER_NAME
USER_ID=$(id -ru $USER_NAME)

# install and configure cloudwatch logging agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb
amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:${ssm_key_cloudwatch_agent_config}

# configure systemd for running service in users accounts
cat >/etc/systemd/user@UID.service <<-EOF

[Unit]
Description=User Manager for UID %i
After=user-runtime-dir@%i.service
Wants=user-runtime-dir@%i.service

[Service]
LimitNOFILE=infinity
LimitNPROC=infinity
User=%i
PAMName=systemd-user
Type=notify

[Install]
WantedBy=default.target

EOF

echo export XDG_RUNTIME_DIR=/run/user/$USER_ID >>/home/$USER_NAME/.profile

systemctl daemon-reload
systemctl enable user@UID.service
systemctl start user@UID.service

#curl -fsSL https://get.docker.com/rootless >>/opt/rootless.sh && chmod 755 /opt/rootless.sh
#su -l $USER_NAME -c /opt/rootless.sh
#echo export DOCKER_HOST=unix:///run/user/$USER_ID/docker.sock >>/home/$USER_NAME/.profile
#echo export PATH=/home/$USER_NAME/bin:$PATH >>/home/$USER_NAME/.profile

# Run docker service by default
#loginctl enable-linger $USER_NAME
#su -l $USER_NAME -c "systemctl --user enable docker"
# install docker

apt-get remove docker docker-engine docker.io containerd runc
apt-get update
apt-get install apt-transport-https ca-certificates curl gnupg lsb-release -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg  --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
    "deb [arch=arm64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install docker-ce docker-ce-cli containerd.io -y

${install_config_runner}

# add user to docker group
usermod -aG docker runners

${post_install}

./svc.sh start
