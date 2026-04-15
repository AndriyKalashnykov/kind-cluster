FROM alpine:3.22

LABEL maintainer="Andriy Kalashnykov" description="Kubernetes testing image"

ARG KUBECTL_VERSION=v1.35.1
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