FROM ubuntu:20.04
# gcc 9 on purpose: linux 5.4.14 predates newer compilers
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential bc bison flex libssl-dev libelf-dev cpio kmod xz-utils python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
