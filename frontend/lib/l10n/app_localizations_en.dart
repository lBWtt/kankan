// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Kankan';

  @override
  String get discoverTab => 'Discover';

  @override
  String get kankanTab => 'Kankan';

  @override
  String get libraryTab => 'Library';

  @override
  String get meTab => 'Me';

  @override
  String get publish => 'Publish';

  @override
  String get search => 'Search';

  @override
  String get save => 'Save';

  @override
  String get like => 'Like';

  @override
  String get comment => 'Comment';

  @override
  String get share => 'Share';

  @override
  String get follow => 'Follow';

  @override
  String get unfollow => 'Following';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get retry => 'Retry';

  @override
  String get ranking => 'Rankings';

  @override
  String get emptyFeed => 'Nothing here yet';

  @override
  String get emptyGeneric => 'Nothing found';

  @override
  String get emptySearch => 'No results found';

  @override
  String get loadFailed => 'Failed to load';

  @override
  String get connectFailed => 'Cannot reach server';

  @override
  String projectSemantic(Object title) {
    return 'Project: $title';
  }

  @override
  String postSemantic(Object author) {
    return 'Post: $author';
  }
}
