package com.woaoaao.html;

import android.content.Context;
import android.content.SharedPreferences;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.Writer;
import java.io.OutputStreamWriter;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.CharsetDecoder;
import java.nio.charset.CodingErrorAction;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/** 沙盒文件 / 收藏夹 / 设置 的统一入口。纯本地，不联网。 */
public final class Store {

    private static final String[] EXTENSIONS = {
            "html", "htm", "xhtml", "shtml", "css", "js", "mjs",
            "json", "txt", "md", "markdown", "xml", "svg"
    };
    private static final String PREFS = "aidou";
    private static final String KEY_FAVORITES = "favorites";

    public static class Item {
        public final File file;
        public final String name;
        public final String rel;
        public final long size;
        public final long modified;
        public final boolean favorite;

        Item(File file, String rel, long size, long modified, boolean favorite) {
            this.file = file;
            this.name = file.getName();
            this.rel = rel;
            this.size = size;
            this.modified = modified;
            this.favorite = favorite;
        }
    }

    private Store() {
    }

    public static File root(Context context) {
        File dir = new File(context.getFilesDir(), "HTML");
        if (!dir.exists()) {
            dir.mkdirs();
        }
        return dir;
    }

    public static List<Item> list(Context context) {
        List<Item> result = new ArrayList<Item>();
        File root = root(context);
        Set<String> favorites = favorites(context);
        collect(root, root, result, favorites);
        Collections.sort(result, new Comparator<Item>() {
            @Override
            public int compare(Item a, Item b) {
                return Long.compare(b.modified, a.modified);
            }
        });
        return result;
    }

    private static void collect(File root, File dir, List<Item> out, Set<String> favorites) {
        File[] children = dir.listFiles();
        if (children == null) {
            return;
        }
        for (File child : children) {
            if (child.isDirectory()) {
                collect(root, child, out, favorites);
                continue;
            }
            if (!isSupported(child.getName())) {
                continue;
            }
            String rel = relative(root, child);
            out.add(new Item(child, rel, child.length(), child.lastModified(), favorites.contains(rel)));
        }
    }

    public static boolean isSupported(String name) {
        int dot = name.lastIndexOf('.');
        if (dot < 0) {
            return false;
        }
        String ext = name.substring(dot + 1).toLowerCase(Locale.US);
        for (String candidate : EXTENSIONS) {
            if (candidate.equals(ext)) {
                return true;
            }
        }
        return false;
    }

    public static String relative(File root, File file) {
        String rootPath = root.getAbsolutePath();
        String path = file.getAbsolutePath();
        if (path.startsWith(rootPath)) {
            String rel = path.substring(rootPath.length());
            if (rel.startsWith("/")) {
                rel = rel.substring(1);
            }
            return rel;
        }
        return path;
    }

    public static File uniqueTarget(Context context, String name) {
        File dir = root(context);
        File candidate = new File(dir, name);
        if (!candidate.exists()) {
            return candidate;
        }
        int dot = name.lastIndexOf('.');
        String base = dot > 0 ? name.substring(0, dot) : name;
        String ext = dot > 0 ? name.substring(dot) : "";
        int index = 2;
        while (candidate.exists()) {
            candidate = new File(dir, base + "-" + index + ext);
            index++;
        }
        return candidate;
    }

    public static File importStream(Context context, InputStream input, String name) throws Exception {
        File target = uniqueTarget(context, name);
        FileOutputStream output = new FileOutputStream(target);
        byte[] buffer = new byte[8192];
        int read;
        while ((read = input.read(buffer)) > 0) {
            output.write(buffer, 0, read);
        }
        output.close();
        input.close();
        return target;
    }

    public static File createFile(Context context, String name, String content) throws Exception {
        if (!name.contains(".")) {
            name = name + ".html";
        }
        File target = uniqueTarget(context, name);
        writeText(target, content);
        return target;
    }

    /** 读取文本：UTF-8 → GB18030 → UTF-16 → Latin-1 */
    public static String readText(File file) {
        try {
            byte[] data = readAll(file);
            if (data.length == 0) {
                return "";
            }
            String text = decode(data, Charset.forName("UTF-8"));
            if (text == null) {
                text = decode(data, Charset.forName("GB18030"));
            }
            if (text == null) {
                text = decode(data, Charset.forName("UTF-16"));
            }
            if (text == null) {
                text = decode(data, Charset.forName("ISO-8859-1"));
            }
            return text == null ? "" : text;
        } catch (Exception e) {
            return "";
        }
    }

    private static String decode(byte[] data, Charset charset) {
        try {
            CharsetDecoder decoder = charset.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT);
            return decoder.decode(ByteBuffer.wrap(data)).toString();
        } catch (CharacterCodingException e) {
            return null;
        } catch (Exception e) {
            return null;
        }
    }

    public static boolean writeText(File file, String text) {
        try {
            Writer writer = new OutputStreamWriter(new FileOutputStream(file), Charset.forName("UTF-8"));
            writer.write(text);
            writer.close();
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    public static byte[] readAll(File file) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        FileInputStream in = new FileInputStream(file);
        byte[] buffer = new byte[8192];
        int read;
        while ((read = in.read(buffer)) > 0) {
            out.write(buffer, 0, read);
        }
        in.close();
        return out.toByteArray();
    }

    // ---------------- 收藏夹 ----------------

    public static Set<String> favorites(Context context) {
        String raw = prefs(context).getString(KEY_FAVORITES, "");
        Set<String> set = new HashSet<String>();
        if (raw != null && raw.length() > 0) {
            for (String line : raw.split("\n")) {
                if (line.length() > 0) {
                    set.add(line);
                }
            }
        }
        return set;
    }

    public static boolean isFavorite(Context context, String rel) {
        return favorites(context).contains(rel);
    }

    public static void toggleFavorite(Context context, String rel) {
        Set<String> set = favorites(context);
        if (set.contains(rel)) {
            set.remove(rel);
        } else {
            set.add(rel);
        }
        StringBuilder builder = new StringBuilder();
        for (String line : set) {
            if (builder.length() > 0) {
                builder.append("\n");
            }
            builder.append(line);
        }
        prefs(context).edit().putString(KEY_FAVORITES, builder.toString()).apply();
    }

    public static void clearAll(Context context) {
        deleteRecursive(root(context));
        prefs(context).edit().remove(KEY_FAVORITES).apply();
    }

    private static void deleteRecursive(File file) {
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteRecursive(child);
                }
            }
        }
        file.delete();
    }

    // ---------------- 设置 ----------------

    public static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    public static boolean allowJs(Context context) {
        return prefs(context).getBoolean("allowJs", true);
    }

    public static boolean allowNetwork(Context context) {
        return prefs(context).getBoolean("allowNetwork", true);
    }

    public static boolean externalBrowser(Context context) {
        return prefs(context).getBoolean("externalBrowser", true);
    }

    public static String sizeText(long bytes) {
        if (bytes < 1024) {
            return bytes + " B";
        }
        if (bytes < 1024L * 1024L) {
            return String.format(Locale.US, "%.1f KB", bytes / 1024.0);
        }
        return String.format(Locale.US, "%.1f MB", bytes / 1024.0 / 1024.0);
    }

    public static String dateText(long millis) {
        return new java.text.SimpleDateFormat("MM-dd HH:mm", Locale.US).format(new Date(millis));
    }
}
