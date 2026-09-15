FROM nikolaik/python-nodejs:python3.11-nodejs20
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends graphviz \
    && rm -rf /var/lib/apt/lists/*
USER pn
