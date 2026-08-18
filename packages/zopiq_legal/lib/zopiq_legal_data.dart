/// The corpus without the widgets.
///
/// Exists because `tool/build_legal.dart` runs under the **plain Dart VM**, not
/// Flutter — it is a script that writes HTML files, and `dart run` is the only
/// way to run it. Importing the main barrel drags in `package:flutter` and the
/// FFI plugins behind `supabase_flutter`, which the standalone VM cannot
/// compile: it does not fail politely, it crashes the front end with
/// `'InvalidType' is not a subtype of 'FunctionType'`.
///
/// So the data is exportable on its own. Everything here is pure Dart with no
/// import outside `dart:core`, and it is the same data the widgets render —
/// there is still one copy of every document.
library;

export 'src/legal_document.dart';
export 'src/registry.dart';
