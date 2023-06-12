```bash
docker run --rm -it swiftlang/swift:nightly-5.9-focal swiftc -v
```

```bash
docker run --rm -it -v $PWD/swift-src:/swift-src swiftlang/swift:nightly-5.9-focal bash /swift-src/run.sh
```

```bash
docker run --rm -it -v $PWD/swift-src:/swift-src -v $HOME/oss/swift-cmake-examples:/swift-cmake-examples -w /swift-cmake-examples jackalcooper/kinda-dev-llvm-17-arm64 bash /swift-src/cmake.sh
```
