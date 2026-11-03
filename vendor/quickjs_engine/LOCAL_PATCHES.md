# Local patches to quickjs_engine 0.1.6

Source: https://pub.dev/packages/quickjs_engine/versions/0.1.6 . Upstream licenses retained.

- Native `jsNewRuntime` now accepts the timeout argument already passed by upstream Dart FFI. A monotonic native interrupt budget applies to each `jsEval`; runtime budgets are removed on disposal. The unpatched package silently ignored timeout.
- macOS CocoaPods compiles vendored QuickJS-NG sources (as iOS does), rather than linking the upstream prebuilt dylib, so the interrupt patch applies to both Apple platforms and Android.
- This fork is pinned locally; updates must re-run script infinite-loop and memory-limit tests.
