// Generates the public web copies of the legal documents from
// `package:zopiq_legal`, which is itself generated from the Word originals in
// `legal/source/` by `tool/import_legal.mjs`.
//
//   dart run tool/build_legal.dart
//
// Writes into `<repo>/docs/`, which is the GitHub Pages root and therefore the
// published site (8a957cc: "the documents move to where Pages can serve them").
// It is **not** `legal/` — that directory holds the Word originals the importer
// reads, and HTML written there is HTML nobody serves. Google Play needs the
// privacy policy and the account-deletion page to be reachable *without*
// installing the app, and it checks the URLs, so they have to be live before
// the listing is submitted and stay live afterwards.
//
// **Do not edit the generated HTML.** Edit the .docx, run the importer, run
// this. The whole point of the chain is that the three apps and the website
// cannot drift apart.
import 'dart:io';

// The **data** barrel, not the main one. This script runs under the plain Dart
// VM, which cannot compile `package:flutter` or the FFI plugins behind
// `supabase_flutter` — it crashes the compiler front end rather than failing
// politely. See `zopiq_legal_data.dart`.
import 'package:zopiq_legal/zopiq_legal_data.dart';
import 'package:zopiqnow/features/account/domain/contact.dart';

void main() {
  final Directory out = Directory('../../docs');
  out.createSync(recursive: true);

  // Pages serves this directory raw only if Jekyll is told not to touch it.
  // Recreated rather than assumed: an empty marker file is exactly the kind of
  // thing a clean checkout or an over-eager tidy-up loses, and losing it makes
  // every page 404 in a way that looks like a DNS problem.
  File('${out.path}/.nojekyll').writeAsStringSync('');

  for (final LegalDocument doc in allLegalDocuments) {
    File(
      '${out.path}/${doc.slug}.html',
    ).writeAsStringSync(_render(doc));
  }
  stdout.writeln('wrote ${allLegalDocuments.length} documents');

  File('${out.path}/delete-account.html').writeAsStringSync(_renderDeletion());
  File('${out.path}/index.html').writeAsStringSync(_renderIndex());
  stdout.writeln('wrote delete-account.html and index.html');

  // Play's listing points at fixed URLs, and the two it points at are the ones
  // whose slugs changed when the corpus arrived. A redirect stub costs nothing
  // and means a link already submitted to Google does not 404 the week the
  // review happens.
  _writeRedirect(out, 'privacy.html', 'privacy-policy.html');
  _writeRedirect(out, 'terms.html', 'terms-and-conditions.html');
  stdout.writeln('wrote redirects for the previous two URLs');
}

String _render(LegalDocument doc) {
  final StringBuffer b = StringBuffer();
  b.writeln(_head(doc.title));
  b.writeln('<h1>${_esc(doc.title)}</h1>');
  if (doc.subtitle != null) {
    b.writeln('<p class="lede">${_esc(doc.subtitle!)}</p>');
  }
  b.writeln(
    '<p class="meta">Version ${_esc(doc.version)} · '
    'Effective ${_esc(doc.effectiveDate)}'
    '${doc.docId != null ? ' · ${_esc(doc.docId!)}' : ''}</p>',
  );

  for (final LegalBlock block in doc.blocks) {
    switch (block) {
      case LegalHeading(level: final int level, text: final String text):
        // h1 is the document title, so the source's level 1 starts at h2 — a
        // page with two h1s is a page a screen reader cannot navigate.
        final int tag = level + 1;
        b.writeln('<h$tag>${_esc(text)}</h$tag>');
      case LegalParagraph(text: final String text):
        b.writeln('<p>${_esc(text)}</p>');
      case LegalBullets(items: final List<String> items):
        b.writeln('<ul>');
        for (final String item in items) {
          b.writeln('  <li>${_esc(item)}</li>');
        }
        b.writeln('</ul>');
      case LegalTable(
        headers: final List<String> headers,
        rows: final List<List<String>> rows,
      ):
        // Wrapped in its own scroller: a four-column retention schedule is
        // wider than a phone, and a table that widens the page body makes the
        // whole document scroll sideways.
        b.writeln('<div class="scroll"><table>');
        b.writeln('<thead><tr>');
        for (final String h in headers) {
          b.writeln('  <th>${_esc(h)}</th>');
        }
        b.writeln('</tr></thead><tbody>');
        for (final List<String> row in rows) {
          b.writeln('<tr>');
          for (final String cell in row) {
            b.writeln('  <td>${_esc(cell)}</td>');
          }
          b.writeln('</tr>');
        }
        b.writeln('</tbody></table></div>');
    }
  }

  b.writeln(_foot());
  return b.toString();
}

/// The page Play links to from the store listing: how to delete an account
/// without installing anything.
///
/// A separate page and not a paragraph in a policy because the requirement is
/// specific — a *route* to deletion, reachable from the web, stating what is
/// deleted and what is kept. The same three facts the in-app screen states, so
/// they are worded the same way here on purpose.
String _renderDeletion() {
  final StringBuffer b = StringBuffer();
  b.writeln(_head('Delete your $brandName account'));
  b.writeln('<h1>Delete your $brandName account</h1>');
  b.writeln(
    '<p class="lede">You can delete your account yourself, from inside the app, '
    'and it takes two taps. If you no longer have the app installed, email us '
    'and we will do it for you.</p>',
  );

  b.writeln('<h2>In the app</h2>');
  b.writeln(
    '<p>Open $brandName, go to <strong>Account</strong>, scroll to the bottom '
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
    '<p>Full detail is in the <a href="privacy-policy.html">privacy policy</a> '
    'and the <a href="account-deletion-data-retention-policy.html">account '
    'deletion &amp; data retention policy</a>.</p>',
  );
  b.writeln(_foot());
  return b.toString();
}

String _renderIndex() {
  final StringBuffer b = StringBuffer();
  b.writeln(_head('$brandName — legal'));
  b.writeln('<h1>$brandName</h1>');
  b.writeln(
    '<p class="lede">Everything $brandName is bound by, and everything it asks '
    'of the people who use it. $brandName is operated by $legalEntity, '
    'Sadri, Rajasthan.</p>',
  );

  // Grouped the way the app groups them, and — unlike the app — showing every
  // group, because a restaurant owner and a delivery partner read this page too
  // and neither has an app-shaped audience here.
  for (final String group in legalGroupOrder) {
    final List<LegalDocument> inGroup = allLegalDocuments
        .where((LegalDocument d) => d.group == group)
        .toList(growable: false);
    if (inGroup.isEmpty) continue;

    b.writeln('<h2>${_esc(legalGroupTitles[group]!)}</h2>');
    b.writeln('<ul>');
    for (final LegalDocument doc in inGroup) {
      final String title = doc.title.replaceFirst('Zopiq ', '');
      b.writeln(
        '  <li><a href="${doc.slug}.html">${_esc(title)}</a>'
        '${doc.subtitle != null ? ' — ${_esc(doc.subtitle!)}' : ''}</li>',
      );
    }
    b.writeln('</ul>');
  }

  b.writeln('<h2>Your account</h2>');
  b.writeln('<ul>');
  b.writeln('  <li><a href="delete-account.html">Delete your account</a></li>');
  b.writeln('</ul>');
  b.writeln(
    '<p>Questions: <a href="mailto:$supportEmail">$supportEmail</a>. '
    'Legal notices: <a href="mailto:hello@hybridmonks.com">'
    'hello@hybridmonks.com</a>.</p>',
  );
  b.writeln(_foot());
  return b.toString();
}

/// A meta-refresh rather than a server rule, because the publishing target is a
/// static folder and may not have one to configure.
void _writeRedirect(Directory out, String from, String to) {
  File('${out.path}/$from').writeAsStringSync('''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="0; url=$to">
<link rel="canonical" href="$to">
<title>Moved</title>
</head>
<body><p>This document has moved to <a href="$to">$to</a>.</p></body>
</html>''');
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
  h2 { font-size: 1.05rem; letter-spacing: .02em; margin: 2.25rem 0 .6rem; }
  h3 { font-size: 1rem; margin: 1.6rem 0 .5rem; }
  h4 { font-size: .95rem; margin: 1.3rem 0 .4rem; }
  p, li, td, th { color: #3a3a3c; }
  .lede { font-size: 1.05rem; }
  .meta { font-size: .85rem; color: #8e8e93; margin-top: -.4rem; }
  ul { padding-left: 1.15rem; }
  li { margin-bottom: .5rem; }
  a { color: #fc8019; }
  .scroll { overflow-x: auto; margin: 1rem 0; }
  table { border-collapse: collapse; width: 100%; font-size: .9rem; }
  th, td { border: 1px solid #e5e5ea; padding: .5rem .65rem; text-align: left;
           vertical-align: top; }
  th { font-weight: 600; }
  footer { margin-top: 3.5rem; padding-top: 1.25rem; border-top: 1px solid #e5e5ea;
           font-size: .85rem; color: #8e8e93; }
  @media (prefers-color-scheme: dark) {
    body { color: #f2f2f7; background: #121212; }
    p, li, td, th { color: #c7c7cc; }
    th, td { border-color: #2c2c2e; }
    footer { border-top-color: #2c2c2e; color: #8e8e93; }
  }
</style>
</head>
<body>''';

String _foot() =>
    '''
<footer>
  $brandName, operated by $legalEntity ·
  <a href="mailto:$supportEmail">$supportEmail</a><br>
  <a href="index.html">All documents</a>
</footer>
</body>
</html>''';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
