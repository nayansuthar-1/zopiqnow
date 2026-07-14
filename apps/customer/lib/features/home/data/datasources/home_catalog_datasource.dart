import 'package:zopiqnow/features/home/domain/entities/food_category.dart';
import 'package:zopiqnow/features/home/domain/entities/offer.dart';

/// Static Home merchandising content: the dish-category rail and the offers
/// carousel.
///
/// Deliberately synchronous. Unlike the restaurant feed these are small,
/// slow-changing lists that Swiggy renders immediately — modelling them as
/// futures would buy nothing but a shimmer nobody sees. When they move behind
/// the API, this class grows the `async` and the providers become FutureProviders.
class HomeCatalogDataSource {
  const HomeCatalogDataSource();

  List<FoodCategory> fetchCategories() => _categories;

  List<Offer> fetchOffers() => _offers;

  /// Artwork is Microsoft Fluent Emoji (3D) — MIT licensed, free to ship. See
  /// ATTRIBUTIONS.md. Each category maps to its closest food emoji; these are
  /// stand-ins for commissioned renders, and swapping one is a single edit here.
  static const String _art = 'assets/icons_zopiq';

  static const List<FoodCategory> _categories = <FoodCategory>[
    FoodCategory(id: 'sandwich', label: 'Sandwich', imageAsset: '$_art/realistic_sandwich.svg'),
    FoodCategory(id: 'pizza', label: 'Pizza', imageAsset: '$_art/realistic_pizza.svg'),
    FoodCategory(id: 'burger', label: 'Burger', imageAsset: '$_art/realistic_burger.svg'),
    FoodCategory(id: 'momos', label: 'Momos', imageAsset: '$_art/momos_hd.svg'),
    FoodCategory(id: 'pav_bhaji', label: 'Pav Bhaji', imageAsset: '$_art/pav_bhaji_plate.svg'),
    FoodCategory(id: 'dosa', label: 'Dosa', imageAsset: '$_art/dosa_hd.svg'),
    FoodCategory(id: 'aloo_paratha', label: 'Aloo Paratha', imageAsset: '$_art/realistic_aloo_paratha.svg'),
    FoodCategory(id: 'paneer_tikka', label: 'Paneer Tikka', imageAsset: '$_art/paneer_tikka_hd.svg'),
    FoodCategory(id: 'paneer_sabji', label: 'Paneer Sabji', imageAsset: '$_art/paneer_sabji_1.svg'),
    FoodCategory(id: 'icecream', label: 'Ice Cream', imageAsset: '$_art/ice_cream_sundae_2.svg'),
    FoodCategory(id: 'sweet_box', label: 'Sweet Box', imageAsset: '$_art/mix_sweet_box.svg'),
    FoodCategory(id: 'chocolate_cake', label: 'Cake', imageAsset: '$_art/chocolate_cake_2.svg'),
    FoodCategory(id: 'cold_coffee', label: 'Cold Coffee', imageAsset: '$_art/cold_coffee_hd.svg'),
    FoodCategory(id: 'view_more', label: 'View More', imageAsset: null),
  ];

  static const List<Offer> _offers = <Offer>[
    Offer(id: 'o1', headline: '60% OFF', detail: 'UPTO ₹120', code: 'TRYNEW'),
    Offer(
      id: 'o2',
      headline: 'FLAT ₹150 OFF',
      detail: 'ABOVE ₹399',
      code: 'ZOPIQ150',
    ),
    Offer(
      id: 'o3',
      headline: 'FREE DELIVERY',
      detail: 'ON FIRST ORDER',
      code: 'WELCOME',
    ),
    Offer(id: 'o4', headline: '30% OFF', detail: 'UPTO ₹75', code: 'SAVE30'),
  ];
}
