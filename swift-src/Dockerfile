FROM swiftlang/swift:nightly-5.9-focal
RUN --mount=type=cache,id=apt-dev,target=/var/cache/apt \
    apt update \
    && apt install -y --allow-downgrades --allow-change-held-packages --no-install-recommends wget && \
    wget https://apt.llvm.org/llvm.sh && \
    chmod +x llvm.sh && \
    ./llvm.sh 16
