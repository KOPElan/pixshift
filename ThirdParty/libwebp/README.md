# libwebp dependency

- Upstream: <https://chromium.googlesource.com/webm/libwebp>
- Version: `v1.6.0`
- Resolved commit: `4fa21912338357f89e4fd51cf2368325b59e9bd9`
- License: BSD-style license; see `LICENSE` in this directory.
- Product: static macOS XCFramework containing `libwebp`, `libwebpmux`, and `libsharpyuv`.
- Architectures: arm64 and x86_64.
- Minimum macOS deployment target used for compilation: macOS 15.0.

The framework was built from the upstream `makefile.unix` with Xcode 26.6 clang. Each architecture was compiled separately with `-O3 -DNDEBUG`, combined with `/usr/bin/libtool`, merged with `lipo`, and packaged with `xcodebuild -create-xcframework`.

Static archive SHA-256:

```text
6d245affc80257e82e2f429c11c6fe7a4ed7dadd18fec45aaf8f4108ae0eff10
```

The app does not ship the `cwebp` or other command-line tools.

