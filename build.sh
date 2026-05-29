#!/bin/bash
set -e

PROJECT="MSTAutoType"
PKG="com/mstauto"

echo "==> Tạo cấu trúc thư mục..."
mkdir -p $PROJECT/app/src/main/java/$PKG
mkdir -p $PROJECT/app/src/main/res/layout
mkdir -p $PROJECT/app/src/main/res/values
mkdir -p $PROJECT/app/src/main/res/drawable
mkdir -p $PROJECT/app/src/main/res/mipmap-mdpi
mkdir -p $PROJECT/app/src/main/res/mipmap-hdpi
mkdir -p $PROJECT/app/src/main/res/mipmap-xhdpi
mkdir -p $PROJECT/app/src/main/res/mipmap-xxhdpi
mkdir -p $PROJECT/app/src/main/res/mipmap-xxxhdpi
mkdir -p $PROJECT/gradle/wrapper

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

cat > $PROJECT/build.gradle << 'EOF'
plugins {
    id 'com.android.application' version '8.2.0' apply false
}
EOF

cat > $PROJECT/gradle.properties << 'EOF'
android.useAndroidX=false
android.enableJetifier=false
org.gradle.jvmargs=-Xmx2048m
EOF

cat > $PROJECT/gradle/wrapper/gradle-wrapper.properties << 'EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.4-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

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
        versionCode 3
        versionName "3.0"
    }
    buildTypes {
        release { minifyEnabled false }
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
}
EOF

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
            android:launchMode="singleTop"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

# ── MainActivity.java ────────────────────────────────────────
cat > $PROJECT/app/src/main/java/$PKG/MainActivity.java << 'EOF'
package com.mstauto;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.view.View;
import android.view.ViewGroup;
import android.widget.*;

import java.io.*;
import java.util.*;

public class MainActivity extends Activity {

    private TextView  tvCurrentMST, tvCurrentLabel, tvInfo;
    private Button    btnLoadFile, btnResetAll, btnSkip;
    private ListView  lvMSTList;
    private MSTAdapter adapter;

    private final List<MSTItem> mstItems  = new ArrayList<>();
    private int currentIndex = 0;  // con trỏ MST tiếp theo chưa copy

    // Delay chuyển app (ms) — đủ để user thấy animation copy
    private static final int SWITCH_DELAY_MS = 800;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        tvCurrentMST   = findViewById(R.id.tvCurrentMST);
        tvCurrentLabel = findViewById(R.id.tvCurrentLabel);
        tvInfo         = findViewById(R.id.tvInfo);
        btnLoadFile    = findViewById(R.id.btnLoadFile);
        btnResetAll    = findViewById(R.id.btnResetAll);
        btnSkip        = findViewById(R.id.btnSkip);
        lvMSTList      = findViewById(R.id.lvMSTList);

        adapter = new MSTAdapter();
        lvMSTList.setAdapter(adapter);

        // Nhấn vào MST hiện tại (card lớn) → copy + chuyển app
        tvCurrentMST.setOnClickListener(v -> copyCurrentAndSwitch());

        // Nút bỏ qua — không copy, chuyển sang MST tiếp theo
        btnSkip.setOnClickListener(v -> {
            if (mstItems.isEmpty()) return;
            advanceTo(currentIndex + 1);
            Toast.makeText(this, "Bo qua, chuyen sang MST tiep theo", Toast.LENGTH_SHORT).show();
        });

        btnLoadFile.setOnClickListener(v -> {
            Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
            intent.setType("text/plain");
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            startActivityForResult(
                Intent.createChooser(intent, "Chon file MST (.txt)"), 100);
        });

        btnResetAll.setOnClickListener(v -> {
            for (MSTItem item : mstItems) item.copied = false;
            currentIndex = 0;
            adapter.notifyDataSetChanged();
            updateCurrentCard();
            updateInfo();
            Toast.makeText(this, "Da reset ve dau danh sach", Toast.LENGTH_SHORT).show();
        });

        // Nhấn 1 lần vào item trong list → copy + chuyển app
        lvMSTList.setOnItemClickListener((parent, view, position, id) -> {
            currentIndex = position;
            copyCurrentAndSwitch();
        });

        updateCurrentCard();
        updateInfo();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == 100 && resultCode == RESULT_OK && data != null)
            loadFile(data.getData());
    }

    // ── Core logic ─────────────────────────────────────────────

    /**
     * Copy MST hiện tại vào clipboard, đánh dấu đã copy,
     * cập nhật UI, rồi sau SWITCH_DELAY_MS chuyển về app trước.
     */
    private void copyCurrentAndSwitch() {
        if (mstItems.isEmpty()) {
            Toast.makeText(this, "Chua tai file MST!", Toast.LENGTH_SHORT).show();
            return;
        }
        if (currentIndex >= mstItems.size()) {
            Toast.makeText(this, "Het danh sach! Nhan Reset de bat dau lai.",
                Toast.LENGTH_LONG).show();
            return;
        }

        MSTItem item = mstItems.get(currentIndex);
        copyToClipboard(item.mst);
        item.copied = true;
        adapter.notifyDataSetChanged();
        lvMSTList.smoothScrollToPosition(currentIndex);

        // Hiển thị flash xanh trên card lớn
        tvCurrentMST.setBackgroundColor(0xFF1B5E20);
        tvCurrentMST.setText("✓  " + item.mst);

        // Tự động chuyển sang MST tiếp theo trong con trỏ
        int nextIndex = currentIndex + 1;

        // Sau delay → cập nhật card sang MST tiếp theo + chuyển app
        new Handler().postDelayed(() -> {
            advanceTo(nextIndex);
            switchToPreviousApp();
        }, SWITCH_DELAY_MS);
    }

    /** Di chuyển con trỏ đến index mới và cập nhật UI */
    private void advanceTo(int newIndex) {
        currentIndex = newIndex;
        updateCurrentCard();
        updateInfo();
    }

    /** Chuyển về app đang chạy trước đó (Recent Apps → app đầu tiên) */
    private void switchToPreviousApp() {
        // Dùng moveTaskToBack để đưa app này xuống nền,
        // hệ thống sẽ hiện app đang chạy trước đó lên đầu
        moveTaskToBack(true);
    }

    // ── Helpers ────────────────────────────────────────────────

    private void copyToClipboard(String text) {
        ClipboardManager cm =
            (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        cm.setPrimaryClip(ClipData.newPlainText("MST", text));
    }

    private void updateCurrentCard() {
        if (mstItems.isEmpty()) {
            tvCurrentLabel.setText("TAI FILE DE BAT DAU");
            tvCurrentMST.setText("---");
            tvCurrentMST.setBackgroundColor(0xFF1E1E1E);
            tvCurrentMST.setTextColor(0xFF888888);
            btnSkip.setVisibility(View.GONE);
        } else if (currentIndex >= mstItems.size()) {
            tvCurrentLabel.setText("DA DIEN HET DANH SACH");
            tvCurrentMST.setText("Nhan Reset de bat dau lai");
            tvCurrentMST.setBackgroundColor(0xFF1E1E1E);
            tvCurrentMST.setTextColor(0xFF888888);
            btnSkip.setVisibility(View.GONE);
        } else {
            tvCurrentLabel.setText("NHAN DE COPY VA CHUYEN APP  •  " +
                (currentIndex + 1) + " / " + mstItems.size());
            tvCurrentMST.setText(mstItems.get(currentIndex).mst);
            tvCurrentMST.setBackgroundColor(0xFF0D47A1);  // xanh dương
            tvCurrentMST.setTextColor(0xFFFFFFFF);
            btnSkip.setVisibility(View.VISIBLE);
        }
    }

    private void updateInfo() {
        int total  = mstItems.size();
        int copied = 0;
        for (MSTItem item : mstItems) if (item.copied) copied++;
        if (total == 0) {
            tvInfo.setText("Chua tai file");
        } else {
            tvInfo.setText("Da copy: " + copied + " / " + total
                + "   |   Con lai: " + (total - copied));
        }
    }

    private void loadFile(Uri uri) {
        try {
            InputStream is = getContentResolver().openInputStream(uri);
            BufferedReader reader = new BufferedReader(new InputStreamReader(is, "UTF-8"));
            mstItems.clear();
            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                if (!line.isEmpty()) mstItems.add(new MSTItem(line));
            }
            reader.close();

            if (mstItems.isEmpty()) {
                Toast.makeText(this, "File trong!", Toast.LENGTH_LONG).show();
                return;
            }
            currentIndex = 0;
            adapter.notifyDataSetChanged();
            updateCurrentCard();
            updateInfo();
            Toast.makeText(this,
                "Da tai " + mstItems.size() + " ma so thue", Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Toast.makeText(this, "Loi: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    // ── Model ──────────────────────────────────────────────────
    static class MSTItem {
        String mst;
        boolean copied = false;
        MSTItem(String mst) { this.mst = mst; }
    }

    // ── Adapter ────────────────────────────────────────────────
    class MSTAdapter extends BaseAdapter {
        @Override public int getCount() { return mstItems.size(); }
        @Override public Object getItem(int pos) { return mstItems.get(pos); }
        @Override public long getItemId(int pos) { return pos; }

        @Override
        public View getView(int position, View convertView, ViewGroup parent) {
            if (convertView == null)
                convertView = getLayoutInflater().inflate(R.layout.item_mst, parent, false);

            MSTItem item    = mstItems.get(position);
            TextView tvNum  = convertView.findViewById(R.id.tvNumber);
            TextView tvMST  = convertView.findViewById(R.id.tvMST);
            TextView tvStat = convertView.findViewById(R.id.tvStatus);
            View     root   = convertView.findViewById(R.id.itemRoot);

            tvNum.setText(String.valueOf(position + 1));
            tvMST.setText(item.mst);

            boolean isCurrent = (position == currentIndex && !item.copied);

            if (item.copied) {
                // Đã copy → xanh lá
                root.setBackgroundColor(0xFF1B5E20);
                tvMST.setTextColor(0xFF69F0AE);
                tvNum.setTextColor(0xFF69F0AE);
                tvStat.setText("✓ Da copy");
                tvStat.setTextColor(0xFF69F0AE);
            } else if (isCurrent) {
                // Đang chờ copy → xanh dương highlight
                root.setBackgroundColor(0xFF0D47A1);
                tvMST.setTextColor(0xFFFFFFFF);
                tvNum.setTextColor(0xFFFFFFFF);
                tvStat.setText("→ Tiep theo");
                tvStat.setTextColor(0xFFFFFFFF);
            } else {
                // Chưa copy → nền tối
                root.setBackgroundColor(0xFF1E1E1E);
                tvMST.setTextColor(0xFFFFFFFF);
                tvNum.setTextColor(0xFF888888);
                tvStat.setText("Chua copy");
                tvStat.setTextColor(0xFF888888);
            }
            return convertView;
        }
    }
}
EOF

# ── activity_main.xml ────────────────────────────────────────
cat > $PROJECT/app/src/main/res/layout/activity_main.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#121212"
    android:orientation="vertical"
    android:padding="14dp">

    <!-- Tiêu đề -->
    <TextView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="MST AutoType"
        android:textColor="#FFC107"
        android:textSize="22sp"
        android:textStyle="bold"
        android:gravity="center"
        android:paddingBottom="10dp"/>

    <!-- Card MST hiện tại — to, dễ nhấn -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:background="#1E1E1E"
        android:padding="14dp"
        android:layout_marginBottom="10dp">

        <TextView
            android:id="@+id/tvCurrentLabel"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="TAI FILE DE BAT DAU"
            android:textColor="#888888"
            android:textSize="11sp"
            android:paddingBottom="6dp"/>

        <!-- MST lớn — nhấn vào để copy + chuyển app -->
        <TextView
            android:id="@+id/tvCurrentMST"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="---"
            android:textColor="#888888"
            android:textSize="38sp"
            android:textStyle="bold"
            android:gravity="center"
            android:padding="18dp"
            android:background="#1E1E1E"
            android:clickable="true"
            android:focusable="true"/>

    </LinearLayout>

    <!-- Thống kê + nút Skip -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:layout_marginBottom="10dp"
        android:gravity="center_vertical">

        <TextView
            android:id="@+id/tvInfo"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="Chua tai file"
            android:textColor="#AAAAAA"
            android:textSize="13sp"/>

        <Button
            android:id="@+id/btnSkip"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Bo qua ›"
            android:backgroundTint="#37474F"
            android:textColor="#FFFFFF"
            android:textSize="12sp"
            android:visibility="gone"/>

    </LinearLayout>

    <!-- Nút tải file + reset -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:layout_marginBottom="10dp">

        <Button
            android:id="@+id/btnLoadFile"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="Tai file MST"
            android:layout_marginEnd="6dp"
            android:backgroundTint="#1565C0"
            android:textColor="#FFFFFF"/>

        <Button
            android:id="@+id/btnResetAll"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="Reset dau"
            android:backgroundTint="#37474F"
            android:textColor="#FFFFFF"/>

    </LinearLayout>

    <!-- Nhãn list -->
    <TextView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="DANH SACH  (nhan de copy va chuyen app)"
        android:textColor="#888888"
        android:textSize="11sp"
        android:paddingBottom="6dp"/>

    <!-- Danh sách MST -->
    <ListView
        android:id="@+id/lvMSTList"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:divider="#2E2E2E"
        android:dividerHeight="1dp"/>

</LinearLayout>
EOF

# ── item_mst.xml ─────────────────────────────────────────────
cat > $PROJECT/app/src/main/res/layout/item_mst.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/itemRoot"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:padding="12dp"
    android:gravity="center_vertical"
    android:background="#1E1E1E">

    <TextView
        android:id="@+id/tvNumber"
        android:layout_width="36dp"
        android:layout_height="wrap_content"
        android:textColor="#888888"
        android:textSize="12sp"
        android:text="1"/>

    <TextView
        android:id="@+id/tvMST"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:textColor="#FFFFFF"
        android:textSize="18sp"
        android:textStyle="bold"
        android:text="0100109106"/>

    <TextView
        android:id="@+id/tvStatus"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:textColor="#888888"
        android:textSize="11sp"
        android:text="Chua copy"/>

</LinearLayout>
EOF

# ── strings + styles ─────────────────────────────────────────
cat > $PROJECT/app/src/main/res/values/strings.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">MST AutoType</string>
</resources>
EOF

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

# ── Icons ─────────────────────────────────────────────────────
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

# ── Gradle wrapper ────────────────────────────────────────────
echo "==> Tai gradle wrapper..."
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
    echo "================================================"
    echo "  BUILD THANH CONG! v3.0"
    echo "================================================"
else
    echo "BUILD THAT BAI"; exit 1
fi
