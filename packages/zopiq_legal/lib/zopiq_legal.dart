/// zopiq_legal — the terms, the privacy policy, and the nineteen documents
/// beside them.
///
/// The Word originals in `legal/source/` are the source of truth.
/// `tool/import_legal.mjs` generates the Dart under `src/documents/`, and
/// `apps/customer/tool/build_legal.dart` generates the public HTML from the
/// same data. Three surfaces, one text, no retyping.
library;

/// The data half is also exportable on its own, for the HTML build — see
/// `zopiq_legal_data.dart` for why that has to be possible.
export 'src/consent.dart';
export 'src/legal_document.dart';
export 'src/legal_document_page.dart';
export 'src/legal_index_page.dart';
export 'src/registry.dart';
