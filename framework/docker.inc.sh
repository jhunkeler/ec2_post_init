## @file
## @brief Docker functions

(( $EC2PINIT_DOCKER_INCLUDED )) && return
EC2PINIT_DOCKER_INCLUDED=1
source $ec2pinit_root/ec2pinit.inc.sh

## @fn docker_setup()
## @brief Install docker on the server
## @param user account to add to docker group
## @param bind_port binds the docker daemon to a TCP port. When this option is
## enabled the ``user`` account argument is ignored in favor of setting 
## ``DOCKER_HOST=tcp://127.0.0.1:${bind_port}`` at login
docker_setup() {
    local user="${1:-$USER}"
    local bind_port=

    if (( HAVE_DEBIAN )); then
        # see: https://docs.docker.com/engine/install/debian/ 
        sys_pkg_install apt-transport-https ca-certificates curl gnupg lsb-release
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sys_pkg_clean
        sys_pkg_install docker-ce docker-ce-cli containerd.io docker-compose
    elif (( HAVE_REDHAT )); then
        # see: https://docs.docker.com/engine/install/centos/
        yum-config-manager --add-repo \
            https://download.docker.com/linux/centos/docker-ce.repo
        sys_pkg_install docker-ce docker-ce-cli containerd.io docker-compose-plugin
    else
        echo "WARNING: Operating system was not recognized. Blindly attempting to install docker." >&2
        sys_pkg_install docker docker-compose
    fi
    
    # Enable the system service
    systemctl enable docker

    if [ -n "$bind_port" ] && [[ $bind_port =~ [0-9]+ ]]; then
        # Allow any local account to use the docker API port
        mkdir -p /etc/systemd/system/docker.service.d
cat << CONFIG > /etc/systemd/system/docker.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H 127.0.0.1:${bind_port} --containerd=/run/containerd/containerd.sock
CONFIG
        echo "DOCKER_HOST=tcp://127.0.0.1:${bind_port}" > /etc/profile.d/docker_host.sh
        source /etc/profile.d/docker_host.sh
    else
        # Only the named can use docker
        docker_user_add "$user"
    fi
    systemctl daemon-reload
    systemctl start docker
}

## @fn docker_user_add()
## @brief Add a user account to the ``docker`` group
## @param user an account to modify (must exist)
docker_user_add() {
    local user="${1:-$USER}"
    if groups "$user" | grep docker; then
        usermod -a -G docker "$user"
    fi
}

## @fn docker_pull_many()
## @brief Wrapper for ``docker pull``
## @details Pull multiple docker images with a single command
## @param image... image to pull
##
## ~~~{.sh}
## images=(centos:7 centos:8)
## docker_pull_many "${images[@]}"
## # or
## docker_pull_many "centos:7" "centos:8"
## ~~~
docker_pull_many() {
    local image=($@)
    local image_count="${#image[@]}"
    local error_count=0
    
    if [ -z "$image_count" ]; then
        false
        return
    fi

    echo "Pulling $image_count image(s)..."
    for ((i = 0; i < image_count; i++)); do
        echo "Image #$((i+1)): ${image[i]}"
        if ! docker pull "${image[$i]}"; then
            (( error_count++ ))
        fi
    done
    (( error_count )) && false
    return
}