import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/home/domain/entities/hero_slide.dart';

/// The campaign slides for the Home hero: `public.hero_slides` over PostgREST.
///
/// No repository and no abstract data source behind it, unlike `restaurants`.
/// That seam exists so tests can inject latency and failure into the feed; the
/// hero has no failure state to inject — an error here is an empty list and the
/// carousel falls back to the art it ships with.
///
/// There is no `is_active`, `starts_at` or `ends_at` filter in the query below
/// and there must not be. Migration 0053's read policy applies all three, so a
/// scheduled campaign is *unreadable* rather than merely unrendered — a client
/// filter would ship next week's slide to every phone a week early.
class HeroSlideDataSource {
  const HeroSlideDataSource();

  /// Resolved per call, for the same reason `RestaurantSupabaseDataSource` does
  /// it: `Supabase.instance` only exists after `initialize` in `main`.
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<HeroSlide>> fetchLive() async {
    final List<Map<String, dynamic>> rows = await _db
        .from('hero_slides')
        .select(
          'id, title, subtitle, cta_label, cta_target, image_url, motion_url',
        )
        // Explicitly ascending — postgrest-dart's `order()` defaults to
        // descending, which would run the carousel backwards.
        .order('sort_order', ascending: true)
        // The tie-break, so two slides sharing a position keep a stable order
        // between builds instead of swapping places at random.
        .order('created_at', ascending: true);

    return rows.map(_fromRow).toList(growable: false);
  }
}

HeroSlide _fromRow(Map<String, dynamic> row) => HeroSlide(
  id: row['id'] as String,
  title: row['title'] as String,
  subtitle: (row['subtitle'] as String?) ?? '',
  ctaLabel: (row['cta_label'] as String?) ?? 'Order now',
  imageUrl: row['image_url'] as String,
  motionUrl: row['motion_url'] as String?,
  ctaTarget: row['cta_target'] as String?,
);
