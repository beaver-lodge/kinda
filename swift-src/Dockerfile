FROM swiftlang/swift:nightly-5.9-focal
ARG LLVM_VERSION=17
RUN --mount=type=cache,id=apt-dev,target=/var/cache/apt \
    apt update \
    && apt install -y --allow-downgrades --allow-change-held-packages --no-install-recommends \
    cmake \
    wget lsb-release software-properties-common gnupg && \
    wget https://apt.llvm.org/llvm.sh && \
    chmod +x llvm.sh && \
    ./llvm.sh ${LLVM_VERSION} && \
    apt-get install -y libmlir-${LLVM_VERSION}-dev mlir-${LLVM_VERSION}-tools
