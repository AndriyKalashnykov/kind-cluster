FROM alpine:3.16.2

LABEL MAINTAINER="Andriy Kalashnykov" description="Kubernetes testing image"

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
                  
                  

#ENV KUBECTL_VERSION="v1.25.2"
# Download Versioned Kubectl
# curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"  && \
# curl -LO "https://dl.k8s.io/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" && \

RUN apk --no-cache add --update $APK_PACKAGES && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256" && \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c && \
    chmod +x kubectl && \
    mv ./kubectl /usr/local/bin/kubectl && \
    rm -rf /var/cache/apk/*

CMD ["/bin/bash"]