package com.postdee.postdee_mobile

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** Returns to the same Flutter activity without creating a second connection screen. */
class SocialConnectReturnActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            if (intent.action == Intent.ACTION_VIEW &&
                SocialConnectReturn.matches(intent.dataString, packageName)
            ) {
                // Do not carry tokens, profile ids or success flags from the
                // browser. The resumed screen reconciles its signed-in owner.
                startActivity(
                    Intent(this, MainActivity::class.java)
                        .setAction(Intent.ACTION_MAIN)
                        .addCategory(Intent.CATEGORY_LAUNCHER)
                        .addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP,
                        ),
                )
            }
        } finally {
            finish()
        }
    }
}
