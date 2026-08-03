/// The privacy policy and the terms, as data.
///
/// **This file is the only copy.** The same text has to exist in two places —
/// inside the app, where a customer reads it, and on a public web page, because
/// Google Play will not list an app whose privacy policy is not reachable
/// without installing it. Two hand-written copies of a legal document is two
/// documents that disagree within a year, and the one that disagrees is always
/// the one somebody is reading.
///
/// So the text lives here once. [LegalPage] renders it in the app, and
/// `tool/build_legal.dart` generates the HTML pages from the same structure.
/// Edit this file; run the tool; publish. Never edit the generated HTML.
library;

/// Where a customer writes to about any of this. One constant because it
/// appears in both documents, in the Play listing, and in the grievance section
/// the DPDP Act requires — four places that must not drift apart.
const String supportEmail = 'support@zopiqnow.com';

/// The legal entity behind the app, as it should appear on a legal document.
const String legalEntity = 'Zopiqnow';

/// When these documents were last changed. Update it when you change them —
/// a policy with a stale date is evidence of a policy nobody maintains.
const String lastUpdated = '1 August 2026';

/// One document: a title, a preamble, and the sections under it.
class LegalDocument {
  const LegalDocument({
    required this.slug,
    required this.title,
    required this.preamble,
    required this.sections,
  });

  /// The url segment — `privacy` or `terms`.
  final String slug;
  final String title;
  final String preamble;
  final List<LegalSection> sections;
}

class LegalSection {
  const LegalSection({required this.heading, required this.paragraphs, this.bullets = const <String>[]});

  final String heading;
  final List<String> paragraphs;
  final List<String> bullets;
}

/// Both documents, by slug.
const Map<String, LegalDocument> legalDocuments = <String, LegalDocument>{
  'privacy': privacyPolicy,
  'terms': termsOfService,
};

// ---------------------------------------------------------------------------
// Privacy policy
// ---------------------------------------------------------------------------
// Written against the schema, not from a template. Every item in "What we
// collect" is a column that exists; nothing is listed that we do not actually
// hold, and nothing we hold is left out. If a migration adds a personal field,
// it belongs here in the same commit.
const LegalDocument privacyPolicy = LegalDocument(
  slug: 'privacy',
  title: 'Privacy Policy',
  preamble:
      'This policy explains what $legalEntity collects when you order food '
      'through our app, why we need it, who else sees it, and how to get rid of '
      'it. It is written to be read, not to be survived. Last updated $lastUpdated.',
  sections: <LegalSection>[
    LegalSection(
      heading: 'What we collect',
      paragraphs: <String>[
        'Only what an order needs, plus what you choose to tell us:',
      ],
      bullets: <String>[
        'Your email address, which is how you sign in. If you use Google to '
            'sign in, we receive your email address, your name and your profile '
            'picture from Google.',
        'Your phone number. The restaurant and the delivery partner need to be '
            'able to reach you.',
        'Your delivery addresses, including the location you pin on the map and '
            'any note you add for the delivery partner.',
        'Your device location while you are choosing an address, so the map can '
            'start somewhere near you. We do not track your location in the '
            'background and we do not collect it when the app is closed.',
        'Your orders: what you ordered, from where, when, what it cost, and how '
            'you paid.',
        'Your ratings and any review you write.',
        'A push notification token for the device you installed the app on, so '
            'we can tell you your order is on its way.',
        'Optionally, if you fill them in: your name, your profile photo, your '
            'date of birth and your gender.',
      ],
    ),
    LegalSection(
      heading: 'What we do not collect',
      paragraphs: <String>[
        'We do not collect your contacts, your photos beyond the one you choose '
            'as a profile picture, your messages, your calendar, or anything '
            'about the other apps on your phone. We do not track you across '
            'other apps or websites, and we do not sell your data to anybody, '
            'for any purpose, ever.',
        'We never see your card, UPI PIN or bank credentials. Payments are '
            'handled by our payment provider; what comes back to us is whether '
            'the payment succeeded and a reference number for it.',
      ],
    ),
    LegalSection(
      heading: 'Who else sees it',
      paragraphs: <String>[
        'Only the people an order cannot happen without:',
      ],
      bullets: <String>[
        'The restaurant you ordered from sees your order, your first name and '
            'your delivery address.',
        'The delivery partner carrying your order sees your name, your phone '
            'number and your delivery address, for as long as they are carrying '
            'it.',
        'Our payment provider (Razorpay) handles the payment itself.',
        'Our technical providers store the data on our behalf: Supabase '
            '(database and accounts), Google Firebase (push notifications, and '
            'crash reports when the app goes wrong), Cloudinary (images), and '
            'Google Maps and Ola Maps (maps and routing). They process it for '
            'us and for nobody else.',
        'A crash report says what broke, on what kind of phone, and which '
            'account hit it. It does not carry your name, email, phone number '
            'or address. We read them to fix the app, and for nothing else.',
        'Government authorities, if the law requires it of us.',
      ],
    ),
    LegalSection(
      heading: 'How long we keep it',
      paragraphs: <String>[
        'Your account details stay until you delete your account. Your delivery '
            'addresses, saved restaurants and notifications go the moment you do.',
        'Your orders are kept for as long as tax and accounting law requires us '
            'to keep financial records, because an order is also an invoice and '
            'the money from it is paid to a restaurant. After you delete your '
            'account those records no longer name you: your phone number and '
            'delivery address are erased from them, and the order is no longer '
            'connected to any person.',
      ],
    ),
    LegalSection(
      heading: 'Deleting your account',
      paragraphs: <String>[
        'Open the app, go to Account, and tap Delete account. It is immediate '
            'and it cannot be undone. The screen lists exactly what is deleted '
            'and what has to be kept before you confirm.',
        'You can also ask us to delete your account by writing to $supportEmail '
            'from the email address you signed up with. There is a web page for '
            'this too, linked from our Play Store listing, if you no longer have '
            'the app installed.',
      ],
    ),
    LegalSection(
      heading: 'Your rights',
      paragraphs: <String>[
        'Under India\'s Digital Personal Data Protection Act you can ask us for '
            'a copy of what we hold about you, ask us to correct anything that '
            'is wrong, and ask us to erase it. Write to $supportEmail and we '
            'will answer within 30 days.',
        'If you are not satisfied with how we handled your request, you can '
            'escalate it to our Grievance Officer at the same address, and after '
            'that to the Data Protection Board of India.',
      ],
    ),
    LegalSection(
      heading: 'Children',
      paragraphs: <String>[
        'The app is not intended for anybody under 18, and we do not knowingly '
            'create accounts for children. If you believe a child has an '
            'account with us, write to $supportEmail and we will delete it.',
      ],
    ),
    LegalSection(
      heading: 'Security',
      paragraphs: <String>[
        'Data travels to us encrypted and is stored encrypted. Access to it is '
            'restricted to the people who need it to run the service. No system '
            'is perfectly secure, and we will tell you if something happens that '
            'affects your data.',
      ],
    ),
    LegalSection(
      heading: 'Changes to this policy',
      paragraphs: <String>[
        'If we change this policy we will update the date at the top and, if the '
            'change matters to you, tell you in the app. Continuing to use '
            '$legalEntity after a change means you accept it.',
      ],
    ),
    LegalSection(
      heading: 'Contact',
      paragraphs: <String>[
        'Write to $supportEmail about anything in this policy, including '
            'grievances under the DPDP Act.',
      ],
    ),
  ],
);

// ---------------------------------------------------------------------------
// Terms of service
// ---------------------------------------------------------------------------
const LegalDocument termsOfService = LegalDocument(
  slug: 'terms',
  title: 'Terms of Service',
  preamble:
      'These are the terms you agree to when you use $legalEntity. '
      'Last updated $lastUpdated.',
  sections: <LegalSection>[
    LegalSection(
      heading: 'What we do',
      paragraphs: <String>[
        '$legalEntity is a platform. Restaurants list their food on it, you '
            'order from them through it, and delivery partners bring the order '
            'to you. The restaurant cooks the food and is responsible for it; we '
            'are responsible for the platform and for arranging the delivery.',
      ],
    ),
    LegalSection(
      heading: 'Your account',
      paragraphs: <String>[
        'You must be 18 or older to have an account. Keep your email account '
            'secure, because whoever can read your email can sign in as you. '
            'Tell us at $supportEmail if you think somebody else has used your '
            'account.',
        'You can delete your account at any time from the Account screen.',
      ],
    ),
    LegalSection(
      heading: 'Orders and payment',
      paragraphs: <String>[
        'Prices, taxes and fees are shown before you pay, and the total you see '
            'at checkout is what is charged. Payment is taken when you place the '
            'order.',
        'A restaurant can refuse an order — because it is closed, out of an '
            'ingredient, or too busy. If that happens, or if we cancel an order, '
            'you are refunded in full to the way you paid.',
        'You can cancel an order yourself until the restaurant has started '
            'cooking it. After that, cancelling may not be possible, and a '
            'refund is at our discretion.',
      ],
    ),
    LegalSection(
      heading: 'Delivery',
      paragraphs: <String>[
        'Delivery times are estimates. Traffic, weather and how busy a kitchen '
            'is all move them.',
        'Somebody has to be at the address to receive the order. The delivery '
            'partner will ask for the one-time code shown in the app. If nobody '
            'can be reached at the address, the order may be returned and not '
            'refunded.',
      ],
    ),
    LegalSection(
      heading: 'Ratings and reviews',
      paragraphs: <String>[
        'You can rate an order you actually placed. Do not write anything '
            'abusive, untrue, or about anybody other than the food and the '
            'service. We may remove a review that breaks this.',
      ],
    ),
    LegalSection(
      heading: 'Using the app properly',
      paragraphs: <String>[
        'Do not use $legalEntity to break the law, to abuse restaurant staff or '
            'delivery partners, to place orders you do not intend to accept, or '
            'to attack, copy or interfere with the app or our systems. We can '
            'suspend or close an account that does.',
      ],
    ),
    LegalSection(
      heading: 'Coupons and offers',
      paragraphs: <String>[
        'A coupon is valid for what its terms say and no longer. We can '
            'withdraw an offer, and we can cancel a discount obtained by '
            'misusing one.',
      ],
    ),
    LegalSection(
      heading: 'When something goes wrong',
      paragraphs: <String>[
        'Tell us at $supportEmail. If the food was wrong, missing or not fit to '
            'eat, tell us the same day and we will make it right — a refund, or '
            'the order again.',
        'Beyond that, our liability to you for any order is limited to what you '
            'paid for it. We are not liable for things outside our control.',
      ],
    ),
    LegalSection(
      heading: 'Changes and governing law',
      paragraphs: <String>[
        'We may change these terms; the date at the top says when we last did. '
            'These terms are governed by the laws of India, and the courts of '
            'India have jurisdiction over any dispute.',
      ],
    ),
  ],
);
