package com.mech.workcalendar;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.InetAddress;
import java.net.Proxy;
import java.net.UnknownHostException;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.TimeUnit;
import okhttp3.HttpUrl;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;

@CapacitorPlugin(name = "SafeWeb")
public class SafeWebPlugin extends Plugin {
    private final ExecutorService workers = Executors.newFixedThreadPool(2);

    static List<InetAddress> publicAddresses(String host) throws UnknownHostException {
        List<InetAddress> addresses = Arrays.asList(InetAddress.getAllByName(host));
        for (InetAddress ip : addresses) {
            byte[] bytes = ip.getAddress();
            boolean blocked = ip.isAnyLocalAddress() || ip.isLoopbackAddress() || ip.isLinkLocalAddress()
                || ip.isSiteLocalAddress() || ip.isMulticastAddress();
            if (bytes.length == 4) {
                int a = bytes[0] & 255, b = bytes[1] & 255;
                blocked |= a == 0 || a >= 224 || a == 127 || a == 10
                    || (a == 100 && b >= 64 && b <= 127) || (a == 169 && b == 254)
                    || (a == 172 && b >= 16 && b <= 31) || (a == 192 && (b == 168 || b == 0 || b == 2))
                    || (a == 198 && (b == 18 || b == 19 || b == 51)) || (a == 203 && b == 0);
            } else {
                // Only global unicast, excluding transition/documentation ranges.
                blocked |= (bytes[0] & 0xe0) != 0x20
                    || ((bytes[0] & 255) == 0x20 && (bytes[1] & 255) == 0x02)
                    || ((bytes[0] & 255) == 0x20 && (bytes[1] & 255) == 0x01 && (bytes[2] & 255) < 0x20);
            }
            if (blocked) throw new UnknownHostException("禁止访问非公网地址");
        }
        if (addresses.isEmpty()) throw new UnknownHostException("域名没有可用地址");
        return addresses;
    }

    @PluginMethod
    public void fetchPage(PluginCall call) {
        final String input = call.getString("url", "");
        workers.execute(() -> {
            OkHttpClient client = new OkHttpClient.Builder()
                .dns(SafeWebPlugin::publicAddresses).proxy(Proxy.NO_PROXY)
                .followRedirects(false).followSslRedirects(false)
                .connectTimeout(10, TimeUnit.SECONDS).readTimeout(15, TimeUnit.SECONDS)
                .callTimeout(20, TimeUnit.SECONDS).build();
            try {
                HttpUrl url = HttpUrl.parse(input);
                for (int hop = 0; hop < 4; hop++) {
                    if (url == null || !url.username().isEmpty() || !url.password().isEmpty()
                        || (url.port() != 80 && url.port() != 443)) throw new Exception("网页地址无效，仅支持 80/443 端口");
                    Request request = new Request.Builder().url(url).header("User-Agent", "WorkCalendar/0.4.2").build();
                    try (Response response = client.newCall(request).execute()) {
                        if (response.isRedirect()) {
                            String location = response.header("Location");
                            if (location == null) throw new Exception("重定向缺少地址");
                            url = url.resolve(location);
                            continue;
                        }
                        if (!response.isSuccessful() || response.body() == null) throw new Exception("抓取失败：HTTP " + response.code());
                        ByteArrayOutputStream out = new ByteArrayOutputStream();
                        InputStream stream = response.body().byteStream();
                        byte[] block = new byte[8192];
                        int count;
                        while ((count = stream.read(block)) != -1) {
                            if (out.size() + count > 1024 * 1024) throw new Exception("网页超过 1MB 上限");
                            out.write(block, 0, count);
                        }
                        JSObject result = new JSObject();
                        java.nio.charset.Charset charset = java.nio.charset.StandardCharsets.UTF_8;
                        if (response.body().contentType() != null) charset = response.body().contentType().charset(charset);
                        result.put("data", new String(out.toByteArray(), charset));
                        call.resolve(result);
                        return;
                    }
                }
                throw new Exception("重定向次数过多");
            } catch (Exception e) {
                call.reject("安全网页读取失败：" + e.getMessage());
            } finally {
                client.connectionPool().evictAll();
                client.dispatcher().executorService().shutdown();
            }
        });
    }

    @Override
    protected void handleOnDestroy() {
        workers.shutdownNow();
    }
}
