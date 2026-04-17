FROM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11

LABEL maintainer="Andriy Kalashnykov" description="Kubernetes testing image"

# Default version — Makefile `image-build` overrides via --build-arg from its
# own KUBECTL_VERSION pin, but this default is used on standalone `docker build`
# invocations. Renovate tracks this ARG via a Dockerfile custom.regex manager;
# the kubectl packageRule groups it with the Makefile + .mise.toml + cloud-init.
# renovate: datasource=github-tags depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=v1.35.4
ARG APK_PACKAGES="bash \
                  bind-tools \
                  curl \
                  iputils \
                  iperf3 \
                  mtr \
                  netcat-openbsd \
                  nmap \
                  openssh-client \
                  tcpdump \
                  vim \
                  wget"


RUN apk --no-cache add --update $APK_PACKAGES && \
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" && \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c && \
    chmod +x kubectl && \
    mv ./kubectl /usr/local/bin/kubectl && \
    rm -rf /var/cache/apk/* kubectl.sha256

CMD ["/bin/bash"]