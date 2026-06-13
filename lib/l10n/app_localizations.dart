import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Qahwa TV'**
  String get appTitle;

  /// No description provided for @bottomNav_home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get bottomNav_home;

  /// No description provided for @bottomNav_recommend.
  ///
  /// In en, this message translates to:
  /// **'Recommend'**
  String get bottomNav_recommend;

  /// No description provided for @bottomNav_explore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get bottomNav_explore;

  /// No description provided for @bottomNav_games.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get bottomNav_games;

  /// No description provided for @bottomNav_profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get bottomNav_profile;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @explore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get explore;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search dramas...'**
  String get searchHint;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @logoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get logoutConfirm;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get welcomeBack;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// No description provided for @continueAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Continue as Guest'**
  String get continueAsGuest;

  /// No description provided for @continueWatching.
  ///
  /// In en, this message translates to:
  /// **'Continue Watching'**
  String get continueWatching;

  /// No description provided for @trending.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get trending;

  /// No description provided for @newReleases.
  ///
  /// In en, this message translates to:
  /// **'New Releases'**
  String get newReleases;

  /// No description provided for @recommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get recommended;

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// No description provided for @drama.
  ///
  /// In en, this message translates to:
  /// **'Drama'**
  String get drama;

  /// No description provided for @episode.
  ///
  /// In en, this message translates to:
  /// **'Episode'**
  String get episode;

  /// No description provided for @episodes.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get episodes;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @season.
  ///
  /// In en, this message translates to:
  /// **'Season'**
  String get season;

  /// No description provided for @seasons.
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get seasons;

  /// No description provided for @rating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get rating;

  /// No description provided for @reviews.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get reviews;

  /// No description provided for @topRecommend.
  ///
  /// In en, this message translates to:
  /// **'Top Recommend'**
  String get topRecommend;

  /// No description provided for @newForThisMonth.
  ///
  /// In en, this message translates to:
  /// **'New For This Month'**
  String get newForThisMonth;

  /// No description provided for @allRecommended.
  ///
  /// In en, this message translates to:
  /// **'All Recommended'**
  String get allRecommended;

  /// No description provided for @vipZone.
  ///
  /// In en, this message translates to:
  /// **'VIP Zone'**
  String get vipZone;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAll;

  /// No description provided for @seeMore.
  ///
  /// In en, this message translates to:
  /// **'See More'**
  String get seeMore;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'My Favorites'**
  String get favorites;

  /// No description provided for @watchHistory.
  ///
  /// In en, this message translates to:
  /// **'Watch History'**
  String get watchHistory;

  /// No description provided for @downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloads;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get lightMode;

  /// No description provided for @subscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get subscription;

  /// No description provided for @premium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get premium;

  /// No description provided for @buyCoins.
  ///
  /// In en, this message translates to:
  /// **'Buy Coins'**
  String get buyCoins;

  /// No description provided for @paymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get paymentMethod;

  /// No description provided for @vipMembership.
  ///
  /// In en, this message translates to:
  /// **'VIP Membership'**
  String get vipMembership;

  /// No description provided for @vipMember.
  ///
  /// In en, this message translates to:
  /// **'VIP Member'**
  String get vipMember;

  /// No description provided for @vipSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock all series with one tap'**
  String get vipSubtitle;

  /// No description provided for @subscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get subscribe;

  /// No description provided for @activate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get activate;

  /// No description provided for @monthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get monthly;

  /// No description provided for @yearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get yearly;

  /// No description provided for @games.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get games;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @like.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get like;

  /// No description provided for @comment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get comment;

  /// No description provided for @watch.
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get watch;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResults;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Network error. Please check your connection.'**
  String get networkError;

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'An unknown error occurred'**
  String get unknownError;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get requiredField;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get invalidEmail;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get passwordTooShort;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @underDevelopment.
  ///
  /// In en, this message translates to:
  /// **'Under Development'**
  String get underDevelopment;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon, stay tuned!'**
  String get comingSoon;

  /// No description provided for @noDataAvailableAtTheMoment.
  ///
  /// In en, this message translates to:
  /// **'No data available at the moment'**
  String get noDataAvailableAtTheMoment;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @nickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nickname;

  /// No description provided for @feedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback & Suggestions'**
  String get feedback;

  /// No description provided for @aboutUs.
  ///
  /// In en, this message translates to:
  /// **'About Us'**
  String get aboutUs;

  /// No description provided for @loginToAccess.
  ///
  /// In en, this message translates to:
  /// **'Login to Access Your Profile'**
  String get loginToAccess;

  /// No description provided for @loginDescription.
  ///
  /// In en, this message translates to:
  /// **'Sign in to view your profile, favorites, and more'**
  String get loginDescription;

  /// No description provided for @loginNow.
  ///
  /// In en, this message translates to:
  /// **'Login Now'**
  String get loginNow;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get clearHistory;

  /// No description provided for @clearHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all watch history?'**
  String get clearHistoryConfirm;

  /// No description provided for @noHistory.
  ///
  /// In en, this message translates to:
  /// **'No watch history yet'**
  String get noHistory;

  /// No description provided for @removeFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from Favorites'**
  String get removeFromFavorites;

  /// No description provided for @removeFromFavoritesConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove this from favorites?'**
  String get removeFromFavoritesConfirm;

  /// No description provided for @removedFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get removedFromFavorites;

  /// No description provided for @noFavorites.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get noFavorites;

  /// No description provided for @addFavoritesHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the heart icon on dramas to add them here'**
  String get addFavoritesHint;

  /// No description provided for @appDescription.
  ///
  /// In en, this message translates to:
  /// **'Your premium destination for short dramas. Watch the best series and exclusive content anytime, anywhere.'**
  String get appDescription;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @contactUs.
  ///
  /// In en, this message translates to:
  /// **'Contact Us'**
  String get contactUs;

  /// No description provided for @rateApp.
  ///
  /// In en, this message translates to:
  /// **'Rate Our App'**
  String get rateApp;

  /// No description provided for @followUs.
  ///
  /// In en, this message translates to:
  /// **'Follow Us'**
  String get followUs;

  /// No description provided for @openVip.
  ///
  /// In en, this message translates to:
  /// **'Open VIP'**
  String get openVip;

  /// No description provided for @userAgreement.
  ///
  /// In en, this message translates to:
  /// **'User Agreement'**
  String get userAgreement;

  /// No description provided for @userRechargeAgreement.
  ///
  /// In en, this message translates to:
  /// **'User Recharge Agreement'**
  String get userRechargeAgreement;

  /// No description provided for @messageSettings.
  ///
  /// In en, this message translates to:
  /// **'Message Settings'**
  String get messageSettings;

  /// No description provided for @notificationsOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get notificationsOff;

  /// No description provided for @notificationsOffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off all push notifications.'**
  String get notificationsOffSubtitle;

  /// No description provided for @notificationsImportant.
  ///
  /// In en, this message translates to:
  /// **'Important only'**
  String get notificationsImportant;

  /// No description provided for @notificationsImportantSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Receive important alerts and account-related updates.'**
  String get notificationsImportantSubtitle;

  /// No description provided for @notificationsAll.
  ///
  /// In en, this message translates to:
  /// **'All messages'**
  String get notificationsAll;

  /// No description provided for @notificationsAllSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Receive all notifications including updates and promotions.'**
  String get notificationsAllSubtitle;

  /// No description provided for @versionNumber.
  ///
  /// In en, this message translates to:
  /// **'Version Number'**
  String get versionNumber;

  /// No description provided for @copyrightLabel.
  ///
  /// In en, this message translates to:
  /// **'Copyright:'**
  String get copyrightLabel;

  /// No description provided for @copyrightLicense.
  ///
  /// In en, this message translates to:
  /// **'Text licensed under OFL.'**
  String get copyrightLicense;

  /// No description provided for @copyrightNotice.
  ///
  /// In en, this message translates to:
  /// **'All images and videos are licensed and do not infringe on third-party rights.'**
  String get copyrightNotice;

  /// No description provided for @noContentAvailable.
  ///
  /// In en, this message translates to:
  /// **'No content available'**
  String get noContentAvailable;

  /// No description provided for @failedToLoadContent.
  ///
  /// In en, this message translates to:
  /// **'Failed to load content'**
  String get failedToLoadContent;

  /// No description provided for @login_title.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get login_title;

  /// No description provided for @login_email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get login_email;

  /// No description provided for @login_password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get login_password;

  /// No description provided for @login_button.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get login_button;

  /// No description provided for @login_forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get login_forgotPassword;

  /// No description provided for @login_google.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get login_google;

  /// No description provided for @login_apple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get login_apple;

  /// No description provided for @login_noAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get login_noAccount;

  /// No description provided for @login_signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get login_signUp;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Login to unlock more features'**
  String get loginSubtitle;

  /// No description provided for @register_title.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get register_title;

  /// No description provided for @register_username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get register_username;

  /// No description provided for @register_confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get register_confirmPassword;

  /// No description provided for @register_button.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get register_button;

  /// No description provided for @register_haveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get register_haveAccount;

  /// No description provided for @register_login.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get register_login;

  /// No description provided for @membership_title.
  ///
  /// In en, this message translates to:
  /// **'Unlock Premium'**
  String get membership_title;

  /// No description provided for @membership_monthly.
  ///
  /// In en, this message translates to:
  /// **'VIP Monthly Card'**
  String get membership_monthly;

  /// No description provided for @membership_quarterly.
  ///
  /// In en, this message translates to:
  /// **'VIP Season Pass'**
  String get membership_quarterly;

  /// No description provided for @membership_yearly.
  ///
  /// In en, this message translates to:
  /// **'VIP Annual'**
  String get membership_yearly;

  /// No description provided for @membership_subscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe Now'**
  String get membership_subscribe;

  /// No description provided for @membership_restore.
  ///
  /// In en, this message translates to:
  /// **'Restore Purchase'**
  String get membership_restore;

  /// No description provided for @membership_benefit_adFree.
  ///
  /// In en, this message translates to:
  /// **'Ad-free experience'**
  String get membership_benefit_adFree;

  /// No description provided for @membership_benefit_exclusive.
  ///
  /// In en, this message translates to:
  /// **'Exclusive dramas'**
  String get membership_benefit_exclusive;

  /// No description provided for @membership_benefit_hd.
  ///
  /// In en, this message translates to:
  /// **'HD quality'**
  String get membership_benefit_hd;

  /// No description provided for @membership_benefit_early.
  ///
  /// In en, this message translates to:
  /// **'Early access'**
  String get membership_benefit_early;

  /// No description provided for @membership_benefits_title.
  ///
  /// In en, this message translates to:
  /// **'Member Benefits'**
  String get membership_benefits_title;

  /// No description provided for @membership_benefits_complaint.
  ///
  /// In en, this message translates to:
  /// **'Complaint and Report'**
  String get membership_benefits_complaint;

  /// No description provided for @membership_benefits_unlockEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Unlock all VIP episodes'**
  String get membership_benefits_unlockEpisodes;

  /// No description provided for @membership_benefits_watchHd.
  ///
  /// In en, this message translates to:
  /// **'Watch in 1080p/1440p HD'**
  String get membership_benefits_watchHd;

  /// No description provided for @membership_benefits_singleDevice.
  ///
  /// In en, this message translates to:
  /// **'Only 1 device can be logged in at the same time'**
  String get membership_benefits_singleDevice;

  /// No description provided for @membership_benefits_tipsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tips'**
  String get membership_benefits_tipsLabel;

  /// No description provided for @membership_benefits_tipContent.
  ///
  /// In en, this message translates to:
  /// **'During the subscription period, you can access all VIP series unlimited times.'**
  String get membership_benefits_tipContent;

  /// No description provided for @logoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logoutTitle;

  /// No description provided for @subscriptionConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Subscription'**
  String get subscriptionConfirmTitle;

  /// No description provided for @loginRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Login Required'**
  String get loginRequiredTitle;

  /// No description provided for @vipRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'VIP Required'**
  String get vipRequiredTitle;

  /// No description provided for @quality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get quality;

  /// No description provided for @selectQuality.
  ///
  /// In en, this message translates to:
  /// **'Select Quality'**
  String get selectQuality;

  /// No description provided for @qualityStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard quality'**
  String get qualityStandard;

  /// No description provided for @qualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High quality'**
  String get qualityHigh;

  /// No description provided for @qualityFullHd.
  ///
  /// In en, this message translates to:
  /// **'Full HD'**
  String get qualityFullHd;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @subscriptionSetupGuide.
  ///
  /// In en, this message translates to:
  /// **'Subscription Setup Guide'**
  String get subscriptionSetupGuide;

  /// No description provided for @googlePlay.
  ///
  /// In en, this message translates to:
  /// **'Google Play'**
  String get googlePlay;

  /// No description provided for @appStore.
  ///
  /// In en, this message translates to:
  /// **'App Store'**
  String get appStore;

  /// No description provided for @backend.
  ///
  /// In en, this message translates to:
  /// **'Backend'**
  String get backend;

  /// No description provided for @errors.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get errors;

  /// No description provided for @gamesRoundEnd.
  ///
  /// In en, this message translates to:
  /// **'Round Complete'**
  String get gamesRoundEnd;

  /// No description provided for @gamesBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get gamesBack;

  /// No description provided for @gamesPlayAgain.
  ///
  /// In en, this message translates to:
  /// **'Play Again'**
  String get gamesPlayAgain;

  /// No description provided for @gamesWinTitle.
  ///
  /// In en, this message translates to:
  /// **'You Win!'**
  String get gamesWinTitle;

  /// No description provided for @gamesCompletionTime.
  ///
  /// In en, this message translates to:
  /// **'Completion Time'**
  String get gamesCompletionTime;

  /// No description provided for @gamesRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get gamesRestart;

  /// No description provided for @gamesDailySignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily Sign-in'**
  String get gamesDailySignInTitle;

  /// No description provided for @forgotPasswordSendEmail.
  ///
  /// In en, this message translates to:
  /// **'Send Reset Email'**
  String get forgotPasswordSendEmail;

  /// No description provided for @forgotPasswordEmailSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Email Sent!'**
  String get forgotPasswordEmailSentTitle;

  /// No description provided for @playerVipContent.
  ///
  /// In en, this message translates to:
  /// **'VIP Content'**
  String get playerVipContent;

  /// No description provided for @vipSubscribeNow.
  ///
  /// In en, this message translates to:
  /// **'Subscribe Now'**
  String get vipSubscribeNow;

  /// No description provided for @membershipLoginBeforeSubscribe.
  ///
  /// In en, this message translates to:
  /// **'Please log in before subscribing.'**
  String get membershipLoginBeforeSubscribe;

  /// No description provided for @membershipWebPurchaseUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Web does not support Google Play in-app purchases.'**
  String get membershipWebPurchaseUnsupported;

  /// No description provided for @membershipPurchaseOpened.
  ///
  /// In en, this message translates to:
  /// **'Google Play opened. Please complete the subscription payment.'**
  String get membershipPurchaseOpened;

  /// No description provided for @membershipItemAlreadyOwned.
  ///
  /// In en, this message translates to:
  /// **'You already own this subscription.'**
  String get membershipItemAlreadyOwned;

  /// No description provided for @watchLockedReminderTitle.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get watchLockedReminderTitle;

  /// No description provided for @watchLockedReminderMessage.
  ///
  /// In en, this message translates to:
  /// **'About to jump to activate membership'**
  String get watchLockedReminderMessage;

  /// No description provided for @profileLoginFirst.
  ///
  /// In en, this message translates to:
  /// **'Please log in first'**
  String get profileLoginFirst;

  /// No description provided for @accountDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Account deleted successfully'**
  String get accountDeletedSuccessfully;

  /// No description provided for @dailySigninRewardHint.
  ///
  /// In en, this message translates to:
  /// **'Get one VIP day after signing in for 7 consecutive days'**
  String get dailySigninRewardHint;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @player_loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get player_loading;

  /// No description provided for @player_error.
  ///
  /// In en, this message translates to:
  /// **'Playback error'**
  String get player_error;

  /// No description provided for @player_retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get player_retry;

  /// No description provided for @profile_edit.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get profile_edit;

  /// No description provided for @profile_member.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get profile_member;

  /// No description provided for @profile_notMember.
  ///
  /// In en, this message translates to:
  /// **'Not a member'**
  String get profile_notMember;

  /// No description provided for @profile_upgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get profile_upgrade;

  /// No description provided for @profile_history.
  ///
  /// In en, this message translates to:
  /// **'Watch History'**
  String get profile_history;

  /// No description provided for @profile_favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get profile_favorites;

  /// No description provided for @profile_language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get profile_language;

  /// No description provided for @changeLanguage.
  ///
  /// In en, this message translates to:
  /// **'Change Language'**
  String get changeLanguage;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose Language'**
  String get chooseLanguage;

  /// No description provided for @profile_feedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get profile_feedback;

  /// No description provided for @profile_about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get profile_about;

  /// No description provided for @profile_logout.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get profile_logout;

  /// No description provided for @games_guessLine.
  ///
  /// In en, this message translates to:
  /// **'Guess the Line'**
  String get games_guessLine;

  /// No description provided for @games_matching.
  ///
  /// In en, this message translates to:
  /// **'Matching Game'**
  String get games_matching;

  /// No description provided for @games_dailySign.
  ///
  /// In en, this message translates to:
  /// **'Daily Sign-in'**
  String get games_dailySign;

  /// No description provided for @common_loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get common_loading;

  /// No description provided for @common_retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get common_retry;

  /// No description provided for @common_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get common_cancel;

  /// No description provided for @common_confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get common_confirm;

  /// No description provided for @common_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get common_save;

  /// No description provided for @common_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get common_delete;

  /// No description provided for @common_search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get common_search;

  /// No description provided for @error_network.
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get error_network;

  /// No description provided for @error_server.
  ///
  /// In en, this message translates to:
  /// **'Server error'**
  String get error_server;

  /// No description provided for @error_auth.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed'**
  String get error_auth;

  /// No description provided for @recommend.
  ///
  /// In en, this message translates to:
  /// **'Recommend'**
  String get recommend;

  /// No description provided for @hot.
  ///
  /// In en, this message translates to:
  /// **'Hot'**
  String get hot;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
