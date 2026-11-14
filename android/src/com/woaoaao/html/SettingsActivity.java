package com.woaoaao.html;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.graphics.Color;
import android.os.Bundle;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

/** 设置：安全开关 / 清空数据 / 关于 */
public class SettingsActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ScrollView scroll = new ScrollView(this);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(36, 28, 36, 40);
        scroll.addView(layout, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        setContentView(scroll);

        if (getActionBar() != null) {
            getActionBar().setTitle("设置");
        }

        addSection(layout, "安全");

        final CheckBox js = addCheckBox(layout, "启用 JavaScript", Store.allowJs(this));
        js.setOnClickListener(new android.view.View.OnClickListener() {
            @Override
            public void onClick(android.view.View v) {
                Store.prefs(SettingsActivity.this).edit().putBoolean("allowJs", js.isChecked()).apply();
            }
        });

        final CheckBox network = addCheckBox(layout, "允许网络访问", Store.allowNetwork(this));
        network.setOnClickListener(new android.view.View.OnClickListener() {
            @Override
            public void onClick(android.view.View v) {
                Store.prefs(SettingsActivity.this).edit().putBoolean("allowNetwork", network.isChecked()).apply();
            }
        });

        final CheckBox external = addCheckBox(layout, "外部链接用系统浏览器打开", Store.externalBrowser(this));
        external.setOnClickListener(new android.view.View.OnClickListener() {
            @Override
            public void onClick(android.view.View v) {
                Store.prefs(SettingsActivity.this).edit().putBoolean("externalBrowser", external.isChecked()).apply();
            }
        });

        addSection(layout, "存储与数据");
        Button clear = new Button(this);
        clear.setText("清空数据");
        clear.setTextColor(Color.parseColor("#D32F2F"));
        clear.setOnClickListener(new android.view.View.OnClickListener() {
            @Override
            public void onClick(android.view.View v) {
                new AlertDialog.Builder(SettingsActivity.this)
                        .setTitle("确定清空全部本地数据？")
                        .setMessage("App 目录里的 HTML 文件和收藏记录都会被删除，不可恢复。")
                        .setPositiveButton("全部删除", new DialogInterface.OnClickListener() {
                            @Override
                            public void onClick(DialogInterface dialog, int which) {
                                Store.clearAll(SettingsActivity.this);
                                Toast.makeText(SettingsActivity.this, "已清空", Toast.LENGTH_SHORT).show();
                            }
                        })
                        .setNegativeButton("取消", null)
                        .show();
            }
        });
        layout.addView(clear, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        addSection(layout, "关于");
        addInfoRow(layout, "版本", "1.0");
        addInfoRow(layout, "作者", "爱豆");
        TextView note = new TextView(this);
        note.setText("纯本地运行 · 无广告 · 无内购 · 不收集任何数据");
        note.setTextSize(12);
        note.setTextColor(Color.GRAY);
        note.setPadding(0, 16, 0, 0);
        layout.addView(note);
    }

    private void addSection(LinearLayout parent, String title) {
        TextView header = new TextView(this);
        header.setText(title);
        header.setTextSize(13);
        header.setTextColor(Color.parseColor("#3F51B5"));
        header.setPadding(0, 28, 0, 8);
        parent.addView(header);
    }

    private CheckBox addCheckBox(LinearLayout parent, String title, boolean checked) {
        CheckBox box = new CheckBox(this);
        box.setText(title);
        box.setTextSize(15);
        box.setChecked(checked);
        parent.addView(box, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return box;
    }

    private void addInfoRow(LinearLayout parent, String label, String value) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setPadding(0, 10, 0, 10);

        TextView left = new TextView(this);
        left.setText(label);
        left.setTextSize(15);
        row.addView(left, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        TextView right = new TextView(this);
        right.setText(value);
        right.setTextSize(15);
        right.setTextColor(Color.GRAY);
        row.addView(right);

        parent.addView(row, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
    }
}
