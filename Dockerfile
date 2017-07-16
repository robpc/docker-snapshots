FROM debian:jessie

RUN apt-get update -y && \
    apt-get install -y \
        vim python python-pip groff zip

RUN pip install awscli

RUN mkdir /home/snapshots
RUN mkdir /home/snapshots/backups

WORKDIR /home/snapshots/backups

COPY entrypoint.sh /home/snapshots

ENTRYPOINT bash /home/snapshots/entrypoint.sh