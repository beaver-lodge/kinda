FROM swiftlang/swift:nightly-5.9-focal
RUN --mount=type=cache,id=apt-dev,target=/var/cache/apt \
    apt update \
    && apt install -y --allow-downgrades --allow-change-held-packages --no-install-recommends wget lsb-release software-properties-common gnupg && \
    wget https://apt.llvm.org/llvm.sh && \
    chmod +x llvm.sh && \
    ./llvm.sh 16 && \
    apt-get install libmlir-16-dev mlir-16-tools
