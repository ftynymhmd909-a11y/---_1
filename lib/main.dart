// ==========================================
// 1. ملف واجهة المستخدم: res/layout/activity_main.xml
// ==========================================
/*
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center"
    android:padding="24dp"
    android:background="#121212">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Social VPN Tunnel"
        android:textSize="24sp"
        android:textStyle="bold"
        android:textColor="#FFFFFF"
        android:layout_marginBottom="32dp"/>

    <EditText
        android:id="@+id/etConfig"
        android:layout_width="match_parent"
        android:layout_height="120dp"
        android:hint="أدخل إعدادات الاتصال أو الـ Payload هنا..."
        android:textColor="#FFFFFF"
        android:textColorHint="#888888"
        android:background="#1E1E1E"
        android:padding="12dp"
        android:gravity="top"
        android:layout_marginBottom="24dp"/>

    <Button
        android:id="@+id/btnConnect"
        android:layout_width="match_parent"
        android:layout_height="55dp"
        android:text="اتصال (Connect)"
        android:textSize="18sp"
        android:backgroundTint="#4CAF50"
        android:textColor="#FFFFFF"/>

</LinearLayout>
*/


// ==========================================
// 2. خدمة الـ VPN الخلفية: MyVpnService.kt
// ==========================================
package com.example.socialtunnel

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer

class MyVpnService : VpnService(), Runnable {

    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnThread: Thread? = null
    private var isRunning = false

    companion object {
        const val ACTION_CONNECT = "com.example.socialtunnel.START_VPN"
        const val ACTION_DISCONNECT = "com.example.socialtunnel.STOP_VPN"
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null) {
            when (intent.action) {
                ACTION_CONNECT -> startVpn()
                ACTION_DISCONNECT -> stopVpn()
            }
        }
        return START_NOT_STICKY
    }

    private fun startVpn() {
        if (isRunning) return
        isRunning = true

        vpnThread = Thread(this, "VpnServiceThread")
        vpnThread?.start()
        Log.i("MyVpnService", "تم بدء خدمة الـ VPN بنجاح")
    }

    override fun run() {
        try {
            val builder = Builder()
            builder.setSession("SocialTunnel")
                .addAddress("10.0.0.2", 24)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("8.8.8.8")

            vpnInterface = builder.establish()

            if (vpnInterface == null) {
                Log.e("MyVpnService", "فشل في إنشاء واجهة الـ VPN")
                return
            }

            val descriptor = vpnInterface!!.fileDescriptor
            val inputStream = FileInputStream(descriptor)
            val outputStream = FileOutputStream(descriptor)
            val buffer = ByteBuffer.allocate(32767)

            while (isRunning) {
                val length = inputStream.read(buffer.array())
                if (length > 0) {
                    // معالجة الحزم الواردة عبر النفق
                    buffer.clear()
                } else {
                    Thread.sleep(10)
                }
            }
        } catch (e: Exception) {
            Log.e("MyVpnService", "حدث خطأ داخل خيط الـ VPN", e)
        } finally {
            closeVpn()
        }
    }

    private fun stopVpn() {
        isRunning = false
        vpnThread?.interrupt()
        closeVpn()
        stopSelf()
        Log.i("MyVpnService", "تم إيقاف خدمة الـ VPN")
    }

    private fun closeVpn() {
        try {
            vpnInterface?.close()
            vpnInterface = null
        } catch (e: Exception) {
            Log.e("MyVpnService", "خطأ عند إغلاق واجهة الـ VPN", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopVpn()
    }
}


// ==========================================
// 3. الواجهة البرمجية الرئيسية: MainActivity.kt
// ==========================================
package com.example.socialtunnel

import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    private lateinit var btnConnect: Button
    private lateinit var etConfig: EditText
    private var isConnected = false
    private val VPN_REQUEST_CODE = 100

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        btnConnect = findViewById(R.id.btnConnect)
        etConfig = findViewById(R.id.etConfig)

        btnConnect.setOnClickListener {
            if (!isConnected) {
                val intent = VpnService.prepare(this)
                if (intent != null) {
                    startActivityForResult(intent, VPN_REQUEST_CODE)
                } else {
                    startVpnService()
                }
            } else {
                stopVpnService()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE && resultCode == RESULT_OK) {
            startVpnService()
        } else {
            Toast.makeText(this, "تم رفض صلاحية الـ VPN", Toast.LENGTH_SHORT).show()
        }
    }

    private fun startVpnService() {
        val configText = etConfig.text.toString()
        if (configText.isEmpty()) {
            Toast.makeText(this, "الرجاء إدخال الإعدادات أولاً", Toast.LENGTH_SHORT).show()
            return
        }

        val intent = Intent(this, MyVpnService::class.java).apply {
            action = MyVpnService.ACTION_CONNECT
        }
        startService(intent)

        isConnected = true
        btnConnect.text = "إيقاف الاتصال (Disconnect)"
        btnConnect.backgroundTintList = getColorStateList(android.R.color.holo_red_dark)
        Toast.makeText(this, "جاري تشغيل النفق...", Toast.LENGTH_SHORT).show()
    }

    private fun stopVpnService() {
        val intent = Intent(this, MyVpnService::class.java).apply {
            action = MyVpnService.ACTION_DISCONNECT
        }
        startService(intent)

        isConnected = false
        btnConnect.text = "اتصال (Connect)"
        btnConnect.backgroundTintList = getColorStateList(android.R.color.holo_green_dark)
        Toast.makeText(this, "تم إيقاف النفق", Toast.LENGTH_SHORT).show()
    }
}


// ==========================================
// 4. إعدادات الأذونات والخدمة: AndroidManifest.xml
// ==========================================
/*
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />

<application ...>
    
    <activity
        android:name=".MainActivity"
        android:exported="true">
        <intent-filter>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent-filter>
    </activity>

    <service
        android:name=".MyVpnService"
        android:permission="android.permission.BIND_VPN_SERVICE"
        android:exported="true">
        <intent-filter>
            <action android:name="android.net.VpnService" />
        </intent-filter>
    </service>

</application>
*/

