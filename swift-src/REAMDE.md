```bash
docker run --rm -it swiftlang/swift:nightly-5.9-focal swiftc -v
```

```bash
docker run --rm -it -v $PWD/swift-src:/swift-src swiftlang/swift:nightly-5.9-focal bash /swift-src/run.sh
```
