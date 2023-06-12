FROM swiftlang/swift:nightly-5.9-focal
ARG LLVM_VERSION=17
RUN --mount=type=cache,id=apt-dev,target=/var/cache/apt \
    apt update \
    && apt install -y --allow-downgrades --allow-change-held-packages --no-install-recommends \
    python3-pip ccache clang-12 ninja-build \
    wget lsb-release software-properties-common gnupg && \
    wget https://apt.llvm.org/llvm.sh && \
    chmod +x llvm.sh && \
    ./llvm.sh ${LLVM_VERSION} && \
    apt-get install -y --allow-downgrades --allow-change-held-packages --no-install-recommends \
    libmlir-${LLVM_VERSION}-dev mlir-${LLVM_VERSION}-tools && \
    python3 -m pip install cmake=="3.26"
