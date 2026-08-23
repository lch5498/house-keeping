package com.family.checky.mobile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.ContactsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val pendingDeepLinkKey = "pendingDeepLink"
    private val contactPickerRequestCode = 4017
    private var initialDeepLink: String? = null
    private var latestDeepLink: String? = null
    private var deepLinkChannel: MethodChannel? = null
    private var pendingContactResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        captureDeepLink(intent, isInitial = true)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "checky/share"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareText" -> {
                    val text = call.argument<String>("text")
                    val subject = call.argument<String>("subject") ?: "체키 그룹 초대"

                    if (text.isNullOrBlank()) {
                        result.error("invalid_arguments", "text is required", null)
                        return@setMethodCallHandler
                    }

                    val sendIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                        putExtra(Intent.EXTRA_SUBJECT, subject)
                    }
                    startActivity(Intent.createChooser(sendIntent, subject))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "checky/phone"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "dial" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")

                    if (phoneNumber.isNullOrBlank()) {
                        result.error("invalid_arguments", "phoneNumber is required", null)
                        return@setMethodCallHandler
                    }

                    val dialIntent = Intent(Intent.ACTION_DIAL).apply {
                        data = Uri.parse("tel:${Uri.encode(phoneNumber)}")
                    }
                    startActivity(dialIntent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "checky/contacts"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickPhoneContact" -> pickPhoneContact(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "checky/home_widget"
        ).setMethodCallHandler { call, result ->
            if (call.method != "update") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val arguments = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            val editor = getSharedPreferences("checky.home_widget", Context.MODE_PRIVATE).edit()
            val schedule = arguments["schedule"] as? Map<*, *>
            val items = schedule?.get("items") as? List<*> ?: emptyList<Any>()
            editor.putString("schedule.title", schedule?.get("title") as? String ?: "체키 오늘 일정")
            editor.putString("schedule.weekday", schedule?.get("weekday") as? String ?: "오늘")
            editor.putString("schedule.day", schedule?.get("day") as? String ?: "")
            editor.putString("schedule.fullDate", schedule?.get("fullDate") as? String ?: "오늘")
            editor.putInt("schedule.itemCount", items.size.coerceAtMost(5))
            editor.putInt(
                "schedule.moreCount",
                (schedule?.get("moreCount") as? Number)?.toInt() ?: 0,
            )
            repeat(5) { index ->
                val item = items.getOrNull(index) as? Map<*, *>
                editor.putString("schedule.item.$index.startsAt", item?.get("startsAt") as? String ?: "")
                editor.putString("schedule.item.$index.endsAt", item?.get("endsAt") as? String ?: "")
                editor.putString("schedule.item.$index.title", item?.get("title") as? String ?: "")
                editor.putString("schedule.item.$index.memberName", item?.get("memberName") as? String ?: "")
                editor.putString("schedule.item.$index.memberColor", item?.get("memberColor") as? String ?: "gray")
            }
            editor.apply()
            CheckyHomeWidgetProvider.updateAll(this)
            result.success(null)
        }

        deepLinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "checky/deep_links"
        )

        deepLinkChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    result.success(consumeDeepLink(initialDeepLink))
                    initialDeepLink = null
                }
                "getLatestLink" -> {
                    result.success(consumeDeepLink(latestDeepLink))
                    latestDeepLink = null
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureDeepLink(intent, isInitial = false)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != contactPickerRequestCode) {
            return
        }

        val result = pendingContactResult ?: return
        pendingContactResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.error("cancelled", "Contact pick was cancelled", null)
            return
        }

        val picked = readPickedPhoneContact(data.data!!)
        if (picked == null) {
            result.error("phone_number_unavailable", "Phone number is unavailable", null)
            return
        }

        result.success(picked)
    }

    private fun pickPhoneContact(result: MethodChannel.Result) {
        if (pendingContactResult != null) {
            result.error("pick_in_progress", "Contact picker is already open", null)
            return
        }

        pendingContactResult = result
        val intent = Intent(
            Intent.ACTION_PICK,
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI
        )

        try {
            startActivityForResult(intent, contactPickerRequestCode)
        } catch (error: Exception) {
            pendingContactResult = null
            result.error("contact_picker_unavailable", "Contact picker is unavailable", null)
        }
    }

    private fun readPickedPhoneContact(uri: Uri): Map<String, String>? {
        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER
        )

        contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) {
                return null
            }

            val nameIndex = cursor.getColumnIndex(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME
            )
            val numberIndex = cursor.getColumnIndex(
                ContactsContract.CommonDataKinds.Phone.NUMBER
            )
            val name = if (nameIndex >= 0) cursor.getString(nameIndex) ?: "" else ""
            val phoneNumber = if (numberIndex >= 0) cursor.getString(numberIndex) ?: "" else ""

            if (phoneNumber.isBlank()) {
                return null
            }

            return mapOf("name" to name, "phoneNumber" to phoneNumber)
        }

        return null
    }

    private fun captureDeepLink(intent: Intent?, isInitial: Boolean) {
        val uri = intent?.data ?: return
        val scheme = uri.scheme ?: return
        val host = uri.host ?: return

        if ((scheme == "checky" || scheme == "favis") && host == "family-invite") {
            val value = uri.toString()
            latestDeepLink = value
            preferences().edit().putString(pendingDeepLinkKey, value).apply()
            if (isInitial && initialDeepLink == null) {
                initialDeepLink = value
            }
            deepLinkChannel?.invokeMethod("onLink", value)
        }
    }

    private fun consumeDeepLink(preferred: String?): String? {
        if (!preferred.isNullOrBlank()) {
            preferences().edit().remove(pendingDeepLinkKey).apply()
            return preferred
        }

        val pending = preferences().getString(pendingDeepLinkKey, null)
        if (pending.isNullOrBlank()) {
            return null
        }

        preferences().edit().remove(pendingDeepLinkKey).apply()
        return pending
    }

    private fun preferences() = getSharedPreferences("checky.deep_links", Context.MODE_PRIVATE)
}
