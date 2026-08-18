/// Who a customer writes to, and who they are writing to about.
///
/// This file used to hold the privacy policy and the terms as Dart literals.
/// It no longer does: the corpus moved to `package:zopiq_legal`, generated from
/// the Word originals in `legal/source/`, where it is twenty-one documents
/// rather than two and where the lawyers can edit it. What is left here is the
/// handful of strings the *app* says in its own voice — the support row, the
/// Play listing, the account-deletion page — which are not part of any document
/// and would be a strange thing to generate.
library;

/// The address a customer writes to for help.
///
/// Deliberately **not** the address on the legal documents. Those name
/// `hello@hybridmonks.com`, which is where a legal notice belongs; this is the
/// inbox that is actually watched for "where is my order". Keeping them apart
/// is a decision, not an oversight — a support queue and a legal-notice queue
/// answered by the same person at the same speed is one of them being answered
/// badly.
const String supportEmail = 'zopiqnow@gmail.com';

/// The brand, as a customer sees it.
const String brandName = 'Zopiq';

/// The legal person behind the brand, as it appears on every document and on
/// the GST invoice. Named here because the account-deletion page has to say
/// whose records are being deleted.
const String legalEntity = 'Hybrid Monks LLP';
