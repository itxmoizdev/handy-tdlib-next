# handy_tdlib_next

`handy_tdlib_next` is a community-maintained Flutter/Dart package providing bindings for Telegram's TDLib JSON interface (`libtdjson`). It is intended for Flutter applications that need to communicate with TDLib to build a Telegram client or integrate TDLib features.

## Maintainer

**Abdul Moiz Dev** ([@itxmoizdev](https://github.com/itxmoizdev))

- GitHub: [@itxmoizdev](https://github.com/itxmoizdev)
- LinkedIn: [itxmoizdev](https://www.linkedin.com/in/itxmoizdev)
- Package repository: https://github.com/itxmoizdev/handy-tdlib-next

This package exposes:

- Generated Dart models for TDLib functions and objects (`TdFunction`, `TdObject`)
- FFI access to `libtdjson` through `TdPlugin` (`td_create_client_id`, `td_send`, `td_receive`, `td_execute`)
- Helpers to parse TDLib JSON into typed Dart objects (`convertJsonToObject`, `convertMapToObject`)

Package version: **2.3.13**  
Bundled TDLib / `libtdjson`: **1.8.36** (commit `87d881071`, see [`data/README.md`](data/README.md))

## Features

- Flutter plugin packaging for Android with prebuilt `libtdjson.so` libraries
- Dart FFI wrapper around the TDLib JSON client API via `TdPlugin`
- Typed TDLib API surface generated from `data/td_api.tl` (functions and objects under `lib/src/tdapi/`)
- JSON encode/decode helpers for TDLib requests and responses
- Optional custom native library path in `TdPlugin.initialize([String? libPath])`
- Android ABIs shipped in this repository: `armeabi-v7a`, `arm64-v8a`, `x86`, `x86_64`

## Requirements

From [`pubspec.yaml`](pubspec.yaml) and the Android plugin configuration:

| Requirement | Value |
|---|---|
| Dart SDK | `>=3.3.0 <4.0.0` |
| Flutter | `>=3.15.0` |
| Supported plugin platform | Android (`ffiPlugin: true`) |
| Android `minSdkVersion` | `21` |
| Android `compileSdkVersion` | `34` |
| Dependency | `ffi: ^2.1.2` |

Consumers do not need to build TDLib themselves for Android: `libtdjson.so` is included under `android/src/main/jniLibs/`.

The plugin Android manifest declares `android.permission.INTERNET`.

## Installation

```bash
flutter pub add handy_tdlib_next
```

Or add the dependency manually:

```yaml
dependencies:
  handy_tdlib_next: ^2.3.13
```

Then run:

```bash
flutter pub get
```

## Import

Main entrypoint (API + client):

```dart
import 'package:handy_tdlib_next/handy_tdlib_next.dart';
```

Or import separately:

```dart
import 'package:handy_tdlib_next/api.dart';
import 'package:handy_tdlib_next/client.dart';
```

Some generated TDLib type names (for example `File`) can clash with `dart:io` or Flutter types. Prefer a prefix when needed:

```dart
import 'package:handy_tdlib_next/api.dart' as td;
```

## Getting Started

`TdPlugin` must be initialized before use. By default it loads `libtdjson.so`:

```dart
import 'dart:convert';

import 'package:handy_tdlib_next/handy_tdlib_next.dart';

Future<void> setupTdlib() async {
  await TdPlugin.initialize();

  // Optional: load a non-default library path
  // await TdPlugin.initialize('/absolute/path/to/libtdjson.so');

  final clientId = TdPlugin.instance.tdCreateClientId();

  // Example of a synchronous TDLib call (see function docs for which
  // methods support tdExecute / "Can be called synchronously").
  final syncJson = TdPlugin.instance.tdExecute(
    const SetLogVerbosityLevel(newVerbosityLevel: 1).toString(),
  );
  final syncObject = convertJsonToObject(syncJson);

  // Asynchronous request/response uses tdSend + tdReceive and @extra.
  const extra = 42;
  TdPlugin.instance.tdSend(
    clientId,
    jsonEncode(const GetMe().toJson(extra)),
  );

  final responseJson = TdPlugin.instance.tdReceive(); // default timeout: 1s
  final response = convertJsonToObject(responseJson);
  // Match responses with the same TdObject.extra value you sent.
}
```

Notes from the current API:

- `TdFunction.toJson([dynamic extra])` builds a TDLib JSON map (`@type`, fields, optional `@extra`).
- `TdFunction.toString()` returns `jsonEncode(toJson())` (without an `extra` value unless you call `toJson(extra)` yourself and encode it).
- `convertJsonToObject` / `convertMapToObject` return a `TdObject?`.

## TDLib Client and Updates

This package exposes the low-level TDLib JSON client workflow through `TdPlugin`:

1. **`TdPlugin.initialize([libPath])`** — opens the dynamic library and sets `TdPlugin.instance`.
2. **`tdCreateClientId()`** — creates a client id for `tdSend` / association with received objects.
3. **`tdSend(clientId, request)`** — sends a JSON request string to TDLib.
4. **`tdReceive([timeout])`** — receives the next JSON update or response string (or `null`). Default timeout is `1` second.
5. **`tdExecute(request)`** — executes a request synchronously and returns the JSON result string (or `null`). Only some TDLib methods support this; check the generated function documentation (for example methods that state they can be called synchronously).

Typical correlation rules (as documented on `TdPlugin`):

- Responses to `TdFunction` requests include `TdObject.extra` matching the `@extra` you sent.
- TDLib updates arrive without `extra`.

```dart
final bool isUpdate = object?.extra == null;
```

There is no separate high-level stream client class in the current public API; applications drive send/receive themselves (often from isolates).

## Isolates and Performance

`TdPlugin` documents that `tdSend` and `tdReceive` should typically run off the UI isolate so JSON work and native calls do not block Flutter frames. `ReceivePort` / `SendPort` can transfer `TdObject` and `TdFunction` instances.

A minimal pattern:

```dart
import 'dart:convert';
import 'dart:isolate';

import 'package:handy_tdlib_next/handy_tdlib_next.dart';

Future<void> startReceiveLoop(SendPort toUi) async {
  await TdPlugin.initialize();
  final clientId = TdPlugin.instance.tdCreateClientId();
  toUi.send(clientId);

  while (true) {
    final raw = TdPlugin.instance.tdReceive(1);
    if (raw == null) continue;
    final object = convertJsonToObject(raw);
    if (object != null) {
      toUi.send(object);
    }
  }
}
```

Use a second isolate (or the same background isolate) for encoding and `tdSend` if you need to keep the UI isolate free of TDLib traffic.

## Handling Invokes and Updates

```dart
import 'dart:convert';

import 'package:handy_tdlib_next/handy_tdlib_next.dart';

void sendGetMe(int clientId, int extra) {
  TdPlugin.instance.tdSend(
    clientId,
    jsonEncode(const GetMe().toJson(extra)),
  );
}

void handleIncoming(TdObject? object, int expectedExtra) {
  if (object == null) return;

  if (object.extra == expectedExtra) {
    // Invoke result for that request
  } else if (object.extra == null) {
    // TDLib update
  }
}
```

You can also use Dart 3 pattern matching / `switch` on sealed `TdObject` / `TdFunction` subtypes generated in this package.

## Supported Platform

| Platform | Status in this package |
|---|---|
| Android | Supported (`flutter.plugin.platforms.android`, FFI plugin, bundled `libtdjson.so`) |
| iOS | Not declared |
| Web | Not declared |
| Windows / macOS / Linux | Not declared |

Default library name used by `TdPlugin.initialize()` is `libtdjson.so`, which matches the Android JNI libraries shipped in this repository.

## Compatibility

| Component | Value in this repository |
|---|---|
| Package name | `handy_tdlib_next` |
| Package version | `2.3.13` |
| TDLib version | `1.8.36` |
| TDLib commit | `87d881071` |
| Scheme | `data/td_api.tl` |
| Dart | `>=3.3.0 <4.0.0` |
| Flutter | `>=3.15.0` |

TDLib update scripts (`update-tdlib.sh`, `full-update-tdlib.sh`) and the code generator (`generator/generate.dart`) are for maintainers regenerating bindings and native libraries; they are not required for normal app usage of the published package.

## Migrating from handy_tdlib

`handy_tdlib_next` uses a different package name and is intended for projects that need a maintained package under this new name.

If your project currently depends on `handy_tdlib` and you need to move to this package:

1. Replace the dependency:

```yaml
dependencies:
  handy_tdlib_next: ^2.3.13
```

2. Update imports:

```dart
// before
import 'package:handy_tdlib/handy_tdlib.dart';

// after
import 'package:handy_tdlib_next/handy_tdlib_next.dart';
```

3. Keep using the same core types where the API still matches: `TdPlugin`, `TdFunction`, `TdObject`, `convertJsonToObject`, and the generated function/object classes.

4. Re-test Android startup, native library loading, authorization flow, and isolate wiring against TDLib **1.8.36** as bundled here.

`handy_tdlib_next` is an independently maintained community package. It is not presented as an official continuation of `handy_tdlib`.

## Troubleshooting

- **`TdPlugin.initialize` / `DynamicLibrary.open` fails**  
  Confirm you are running on Android with the plugin linked, and that your ABI is one of `armeabi-v7a`, `arm64-v8a`, `x86`, or `x86_64`. Pass an explicit `libPath` only if you intentionally load a custom `libtdjson` build.

- **Using `TdPlugin.instance` before `initialize`**  
  `instance` is set inside `TdPlugin.initialize`. Always `await TdPlugin.initialize()` first.

- **UI jank / freezes**  
  Move `tdReceive`, heavy `convertJsonToObject` work, and preferably `tdSend` / `jsonEncode` off the UI isolate, as recommended in the `TdPlugin` API comments.

- **No response from `tdReceive`**  
  `tdReceive` returns `null` on timeout (default 1 second). Keep looping, and ensure you created a client id and sent a valid JSON request.

- **`tdExecute` returns unexpected results**  
  Only some TDLib methods support synchronous execution. Prefer `tdSend` / `tdReceive` unless the generated function documentation indicates synchronous use.

- **Name conflicts with `File` or similar types**  
  Import the API with a prefix (`as td`).

## License

This package is distributed under the **BSD 3-Clause** license. See [`LICENSE`](LICENSE).

Copyright notices in `LICENSE`:

- Copyright 2019 Naji
- Copyright 2026 Abdul Moiz Dev

## Attribution

Maintained and published by **Abdul Moiz Dev** ([@itxmoizdev](https://github.com/itxmoizdev)).

This repository’s public API and packaging lineage derive from earlier Flutter/Dart TDLib binding work distributed under the BSD 3-Clause license (copyright Naji). TDLib itself is developed at [tdlib/td](https://github.com/tdlib/td).

Build metadata for the bundled Android `libtdjson` libraries is recorded in [`data/README.md`](data/README.md).

Per the BSD 3-Clause terms, neither the name of Naji nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

## Contributing

Issues and pull requests are welcome:

- Maintainer: **Abdul Moiz Dev** — [@itxmoizdev](https://github.com/itxmoizdev)
- LinkedIn: [itxmoizdev](https://www.linkedin.com/in/itxmoizdev)
- Repository: https://github.com/itxmoizdev/handy-tdlib-next

When changing the TDLib scheme or native libraries, use the maintainer scripts and regenerate Dart bindings with `dart generator/generate.dart` from the repository root, then verify with `dart analyze`.

## Disclaimer

`handy_tdlib_next` is an independent community package maintained by **Abdul Moiz Dev**. It is **not** an official Telegram or TDLib package, and it is **not** affiliated with, endorsed by, or maintained by Telegram, the TDLib project, Naji, HandyGram, or the original `handy_tdlib` authors unless stated otherwise by those parties.

Use of Telegram / TDLib is subject to Telegram’s and TDLib’s own terms and documentation. This package only provides Dart/Flutter bindings and packaging around `libtdjson`.
