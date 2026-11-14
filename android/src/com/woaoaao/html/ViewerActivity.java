package com.woaoaao.html;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.Menu;
import android.view.MenuItem;
import android.view.ViewGroup;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;

import java.io.ByteArrayInputStream;
import java.io.File;

/** 预览页：WebView + 收藏 / 编辑源码 / 重载 / 网络 / 外部链接 / 分享 */
public class ViewerActivity extends Activity {

    private WebView webView;
    private File file;
    private boolean allowNetwork;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        String path = getIntent().getStringExtra("path");
        if (path == null) {
            finish();
            return;
        }
        file = new File(path);
        allowNetwork = Store.allowNetwork(this);

        FrameLayout root = new FrameLayout(this);
        webView = new WebView(this);
        root.addView(webView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        setContentView(root);

        if (getActionBar() != null) {
            getActionBar().setTitle(file.getName());
            getActionBar().setSubtitle(null);
        }

        configureWebView();
        load();
    }

    private void configureWebView() {
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(Store.allowJs(this));
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setAllowFileAccessFromFileURLs(true);
        settings.setAllowUniversalAccessFromFileURLs(true);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        if (Build.VERSION.SDK_INT >= 21) {
            settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        }

        webView.setWebViewClient(new WebViewClient() {

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                return handleUrl(url);
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return handleUrl(request.getUrl().toString());
            }

            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                return blockIfNeeded(request.getUrl().toString());
            }

            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, String url) {
                return blockIfNeeded(url);
            }
        });
    }

    private WebResourceResponse blockIfNeeded(String url) {
        if (allowNetwork) {
            return null;
        }
        String lower = url.toLowerCase();
        if (lower.startsWith("http://") || lower.startsWith("https://")) {
            return new WebResourceResponse("text/plain", "utf-8", new ByteArrayInputStream(new byte[0]));
        }
        return null;
    }

    private boolean handleUrl(String url) {
        String lower = url.toLowerCase();
        if (lower.startsWith("file://") || lower.startsWith("about:") || lower.startsWith("data:")) {
            return false;
        }
        if (!allowNetwork) {
            Toast.makeText(this, "已禁止网络访问", Toast.LENGTH_SHORT).show();
            return true;
        }
        if (Store.externalBrowser(this)) {
            try {
                startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
            } catch (Exception ignored) {
            }
            return true;
        }
        return false;
    }

    private void load() {
        String css =
                "(function(){var head=document.head;if(!head)return;" +
                "var m=document.querySelector('meta[name=\"viewport\"]');" +
                "if(!m){m=document.createElement('meta');m.name='viewport';head.appendChild(m);}" +
                "if(m.content.indexOf('viewport-fit')<0){m.content='width=device-width,initial-scale=1,viewport-fit=cover';}" +
                "var st=document.createElement('style');" +
                "st.textContent='body{padding-bottom:env(safe-area-inset-bottom,0px)!important;}';" +
                "head.appendChild(st);})();";
        webView.loadUrl("file://" + file.getAbsolutePath());
        webView.evaluateJavascript(css, null);
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        boolean favorite = Store.isFavorite(this, Store.relative(Store.root(this), file));
        menu.add(0, 1, 0, favorite ? "取消收藏" : "添加到收藏");
        menu.add(0, 2, 1, "编辑源代码");
        menu.add(0, 3, 2, "重新加载");
        menu.add(0, 4, 3, allowNetwork ? "网络访问：允许" : "网络访问：禁止");
        menu.add(0, 5, 4, "分享文件");
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        switch (item.getItemId()) {
            case 1: {
                Store.toggleFavorite(this, Store.relative(Store.root(this), file));
                invalidateOptionsMenu();
                Toast.makeText(this, "已更新收藏", Toast.LENGTH_SHORT).show();
                return true;
            }
            case 2: {
                Intent intent = new Intent(this, EditorActivity.class);
                intent.putExtra("path", file.getAbsolutePath());
                startActivity(intent);
                return true;
            }
            case 3:
                load();
                return true;
            case 4:
                allowNetwork = !allowNetwork;
                Store.prefs(this).edit().putBoolean("allowNetwork", allowNetwork).apply();
                invalidateOptionsMenu();
                load();
                Toast.makeText(this, allowNetwork ? "已允许网络" : "已禁止网络", Toast.LENGTH_SHORT).show();
                return true;
            case 5: {
                Intent share = new Intent(Intent.ACTION_SEND);
                share.setType("text/html");
                share.putExtra(Intent.EXTRA_STREAM, Uri.fromFile(file));
                try {
                    startActivity(Intent.createChooser(share, "分享文件"));
                } catch (Exception e) {
                    Toast.makeText(this, "分享失败：" + e.getMessage(), Toast.LENGTH_LONG).show();
                }
                return true;
            }
            default:
                return super.onOptionsItemSelected(item);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        // 从编辑器回来：文件可能被改了，重新加载
        load();
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
        }
        super.onDestroy();
    }
}
