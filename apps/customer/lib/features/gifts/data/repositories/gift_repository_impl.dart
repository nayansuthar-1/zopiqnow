import 'package:zopiqnow/features/gifts/data/datasources/gift_datasource.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';
import 'package:zopiqnow/features/gifts/domain/repositories/gift_repository.dart';

/// Default [GiftRepository]. It names the data source *interface*, so a backend
/// swap is one provider binding and nothing else.
class GiftRepositoryImpl implements GiftRepository {
  const GiftRepositoryImpl(this._dataSource);

  final GiftDataSource _dataSource;

  @override
  Future<List<GiftShop>> getShops() async {
    try {
      return await _dataSource.fetchShops();
    } on Object catch (_) {
      // Any transport/parse error becomes a domain failure — the UI never sees
      // infrastructure exceptions.
      throw const GiftLoadFailure();
    }
  }

  @override
  Future<List<GiftItem>> getItems() async {
    try {
      return await _dataSource.fetchItems();
    } on Object catch (_) {
      throw const GiftLoadFailure();
    }
  }

  @override
  Future<GiftShop> getShopById(String id) async {
    final GiftShop? found;
    try {
      found = await _dataSource.fetchShopById(id);
    } on Object catch (_) {
      throw const GiftLoadFailure();
    }
    // Thrown outside the try: a missing shop is a domain outcome, not a
    // transport failure to be relabelled.
    if (found == null) throw const GiftShopNotFound();
    return found;
  }

  @override
  Future<List<GiftItem>> getItemsByShop(String shopId) async {
    try {
      return await _dataSource.fetchItemsByShop(shopId);
    } on Object catch (_) {
      throw const GiftLoadFailure();
    }
  }
}
