FROM debian:trixie

ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH}

ENV DIR=/tmp/config ID=100 IP=127.0.0.1
ENV ANSIBLE_ROLES_PATH=${DIR}/base LC_ALL=C.UTF-8

STOPSIGNAL SIGRTMIN+3

RUN apt update -y && apt install -y \
      systemd python3 python3-pip python3-proxmoxer openssh-client ansible && \
    apt clean all && apt autoremove -y

RUN rm -rf /lib/systemd/system/multi-user.target.wants/* && \
    rm -rf /etc/systemd/system/*.wants/* && \
    rm -rf /lib/systemd/system/local-fs.target.wants/* && \
    rm -rf /lib/systemd/system/sockets.target.wants/*udev* && \
    rm -rf /lib/systemd/system/sockets.target.wants/*initctl* && \
    rm -rf /lib/systemd/system/sysinit.target.wants/systemd-tmpfiles-setup* && \
    rm -rf /lib/systemd/system/systemd-update-utmp*

RUN ansible-galaxy collection install community.general --force

RUN mkdir -p /app/.ssh /share/.certs /share/.ssh
RUN ssh-keygen -t ed25519 -f "/share/.ssh/${ID}" -N ''

COPY ../base/roles ${ANSIBLE_ROLES_PATH}
RUN ansible localhost -m include_role -a name=base \
    -e "ip=${IP}" -e "id=${ID}" -e "SHARE=/share" -e "configure_ssh=0" -e "arch=${TARGETARCH}" \
    -e "private_key='$(cat /share/.ssh/${ID})\n'" -e "public_key='$(cat /share/.ssh/${ID}.pub)\n'"

RUN chown -R app:config /app

WORKDIR /

VOLUME ["/tmp", "/run"]

ENTRYPOINT ["/usr/lib/systemd/systemd"]
CMD ["/bin/bash"]
