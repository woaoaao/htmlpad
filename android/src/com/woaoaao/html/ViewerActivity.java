package com.woaoaao.html;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.ViewGroup;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.Toast;

import java.io.ByteArrayInputStream;
import java.io.File;

/** 预览页：WebView 铺满 + 收藏 / 编辑源码 / 重载 / 网络 / 分享 */
public class ViewerActivity extends Activity {

    private WebView webView;
    private File file;
    private boolean allowNetwork;
    private Ui.Shell shell;

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

        shell = Ui.build(this, file.getName(),
                new Ui.MenuProvider() {
                    @Override
                    public String[] items() {
                        boolean favorite = Store.isFavorite(ViewerActivity.this,
                                Store.relative(Store.root(ViewerActivity.this), file));
                        return new String[]{
                                favorite ? "取消收藏" : "添加到收藏",
                                "编辑源代码",
                                "重新加载",
                                allowNetwork ? "网络访问：允许" : "网络访问：禁止",
                                "分享文件"
                        };
                    }
                },
                new Ui.MenuHandler() {
                    @Override
                    public void onSelected(int index) {
                        handleMenu(index);
                    }
                });

        // 网页铺满到屏幕底部（底部安全区交给注入的 CSS 处理）
        shell.content.setPadding(0, 0, 0, 0);

        FrameLayout box = new FrameLayout(this);
        shell.content.addView(box, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        webView = new WebView(this);
        box.addView(webView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        configureWebView();
        load();
    }

    private void handleMenu(int index) {
        switch (index) {
            case 0:
                Store.toggleFavorite(this, Store.relative(Store.root(this), file));
                Toast.makeText(this, "已更新收藏", Toast.LENGTH_SHORT).show();
                break;
            case 1: {
                Intent intent = new Intent(this, EditorActivity.class);
                intent.putExtra("path", file.getAbsolutePath());
                startActivity(intent);
                break;
            }
            case 2:
                load();
                break;
            case 3:
                allowNetwork = !allowNetwork;
                Store.prefs(this).edit().putBoolean("allowNetwork", allowNetwork).apply();
                load();
                Toast.makeText(this, allowNetwork ? "已允许网络" : "已禁止网络", Toast.LENGTH_SHORT).show();
                break;
            case 4: {
                Intent share = new Intent(Intent.ACTION_SEND);
                share.setType("text/html");
                share.putExtra(Intent.EXTRA_STREAM, Uri.fromFile(file));
                try {
                    startActivity(Intent.createChooser(share, "分享文件"));
                } catch (Exception e) {
                    Toast.makeText(this, "分享失败：" + e.getMessage(), Toast.LENGTH_LONG).show();
                }
                break;
            }
            default:
                break;
        }
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
        webView.setBackgroundColor(0xFFFFFFFF);

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
        webView.loadUrl("file://" + file.getAbsolutePath());
        webView.evaluateJavascript(safeAreaScript(), null);
    }

    /** 让页面自己避让底部手势条；顶部由自绘顶栏保证 */
    private String safeAreaScript() {
        return "(function(){try{"
                + "var head=document.head;if(!head){return;}"
                + "var m=document.querySelector('meta[name=\"viewport\"]');"
                + "if(!m){m=document.createElement('meta');m.name='viewport';head.appendChild(m);}"
                + "if(m.content.indexOf('viewport-fit')<0){m.content='width=device-width,initial-scale=1,viewport-fit=cover';}"
                + "var p=document.createElement('div');"
                + "p.style.cssText='position:fixed;left:0;top:0;width:1px;height:0;visibility:hidden;';"
                + "p.style.height='env(safe-area-inset-bottom, 0px)';"
                + "document.body.appendChild(p);"
                + "var bottom=p.getBoundingClientRect().height;p.remove();"
                + "if(!window.__aidouSafe){window.__aidouSafe={pb:parseFloat(getComputedStyle(document.body).paddingBottom)||0};}"
                + "var old=document.getElementById('aidou-safe');if(old){old.remove();}"
                + "if(bottom>0.5){var st=document.createElement('style');st.id='aidou-safe';"
                + "st.textContent='body{padding-bottom:'+(window.__aidouSafe.pb+bottom)+'px !important;}';head.appendChild(st);}"
                + "}catch(e){}})();";
    }

    @Override
    protected void onResume() {
        super.onResume();
        // 从编辑器回来时文件可能改过
        load();
        if (shell != null) {
            shell.setTitle(file.getName());
        }
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }
}
