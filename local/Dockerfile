FROM debian:trixie

ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH}

ENV IP=127.0.0.1 ID=254 LC_ALL=C.UTF-8
ENV  ANSIBLE_ROLES_PATH=/tmp/config/base

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

RUN mkdir -p /app/.ssh /share/.ssh && ssh-keygen -t ed25519 -f "/share/.ssh/${ID}" -N ''

COPY ../base/roles /tmp/config/base
RUN ansible localhost -m include_role -a name=base \
    -e "ip=${IP}" -e "id=${ID}" -e "KEYS_DIR=/share/.ssh" -e "configure_ssh=0" -e "arch=${TARGETARCH}" \
    -e "private_key='$(cat /share/.ssh/${ID})\n'" -e "public_key='$(cat /share/.ssh/${ID}.pub)\n'"

RUN chown -R app:config /app

WORKDIR /

VOLUME ["/tmp", "/run"]

ENTRYPOINT ["/usr/lib/systemd/systemd"]
CMD ["/bin/bash"]
