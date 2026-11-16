package com.giggre.mobile

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import java.io.File
import java.security.KeyStore

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Must run before the Flutter engine starts, i.e. before Firebase Auth
        // reads its storage.
        repairRestoredFirebaseAuthStorage()
        super.onCreate(savedInstanceState)
    }

    // Firebase Auth encrypts the saved session with a key held in the Android
    // Keystore, and records that key's alias in a "crypto" shared-prefs file.
    // Android backup restored that file on reinstall (Play Store
    // restoreAtInstall), but Keystore keys are never backed up, so the alias
    // pointed at a key that doesn't exist. Firebase then failed with "Keystore
    // cannot load the key ... unable to encrypt data" and could never save a
    // session, so every relaunch landed on the login screen.
    //
    // Backup is now off (AndroidManifest), but installs that already restored
    // the broken file keep it across app updates. If the alias is missing from
    // the Keystore, delete the orphaned files so Firebase starts clean. The
    // session they hold is unreadable anyway, so nobody is logged out who
    // wasn't already.
    private fun repairRestoredFirebaseAuthStorage() {
        try {
            val prefsDir = File(applicationInfo.dataDir, "shared_prefs")
            val cryptoFiles = prefsDir.listFiles { f ->
                f.name.startsWith(CRYPTO_PREFIX) && f.name.endsWith(".xml")
            } ?: return
            if (cryptoFiles.isEmpty()) return

            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            for (crypto in cryptoFiles) {
                val suffix = crypto.name.removePrefix(CRYPTO_PREFIX).removeSuffix(".xml")
                if (keyStore.containsAlias(KEY_ALIAS_PREFIX + suffix)) continue

                crypto.delete()
                File(prefsDir, "$STORE_PREFIX$suffix.xml").delete()
                Log.w(TAG, "Removed restored Firebase Auth storage with a missing Keystore key")
            }
        } catch (e: Exception) {
            // Never block app start over this; worst case is the old behaviour.
            Log.w(TAG, "Firebase Auth storage check failed", e)
        }
    }

    private companion object {
        const val TAG = "GiggreAuthRepair"
        const val CRYPTO_PREFIX = "com.google.firebase.auth.api.crypto."
        const val STORE_PREFIX = "com.google.firebase.auth.api.Store."
        const val KEY_ALIAS_PREFIX = "firebear_main_key_id_for_storage_crypto."
    }
}
