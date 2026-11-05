import 'package:flutter_test/flutter_test.dart';
import 'package:workcalendar/services/release_updater.dart';
void main(){
 test('Flutter channel excludes legacy and orders alpha numerically',(){
  expect(newerRelease('flutter-v1.0.0-alpha.10','1.0.0-alpha.6'),true);
  expect(newerRelease('flutter-v1.0.0','1.0.0-alpha.6'),true);
  expect(selectFlutterUpdate([{'tag_name':'v0.5.99','assets':[]}],'1.0.0-alpha.6'),null);
 });
 test('Flutter release requires exact asset URL and digest',(){
  final release={'tag_name':'flutter-v1.0.0-alpha.7','assets':[{'name':'WorkCalendar-Flutter-Windows-x64-v1.0.0-alpha.7.zip','browser_download_url':'https://github.com/Semyon11275/WorkCalendar/releases/download/flutter-v1.0.0-alpha.7/WorkCalendar-Flutter-Windows-x64-v1.0.0-alpha.7.zip','digest':'sha256:${'a'*64}','size':20}]};
  expect(selectFlutterUpdate([release],'1.0.0-alpha.6')!['version'],'1.0.0-alpha.7');
  (release['assets'] as List).first['browser_download_url']='https://evil.test/package';
  expect(()=>selectFlutterUpdate([release],'1.0.0-alpha.6'),throwsFormatException);
 });
}