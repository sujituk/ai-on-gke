# Copyright (c) 2024, NVIDIA CORPORATION. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ARG BASE_CONTAINER_IMAGE=nvcr.io/nvidia/tritonserver:24.10-trtllm-python-py3
FROM ${BASE_CONTAINER_IMAGE}

ENV NCCL_VERSION=2.21.5-1
ENV NCCL_TESTS_VERSION=2.13.9

# Set a set of useful labels.
LABEL "base"="${BASE_CONTAINER_IMAGE}"
LABEL "role"="server"

# Stop APT (Debian package manager) from complaining about interactivity.
ENV DEBIAN_FRONTEND=noninteractive
# Set additional environment values that make usage more pleasant.
ENV TERM=xterm-256color

RUN apt update \
	&& apt install --yes \
	apt-transport-https \
	ca-certificates \
	curl \
	gnupg \
	cgroup-tools \
	&& rm -rf /var/lib/apt/lists/*

# Install kubectl because server.py script depends on it.
# Step 1: acquire the Kubernetes APT GPG key.
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
	| gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
	&& chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Step 2: Acquire the API sources list for Kubernetes.
RUN echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' \
	| tee /etc/apt/sources.list.d/kubernetes.list \
	&& chmod 644 /etc/apt/sources.list.d/kubernetes.list

# Step 3: Install kubectl.
RUN apt update \
	&& apt install --yes \
	kubectl \
	&& apt autoremove --yes \
	&& apt purge --yes \
	&& rm -rf /var/lib/apt/lists/*

###############################################
#### For NCCL Test
RUN apt-get update -y && \
	apt-get install -y --no-install-recommends \
	openssh-client \
	openssh-server \
	libopenmpi-dev \
	openmpi-bin \
	libnuma-dev \
	hwloc \
	libgflags-dev \
	libgoogle-glog-dev \
	libhdf5-serial-dev && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd
RUN sed -i 's/[ #]\(.*StrictHostKeyChecking \).*/ \1no/g' /etc/ssh/ssh_config && \
	echo "    UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config && \
	sed -i 's/#\(StrictModes \).*/\1no/g' /etc/ssh/sshd_config

# NCCL
RUN apt-get remove -y libnccl2 libnccl-dev \
	&& cd /tmp \
	&& git clone https://github.com/NVIDIA/nccl.git -b v${NCCL_VERSION} \
	&& cd nccl \
	&& make -j src.build BUILDDIR=/usr/local \
	NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_89,code=sm_89 -gencode=arch=compute_90,code=sm_90" \
	&& rm -rf /tmp/nccl

RUN echo "/usr/local/lib" >> /etc/ld.so.conf.d/local.conf && \
	ldconfig

# NCCL-tests
RUN git clone https://github.com/NVIDIA/nccl-tests.git /opt/nccl-tests \
	&& cd /opt/nccl-tests \
	&& git checkout v${NCCL_TESTS_VERSION} \
	&& make MPI=1 \
	CUDA_HOME=/usr/local/cuda \
	# nvcc to target p5 and p4 instances
	NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_89,code=sm_89 -gencode=arch=compute_90,code=sm_90"

###############################################

# Set the active working directory.
WORKDIR /workspace

# Copy kubessh script w/ executable permissions for everyone.
# This enables the script to be executed no matter the user the container is run as.
# This works around the issue of the file being non-executable when the container is build on a Windows host.
COPY --chmod=555 kubessh .
# COPY server.py .

RUN apt list --installed \
	&& pip list --version

ENTRYPOINT [ "/bin/bash" ]