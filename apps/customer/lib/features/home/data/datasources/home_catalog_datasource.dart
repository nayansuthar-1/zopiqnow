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

  /// The long tail behind "View More" — the full dish list, shown in the
  /// bottom sheet rather than the rail. Separate from [fetchCategories] on
  /// purpose: the rail is a curated thirteen, this is everything we stock art
  /// for, and the two lists are merchandised independently.
  List<FoodCategory> fetchMoreCategories() => _moreCategories;

  List<Offer> fetchOffers() => _offers;

  /// Rendered dish art, drawn at 58dp — so the files are 256px and no larger.
  ///
  /// They used to be `.svg`, which they never were: each was an `<svg>` element
  /// wrapping one 1536x1024 base64 PNG, so flutter_svg parsed XML and decoded a
  /// megapixel image to fill a circle the size of a thumbnail. 146 MB of the
  /// APK, and the slowest thing on the home screen. Swapping one is still a
  /// single edit here.
  static const String _art = 'assets/icons_zopiq';

  static const List<FoodCategory> _categories = <FoodCategory>[
    FoodCategory(id: 'sandwich', label: 'Sandwich', imageAsset: '$_art/realistic_sandwich.png'),
    FoodCategory(id: 'pizza', label: 'Pizza', imageAsset: '$_art/realistic_pizza.png'),
    FoodCategory(id: 'burger', label: 'Burger', imageAsset: '$_art/realistic_burger.png'),
    FoodCategory(id: 'momos', label: 'Momos', imageAsset: '$_art/momos_hd.png'),
    FoodCategory(id: 'pav_bhaji', label: 'Pav Bhaji', imageAsset: '$_art/pav_bhaji_plate.png'),
    FoodCategory(id: 'dosa', label: 'Dosa', imageAsset: '$_art/dosa_hd.png'),
    FoodCategory(id: 'aloo_paratha', label: 'Aloo Paratha', imageAsset: '$_art/realistic_aloo_paratha.png'),
    FoodCategory(id: 'paneer_tikka', label: 'Paneer Tikka', imageAsset: '$_art/paneer_tikka_hd.png'),
    FoodCategory(id: 'paneer_sabji', label: 'Paneer Sabji', imageAsset: '$_art/paneer_sabji_1.png'),
    FoodCategory(id: 'icecream', label: 'Ice Cream', imageAsset: '$_art/ice_cream_sundae_2.png'),
    FoodCategory(id: 'sweet_box', label: 'Sweet Box', imageAsset: '$_art/mix_sweet_box.png'),
    FoodCategory(id: 'chocolate_cake', label: 'Cake', imageAsset: '$_art/chocolate_cake_2.png'),
    FoodCategory(id: 'cold_coffee', label: 'Cold Coffee', imageAsset: '$_art/cold_coffee_hd.png'),
    FoodCategory(id: 'view_more', label: 'View More', imageAsset: null),
  ];

  /// Photographic dish art, unlike the rail's flat illustrations — square
  /// frames with their own backdrop, so they are drawn cropped to a disc.
  static const String _photos = 'assets/icons-2.0';

  static const List<FoodCategory> _moreCategories = <FoodCategory>[
    FoodCategory(id: 'north_indian', label: 'North Indian', imageAsset: '$_photos/north-indian.PNG'),
    FoodCategory(id: 'south_indian', label: 'South Indian', imageAsset: '$_photos/south-indian.PNG'),
    FoodCategory(id: 'chinese', label: 'Chinese', imageAsset: '$_photos/chinese.PNG'),
    FoodCategory(id: 'thali', label: 'Thali', imageAsset: '$_photos/Thali.PNG'),
    FoodCategory(id: 'chole_bhature', label: 'Chole Bhature', imageAsset: '$_photos/chole-bhature.PNG'),
    FoodCategory(id: 'chicken_curry', label: 'Chicken Curry', imageAsset: '$_photos/chicken-curry.PNG', isVeg: false),
    FoodCategory(id: 'chicken_tikka', label: 'Chicken Tikka', imageAsset: '$_photos/IMG_7529.PNG', isVeg: false),
    FoodCategory(id: 'mutton', label: 'Mutton', imageAsset: '$_photos/Mutton.PNG', isVeg: false),
    FoodCategory(id: 'egg_curry', label: 'Egg Curry', imageAsset: '$_photos/egg-curry.PNG', isVeg: false),
    FoodCategory(id: 'chilli_paneer', label: 'Chilli Paneer', imageAsset: '$_photos/chilli-paneer.PNG'),
    FoodCategory(id: 'manchurian', label: 'Manchurian', imageAsset: '$_photos/manchurian.PNG'),
    FoodCategory(id: 'pulao', label: 'Pulao', imageAsset: '$_photos/pulao.PNG'),
    FoodCategory(id: 'rice', label: 'Rice', imageAsset: '$_photos/rice.PNG'),
    FoodCategory(id: 'paratha', label: 'Paratha', imageAsset: '$_photos/paratha.PNG'),
    FoodCategory(id: 'vada', label: 'Vada', imageAsset: '$_photos/vada.PNG'),
    FoodCategory(id: 'vadapav', label: 'Vada Pav', imageAsset: '$_photos/vadapav.PNG'),
    FoodCategory(id: 'samosa', label: 'Samosa', imageAsset: '$_photos/samosa.PNG'),
    FoodCategory(id: 'pakode', label: 'Pakode', imageAsset: '$_photos/pakode.PNG'),
    FoodCategory(id: 'maggi', label: 'Maggi', imageAsset: '$_photos/maggi.PNG'),
    FoodCategory(id: 'pasta', label: 'Pasta', imageAsset: '$_photos/pasta.PNG'),
    FoodCategory(id: 'white_sauce_pasta', label: 'White Sauce Pasta', imageAsset: '$_photos/white-sauce-pasta.PNG'),
    FoodCategory(id: 'fries', label: 'Fries', imageAsset: '$_photos/fries.PNG'),
    FoodCategory(id: 'waffle', label: 'Waffle', imageAsset: '$_photos/waffle.PNG'),
    FoodCategory(id: 'shake', label: 'Shake', imageAsset: '$_photos/shake.PNG'),
    FoodCategory(id: 'lassi', label: 'Lassi', imageAsset: '$_photos/lassi.PNG'),
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
