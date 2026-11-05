import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:workcalendar/data/repository.dart';
import 'package:workcalendar/data/previews.dart';
import 'package:workcalendar/domain/models.dart';
void main() {
 test('invalid stored records cannot be overwritten by import', () async {
  final dir=await Directory.systemTemp.createTemp('wc_guard');
  try {
   final f=File('${dir.path}/competitions.json');
   final raw=jsonEncode({'competitions':[{'name':'bad','deadline':'invalid'}]});
   await f.writeAsString(raw);
   final repo=await WcRepository.open(dir.path);
   final c=Competition.fromLegacyJson({'name':'new','deadline':'2027-01-01'});
   await expectLater(repo.upsertComp(c), throwsA(isA<FileSystemException>()));
   expect(await f.readAsString(),raw);expect(repo.compCount,0);
  } finally {await dir.delete(recursive:true);}
 });
 test('headless preview preserves original bytes', () async {
  final dir=await Directory.systemTemp.createTemp('wc_preview');
  try {
   final f=File('${dir.path}/sample.png');
   final bytes=img.encodePng(img.Image(width:1800,height:100));
   await f.writeAsBytes(bytes);await ensureCertificatePreview(f.path);
   expect(await f.readAsBytes(),bytes);
   final preview=img.decodeJpg(await File('${f.path}.preview.jpg').readAsBytes());
   expect(preview!.width,1600);
  } finally {await dir.delete(recursive:true);}
 });
}