import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/categories_repository.dart';
import '../domain/category_set.dart';
import '../domain/user_category.dart';

/// Providers for user-editable categories.

final Provider<CategoriesRepository?> categoriesRepositoryProvider =
    Provider<CategoriesRepository?>((Ref ref) {
      final User? user = ref.watch(currentUserProvider);
      if (user == null) return null;
      return CategoriesRepository(uid: user.uid);
    });

final StreamProvider<List<UserCategory>> categoriesStreamProvider =
    StreamProvider<List<UserCategory>>((Ref ref) {
      final CategoriesRepository? repository = ref.watch(
        categoriesRepositoryProvider,
      );
      if (repository == null) return const Stream<List<UserCategory>>.empty();
      return repository.watchAll();
    });

/// The categories a form should offer for [kind].
///
/// **Never in a loading state.** While the stream is still connecting — which
/// on a cold start is the moment a form is most likely to be opened — this
/// falls back to the built-in defaults rather than to an empty list. A picker
/// that is briefly empty is a picker the user taps and finds broken; showing
/// the defaults for a few hundred milliseconds and then the stored list is
/// invisible, because on an unedited install they are the same list.
final Provider<CategorySet> Function(CategoryKind) categorySetProvider =
    Provider.family<CategorySet, CategoryKind>((Ref ref, CategoryKind kind) {
      final List<UserCategory>? stored = ref
          .watch(categoriesStreamProvider)
          .asData
          ?.value;
      if (stored == null) return CategorySet.defaults(kind);
      return CategorySet.resolve(kind, stored);
    });

/// Whether [kind] has been written down yet.
///
/// The editor uses this to decide whether it needs to seed before it can offer
/// anything to edit.
final Provider<bool> Function(CategoryKind) categoriesAreSeededProvider =
    Provider.family<bool, CategoryKind>((Ref ref, CategoryKind kind) {
      final List<UserCategory>? stored = ref
          .watch(categoriesStreamProvider)
          .asData
          ?.value;
      if (stored == null) return false;
      return stored.any((UserCategory c) => c.kind == kind);
    });
