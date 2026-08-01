// Generates the public web copies of the legal documents from the single
// source in `lib/features/account/domain/legal_documents.dart`.
//
//   dart run tool/build_legal.dart
//
// Writes into `<repo>/legal/`, which is what gets published — GitHub Pages, a
// folder on the marketing site, anywhere with a stable URL. Google Play needs
// the privacy policy and the account-deletion page to be reachable *without*
// installing the app, and it checks the URLs, so they have to be live before
// the listing is submitted and stay live afterwards.
//
// **Do not edit the generated HTML.** Edit the Dart and run this again; the
// whole point of the tool is that the app and the website cannot drift apart.
import 'dart:io';

import 'package:zopiqnow/features/account/domain/legal_documents.dart';

void main() {
  final Directory out = Directory('../../legal');
  out.createSync(recursive: true);

  for (final LegalDocument doc in <LegalDocument>[privacyPolicy, termsOfService]) {
    final File file = File('${out.path}/${doc.slug}.html');
    file.writeAsStringSync(_render(doc));
    stdout.writeln('wrote ${file.path}');
  }

  final File deletion = File('${out.path}/delete-account.html');
  deletion.writeAsStringSync(_renderDeletion());
  stdout.writeln('wrote ${deletion.path}');

  final File index = File('${out.path}/index.html');
  index.writeAsStringSync(_renderIndex());
  stdout.writeln('wrote ${index.path}');
}

String _render(LegalDocument doc) {
  final StringBuffer b = StringBuffer();
  b.writeln(_head(doc.title));
  b.writeln('<h1>${_esc(doc.title)}</h1>');
  b.writeln('<p class="lede">${_esc(doc.preamble)}</p>');

  for (final LegalSection s in doc.sections) {
    b.writeln('<h2>${_esc(s.heading)}</h2>');
    for (final String p in s.paragraphs) {
      b.writeln('<p>${_esc(p)}</p>');
    }
    if (s.bullets.isNotEmpty) {
      b.writeln('<ul>');
      for (final String item in s.bullets) {
        b.writeln('  <li>${_esc(item)}</li>');
      }
      b.writeln('</ul>');
    }
  }

  b.writeln(_foot());
  return b.toString();
}

/// The page Play links to from the store listing: how to delete an account
/// without installing anything.
///
/// It is a separate page and not a paragraph in the policy because the
/// requirement is specific — a *route* to deletion, reachable from the web,
/// stating what is deleted and what is kept. The same three facts the in-app
/// screen states, so they are worded the same way here on purpose.
String _renderDeletion() {
  final StringBuffer b = StringBuffer();
  b.writeln(_head('Delete your $legalEntity account'));
  b.writeln('<h1>Delete your $legalEntity account</h1>');
  b.writeln(
    '<p class="lede">You can delete your account yourself, from inside the app, '
    'and it takes two taps. If you no longer have the app installed, email us '
    'and we will do it for you.</p>',
  );

  b.writeln('<h2>In the app</h2>');
  b.writeln(
    '<p>Open $legalEntity, go to <strong>Account</strong>, scroll to the bottom '
    'and tap <strong>Delete account</strong>. The screen lists what is deleted '
    'and what has to be kept, and asks you to confirm. It happens immediately '
    'and cannot be undone.</p>',
  );

  b.writeln('<h2>By email</h2>');
  b.writeln(
    '<p>Write to <a href="mailto:$supportEmail">$supportEmail</a> from the email '
    'address you signed up with, asking us to delete your account. We will '
    'confirm and delete it within 30 days, usually much sooner. We may ask you '
    'to confirm the request from that address — that is the only way we can '
    'tell it is you.</p>',
  );

  b.writeln('<h2>What is deleted</h2>');
  b.writeln('<ul>');
  b.writeln('  <li>Your login, and your Google sign-in if you used one</li>');
  b.writeln('  <li>Your name, phone number and profile photo</li>');
  b.writeln('  <li>Every saved delivery address</li>');
  b.writeln('  <li>Your saved restaurants</li>');
  b.writeln('  <li>Your notifications, and the push tokens for your devices</li>');
  b.writeln('  <li>Anything you wrote in a review</li>');
  b.writeln('</ul>');

  b.writeln('<h2>What is kept, with you removed from it</h2>');
  b.writeln(
    '<p>Your past orders — the amounts, the restaurant and the date. We are '
    'required to keep these as tax records, and the restaurants are paid from '
    'them. Your name, phone number and delivery address are erased from every '
    'one of them, and the records no longer identify you. Your star ratings stay '
    'so that restaurants\' scores do not change, shown without a name.</p>',
  );

  b.writeln(
    '<p>Full detail is in the <a href="privacy.html">privacy policy</a>.</p>',
  );
  b.writeln(_foot());
  return b.toString();
}

String _renderIndex() {
  final StringBuffer b = StringBuffer();
  b.writeln(_head('$legalEntity — legal'));
  b.writeln('<h1>$legalEntity</h1>');
  b.writeln('<ul>');
  b.writeln('  <li><a href="privacy.html">Privacy Policy</a></li>');
  b.writeln('  <li><a href="terms.html">Terms of Service</a></li>');
  b.writeln('  <li><a href="delete-account.html">Delete your account</a></li>');
  b.writeln('</ul>');
  b.writeln('<p>Questions: <a href="mailto:$supportEmail">$supportEmail</a></p>');
  b.writeln(_foot());
  return b.toString();
}

/// One stylesheet, inline, and no external anything. A legal page that depends
/// on a CDN is a legal page that is blank the day the CDN is blocked — and Play
/// checks these URLs from somewhere that is not your office.
String _head(String title) =>
    '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_esc(title)}</title>
<style>
  :root { color-scheme: light dark; }
  body {
    margin: 0 auto; padding: 2.5rem 1.25rem 5rem; max-width: 44rem;
    font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    color: #1c1c1e; background: #fff;
  }
  h1 { font-size: 1.9rem; line-height: 1.2; margin: 0 0 1rem; }
  h2 { font-size: 1.15rem; margin: 2.25rem 0 .6rem; }
  p, li { color: #3a3a3c; }
  .lede { font-size: 1.05rem; }
  ul { padding-left: 1.15rem; }
  li { margin-bottom: .5rem; }
  a { color: #fc8019; }
  footer { margin-top: 3.5rem; padding-top: 1.25rem; border-top: 1px solid #e5e5ea;
           font-size: .85rem; color: #8e8e93; }
  @media (prefers-color-scheme: dark) {
    body { color: #f2f2f7; background: #121212; }
    p, li { color: #c7c7cc; }
    footer { border-top-color: #2c2c2e; color: #8e8e93; }
  }
</style>
</head>
<body>''';

String _foot() =>
    '''
<footer>
  $legalEntity · Last updated $lastUpdated ·
  <a href="mailto:$supportEmail">$supportEmail</a><br>
  <a href="index.html">All documents</a>
</footer>
</body>
</html>''';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
