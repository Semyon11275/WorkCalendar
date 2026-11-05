import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

const updaterVersion = '1.0.0-alpha.6';
const updateRepo = 'Semyon11275/WorkCalendar';
List<int>? releaseVersion(String value) {
  final m = RegExp(r'^(?:flutter-v|v)?(\d+)\.(\d+)\.(\d+)(?:-alpha\.(\d+))?$').firstMatch(value);
  return m == null ? null : [int.parse(m[1]!),int.parse(m[2]!),int.parse(m[3]!),m[4] == null ? 1000000 : int.parse(m[4]!)];
}
bool newerRelease(String a, String b) {
  final x=releaseVersion(a),y=releaseVersion(b);if(x==null||y==null)return false;
  for(var i=0;i<4;i++){if(x[i]!=y[i])return x[i]>y[i];}return false;
}
Map<String,dynamic>? selectFlutterUpdate(List<dynamic> releases, String current) {
  Map<String,dynamic>? best;
  for(final raw in releases){
    final r=raw as Map<String,dynamic>;final tag='${r['tag_name']}';
    if(r['draft']==true||!tag.startsWith('flutter-v')||!newerRelease(tag,current))continue;
    if(best==null||newerRelease(tag,'${best['tag_name']}'))best=r;
  }
  if(best==null)return null;
  final tag='${best['tag_name']}';final v=tag.substring(9);
  final name='WorkCalendar-Flutter-Windows-x64-v$v.zip';
  final assets=best['assets'] as List? ?? [];
  final a=assets.cast<Map<String,dynamic>>().where((a)=>a['name']==name).firstOrNull;
  if(a==null)throw const FormatException('新版缺少 Flutter Windows 安装包');
  final url='https://github.com/$updateRepo/releases/download/$tag/$name';
  if(a['browser_download_url']!=url||!RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch('${a['digest']}')||a['size'] is! int||a['size']<=0||a['size']>512*1024*1024)throw const FormatException('更新包来源或校验值异常');
  return {'version':v,'url':url,'size':a['size'],'sha256':'${a['digest']}'.substring(7).toLowerCase(),'notes':best['body']??''};
}
class ReleaseUpdater extends ChangeNotifier {
  static final instance=ReleaseUpdater();
  String status='尚未检查',error='';int progress=0;bool busy=false,ready=false;
  Map<String,dynamic>? available;
  String get root=>File(Platform.resolvedExecutable).parent.path;
  Directory get work=>Directory(p.join(root,'.updates'));
  File get archive=>File(p.join(work.path,'update.zip'));
  Future<void> check() async {
    if(busy)return;busy=true;error='';status='正在检查';notifyListeners();
    final client=HttpClient()..connectionTimeout=const Duration(seconds:20);
    try{
      final req=await client.getUrl(Uri.parse('https://api.github.com/repos/$updateRepo/releases?per_page=30'));
      req.headers.set('User-Agent','WorkCalendar-Flutter-Updater');
      final res=await req.close().timeout(const Duration(seconds:30));
      if(res.statusCode!=200)throw HttpException('GitHub HTTP ${res.statusCode}');
      final bytes=<int>[];
      await for(final chunk in res.timeout(const Duration(seconds:30))){bytes.addAll(chunk);if(bytes.length>2*1024*1024)throw const FormatException('发布信息过大');}
      available=selectFlutterUpdate(jsonDecode(utf8.decode(bytes)) as List,updaterVersion);
      ready=false;status=available==null?'当前没有更高的 Flutter 版本':'发现新版本 ${available!['version']}';
    }catch(e){error='$e';status='检查失败';}finally{client.close(force:true);busy=false;notifyListeners();}
  }
  Future<void> download() async {
    if(busy||available==null)return;busy=true;ready=false;error='';status='下载中';progress=0;notifyListeners();
    final client=HttpClient()..connectionTimeout=const Duration(seconds:20);
    final tmp=File('${archive.path}.part');
    try{
      await work.create(recursive:true);
      final req=await client.getUrl(Uri.parse(available!['url'] as String));
      final res=await req.close().timeout(const Duration(seconds:60));
      if(res.statusCode!=200)throw HttpException('下载 HTTP ${res.statusCode}');
      final out=tmp.openWrite();var count=0;
      try{await for(final b in res.timeout(const Duration(seconds:60))){count+=b.length;if(count>available!['size'])throw const FormatException('大小超限');out.add(b);progress=(100*count/available!['size']).floor();notifyListeners();}}finally{await out.close();}
      if(count!=available!['size']||'${await sha256.bind(tmp.openRead()).first}'!=available!['sha256'])throw const FormatException('SHA256 校验失败');
      if(await archive.exists())await archive.delete();await tmp.rename(archive.path);ready=true;status='已校验，可以安装';
    }catch(e){error='$e';status='下载失败';}finally{client.close(force:true);if(await tmp.exists())await tmp.delete();busy=false;notifyListeners();}
  }
  Future<void> install() async {
    if(!Platform.isWindows||kDebugMode||!ready||busy)throw StateError('仅 Windows release 构建支持安装已下载更新');
    if('${await sha256.bind(archive.openRead()).first}'!=available!['sha256'])throw StateError('安装包改变，请重新下载');
    final script=File(p.join(work.path,'apply-update.ps1'));
    await script.writeAsString(await rootBundle.loadString('assets/apply-update.ps1'));
    final job=File(p.join(work.path,'job.json'));
    await job.writeAsString(jsonEncode({'root':root,'zip':archive.path,'version':available!['version'],'sha256':available!['sha256'],'pid':pid}));
    await Process.start('powershell.exe',['-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',script.path,'-JobFile',job.path],mode:ProcessStartMode.detached);
    exit(0);
  }
}