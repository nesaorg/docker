FROM nvcr.io/nvidia/cuda:11.0.3-cudnn8-devel-ubuntu20.04
LABEL maintainer="nesaorg"
LABEL repository="node"

WORKDIR /home
# Set en_US.UTF-8 locale by default
RUN echo "LC_ALL=en_US.UTF-8" >> /etc/environment

# Install packages
RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  wget \
  git \
  && apt-get clean autoclean && rm -rf /var/lib/apt/lists/{apt,dpkg,cache,log} /tmp/* /var/tmp/*

RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O install_miniconda.sh && \
  bash install_miniconda.sh -b -p /opt/conda && rm install_miniconda.sh
ENV PATH="/opt/conda/bin:${PATH}"

RUN conda install python~=3.10.12 pip && \
    pip install --no-cache-dir "torch>=1.12" && \
    conda clean --all && rm -rf ~/.cache/pip


# chain node


# ipfs node?


# agent


# Orchestrator/Infernece specific 
# for inference side we will likely be doing something like this.
# VOLUME /cache
# ENV NESA_CACHE=/cache

# COPY . inference/
# RUN pip install --no-cache-dir -e inference

# WORKDIR /home/inference/
# CMD bash

# I will also need to run the http interface for the agent to orchestrator communication 

