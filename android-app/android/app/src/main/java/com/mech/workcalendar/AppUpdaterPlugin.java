package com.mech.workcalendar;

import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import androidx.core.content.FileProvider;
import com.getcapacitor.*;
import com.getcapacitor.annotation.CapacitorPlugin;
import org.json.*;
import java.io.*;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.concurrent.*;
import okhttp3.*;

@CapacitorPlugin(name="AppUpdater")
public class AppUpdaterPlugin extends Plugin {
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final OkHttpClient client=new OkHttpClient.Builder().connectTimeout(20,TimeUnit.SECONDS).readTimeout(60,TimeUnit.SECONDS).callTimeout(15,TimeUnit.MINUTES).build();
    private volatile String status="idle", error="";
    private volatile int progress=0;
    private volatile JSONObject available;
    private volatile boolean busy=false;
    private static final String REPO="Semyon11275/WorkCalendar";
    private File apk(){return new File(getContext().getCacheDir(),"workcalendar-update.apk");}
    private PackageInfo installed() throws Exception {return getContext().getPackageManager().getPackageInfo(getContext().getPackageName(),PackageManager.GET_SIGNATURES);}
    private long number(String s){if(!s.matches("v?0\\.5\\.\\d+")) return -1;return Long.parseLong(s.substring(s.lastIndexOf('.')+1));}
    private String hash(File f) throws Exception {MessageDigest h=MessageDigest.getInstance("SHA-256");try(InputStream in=new FileInputStream(f)){byte[] b=new byte[65536];int n;while((n=in.read(b))!=-1)h.update(b,0,n);}StringBuilder s=new StringBuilder();for(byte v:h.digest())s.append(String.format("%02x",v&255));return s.toString();}
    private JSObject state(){JSObject s=new JSObject();s.put("status",status);s.put("progress",progress);s.put("error",error);s.put("available",available==null?JSONObject.NULL:available);return s;}
    @PluginMethod public void snapshot(PluginCall call){call.resolve(state());}
    private synchronized boolean begin(PluginCall call,String next){if(busy){call.resolve(state());return false;}busy=true;status=next;error="";return true;}
    @PluginMethod public void check(PluginCall call){if(!begin(call,"checking"))return;call.resolve(state());worker.execute(()->{try{
        Request req=new Request.Builder().url("https://api.github.com/repos/"+REPO+"/releases?per_page=30").header("User-Agent","WorkCalendar-Updater").build();
        JSONArray releases;
        try(Response r=client.newCall(req).execute()){if(!r.isSuccessful())throw new IOException("GitHub HTTP "+r.code());if(r.body()==null)throw new IOException("空响应");
            ByteArrayOutputStream out=new ByteArrayOutputStream();InputStream in=r.body().byteStream();byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1){out.write(b,0,n);if(out.size()>2*1024*1024)throw new IOException("发布信息过大");}releases=new JSONArray(out.toString("UTF-8"));}
        JSONObject selected=null;long best=number(installed().versionName);
        for(int i=0;i<releases.length();i++){JSONObject r=releases.getJSONObject(i);long v=number(r.optString("tag_name"));if(!r.optBoolean("draft")&&!r.optBoolean("prerelease")&&v>best){selected=r;best=v;}}
        available=null;
        if(selected==null){status="current";return;}
        String tag=selected.getString("tag_name"),v=tag.replaceFirst("^v","");String name="WorkCalendar-Android-v"+v+".apk";
        JSONArray assets=selected.getJSONArray("assets");
        for(int i=0;i<assets.length();i++){JSONObject a=assets.getJSONObject(i);if(!name.equals(a.optString("name")))continue;
            String url="https://github.com/"+REPO+"/releases/download/"+tag+"/"+name,digest=a.optString("digest");long size=a.optLong("size");
            if(!url.equals(a.optString("browser_download_url"))||!digest.matches("sha256:[a-fA-F0-9]{64}")||size<=0||size>256L*1024*1024)throw new IOException("更新包来源或校验信息异常");
            available=new JSONObject().put("version",v).put("url",url).put("sha256",digest.substring(7).toLowerCase()).put("size",size).put("notes",selected.optString("body"));break;
        }
        if(available==null)throw new IOException("新版尚未提供可校验的 APK");status="available";
    }catch(Exception e){error=e.getMessage();status="error";}finally{busy=false;}});}
    @PluginMethod public void download(PluginCall call){if(available==null){call.reject("请先检查更新");return;}if(!begin(call,"downloading"))return;call.resolve(state());worker.execute(()->{File tmp=new File(apk()+".part");try{
        Request req=new Request.Builder().url(available.getString("url")).build();long size=available.getLong("size"),count=0;
        try(Response r=client.newCall(req).execute()){if(!r.isSuccessful()||r.body()==null)throw new IOException("下载失败");try(InputStream in=r.body().byteStream();OutputStream out=new FileOutputStream(tmp)){byte[] b=new byte[65536];int n;while((n=in.read(b))!=-1){count+=n;if(count>size)throw new IOException("大小超限");out.write(b,0,n);progress=(int)(count*100/size);}}}
        if(count!=size||!hash(tmp).equals(available.getString("sha256")))throw new IOException("安装包 SHA256 校验失败");
        if(apk().exists()&&!apk().delete())throw new IOException("缓存被占用");if(!tmp.renameTo(apk()))throw new IOException("无法保存安装包");validate();status="ready";progress=100;
    }catch(Exception e){error=e.getMessage();status="error";}finally{tmp.delete();busy=false;}});}
    private void validate() throws Exception {
        if(available==null||!apk().isFile()||!hash(apk()).equals(available.getString("sha256")))throw new IOException("请重新下载更新");
        PackageInfo remote=getContext().getPackageManager().getPackageArchiveInfo(apk().getPath(),PackageManager.GET_SIGNATURES),local=installed();
        if(remote==null||!local.packageName.equals(remote.packageName)||remote.versionCode<=local.versionCode||!Arrays.equals(local.signatures,remote.signatures))throw new IOException("安装包包名、版本或签名不匹配");
    }
    @PluginMethod public void install(PluginCall call){try{
        if(busy||!status.equals("ready"))throw new IOException("请先下载并校验更新");validate();
        if(Build.VERSION.SDK_INT>=26&&!getContext().getPackageManager().canRequestPackageInstalls()){
            getActivity().startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:"+getContext().getPackageName())));JSObject result=new JSObject();result.put("permission_required",true);call.resolve(result);return;
        }
        Uri uri=FileProvider.getUriForFile(getContext(),getContext().getPackageName()+".fileprovider",apk());
        getActivity().startActivity(new Intent(Intent.ACTION_VIEW).setDataAndType(uri,"application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION));call.resolve(state());
    }catch(Exception e){call.reject(e.getMessage());}}
}