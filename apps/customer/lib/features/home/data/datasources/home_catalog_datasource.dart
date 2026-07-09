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

  /// `imageAsset` is null throughout: the rail renders generated placeholder art
  /// until licensed illustrations are supplied. See [FoodCategory.imageAsset].
  static const List<FoodCategory> _categories = <FoodCategory>[
    FoodCategory(id: 'biryani', label: 'Biryani'),
    FoodCategory(id: 'pizza', label: 'Pizza'),
    FoodCategory(id: 'burger', label: 'Burger'),
    FoodCategory(id: 'rolls', label: 'Rolls'),
    FoodCategory(id: 'north_indian', label: 'North Indian'),
    FoodCategory(id: 'chinese', label: 'Chinese'),
    FoodCategory(id: 'dosa', label: 'Dosa'),
    FoodCategory(id: 'idli', label: 'Idli'),
    FoodCategory(id: 'momos', label: 'Momos'),
    FoodCategory(id: 'cake', label: 'Cake'),
    FoodCategory(id: 'ice_cream', label: 'Ice Cream'),
    FoodCategory(id: 'noodles', label: 'Noodles'),
    FoodCategory(id: 'shawarma', label: 'Shawarma'),
    FoodCategory(id: 'paratha', label: 'Paratha'),
    FoodCategory(id: 'chaat', label: 'Chaat'),
    FoodCategory(id: 'pure_veg', label: 'Pure Veg'),
  ];

  static const List<Offer> _offers = <Offer>[
    Offer(
      id: 'o1',
      headline: '60% OFF',
      detail: 'UPTO ₹120',
      code: 'TRYNEW',
    ),
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
    Offer(
      id: 'o4',
      headline: '30% OFF',
      detail: 'UPTO ₹75',
      code: 'SAVE30',
    ),
  ];
}
