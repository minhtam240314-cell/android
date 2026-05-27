#!/bin/bash
# ============================================================
#  MST AutoType — One-file Android build script
#  Upload file này lên GitHub, Actions sẽ tự chạy build APK
# ============================================================
set -e

PROJECT="MSTAutoType"
PKG="com/mstauto"

echo "==> Tạo cấu trúc thư mục..."
mkdir -p $PROJECT/app/src/main/java/$PKG
mkdir -p $PROJECT/app/src/main/res/layout
mkdir -p $PROJECT/app/src/main/res/values
mkdir -p $PROJECT/app/src/main/res/xml
mkdir -p $PROJECT/app/src/main/res/drawable
mkdir -p $PROJECT/app/src/main/res/mipmap-mdpi
mkdir -p $PROJECT/app/src/main/res/mipmap-hdpi
mkdir -p $PROJECT/app/src/main/res/mipmap-xhdpi
mkdir -p $PROJECT/app/src/main/res/mipmap-xxhdpi
mkdir -p $PROJECT/app/src/main/res/mipmap-xxxhdpi
mkdir -p $PROJECT/gradle/wrapper

# ── settings.gradle ──────────────────────────────────────────
cat > $PROJECT/settings.gradle << 'EOF'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "MSTAutoType"
include ':app'
EOF

# ── build.gradle (root) ──────────────────────────────────────
cat > $PROJECT/build.gradle << 'EOF'
plugins {
    id 'com.android.application' version '8.2.0' apply false
}
EOF

# ── gradle.properties ────────────────────────────────────────
cat > $PROJECT/gradle.properties << 'EOF'
android.useAndroidX=false
android.enableJetifier=false
org.gradle.jvmargs=-Xmx2048m
EOF

# ── gradle-wrapper.properties ────────────────────────────────
cat > $PROJECT/gradle/wrapper/gradle-wrapper.properties << 'EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.4-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# ── app/build.gradle ─────────────────────────────────────────
cat > $PROJECT/app/build.gradle << 'EOF'
plugins {
    id 'com.android.application'
}
android {
    namespace 'com.mstauto'
    compileSdk 34
    defaultConfig {
        applicationId "com.mstauto"
        minSdk 26
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }
    buildTypes {
        release {
            minifyEnabled false
        }
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
}
EOF

# ── AndroidManifest.xml ──────────────────────────────────────
cat > $PROJECT/app/src/main/AndroidManifest.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.mstauto">
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="MST AutoType"
        android:roundIcon="@mipmap/ic_launcher"
        android:supportsRtl="true"
        android:theme="@style/AppTheme">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service
            android:name=".MSTAccessibilityService"
            android:exported="true"
            android:label="MST AutoType Service"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService" />
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/accessibility_service_config" />
        </service>
    </application>
</manifest>
EOF

# ── MSTManager.java ──────────────────────────────────────────
cat > $PROJECT/app/src/main/java/$PKG/MSTManager.java << 'EOF'
package com.mstauto;
import java.util.ArrayList;
import java.util.List;

public class MSTManager {
    private static final MSTManager INSTANCE = new MSTManager();
    private final List<String> mstList = new ArrayList<>();
    private int currentIndex = 0;
    private MSTManager() {}
    public static MSTManager getInstance() { return INSTANCE; }

    public synchronized void setMSTList(List<String> list) {
        mstList.clear(); mstList.addAll(list); currentIndex = 0;
    }
    public synchronized List<String> getMSTList() { return new ArrayList<>(mstList); }
    public synchronized int getSize() { return mstList.size(); }
    public synchronized int getCurrentIndex() { return currentIndex; }
    public synchronized boolean hasData() { return !mstList.isEmpty(); }

    public synchronized String getNextMST() {
        if (mstList.isEmpty() || currentIndex >= mstList.size()) return null;
        return mstList.get(currentIndex++);
    }
    public synchronized String peekCurrentMST() {
        if (mstList.isEmpty() || currentIndex >= mstList.size()) return null;
        return mstList.get(currentIndex);
    }
    public synchronized void reset() { currentIndex = 0; }
    public synchronized void setIndex(int index) {
        if (index >= 0 && index < mstList.size()) currentIndex = index;
    }
    public synchronized boolean hasRemaining() { return currentIndex < mstList.size(); }
    public synchronized int getRemainingCount() { return Math.max(0, mstList.size() - currentIndex); }
}
EOF

# ── MSTAccessibilityService.java ─────────────────────────────
cat > $PROJECT/app/src/main/java/$PKG/MSTAccessibilityService.java << 'EOF'
package com.mstauto;
import android.accessibilityservice.AccessibilityService;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

public class MSTAccessibilityService extends AccessibilityService {
    public static final String ACTION_PASTE_MST = "com.mstauto.PASTE_MST";
    public static final String EXTRA_MST_TEXT   = "mst_text";
    private static MSTAccessibilityService instance;
    private BroadcastReceiver pasteReceiver;

    public static MSTAccessibilityService getInstance() { return instance; }

    @Override
    public void onServiceConnected() {
        instance = this;
        pasteReceiver = new BroadcastReceiver() {
            @Override public void onReceive(Context context, Intent intent) {
                if (ACTION_PASTE_MST.equals(intent.getAction())) {
                    String mst = intent.getStringExtra(EXTRA_MST_TEXT);
                    if (mst != null) injectText(mst);
                }
            }
        };
        IntentFilter filter = new IntentFilter(ACTION_PASTE_MST);
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pasteReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(pasteReceiver, filter);
        }
    }

    @Override
    public void onDestroy() {
        instance = null;
        if (pasteReceiver != null) unregisterReceiver(pasteReceiver);
        super.onDestroy();
    }

    @Override
    protected boolean onKeyEvent(KeyEvent event) {
        if (event.getKeyCode() == KeyEvent.KEYCODE_F1
                && event.getAction() == KeyEvent.ACTION_DOWN) {
            String nextMst = MSTManager.getInstance().getNextMST();
            if (nextMst != null) {
                injectText(nextMst);
                sendBroadcast(new Intent(MainActivity.ACTION_MST_ADVANCED)
                        .putExtra(MainActivity.EXTRA_INDEX,
                                MSTManager.getInstance().getCurrentIndex()));
                return true;
            }
        }
        return super.onKeyEvent(event);
    }

    public void injectText(String text) {
        AccessibilityNodeInfo focused = findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        if (focused == null) {
            AccessibilityNodeInfo root = getRootInActiveWindow();
            if (root != null) focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        }
        if (focused != null && focused.isEditable()) {
            Bundle args = new Bundle();
            args.putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text);
            focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
            focused.recycle();
        }
    }

    @Override public void onAccessibilityEvent(AccessibilityEvent event) {}
    @Override public void onInterrupt() {}
}
EOF

# ── MainActivity.java ────────────────────────────────────────
cat > $PROJECT/app/src/main/java/$PKG/MainActivity.java << 'EOF'
package com.mstauto;
import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.view.KeyEvent;
import android.widget.*;
import java.io.*;
import java.util.*;

public class MainActivity extends Activity {
    public static final String ACTION_MST_ADVANCED = "com.mstauto.MST_ADVANCED";
    public static final String EXTRA_INDEX         = "current_index";

    private TextView  tvStatus, tvCurrentMST, tvProgress;
    private ListView  lvMSTList;
    private Button    btnLoadFile, btnReset, btnEnableService;
    private ArrayAdapter<String> listAdapter;

    private final BroadcastReceiver advanceReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context ctx, Intent intent) {
            int index = intent.getIntExtra(EXTRA_INDEX, 0);
            runOnUiThread(() -> updateUI(index));
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        bindViews(); setupListeners(); updateServiceStatus();
    }

    @Override
    protected void onResume() {
        super.onResume();
        updateServiceStatus();
        IntentFilter f = new IntentFilter(ACTION_MST_ADVANCED);
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(advanceReceiver, f, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(advanceReceiver, f);
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        try { unregisterReceiver(advanceReceiver); } catch (Exception ignored) {}
    }

    private void bindViews() {
        tvStatus      = findViewById(R.id.tvStatus);
        tvCurrentMST  = findViewById(R.id.tvCurrentMST);
        tvProgress    = findViewById(R.id.tvProgress);
        lvMSTList     = findViewById(R.id.lvMSTList);
        btnLoadFile   = findViewById(R.id.btnLoadFile);
        btnReset      = findViewById(R.id.btnReset);
        btnEnableService = findViewById(R.id.btnEnableService);
        listAdapter = new ArrayAdapter<>(this,
            android.R.layout.simple_list_item_1, new ArrayList<>());
        lvMSTList.setAdapter(listAdapter);
    }

    private void setupListeners() {
        btnLoadFile.setOnClickListener(v -> {
            Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
            intent.setType("text/plain");
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            startActivityForResult(
                Intent.createChooser(intent, "Chon file MST (.txt)"), 100);
        });
        btnReset.setOnClickListener(v -> {
            MSTManager.getInstance().reset(); updateUI(0);
            Toast.makeText(this, "Da reset ve dau danh sach", Toast.LENGTH_SHORT).show();
        });
        btnEnableService.setOnClickListener(v ->
            startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)));
        lvMSTList.setOnItemClickListener((parent, view, position, id) -> {
            MSTManager.getInstance().setIndex(position); updateUI(position);
            Toast.makeText(this, "Vi tri: " + (position+1), Toast.LENGTH_SHORT).show();
        });
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == 100 && resultCode == RESULT_OK && data != null)
            loadMSTFromUri(data.getData());
    }

    private void loadMSTFromUri(Uri uri) {
        try {
            InputStream is = getContentResolver().openInputStream(uri);
            BufferedReader reader = new BufferedReader(new InputStreamReader(is, "UTF-8"));
            List<String> list = new ArrayList<>();
            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                if (!line.isEmpty()) list.add(line);
            }
            reader.close();
            if (list.isEmpty()) {
                Toast.makeText(this, "File trong!", Toast.LENGTH_LONG).show(); return;
            }
            MSTManager.getInstance().setMSTList(list);
            listAdapter.clear(); listAdapter.addAll(list); listAdapter.notifyDataSetChanged();
            updateUI(0);
            Toast.makeText(this, "Da tai " + list.size() + " ma so thue",
                Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Toast.makeText(this, "Loi: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void updateUI(int index) {
        MSTManager mgr = MSTManager.getInstance();
        int total = mgr.getSize();
        if (total == 0) { tvCurrentMST.setText("Chua tai file"); tvProgress.setText("0/0"); return; }
        String current = mgr.peekCurrentMST();
        tvCurrentMST.setText(current != null ? current : "Da dien het!");
        tvProgress.setText((index+1) + " / " + total);
        lvMSTList.setSelection(index);
    }

    private void updateServiceStatus() {
        boolean enabled = isAccessibilityServiceEnabled();
        tvStatus.setText(enabled
            ? "Service: BAT - Nhan F1 de tu dien MST"
            : "Can bat Accessibility Service!");
        tvStatus.setBackgroundColor(enabled ? 0xFF1B5E20 : 0xFF7F0000);
        btnEnableService.setText(enabled ? "Mo cai dat Accessibility" : "Bat Service ngay");
    }

    private boolean isAccessibilityServiceEnabled() {
        String s = Settings.Secure.getString(
            getContentResolver(), Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        return s != null && s.contains(
            getPackageName() + "/" + MSTAccessibilityService.class.getName());
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_F1) {
            MSTAccessibilityService svc = MSTAccessibilityService.getInstance();
            String next = MSTManager.getInstance().getNextMST();
            if (next != null && svc != null) {
                svc.injectText(next);
                updateUI(MSTManager.getInstance().getCurrentIndex());
            }
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }
}
EOF

# ── activity_main.xml ────────────────────────────────────────
cat > $PROJECT/app/src/main/res/layout/activity_main.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:background="#121212" android:orientation="vertical" android:padding="16dp">
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="MST AutoType" android:textColor="#FFC107"
        android:textSize="24sp" android:textStyle="bold"
        android:gravity="center" android:paddingBottom="4dp"/>
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="Nhan F1 de tu dien ma so thue"
        android:textColor="#888888" android:textSize="13sp"
        android:gravity="center" android:paddingBottom="12dp"/>
    <TextView android:id="@+id/tvStatus"
        android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="Can bat Accessibility Service"
        android:textColor="#FFFFFF" android:textSize="13sp"
        android:padding="12dp" android:background="#7F0000"
        android:layout_marginBottom="12dp"/>
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:background="#1E1E1E" android:orientation="vertical"
        android:padding="14dp" android:layout_marginBottom="12dp">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="MST SE DIEN TIEP THEO"
            android:textColor="#888888" android:textSize="11sp"/>
        <TextView android:id="@+id/tvCurrentMST"
            android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="Chua tai file" android:textColor="#FFC107"
            android:textSize="28sp" android:textStyle="bold"
            android:paddingTop="4dp" android:paddingBottom="4dp"/>
        <TextView android:id="@+id/tvProgress"
            android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="0 / 0" android:textColor="#888888" android:textSize="13sp"/>
    </LinearLayout>
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:layout_marginBottom="12dp">
        <Button android:id="@+id/btnLoadFile"
            android:layout_width="0dp" android:layout_height="wrap_content"
            android:layout_weight="1" android:text="Tai file MST"
            android:layout_marginEnd="6dp" android:backgroundTint="#1565C0"
            android:textColor="#FFFFFF"/>
        <Button android:id="@+id/btnReset"
            android:layout_width="0dp" android:layout_height="wrap_content"
            android:layout_weight="1" android:text="Reset dau"
            android:backgroundTint="#37474F" android:textColor="#FFFFFF"/>
    </LinearLayout>
    <Button android:id="@+id/btnEnableService"
        android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="Bat Accessibility Service"
        android:backgroundTint="#E65100" android:textColor="#FFFFFF"
        android:layout_marginBottom="12dp"/>
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="DANH SACH MST (nhan de nhay toi)"
        android:textColor="#888888" android:textSize="11sp" android:paddingBottom="6dp"/>
    <ListView android:id="@+id/lvMSTList"
        android:layout_width="match_parent" android:layout_height="0dp"
        android:layout_weight="1" android:background="#1E1E1E"
        android:divider="#2E2E2E" android:dividerHeight="1dp"/>
</LinearLayout>
EOF

# ── strings.xml ──────────────────────────────────────────────
cat > $PROJECT/app/src/main/res/values/strings.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">MST AutoType</string>
    <string name="accessibility_service_description">
        Tu dong dien ma so thue khi nhan F1 tren ban phim Bluetooth.
    </string>
</resources>
EOF

# ── styles.xml ───────────────────────────────────────────────
cat > $PROJECT/app/src/main/res/values/styles.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme" parent="android:Theme.DeviceDefault.NoActionBar">
        <item name="android:colorPrimary">#FFC107</item>
        <item name="android:colorPrimaryDark">#121212</item>
        <item name="android:colorAccent">#FFC107</item>
        <item name="android:windowBackground">#121212</item>
    </style>
</resources>
EOF

# ── accessibility_service_config.xml ─────────────────────────
cat > $PROJECT/app/src/main/res/xml/accessibility_service_config.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeViewFocusChanged|typeWindowStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagDefault|flagReportViewIds|flagRetrieveInteractiveWindows"
    android:canPerformGestures="true"
    android:canRetrieveWindowContent="true"
    android:description="@string/accessibility_service_description"
    android:notificationTimeout="100"
    android:packageNames=""
    android:settingsActivity=".MainActivity"/>
EOF

# ── icons (adaptive) ─────────────────────────────────────────
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
cat > $PROJECT/app/src/main/res/mipmap-$d/ic_launcher.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
EOF
cp $PROJECT/app/src/main/res/mipmap-$d/ic_launcher.xml \
   $PROJECT/app/src/main/res/mipmap-$d/ic_launcher_round.xml
done

cat > $PROJECT/app/src/main/res/drawable/ic_launcher_background.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <solid android:color="#121212"/>
</shape>
EOF

cat > $PROJECT/app/src/main/res/drawable/ic_launcher_foreground.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#FFC107"
        android:pathData="M30,44 L78,44 L78,64 L30,64 Z"/>
    <path android:fillColor="#121212"
        android:pathData="M34,50 L46,50 L46,58 L34,58 Z"/>
    <path android:fillColor="#121212"
        android:pathData="M50,50 L62,50 L62,58 L50,58 Z"/>
    <path android:fillColor="#121212"
        android:pathData="M66,50 L74,50 L74,58 L66,58 Z"/>
</vector>
EOF

# ── Download gradle wrapper jar + gradlew ────────────────────
echo "==> Tải gradle wrapper..."
curl -sL "https://raw.githubusercontent.com/gradle/gradle/v8.4.0/gradle/wrapper/gradle-wrapper.jar" \
    -o $PROJECT/gradle/wrapper/gradle-wrapper.jar
curl -sL "https://raw.githubusercontent.com/gradle/gradle/v8.4.0/gradlew" \
    -o $PROJECT/gradlew
curl -sL "https://raw.githubusercontent.com/gradle/gradle/v8.4.0/gradlew.bat" \
    -o $PROJECT/gradlew.bat
chmod +x $PROJECT/gradlew

echo "==> Build APK..."
cd $PROJECT
./gradlew assembleDebug

APK="app/build/outputs/apk/debug/app-debug.apk"
if [ -f "$APK" ]; then
    echo ""
    echo "================================================"
    echo "  BUILD THANH CONG!"
    echo "  APK: $PROJECT/$APK"
    echo "================================================"
else
    echo "BUILD THAT BAI - kiem tra log ben tren"
    exit 1
fi
