# Third-party notices

The Commons Clause in the project LICENSE applies to WorkCalendar's original code, not to independently licensed third-party components.

| Component | Version | License / source |
|---|---|---|
| Apache ECharts | 5.5.1 | Apache-2.0, https://echarts.apache.org/ |
| Tailwind CSS browser runtime | bundled existing runtime | MIT, https://tailwindcss.com/ |
| QRCode.js | bundled existing runtime | MIT, https://github.com/davidshimjs/qrcodejs |
| jsQR | 1.4.0 | Apache-2.0 |
| SheetJS CE | 0.20.3 | Apache-2.0; see vendor/SheetJS-PROVENANCE.json |
| pywebview | 6.2.1 | BSD-3-Clause |
| Python / pythonnet / clr_loader / cffi | see build environment manifest | Their original licenses in LICENSES |
| Capacitor Android / App / Filesystem / Share | 6.x, exact versions in package-lock.json | MIT |
| Capacitor ML Kit Barcode Scanning | 6.2.0 | Apache-2.0; Google ML Kit dependencies retain Google's terms |
| OkHttp / Okio / Kotlin | resolved by Android build | Apache-2.0 |
| PyInstaller | 6.21.0 (build tool) | GPL with its bootloader exception, see bundled license |
| node-tar | 7.5.22 (build tool) | ISC |

Full license and notice files obtained from distributed packages are in LICENSES/. This directory also contains notices for build and test tools, which does not mean those tools are included in the running application.

Microsoft Edge WebView2 Runtime is a system prerequisite distributed by Microsoft; it is not bundled as an installer. Android SDK and JDK are build prerequisites, not part of the APK.

Google ML Kit's downloaded/native barcode components are not relicensed by this project. See https://developers.google.com/ml-kit/terms and the Android dependency notices. Preserve third-party notices when redistributing or rebuilding.

The vendored SheetJS script was obtained from the @e965/xlsx mirror after the official CDN returned 403. Its complete script MD5 matches the value published by SheetJS for 0.20.3; a SHA256 and the provenance URL are recorded. No third-party package scripts were executed to obtain it.
