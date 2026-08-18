import 'package:zopiqnow/core/l10n/strings.dart';

/// Hindi (हिन्दी).
///
/// **Register: natural Hindi, not shuddh Hindi.** Words that people in Falna,
/// Ranakpur and Sadri already say in English stay in English, written in
/// Devanagari — ऑर्डर, कार्ट, डिलीवरी, रेस्टोरेंट, सपोर्ट. The shuddh
/// alternatives (आदेश, टोकरी, वितरण) are correct and nobody uses them; a
/// customer who switched to Hindi to read faster should not have to decode it.
///
/// Two rules the translations follow:
///   * **Verbs are imperative-polite** (करें, चुनें, देखें) — the register a
///     shop uses with a customer, neither the bare imperative nor the ornate
///     कीजिए.
///   * **Numbers stay Western Arabic** (1, 2, 3), because prices, order numbers
///     and phone numbers all arrive from the backend that way, and mixing
///     १२३ into a screen that also shows ₹120 reads as a bug.
///
/// A getter left out here inherits its English from [AppStrings] rather than
/// breaking the build — see the note there.
class AppStringsHi extends AppStrings {
  const AppStringsHi();

  // ---------------------------------------------------------------------------
  // Common.
  // ---------------------------------------------------------------------------

  @override
  String get close => 'बंद करें';
  @override
  String get cancel => 'रद्द करें';
  @override
  String get save => 'सेव करें';
  @override
  String get retry => 'दोबारा कोशिश करें';
  @override
  String get delete => 'डिलीट करें';
  @override
  String get remove => 'हटाएँ';
  @override
  String get done => 'हो गया';
  @override
  String get next => 'आगे';
  @override
  String get back => 'पीछे';
  @override
  String get confirm => 'कन्फ़र्म करें';
  @override
  String get yes => 'हाँ';
  @override
  String get no => 'नहीं';
  @override
  String get search => 'खोजें';
  @override
  String get somethingWentWrong => 'कुछ गड़बड़ हो गई';
  @override
  String get noInternet => 'इंटरनेट कनेक्शन नहीं है';
  @override
  String get loading => 'लोड हो रहा है…';

  // ---------------------------------------------------------------------------
  // Account screen.
  // ---------------------------------------------------------------------------

  @override
  String get accountTitle => 'अकाउंट';
  @override
  String get accountMyPreferences => 'मेरी प्राथमिकताएँ';
  @override
  String get accountFoodDelivery => 'फ़ूड डिलीवरी';
  @override
  String get accountMore => 'अन्य';

  @override
  String get accountMyOrders => 'मेरे ऑर्डर';
  @override
  String get accountMyOrdersSubtitle => 'ऑर्डर ट्रैक करें और दोबारा मंगाएँ';
  @override
  String get accountGiftOrders => 'गिफ़्ट ऑर्डर';
  @override
  String get accountGiftOrdersSubtitle =>
      'आपने जो गिफ़्ट ख़रीदे, और वे कहाँ तक पहुँचे';
  @override
  String get accountMyAddresses => 'मेरे पते';
  @override
  String get accountMyAddressesSubtitle => 'अपने डिलीवरी पते मैनेज करें';
  @override
  String get accountCollection => 'आपका कलेक्शन';
  @override
  String get accountCollectionSubtitle => 'आपके सेव किए हुए रेस्टोरेंट';

  @override
  String get accountHelpSupport => 'मदद और सपोर्ट';
  @override
  String get accountLegal => 'कानूनी और नीतियाँ';
  @override
  String get accountLicenses => 'लाइसेंस और क्रेडिट';
  @override
  String get accountDesignSystem => 'डिज़ाइन सिस्टम';
  @override
  String get accountDeleteAccount => 'अकाउंट डिलीट करें';
  @override
  String get accountLogOut => 'लॉग आउट';

  @override
  String accountSupportBody(String email) =>
      'हमें ईमेल करें, कोई व्यक्ति जवाब देगा।\n\n$email\n\n'
      'अगर बात किसी ऑर्डर की है, तो ऑर्डर नंबर ज़रूर भेजें — वह '
      '"मेरे ऑर्डर" में उस ऑर्डर पर लिखा होता है।';

  @override
  String get accountWelcome => 'zopiqnow में आपका स्वागत है';
  @override
  String get accountWelcomeSubtitle =>
      'ऑर्डर ट्रैक करने और पते सेव करने के लिए लॉग इन करें';
  @override
  String get accountLogIn => 'लॉग इन';
  @override
  String get accountAddYourName => 'अपना नाम जोड़ें';

  @override
  String get accountVegMode => '100% वेज मोड';
  @override
  String get accountVegModeSubtitle => 'सिर्फ़ वेज रेस्टोरेंट दिखाएँ';

  @override
  String get accountAppearance => 'थीम';
  @override
  String get accountAppearanceSubtitle => 'लाइट, डार्क या सिस्टम';
  @override
  String get accountThemeLight => 'लाइट';
  @override
  String get accountThemeDark => 'डार्क';
  @override
  String get accountThemeSystem => 'सिस्टम';

  @override
  String get accountLanguage => 'भाषा';
  @override
  String get accountLanguageSubtitle => 'अपनी भाषा चुनें';

  // ---------------------------------------------------------------------------
  // Home — the dish-category rail.
  // ---------------------------------------------------------------------------

  /// Keyed by `FoodCategory.id`, never by its label — see [AppStrings.categoryName]
  /// for why translating the label would break every category page.
  ///
  /// These are transliterations, not translations, and that is the right call
  /// for food. A customer looking for pizza is looking for पिज़्ज़ा; rendering
  /// it as some invented Hindi compound would make the rail unreadable to the
  /// very people who switched languages to read it more easily. Only the two
  /// entries that are genuinely words rather than dish names — "View More" and
  /// "Rice" — are actually translated.
  static const Map<String, String> _categoryNames = <String, String>{
    'sandwich': 'सैंडविच',
    'pizza': 'पिज़्ज़ा',
    'burger': 'बर्गर',
    'momos': 'मोमोज़',
    'pav_bhaji': 'पाव भाजी',
    'dosa': 'डोसा',
    'aloo_paratha': 'आलू पराठा',
    'paneer_tikka': 'पनीर टिक्का',
    'paneer_sabji': 'पनीर सब्ज़ी',
    'icecream': 'आइसक्रीम',
    'sweet_box': 'मिठाई बॉक्स',
    'chocolate_cake': 'केक',
    'cold_coffee': 'कोल्ड कॉफ़ी',
    'view_more': 'और देखें',
    'north_indian': 'नॉर्थ इंडियन',
    'south_indian': 'साउथ इंडियन',
    'chinese': 'चाइनीज़',
    'thali': 'थाली',
    'chole_bhature': 'छोले भटूरे',
    'chicken_curry': 'चिकन करी',
    'chicken_tikka': 'चिकन टिक्का',
    'mutton': 'मटन',
    'egg_curry': 'अंडा करी',
    'chilli_paneer': 'चिली पनीर',
    'manchurian': 'मंचूरियन',
    'pulao': 'पुलाव',
    'rice': 'चावल',
    'paratha': 'पराठा',
    'vada': 'वड़ा',
    'vadapav': 'वड़ा पाव',
    'samosa': 'समोसा',
    'pakode': 'पकौड़े',
    'maggi': 'मैगी',
    'pasta': 'पास्ता',
    'white_sauce_pasta': 'व्हाइट सॉस पास्ता',
    'fries': 'फ़्राइज़',
    'waffle': 'वफ़ल',
    'shake': 'शेक',
    'lassi': 'लस्सी',
  };

  @override
  String categoryName(String id, String englishLabel) =>
      _categoryNames[id] ?? englishLabel;

  @override
  String homeNoCategoryNearby(String categoryName) =>
      '$categoryName आपके आस-पास अभी नहीं मिला। कोई और कैटेगरी देखें।';

  @override
  String get homeRecommendedForYou => 'आपके लिए सुझाव';
  @override
  String get homeConnectionError =>
      'अपना इंटरनेट कनेक्शन जाँचें और दोबारा कोशिश करें।';
  @override
  String get homeWhatsOnYourMind => 'आज क्या खाने का मन है?';
  @override
  String get homeVegOnly => 'सिर्फ़ वेज';
}
