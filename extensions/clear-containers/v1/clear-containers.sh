#!/bin/bash
# This script will install all dependencies required by Clear Containers for a cluster.
#
# OS: ubuntu 16.04
set -e
set -o pipefail

# Install the Clear Containers runtime
install_clear_containers_runtime() {
	# Add Clear Containers repository key
	echo "Adding Clear Containers repository key..."
	curl -sSL "https://download.opensuse.org/repositories/home:clearcontainers:clear-containers-3/xUbuntu_16.04/Release.key" | apt-key add -

	# Add Clear Container repository
	echo "Adding Clear Containers repository..."
	echo 'deb http://download.opensuse.org/repositories/home:/clearcontainers:/clear-containers-3/xUbuntu_16.04/ /' > /etc/apt/sources.list.d/cc-runtime.list

	# Install Clear Containers runtime
	echo "Installing Clear Containers runtime..."
	apt-get update
	apt-get install --no-install-recommends -y \
		cc-runtime

	# Install thin tools for devicemapper configuration
	echo "Installing thin tools to provision devicemapper..."
	apt-get install --no-install-recommends -y \
		lvm2 \
		thin-provisioning-tools

	# Load systemd changes
	echo "Loading changes to systemd service files..."
	systemctl daemon-reload

	# Enable and start Clear Containers proxy service
	echo "Enabling and starting Clear Containers proxy service..."
	systemctl enable cc-proxy
	systemctl start cc-proxy

	# If you want to setup docker to run with clear containers uncomment the following line below.
	# setup_clear_containers_runtime;
}

# Setup the Clear Containers runtime
setup_clear_containers_runtime() {
	# Configure Docker to use Clear Containers as the runtime
	echo "Configuring Docker to use Clear Containers as the runtime..."
	SYSTEMD_DOCKER_SERVICE_DIR="/etc/systemd/system/docker.service.d/"
	mkdir -p "$SYSTEMD_DOCKER_SERVICE_DIR"
	cat <<-EOF > "${SYSTEMD_DOCKER_SERVICE_DIR}/clr-containers.conf"
	[Service]
	ExecStart=
	ExecStart=/usr/bin/dockerd -D --add-runtime cc-runtime=/usr/bin/cc-runtime --default-runtime=cc-runtime
	EOF

	# Configure docker to use devicemapper as the storage driver
	echo "Configuring Docker to use devicemapper as the storage driver..."
	ETC_DOCKER_DIR="/etc/docker"
	mkdir -p "$ETC_DOCKER_DIR"
	cat <<-EOF > "${ETC_DOCKER_DIR}/daemon.json"
	{
		"storage-driver": "devicemapper",
		"storage-opts": [
		"dm.directlvm_device=/dev/sdd",
		"dm.thinp_percent=95",
		"dm.thinp_metapercent=1",
		"dm.thinp_autoextend_threshold=80",
		"dm.thinp_autoextend_percent=20",
		"dm.directlvm_device_force=true"
		]
	}
	EOF
}

# Install Go from source
install_go() {
	export GO_SRC=/usr/local/go
	export GOPATH="${HOME}/.go"

	# Remove any old version of Go
	if [[ -d "$GO_SRC" ]]; then
		rm -rf "$GO_SRC"
	fi

	# Remove any old GOPATH
	if [[ -d "$GOPATH" ]]; then
		rm -rf "$GOPATH"
	fi

	# Get the latest Go version
	GO_VERSION=$(curl -sSL "https://golang.org/VERSION?m=text")

	echo "Installing Go version $GO_VERSION..."

	# subshell
	(
	curl -sSL "https://storage.googleapis.com/golang/${GO_VERSION}.linux-amd64.tar.gz" | sudo tar -v -C /usr/local -xz
	)

	# Set GOPATH and update PATH
	echo "Setting GOPATH and updating PATH"
	export PATH="${GO_SRC}/bin:${PATH}:${GOPATH}/bin"
}

# Build and install runc
build_runc() {
	# Clone the runc source
	echo "Cloning the runc source..."
	mkdir -p "${GOPATH}/src/github.com/opencontainers"
	(
	cd "${GOPATH}/src/github.com/opencontainers"
	git clone "https://github.com/opencontainers/runc.git"
	cd runc
	git reset --hard v1.0.0-rc4
	make BUILDTAGS="seccomp apparmor"
	make install
	)

	echo "Successfully built and installed runc..."
}

install_cri_containerd() {
	CRI_CONTAINERD_VERSION="1.0.0-alpha.0"

	echo "Installing dependencies for cri-containerd..."
	apt-get install --no-install-recommends -y \
		socat

	# subshell
	(
	curl -sSL "https://github.com/kubernetes-incubator/cri-containerd/releases/download/v${CRI_CONTAINERD_VERSION}/cri-containerd-${CRI_CONTAINERD_VERSION}.tar.gz" | sudo tar -v -C / -xz
	)

	setup_containerd;
}

# Setup containerd
setup_containerd() {
	# Configure containerd
	echo "Configuring containerd..."

	# Configure /etc/containerd/config.toml
	CONTAINERD_CONFIG="/etc/containerd/config.toml"
	cat <<-EOF > "${CONTAINERD_CONFIG}"
	root = "/var/lib/containerd"
	state = "/run/containerd"
	subreaper = true
	oom_score = -999

	[debug]
	address = "/run/containerd/containerd.sock"
	uid = 0
	gid = 0
	level = "debug"

	[plugins.linux]
	runtime = "cc-runtime"
	shim_debug = true
	EOF

	# Configure /etc/lvm/profile/containerd-thinpool.profile
	CONTAINERD_THINPOOL_PROFILE="/etc/lvm/profile/containerd-thinpool.profile"
	#cat <<-EOF > "${CONTAINERD_THINPOOL_PROFILE}"
	#activation {
	#thin_pool_autoextend_threshold=80
	#thin_pool_autoextend_percent=20
	#}
	#EOF

	# Configure devicemapper for containerd
	SYSTEMD_DEVICEMAPPER_CONTAINERD_SERVICE_FILE="/etc/systemd/system/devicemapper-containerd.service"
	cat <<-EOF > "${SYSTEMD_DEVICEMAPPER_CONTAINERD_SERVICE_FILE}"
	[Unit]
	Description=Devicemapper Setup for Containerd
	Documentation=https://docs.docker.com/engine/userguide/storagedriver/device-mapper-driver/#configure-direct-lvm-mode-manually
	Before=containerd.service

	[Service]
	Type=oneshot
	RemainAfterExit=true
	ExecStart=pgcreate /dev/sdc
	ExecStart=vgcreate containerd /dev/sdc
	ExecStart=lvcreate --wipesignatures y -n thinpool containerd -l 95%VG
	ExecStart=lvcreate --wipesignatures y -n thinpoolmeta docker -l 1%VG
	ExecStart=lvconvert -y \\
	--zero n \\
	-c 512K \\
	--thinpool containerd/thinpool \\
	--poolmetadata containerd/thinpoolmeta
	ExecStart=lvchange --metadataprofile containerd-thinpool containerd/thinpool

	[Install]
	WantedBy=multi-user.target
	EOF

	# Load systemd changes
	echo "Loading changes to systemd service files..."
	systemctl daemon-reload

	# Enable and start containerd and cri-containerd service
	echo "Enabling and starting containerd and cri-containerd service..."
	systemctl enable containerd cri-containerd
	systemctl start containerd cri-containerd
}

# Build and install CRI-O
build_cri_o() {
	install_go;

	# Add CRI-O repositories
	echo "Adding repositories required for cri-o..."
	add-apt-repository -y ppa:projectatomic/ppa
	add-apt-repository -y ppa:alexlarsson/flatpak
	apt-get update

	# Install CRI-O dependencies
	echo "Installing dependencies for CRI-O..."
	apt-get install --no-install-recommends -y \
		btrfs-tools \
		gcc \
		git \
		libapparmor-dev \
		libassuan-dev \
		libc6-dev \
		libdevmapper-dev \
		libglib2.0-dev \
		libgpg-error-dev \
		libgpgme11-dev \
		libostree-dev \
		libseccomp-dev \
		libselinux1-dev \
		make \
		pkg-config \
		skopeo-containers

	# Install md2man
	go get github.com/cpuguy83/go-md2man

	# Fix for templates dependency
	(
	go get -u github.com/docker/docker/daemon/logger/templates
	cd "${GOPATH}/src/github.com/docker/docker"
	mkdir -p utils
	cp -r daemon/logger/templates utils/
	)

	build_runc;

	# Clone the CRI-O source
	echo "Cloning the CRI-O source..."
	mkdir -p "${GOPATH}/src/github.com/kubernetes-incubator"
	(
	cd "${GOPATH}/src/github.com/kubernetes-incubator"
	git clone "https://github.com/kubernetes-incubator/cri-o.git"
	cd cri-o
	git reset --hard v1.0.0
	make BUILDTAGS="seccomp apparmor"
	make install
	make install.config
	make install.systemd
	)

	echo "Successfully built and installed CRI-O..."

	# Cleanup the temporary directory
	rm -vrf "$tmpd"

	# Cleanup the Go install
	rm -vrf "$GO_SRC" "$GOPATH"

	setup_cri_o;
}

# Setup CRI-O
setup_cri_o() {
	# Configure CRI-O
	echo "Configuring CRI-O..."

	# Configure crio systemd service file
	SYSTEMD_CRI_O_SERVICE_FILE="/usr/local/lib/systemd/system/crio.service"
	sed -i 's#ExecStart=/usr/local/bin/crio#ExecStart=/usr/local/bin/crio -log-level debug#' "$SYSTEMD_CRI_O_SERVICE_FILE"

	# Configure /etc/crio/crio.conf
	CRI_O_CONFIG="/etc/crio/crio.conf"
	sed -i 's#storage_driver = ""#storage_driver = "devicemapper"#' "$CRI_O_CONFIG"
	sed -i 's#storage_option = \[#storage_option = \["dm.directlvm_device=/dev/sdc", "dm.thinp_percent=95", "dm.thinp_metapercent=1", "dm.thinp_autoextend_threshold=80", "dm.thinp_autoextend_percent=20", "dm.directlvm_device_force=true"#' "$CRI_O_CONFIG"
	sed -i 's#runtime = "/usr/bin/runc"#runtime = "/usr/local/sbin/runc"#' "$CRI_O_CONFIG"
	sed -i 's#runtime_untrusted_workload = ""#runtime_untrusted_workload = "/usr/bin/cc-runtime"#' "$CRI_O_CONFIG"
	sed -i 's#default_workload_trust = "trusted"#default_workload_trust = "untrusted"#' "$CRI_O_CONFIG"

	# Load systemd changes
	echo "Loading changes to systemd service files..."
	systemctl daemon-reload

	# Enable and start cri-o service
	echo "Enabling and starting cri-o service..."
	systemctl enable crio crio-shutdown
	systemctl start crio
}

# Install container networking plugins
install_cni() {
	CNI_VERSION="v0.6.0"
	CNI_PLUGIN_DIR="/opt/cni/bin"

	# subshell
	(
	echo "Installing CNI plugins..."
	mkdir -p "${CNI_PLUGIN_DIR}"
	curl -sSL "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-amd64-${CNI_VERSION}.tgz" | sudo tar -v -C "${CNI_PLUGIN_DIR}" -xz
	)

	CNI_CONFIG_DIR="/etc/cni/net.d"
	mkdir -p "${CNI_CONFIG_DIR}"
}

# Configure the kubelet systemd service
configure_kubelet() {
	# Configure the kubelet systemd service to use cri-o
	# This is the same file as in parts/kuberneteskublet.service with
	# very few but _important_ modifications:
	# (1) Adding --container-runtime=remote
	# (2) Adding --container-runtime-endpoint=/var/run/crio.sock
	# (3) The most horrible hack ->
	# 		ExecPreStart=-/bin/systemctl restart crio
	# 	This was only needed because this is as run as a "pre-provisioning script"
	# 	so I couldn't restart crio after acs-engine ran it's script to install
	# 	the CNI plugins, so I did it here. This should be removed if you are
	# 	ever to use this for realsies because it is a bit like inception calling
	# 	systemd from systemd and it makes me sad.
	echo "Configuring the kubelet systemd service to use cri-o..."
	SYSTEMD_KUBELET_SERVICE_DIR="/etc/systemd/system/kubelet.service.d/"
	mkdir -p "$SYSTEMD_KUBELET_SERVICE_DIR"
	cat <<-EOF > "${SYSTEMD_KUBELET_SERVICE_DIR}/10-crio.conf"
	[Unit]
	Description=Kubelet
	Requires=docker.service
	After=docker.service

	[Service]
	Restart=always
	EnvironmentFile=/etc/default/kubelet
	SuccessExitStatus=143
	ExecStartPre=/bin/bash /opt/azure/containers/kubelet.sh
	ExecStartPre=/bin/mkdir -p /var/lib/kubelet
	ExecStartPre=/bin/bash -c "if [ \$(mount | grep \\"/var/lib/kubelet\\" | wc -l) -le 0  ] ; then /bin/mount --bind /var/lib/kubelet /var/lib/kubelet ; fi"
	ExecStartPre=/bin/mount --make-shared /var/lib/kubelet
	# This is a partial workaround to this upstream Kubernetes issue:
	#  https://github.com/kubernetes/kubernetes/issues/41916#issuecomment-312428731
	ExecStartPre=/sbin/sysctl -w net.ipv4.tcp_retries2=8
	ExecStartPre=-/sbin/ebtables -t nat --list
	ExecStartPre=-/sbin/iptables -t nat --list
	ExecStartPre=-/bin/systemctl restart crio
	ExecStart=
	ExecStart=/usr/bin/docker run \\
	--net=host \\
	--pid=host \\
	--privileged \\
	--rm \\
	--volume=/dev:/dev \\
	--volume=/sys:/sys:ro \\
	--volume=/var/run:/var/run:rw \\
	--volume=/var/lib/docker/:/var/lib/docker:rw \\
	--volume=/var/lib/containers/:/var/lib/containers:rw \\
	--volume=/var/lib/kubelet/:/var/lib/kubelet:shared \\
	--volume=/var/log:/var/log:rw \\
	--volume=/etc/kubernetes/:/etc/kubernetes:ro \\
	--volume=/srv/kubernetes/:/srv/kubernetes:ro \$DOCKER_OPTS \\
	--volume=/var/lib/waagent/ManagedIdentity-Settings:/var/lib/waagent/ManagedIdentity-Settings:ro \\
	\${KUBELET_IMAGE} \\
	/hyperkube kubelet \\
		--kubeconfig=/var/lib/kubelet/kubeconfig \\
		--require-kubeconfig \
		--pod-infra-container-image="\${KUBELET_POD_INFRA_CONTAINER_IMAGE}" \\
		--address=0.0.0.0 \\
		--allow-privileged=true \\
		\${KUBELET_FIX_43704_1} \\
		\${KUBELET_FIX_43704_2}\${KUBELET_FIX_43704_3} \\
		--enable-server \\
		--pod-manifest-path=/etc/kubernetes/manifests \\
		--cluster-dns=\${KUBELET_CLUSTER_DNS} \\
		--cluster-domain=cluster.local \\
		--node-labels="\${KUBELET_NODE_LABELS}" \\
		--cloud-provider=azure \\
		--cloud-config=/etc/kubernetes/azure.json \\
		--azure-container-registry-config=/etc/kubernetes/azure.json \\
		--container-runtime=remote \\
		--container-runtime-endpoint=/var/run/crio.sock \\
		--runtime-request-timeout=30m \\
		--network-plugin=\${KUBELET_NETWORK_PLUGIN} \\
		--max-pods=\${KUBELET_MAX_PODS} \\
		--node-status-update-frequency=\${KUBELET_NODE_STATUS_UPDATE_FREQUENCY} \\
		--image-gc-high-threshold=\${KUBELET_IMAGE_GC_HIGH_THRESHOLD} \\
		--image-gc-low-threshold=\${KUBELET_IMAGE_GC_LOW_THRESHOLD} \\
		--v=2 \${KUBELET_FEATURE_GATES} \\
		\${KUBELET_NON_MASQUERADE_CIDR} \\
		\${KUBELET_REGISTER_NODE} \${KUBELET_REGISTER_WITH_TAINTS}
	EOF
}

main() {
	# Install Clear Containers runtime
	install_clear_containers_runtime;

	# Install CRI containerd
	# We won't use this because containerd does not currently support devicemapper
	# install_cri_containerd;

	# Install CRI-O
	build_cri_o;

	# Install cni plugins
	install_cni;

	# Configure the kublet to communicate with CRI-O
	configure_kubelet;
}

main
