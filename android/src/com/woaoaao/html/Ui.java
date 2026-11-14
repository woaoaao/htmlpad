package com.woaoaao.html;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Build;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.Menu;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.PopupMenu;
import android.widget.TextView;

/** 统一的自绘顶栏（不依赖系统 ActionBar）+ 边到边布局 */
public final class Ui {

    public interface MenuProvider {
        String[] items();
    }

    public interface MenuHandler {
        void onSelected(int index);
    }

    public static class Shell {
        public final LinearLayout root;
        public final LinearLayout content;
        private final TextView titleView;

        Shell(LinearLayout root, LinearLayout content, TextView titleView) {
            this.root = root;
            this.content = content;
            this.titleView = titleView;
        }

        public void setTitle(String text) {
            titleView.setText(text);
        }
    }

    private Ui() {
    }

    public static int dp(Activity activity, int value) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value,
                activity.getResources().getDisplayMetrics());
    }

    /** 自定义资源 id，避开 R.string.system 之类的冲突 */
    private static int dimen(Activity activity, String name) {
        return activity.getResources().getIdentifier(name, "dimen", "android");
    }

    public static int statusBarHeight(Activity activity) {
        int id = dimen(activity, "status_bar_height");
        return id > 0 ? activity.getResources().getDimensionPixelSize(id) : dp(activity, 24);
    }

    public static int navBarHeight(Activity activity) {
        int id = dimen(activity, "navigation_bar_height");
        return id > 0 ? activity.getResources().getDimensionPixelSize(id) : dp(activity, 48);
    }

    /** 边到边：内容延伸到状态栏 / 导航栏区域，再靠 padding 避让 */
    public static void edgeToEdge(Activity activity) {
        Window window = activity.getWindow();
        if (Build.VERSION.SDK_INT >= 21) {
            window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
            window.setStatusBarColor(Color.TRANSPARENT);
            window.setNavigationBarColor(Color.TRANSPARENT);
        }
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false);
        } else {
            window.getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        }
    }

    /**
     * 搭好「顶栏 + 内容区」的骨架并 setContentView。
     * 顶栏自带状态栏高度的上内边距，所以不会出现黑边。
     */
    public static Shell build(final Activity activity,
                              String titleText,
                              final MenuProvider provider,
                              final MenuHandler handler) {

        edgeToEdge(activity);

        LinearLayout root = new LinearLayout(activity);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);

        LinearLayout topBar = new LinearLayout(activity);
        topBar.setOrientation(LinearLayout.HORIZONTAL);
        topBar.setGravity(Gravity.CENTER_VERTICAL);
        topBar.setBackgroundColor(Color.WHITE);
        topBar.setPadding(dp(activity, 16), statusBarHeight(activity), dp(activity, 8), 0);
        topBar.setMinimumHeight(dp(activity, 52) + statusBarHeight(activity));

        TextView titleView = new TextView(activity);
        titleView.setText(titleText);
        titleView.setTextSize(20);
        titleView.setTypeface(Typeface.DEFAULT_BOLD);
        titleView.setTextColor(Color.parseColor("#1A1A1A"));
        titleView.setSingleLine(true);
        titleView.setEllipsize(TextUtils.TruncateAt.MIDDLE);
        topBar.addView(titleView, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        final Button moreButton = new Button(activity);
        moreButton.setText("⋮");
        moreButton.setTextSize(20);
        moreButton.setTextColor(Color.parseColor("#1A73E8"));
        moreButton.setBackgroundColor(Color.TRANSPARENT);
        moreButton.setPadding(dp(activity, 12), 0, dp(activity, 12), 0);
        moreButton.setMinWidth(0);
        moreButton.setMinimumWidth(0);

        final boolean hasMenu = provider != null && provider.items() != null && provider.items().length > 0;
        if (hasMenu) {
            moreButton.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    PopupMenu popup = new PopupMenu(activity, moreButton);
                    String[] items = provider.items();
                    for (int i = 0; i < items.length; i++) {
                        if (items[i] == null) {
                            continue;
                        }
                        popup.getMenu().add(Menu.NONE, i, i, items[i]);
                    }
                    popup.setOnMenuItemClickListener(new PopupMenu.OnMenuItemClickListener() {
                        @Override
                        public boolean onMenuItemClick(android.view.MenuItem item) {
                            handler.onSelected(item.getItemId());
                            return true;
                        }
                    });
                    popup.show();
                }
            });
            topBar.addView(moreButton, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        }

        root.addView(topBar, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        LinearLayout content = new LinearLayout(activity);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setBackgroundColor(Color.WHITE);
        content.setPadding(0, 0, 0, navBarHeight(activity));
        root.addView(content, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        activity.setContentView(root);
        return new Shell(root, content, titleView);
    }
}
