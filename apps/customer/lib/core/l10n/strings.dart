import 'package:flutter/widgets.dart';

/// Every user-facing string in the customer app, in English.
///
/// **Why this and not `flutter_localizations` + ARB files.** The architecture
/// doc specifies the ARB route, and it is the better route in general — plurals,
/// dates and tooling all come free. It was rejected here for one reason: `intl`
/// is not in `pubspec.lock` at all, and `flutter_localizations` pins it to a
/// version the Flutter SDK dictates. That is a new dependency with the power to
/// move existing pins, which is exactly what the version freeze exists to stop.
/// A class of getters costs nothing, moves no pin, and the compiler still
/// catches a typo in a key — which is most of what ARB codegen was buying.
///
/// **English is concrete, not abstract, and that is deliberate.** A translation
/// subclass overrides what it has translated and inherits what it has not, so a
/// key nobody has reached yet renders readable English instead of failing to
/// compile or showing a raw key to a customer. The trade is that a *missing*
/// translation is silent; `tool/l10n_coverage.dart` exists to make it loud.
///
/// **Adding a string:** add a getter here in English, override it in every
/// subclass, and read it at the call site through `context.l10n`. Never
/// concatenate translated fragments — word order is not a constant across
/// languages. Where a value has to sit inside a sentence, make the entry a
/// method that takes it, so the translation controls where it lands.
class AppStrings {
  const AppStrings();

  // ---------------------------------------------------------------------------
  // Common — actions, states and words that recur on many screens.
  // ---------------------------------------------------------------------------

  String get close => 'Close';
  String get cancel => 'Cancel';
  String get save => 'Save';
  String get retry => 'Retry';
  String get delete => 'Delete';
  String get remove => 'Remove';
  String get done => 'Done';
  String get next => 'Next';
  String get back => 'Back';
  String get confirm => 'Confirm';
  String get yes => 'Yes';
  String get no => 'No';
  String get search => 'Search';
  String get somethingWentWrong => 'Something went wrong';
  String get noInternet => 'No internet connection';
  String get loading => 'Loading…';

  // ---------------------------------------------------------------------------
  // Account screen.
  // ---------------------------------------------------------------------------

  String get accountTitle => 'Account';
  String get accountMyPreferences => 'My Preferences';
  String get accountFoodDelivery => 'Food Delivery';
  String get accountMore => 'More';

  String get accountMyOrders => 'My orders';
  String get accountMyOrdersSubtitle => 'Track and reorder past orders';
  String get accountGiftOrders => 'Gift orders';
  String get accountGiftOrdersSubtitle => 'Gifts you bought, and where they are';
  String get accountMyAddresses => 'My addresses';
  String get accountMyAddressesSubtitle => 'Manage your delivery addresses';
  String get accountCollection => 'Your collection';
  String get accountCollectionSubtitle => 'Restaurants you saved';

  String get accountHelpSupport => 'Help & support';
  String get accountLegal => 'Legal & policies';
  String get accountLicenses => 'Licenses & credits';
  String get accountDesignSystem => 'Design system';
  String get accountDeleteAccount => 'Delete account';
  String get accountLogOut => 'Log out';

  /// The support dialog's body. A method rather than three concatenated
  /// getters: the address sits mid-sentence, and where mid-sentence is depends
  /// on the language.
  String accountSupportBody(String email) =>
      'Email us and a person will answer.\n\n$email\n\n'
      'If it is about an order, send the order number — it is on the order '
      'in My orders.';

  String get accountWelcome => 'Welcome to zopiqnow';
  String get accountWelcomeSubtitle =>
      'Log in to track orders and save addresses';
  String get accountLogIn => 'Log in';
  String get accountAddYourName => 'Add your name';

  String get accountVegMode => '100% Veg Mode';
  String get accountVegModeSubtitle => 'Show only vegetarian restaurants';

  String get accountAppearance => 'Appearance';
  String get accountAppearanceSubtitle => 'Light, Dark, or System';
  String get accountThemeLight => 'Light';
  String get accountThemeDark => 'Dark';
  String get accountThemeSystem => 'System';

  String get accountLanguage => 'Language';
  String get accountLanguageSubtitle => 'Choose your language';

  // ---------------------------------------------------------------------------
  // Home — the dish-category rail.
  // ---------------------------------------------------------------------------

  /// The display name of a home category, keyed by `FoodCategory.id`.
  ///
  /// **Read this before translating a category anywhere else.**
  /// `FoodCategory.label` is not a caption — it is a *matching key*.
  /// `categoryDishPoolProvider` passes it to `dishMatchesCategory`, and it
  /// reaches Postgres as an `ilike` needle besides — both compare it against
  /// dish names and menu sections **written in English**. Translate
  /// `label` and every category silently matches nothing: the page renders "No
  /// पिज़्ज़ा near you yet" for all thirty-nine of them, with no error anywhere.
  ///
  /// So the two jobs are split. `label` stays English and keeps doing the
  /// matching; this decides what the customer reads. The [englishLabel]
  /// fallback means a category added to the rail tomorrow shows up in English
  /// rather than blank until somebody translates it.
  String categoryName(String id, String englishLabel) => englishLabel;

  /// Shown when a category page has no restaurants. Takes the *display* name,
  /// not the matching key.
  String homeNoCategoryNearby(String categoryName) =>
      'No $categoryName near you yet. Try another category.';

  String get homeRecommendedForYou => 'Recommended for you';
  String get homeConnectionError =>
      'Please check your connection and try again.';
  String get homeWhatsOnYourMind => 'What\'s on your mind?';
  String get homeVegOnly => 'Veg only';
}

/// Puts the chosen [AppStrings] in the tree so `context.l10n` can find it.
///
/// Mounted once, in `MaterialApp.router`'s `builder`, which is above every
/// routed screen. Changing language swaps the instance and the framework
/// rebuilds only the widgets that actually read a string.
class AppStringsScope extends InheritedWidget {
  const AppStringsScope({
    required this.strings,
    required super.child,
    super.key,
  });

  final AppStrings strings;

  static AppStrings of(BuildContext context) {
    final AppStringsScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppStringsScope>();
    assert(scope != null, 'No AppStringsScope above this widget.');
    // Falls back to English rather than throwing. A screen reachable from a
    // route that somehow sits outside the scope should render in the wrong
    // language, not crash — this is copy, not correctness.
    return scope?.strings ?? const AppStrings();
  }

  @override
  bool updateShouldNotify(AppStringsScope oldWidget) =>
      oldWidget.strings != strings;
}

extension AppStringsContext on BuildContext {
  /// The string table for the current language. Named to match `context.zc`,
  /// the design system's colour accessor, so screens read the same way.
  AppStrings get l10n => AppStringsScope.of(this);
}
