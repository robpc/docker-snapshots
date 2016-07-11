FROM debian:jessie

RUN apt-get update -y && \
    apt-get install -y \
        vim python python-pip groff

RUN pip install awscli

RUN mkdir /s3
RUN mkdir /backups

WORKDIR /backups

COPY entrypoint.sh /s3

ENTRYPOINT bash /s3/entrypoint.sh