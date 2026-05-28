import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Configuration guide for setting up subscriptions in Google Play Console and App Store Connect
class SubscriptionConfigGuide {
  static const String _googlePlayGuide = '''
# Google Play Console Configuration

## Step 1: Create App
1. Go to Google Play Console: https://play.google.com/console
2. Click "Create App"
3. Fill in:
   - App name: Arabic Drama
   - Default language: English
   - App type: App
   - Free/Paid: Free
4. Click "Create App"

## Step 2: Set Up Store Listing
1. Navigate to "Store presence" > "Main store listing"
2. Fill in:
   - App title
   - Short description (80 characters)
   - Full description
   - Screenshots (phone, tablet)
   - App icon (512x512)
   - Feature graphic (1024x500)
3. Set "Content rating" > "Complete questionnaire"
4. Set "Privacy policy" URL

## Step 3: Configure Pricing
1. Go to "Monetize" > "Monetization"
2. Set "Free" or "Paid"
3. For subscriptions, set "Default price" for reference

## Step 4: Create Subscription Products
1. Go to "Monetize" > "Products" > "Subscriptions"
2. Click "Create subscription"
3. Fill in:
   - **Subscription ID**: com.arabdrama.vip.monthly
     (Use: com.arabdrama.vip.quarterly, com.arabdrama.vip.yearly)
   - Name: VIP Monthly (etc.)
   - Description: Full access to all dramas
   - Period: Monthly/Quarterly/Yearly
   - Price: Set price per region
   - Billing cycle: Auto-renewing
4. Click "Save"

## Step 5: Configure Base Plans
1. Select your subscription
2. Go to "Base plans"
3. Click "Add base plan"
4. Set:
   - **Base plan ID**: monthly_basic
   - Pricing: Set regional prices
   - Grace period: 3 days (recommended)
   - Account hold: 30 days
   - Account linkage: Enable for sharing within family
5. Click "Activate"

## Step 6: Add Offer (Optional - for first-time discounts)
1. Go to "Offers" within the base plan
2. Click "Create offer"
3. Set:
   - **Offer ID**: trial_7days
   - Type: Free trial
   - Duration: 7 days
   - Billing cycle: After trial ends
4. Click "Activate"

## Step 7: Testing Setup
1. Go to "Settings" > "License testing"
2. Add test Gmail accounts
3. Use: opt-in URL for testing
   https://play.google.com/testing/com.arabdrama.vip.monthly

## Step 8: Internal Testing (Before Production)
1. Create internal testing track
2. Upload AAB file
3. Add testers
4. Test purchase flow

## Product IDs to Create:
- com.arabdrama.vip.monthly
- com.arabdrama.vip.quarterly
- com.arabdrama.vip.yearly
''';

  static const String _appStoreGuide = '''
# App Store Connect Configuration

## Step 1: Create App
1. Go to App Store Connect: https://appstoreconnect.apple.com
2. Click "My Apps" > "+" > "New App"
3. Fill in:
   - Platforms: iOS
   - Name: Arabic Drama
   - Primary language: English
   - Bundle ID: com.arabdrama.app
   - SKU: arabdrama001
4. Click "Create"

## Step 2: Set Up App Information
1. Navigate to your app
2. Fill in:
   - App privacy (required!)
   - Age rating
   - App Store screenshots
   - Description, keywords, support URL
3. Upload app icon (1024x1024)

## Step 3: Create Subscriptions
1. Go to "In-App Purchases"
2. Click "+" to create new
3. Select "Subscription" type
4. Fill in:
   - **Reference Name**: VIP Monthly
   - **Product ID**: com.arabdrama.vip.monthly
   - Type: Auto-Renewable Subscription
5. Click "Create"

## Step 4: Configure Subscription Details
1. Select your subscription
2. Set:
   - **Subscription Duration**: 1 Month
   - **Pricing**: Set prices per territory
   - **Review notes**: Describe your content

## Step 5: Create Multiple Subscriptions
Create for each tier:
- com.arabdrama.vip.monthly (1 Month)
- com.arabdrama.vip.quarterly (3 Months)
- com.arabdrama.vip.yearly (1 Year)

## Step 6: Set Up Subscription Group
1. Go to "Subscription Group" > "+"
2. Name: "VIP Subscription"
3. Add all subscription tiers
4. Set ranking order (highest tier first)

## Step 7: Add Introductory Offers
1. Select subscription
2. Go to "Introductory Offers"
3. Create offers:
   - Free trial (7 days)
   - Pay as you go
   - Pay up front
4. Set eligibility requirements

## Step 8: Configure App-Specific Shared Secret
1. Go to "App Store Connect" > "Users and Access"
2. Click "Subscriptions" tab
3. Generate shared secret
4. Use this in your backend for receipt validation

## Step 9: Set Up Sandbox Testing
1. Create sandbox Apple ID
2. Go to "Users and Access" > "Sandbox"
3. Add test accounts
4. Test in sandbox environment

## Step 10: Submit for Review
1. Complete all app information
2. Add demo account if required
3. Submit for review
4. Review typically takes 24-48 hours

## Product IDs to Create:
- com.arabdrama.vip.monthly
- com.arabdrama.vip.quarterly
- com.arabdrama.vip.yearly
''';

  static const String _backendGuide = '''
# Backend Requirements

Your backend MUST implement these endpoints for subscription management:

## 1. Receipt Verification Endpoint
POST /api/v1/subscriptions/verify

Request:
{
  "receipt": {
    "purchase_id": "...",
    "product_id": "com.arabdrama.vip.monthly",
    "status": "purchased",
    "transaction_date": "2024-01-01T00:00:00Z",
    "data": "...",
    "server_verification_data": "..."
  },
  "platform": "google_play" | "app_store",
  "user_id": "user_123"
}

Response:
{
  "success": true,
  "is_valid": true,
  "expire_date": "2024-02-01T00:00:00Z",
  "subscription_type": "monthly"
}

## 2. Subscription Status Endpoint
GET /api/v1/subscriptions/status?user_id=xxx

Response:
{
  "is_active": true,
  "expire_date": "2024-02-01T00:00:00Z",
  "type": "monthly",
  "auto_renew": true
}

## 3. Subscription Cancel Endpoint
POST /api/v1/subscriptions/cancel

Request:
{
  "user_id": "xxx",
  "platform": "google_play",
  "subscription_id": "xxx"
}

## 4. Real-time Developer Notifications

### Google Play RTDN
- Set up Cloud Pub/Sub
- Receive: SUBSCRIPTION_RECOVERED, SUBSCRIPTION_RENEWED, SUBSCRIPTION_CANCELED, etc.

### App Store Server Notifications
- Configure URL in App Store Connect
- Receive: DID_RENEW, DID_CHANGE_RENEWAL_PREF, etc.

## 5. Database Schema

users table:
- id
- email
- is_vip: boolean
- vip_expire_date: datetime
- subscription_type: string
- subscription_id: string
- auto_renew: boolean

subscriptions table:
- id
- user_id
- platform
- product_id
- purchase_token
- start_date
- expire_date
- status
- created_at
- updated_at
''';

  static const String _errorHandlingGuide = '''
# Error Handling Guide

## Common Purchase Errors

### 1. PRODUCT_NOT_AVAILABLE
- Product ID not found in Play Console/App Store Connect
- Product not published yet
- Test account trying to buy production product

### 2. USER_CANCELED
- User dismissed the payment dialog
- Show: "Purchase cancelled"

### 3. NETWORK_ERROR
- No internet connection
- Server timeout
- Retry with exponential backoff

### 4. ITEM_ALREADY_OWNED
- User already has active subscription
- Verify status and grant access

### 5. DEVELOPER_ERROR
- Configuration error
- Check Google Play/App Store settings

### 6. BILLING_UNAVAILABLE
- Google Play services not available
- Device doesn't support billing

### 7. SERVICE_DISCONNECTED
- Billing service disconnected
- Reconnect and retry

## Best Practices

1. Always verify receipts server-side
2. Cache subscription status locally for offline
3. Handle network errors gracefully
4. Provide clear error messages to users
5. Log all purchase attempts for debugging
6. Test with sandbox accounts before release
7. Handle edge cases:
   - Subscription upgrades/downgrades
   - Family sharing
   - Refunds
   - Account suspension
''';

  static void showGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return DefaultTabController(
            length: 4,
            child: Column(
              children: [
                AppBar(
                  title: const Text('Subscription Setup Guide'),
                  automaticallyImplyLeading: false,
                  bottom: const TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: 'Google Play'),
                      Tab(text: 'App Store'),
                      Tab(text: 'Backend'),
                      Tab(text: 'Errors'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _GuideTab(
                        content: _googlePlayGuide,
                        controller: scrollController,
                      ),
                      _GuideTab(
                        content: _appStoreGuide,
                        controller: scrollController,
                      ),
                      _GuideTab(
                        content: _backendGuide,
                        controller: scrollController,
                      ),
                      _GuideTab(
                        content: _errorHandlingGuide,
                        controller: scrollController,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GuideTab extends StatelessWidget {
  const _GuideTab({
    required this.content,
    required this.controller,
  });

  final String content;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.all(16),
      child: Text(
        content,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              height: 1.5,
            ),
      ),
    );
  }
}
