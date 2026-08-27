package com.video.storydrama

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import com.facebook.ads.*
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.video.storydrama/restart"
    private val META_AD_CHANNEL = "com.video.storydrama/meta_ads"
    private val META_AD_EVENT_CHANNEL = "com.video.storydrama/meta_ads_events"
    private val TAG = "AppRestart"
    private val META_AD_TAG = "MetaAdManager"

    private var methodChannel: MethodChannel? = null

    // Meta Rewarded Ad (now using InterstitialAd internally for non-game apps)
    private var metaAdIsLoading = false
    private var metaAdIsReady = false
    private var metaAdPlacementId = ""

    // Meta Interstitial Ad
    private var metaInterstitialAd: InterstitialAd? = null
    private var metaInterstitialAdIsLoading = false
    private var metaInterstitialAdIsReady = false
    private var metaInterstitialAdPlacementId = ""

    // Listeners
    private var onAdLoadedListener: ((Boolean) -> Unit)? = null
    private var onAdFailedListener: ((String) -> Unit)? = null
    private var onAdRewardedListener: (() -> Unit)? = null
    private var onAdClosedListener: (() -> Unit)? = null
    private var onInterstitialAdLoadedListener: ((Boolean) -> Unit)? = null
    private var onInterstitialAdFailedListener: ((String) -> Unit)? = null
    private var onInterstitialAdClosedListener: (() -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Existing app restart channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "restart") {
                    restartApp()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // Meta Ads channel
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, META_AD_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    // Meta SDK is initialized automatically with the app
                    Log.d(META_AD_TAG, "Meta SDK initialized")
                    result.success(true)
                }
                "loadRewardedAd" -> {
                    // For non-game apps, use InterstitialAd instead of RewardedVideoAd
                    val placementId = call.argument<String>("placementId") ?: ""
                    loadMetaInterstitialAd(placementId)
                    result.success(true)
                }
                "isRewardedAdReady" -> {
                    result.success(metaInterstitialAdIsReady)
                }
                "showRewardedAd" -> {
                    showMetaInterstitialAd()
                    result.success(true)
                }
                "destroyRewardedAd" -> {
                    destroyMetaInterstitialAd()
                    result.success(true)
                }
                "loadInterstitialAd" -> {
                    val placementId = call.argument<String>("placementId") ?: ""
                    loadMetaInterstitialAd(placementId)
                    result.success(true)
                }
                "isInterstitialAdReady" -> {
                    result.success(metaInterstitialAdIsReady)
                }
                "showInterstitialAd" -> {
                    showMetaInterstitialAd()
                    result.success(true)
                }
                "destroyInterstitialAd" -> {
                    destroyMetaInterstitialAd()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun invokeDartMethod(method: String, arguments: Any?) {
        runOnUiThread {
            methodChannel?.invokeMethod(method, arguments)
        }
    }

    private fun loadMetaRewardedAd(placementId: String) {
        if (placementId.isEmpty()) {
            Log.e(META_AD_TAG, "Placement ID is empty")
            invokeDartMethod("onAdFailed", "Placement ID is empty")
            return
        }

        if (metaAdIsLoading) {
            Log.d(META_AD_TAG, "Ad is already loading")
            return
        }

        // Destroy existing ad if any
        destroyMetaRewardedAd()

        metaAdPlacementId = placementId
        metaAdIsLoading = true
        metaAdIsReady = false

        Log.d(META_AD_TAG, "Loading Meta interstitial ad (as replacement for rewarded) with placement: $placementId")

        // Enable test mode for development
        AdSettings.setTestMode(true)

        // Use InterstitialAd instead of RewardedVideoAd (Meta doesn't support rewarded ads for non-game apps)
        metaInterstitialAd = InterstitialAd(this, placementId)
        metaInterstitialAd?.loadAd(
            metaInterstitialAd?.buildLoadAdConfig()
                ?.withAdListener(object : InterstitialAdListener {
                    override fun onAdLoaded(ad: Ad?) {
                        Log.d(META_AD_TAG, "Meta interstitial ad (rewarded replacement) loaded successfully")
                        metaAdIsLoading = false
                        metaAdIsReady = true
                        invokeDartMethod("onAdLoaded", true)
                    }

                    override fun onError(ad: Ad?, error: AdError?) {
                        Log.e(META_AD_TAG, "Meta interstitial ad failed to load: ${error?.errorMessage}")
                        metaAdIsLoading = false
                        metaAdIsReady = false
                        invokeDartMethod("onAdFailed", error?.errorMessage ?: "Unknown error")
                        // Don't auto-retry here, let Dart side handle cooldown and retry logic
                    }

                    override fun onAdClicked(ad: Ad?) {
                        Log.d(META_AD_TAG, "Meta interstitial ad clicked")
                    }

                    override fun onLoggingImpression(ad: Ad?) {
                        Log.d(META_AD_TAG, "Meta interstitial ad logged impression")
                    }

                    override fun onInterstitialDisplayed(ad: Ad?) {
                        Log.d(META_AD_TAG, "Meta interstitial ad displayed")
                    }

                    override fun onInterstitialDismissed(ad: Ad?) {
                        Log.d(META_AD_TAG, "Meta interstitial ad dismissed - treating as rewarded")
                        metaAdIsReady = false
                        // Treat interstitial close as reward completion
                        invokeDartMethod("onAdRewarded", true)
                        invokeDartMethod("onAdClosed", true)
                        // Don't auto-preload, let Dart side control the cooldown
                    }
                })?.build()
        )
    }

    private fun showMetaRewardedAd(
        onAdLoaded: (Boolean) -> Unit,
        onAdFailed: (String) -> Unit,
        onAdRewarded: () -> Unit,
        onAdClosed: () -> Unit
    ) {
        if (!metaInterstitialAdIsReady || metaInterstitialAd == null) {
            Log.w(META_AD_TAG, "Meta rewarded ad is not ready, reloading...")
            if (metaInterstitialAdPlacementId.isNotEmpty()) {
                onAdLoadedListener = onAdLoaded
                onAdFailedListener = onAdFailed
                onAdRewardedListener = onAdRewarded
                onAdClosedListener = onAdClosed
                loadMetaInterstitialAd(metaInterstitialAdPlacementId)
            } else {
                onAdFailed("No ad loaded")
            }
            return
        }

        this.onAdLoadedListener = onAdLoaded
        this.onAdFailedListener = onAdFailed
        this.onAdRewardedListener = onAdRewarded
        this.onAdClosedListener = onAdClosed

        Log.d(META_AD_TAG, "Showing Meta interstitial ad (as rewarded)")
        metaInterstitialAd?.show()
    }

    private fun destroyMetaRewardedAd() {
        metaInterstitialAd?.destroy()
        metaInterstitialAd = null
        metaInterstitialAdIsReady = false
        metaInterstitialAdIsLoading = false
    }

    // =========================================================================
    // Meta Interstitial Ad Methods
    // =========================================================================

    private fun loadMetaInterstitialAd(placementId: String) {
        if (placementId.isEmpty()) {
            Log.e(META_AD_TAG, "Interstitial Placement ID is empty")
            invokeDartMethod("onAdFailed", "Placement ID is empty")
            return
        }

        if (metaInterstitialAdIsLoading) {
            Log.d(META_AD_TAG, "Interstitial ad is already loading")
            return
        }

        destroyMetaInterstitialAd()

        metaInterstitialAdPlacementId = placementId
        metaInterstitialAdIsLoading = true
        metaInterstitialAdIsReady = false

        Log.d(META_AD_TAG, "Loading Meta interstitial ad with placement: $placementId")

        // Enable test mode for development
        AdSettings.setTestMode(true)

        metaInterstitialAd = InterstitialAd(this, placementId)
        metaInterstitialAd?.loadAd(
            metaInterstitialAd?.buildLoadAdConfig()
                ?.withAdListener(object : InterstitialAdListener {
                    override fun onInterstitialDisplayed(ad: Ad?) {
                        Log.d(META_AD_TAG, "Meta interstitial ad displayed")
                    }

                    override fun onInterstitialDismissed(ad: Ad?) {
                        Log.d(META_AD_TAG, "Meta interstitial ad dismissed")
                        metaInterstitialAdIsReady = false
                        invokeDartMethod("onAdRewarded", true)
                        invokeDartMethod("onAdClosed", true)
                        // Don't auto-preload, let Dart side control the cooldown
                    }

                    override fun onError(ad: Ad?, error: AdError?) {
                        Log.e(META_AD_TAG, "Meta interstitial ad failed to load: ${error?.errorMessage}")
                        metaInterstitialAdIsLoading = false
                        metaInterstitialAdIsReady = false
                        invokeDartMethod("onAdFailed", error?.errorMessage ?: "Unknown error")
                    }

                    override fun onAdLoaded(ad: Ad?) {
                        Log.d(META_AD_TAG, "Meta interstitial ad loaded successfully")
                        metaInterstitialAdIsLoading = false
                        metaInterstitialAdIsReady = true
                        invokeDartMethod("onAdLoaded", true)
                    }

                    override fun onAdClicked(ad: Ad?) {
                        Log.d(META_AD_TAG, "Meta interstitial ad clicked")
                    }

                    override fun onLoggingImpression(ad: Ad?) {
                        Log.d(META_AD_TAG, "Meta interstitial ad logged impression")
                    }
                })?.build()
        )
    }

    private fun showMetaInterstitialAd() {
        if (!metaInterstitialAdIsReady || metaInterstitialAd == null) {
            Log.w(META_AD_TAG, "Meta interstitial ad is not ready")
            invokeDartMethod("onInterstitialAdFailed", "Interstitial ad not ready")
            return
        }

        Log.d(META_AD_TAG, "Showing Meta interstitial ad")
        metaInterstitialAd?.show()
    }

    private fun destroyMetaInterstitialAd() {
        metaInterstitialAd?.destroy()
        metaInterstitialAd = null
        metaInterstitialAdIsReady = false
        metaInterstitialAdIsLoading = false
    }

    private fun restartApp() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TASK or
            Intent.FLAG_ACTIVITY_NO_ANIMATION
        )

        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_CANCEL_CURRENT
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            1001,
            launchIntent,
            pendingIntentFlags
        )

        Log.d(TAG, "restart requested, scheduling relaunch")

        try {
            startActivity(launchIntent)
        } catch (e: Exception) {
            Log.e(TAG, "startActivity relaunch failed", e)
        }

        val alarmManager = getSystemService(AlarmManager::class.java)
        val triggerAtMillis = System.currentTimeMillis() + 800

        if (alarmManager != null) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC,
                triggerAtMillis,
                pendingIntent
            )
        } else {
            try {
                pendingIntent.send()
            } catch (e: Exception) {
                Log.e(TAG, "pendingIntent relaunch failed", e)
            }
        }

        finishAffinity()
        finishAndRemoveTask()
        android.os.Process.killProcess(android.os.Process.myPid())
    }
}
