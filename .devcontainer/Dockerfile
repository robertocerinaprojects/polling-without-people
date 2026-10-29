FROM ghcr.io/rocker-org/devcontainer/r-ver:4.5@sha256:40714b9f6327f7684c1b9af10e355da1413d5dda1cd97dafb43e61e540c8bdd1

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       cmake pkg-config libabsl-dev libuv1-dev gdal-bin \ \
       libcurl4-openssl-dev libssl-dev libxml2-dev \
       libgdal-dev libgeos-dev libproj-dev \
       libsqlite3-dev libudunits2-dev \
       libfontconfig1-dev libfreetype6-dev \
       libharfbuzz-dev libfribidi-dev \
       libjpeg-dev libpng-dev libtiff-dev libwebp-dev \
    && rm -rf /var/lib/apt/lists/*

USER rstudio
