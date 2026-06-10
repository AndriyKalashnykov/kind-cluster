FROM alpine:3.24@sha256:a2d49ea686c2adfe3c992e47dc3b5e7fa6e6b5055609400dc2acaeb241c829f4

LABEL maintainer="Andriy Kalashnykov" description="Kubernetes testing image"

# Default version — Makefile `image-build` overrides via --build-arg from its
# own KUBECTL_VERSION pin, but this default is used on standalone `docker build`
# invocations. Renovate tracks this ARG via a Dockerfile custom.regex manager;
# the kubectl packageRule groups it with the Makefile + .mise.toml + cloud-init.
# renovate: datasource=github-tags depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=v1.36.1

# Non-root identity. Overridable for hosts whose UID/GID mapping needs it.
ARG APP_UID=10001
ARG APP_GID=10001

# libcap supplies `setcap` so the raw-socket diagnostic tools below remain
# usable under USER ${APP_UID} (tcpdump and nmap have no preset caps and
# no setuid bit on alpine, so without setcap they fail "Operation not
# permitted" non-root; /bin/ping and /usr/sbin/mtr-packet ship setuid on
# alpine 3.23 and already work non-root).
ARG APK_PACKAGES="bash \
                  bind-tools \
                  curl \
                  iputils \
                  iperf3 \
                  libcap \
                  mtr \
                  netcat-openbsd \
                  nmap \
                  openssh-client \
                  tcpdump \
                  vim \
                  wget"


RUN apk --no-cache add --update $APK_PACKAGES && \
    addgroup -g ${APP_GID} -S app && \
    adduser -u ${APP_UID} -G app -S -h /home/app app && \
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" && \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c && \
    chmod +x kubectl && \
    mv ./kubectl /usr/local/bin/kubectl && \
    setcap cap_net_raw,cap_net_admin+eip /usr/bin/tcpdump && \
    setcap cap_net_raw+eip /usr/bin/nmap && \
    rm -rf /var/cache/apk/* kubectl.sha256

USER ${APP_UID}
WORKDIR /home/app

CMD ["/bin/bash"]
