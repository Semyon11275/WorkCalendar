import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/release_updater.dart';
import '../state/providers.dart';
class UpdatePage extends ConsumerWidget {
 const UpdatePage({super.key});
 @override Widget build(BuildContext context,WidgetRef ref){
  final u=ReleaseUpdater.instance;
  return Scaffold(appBar:AppBar(title:const Text('软件更新')),body:ListenableBuilder(listenable:u,builder:(context,_)=>ListView(padding:const EdgeInsets.all(24),children:[
   const Text('Flutter 独立更新通道 · 当前 1.0.0-alpha.6'),
   const Text('启动时检查 GitHub；确认后下载并安装。userdata 保留。'),
   Text(u.status),if(u.error.isNotEmpty)Text(u.error),if(u.busy)LinearProgressIndicator(value:u.status=='下载中'?u.progress/100:null),
   TextButton(onPressed:u.busy?null:u.check,child:const Text('检查更新')),
   TextButton(onPressed:u.busy||u.available==null||!Platform.isWindows?null:u.download,child:const Text('下载 Windows 更新')),
   TextButton(onPressed:!u.ready||u.busy?null:()async{
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('安装并重启？'),content:const Text('请先保存编辑内容。将退出程序、备份运行文件并安装更新，个人数据保留。'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('取消')),TextButton(onPressed:()=>Navigator.pop(c,true),child:const Text('安装'))]));
    if(yes!=true)return;
    final repo=ref.read(repositoryProvider);
    try{await repo.prepareForUpdate();await u.install();}catch(e){repo.updatePending=false;if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
   },child:const Text('安装并重启')),
   Text('${u.available?['notes']??''}'),
   if(!Platform.isWindows)const Text('本开发版暂仅支持 Windows 自动安装。'),
  ])));
 }
}