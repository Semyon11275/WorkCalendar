/// 旧版界面（0.4.2 wenku8 主题）精确还原 token。
/// 来源：_internal/web/assets/theme_wenku8.css + index.html（Tailwind 基底）
/// + core.js STATUS_COLOR / CAT_COLORS / countdownBadge。
/// 仅在 uiMode=legacy 时使用；与新设计体系（DesignTokens）互不混用。
library;

import 'package:flutter/material.dart';

class LegacyTokens {
  // —— 表面（wenku8.css 实测值）——
  static const bgL = Color(0xFFF9F9FF);
  static const bgD = Color(0xFF101318);
  static const headerL = Color(0xFFF5F7FD); // rgba(249,250,253,.94) 叠底近似
  static const headerD = Color(0xFF16191F);
  static const navL = Color(0xFFF1F3FA);
  static const navD = Color(0xFF16191F);
  static const cardL = Color(0xFFFFFFFF);
  static const cardD = Color(0xFF1B1E24);
  static const hairlineL = Color(0xFFE6E8EF);
  static const hairlineD = Color(0xFF2E323A);
  static const drawerL = Color(0xFFF9F9FF);
  static const drawerD = Color(0xFF14171C);

  // —— 文字（Tailwind slate 系）——
  static const textL = Color(0xFF1E293B); // slate-800
  static const textD = Color(0xFFE2E8F0);
  static const mutedL = Color(0xFF64748B); // slate-500
  static const mutedD = Color(0xFF94A3B8);

  // —— 品牌主色（wenku8 M3 蓝）——
  static const primaryL = Color(0xFF0B57D0);
  static const primaryD = Color(0xFFA8C7FA);
  static const onPrimaryL = Color(0xFFFFFFFF);
  static const onPrimaryD = Color(0xFF062E5F);
  static const navActiveBgL = Color(0xFFD3E3FD);
  static const navActiveBgD = Color(0xFF1E3A66);
  static const navActiveTextL = Color(0xFF041E49);
  static const navActiveTextD = Color(0xFFD3E3FD);
  static const navHoverL = Color(0xFFE4E9F5);
  static const navHoverD = Color(0xFF2A2E36);
  static const navTextL = Color(0xFF44474E);
  static const navTextD = Color(0xFFC3C6CF);
  static const portInfoL = Color(0xFFEDF0F7);
  static const portInfoD = Color(0xFF1B1E24);

  // —— 状态徽标（core.js STATUS_COLOR）——
  static const urgentL = Color(0xFFFFE4E6); // rose-100
  static const urgentD = Color(0xFF4C1D33); // rose-900/40 近似
  static const urgentTextL = Color(0xFFBE123C); // rose-700
  static const urgentTextD = Color(0xFFFDA4AF); // rose-300
  static const pastSuggL = Color(0xFFFEF3C7); // amber-100
  static const pastSuggD = Color(0xFF453011);
  static const pastSuggTextL = Color(0xFFB45309); // amber-700
  static const pastSuggTextD = Color(0xFFFCD34D); // amber-300
  static const overdueL = Color(0xFFE2E8F0); // slate-200
  static const overdueD = Color(0xFF334155); // slate-700
  static const overdueTextL = Color(0xFF64748B); // slate-500
  static const overdueTextD = Color(0xFF94A3B8);
  static const submittedL = Color(0xFFD1FAE5); // emerald-100
  static const submittedD = Color(0xFF0B3B2E);
  static const submittedTextL = Color(0xFF047857); // emerald-700
  static const submittedTextD = Color(0xFF6EE7B7); // emerald-300
  static const doneL = Color(0xFFCCFBF1); // teal-100
  static const doneD = Color(0xFF0C3D3A);
  static const doneTextL = Color(0xFF0F766E); // teal-700
  static const doneTextD = Color(0xFF5EEAD4); // teal-300
  static const abandonedL = Color(0xFFE2E8F0);
  static const abandonedD = Color(0xFF334155);
  static const abandonedTextL = Color(0xFF64748B);
  static const abandonedTextD = Color(0xFF94A3B8);
  static const openL = Color(0xFFE0F2FE); // sky-100
  static const openD = Color(0xFF0C3B5E);
  static const openTextL = Color(0xFF0369A1); // sky-700
  static const openTextD = Color(0xFF7DD3FC); // sky-300
  static const notStartedL = Color(0xFFF1F5F9); // slate-100
  static const notStartedD = Color(0xFF334155);
  static const notStartedTextL = Color(0xFF475569); // slate-600
  static const notStartedTextD = Color(0xFFCBD5E1); // slate-300
  static const submittingL = Color(0xFFE0E7FF); // indigo-100
  static const submittingD = Color(0xFF27306B);
  static const submittingTextL = Color(0xFF4338CA); // indigo-700
  static const submittingTextD = Color(0xFFA5B4FC); // indigo-300

  // —— 倒计时渐变（countdownBadge）——
  static const cdToday = [Color(0xFFE11D48), Color(0xFFEF4444)]; // rose-600→red-500
  static const cdUrgent = [Color(0xFFF43F5E), Color(0xFFF97316)]; // rose-500→orange-500
  static const cdSoon = [Color(0xFFF59E0B), Color(0xFFEAB308)]; // amber-500→yellow-500
  static const cdCalm = [Color(0xFF10B981), Color(0xFF14B8A6)]; // emerald-500→teal-500
  static const cdDone = [Color(0xFFECFDF5), Color(0xFFD1FAE5)]; // emerald-50 浅底
  static const cdDoneTextL = Color(0xFF059669);
  static const cdDoneTextD = Color(0xFF6EE7B7);

  // —— 类别 chip（CAT_COLORS，哈希取色）——
  static const catChips = <(Color, Color, Color, Color)>[
    // (浅底, 浅字, 深底, 深字)
    (Color(0xFFEEF2FF), Color(0xFF4F46E5), Color(0xFF27296B), Color(0xFFA5B4FC)), // indigo
    (Color(0xFFFFF1F2), Color(0xFFE11D48), Color(0xFF5F1F2A), Color(0xFFFDA4AF)), // rose
    (Color(0xFFECFDF5), Color(0xFF059669), Color(0xFF0B3B2E), Color(0xFF6EE7B7)), // emerald
    (Color(0xFFFFFBEB), Color(0xFFD97706), Color(0xFF453011), Color(0xFFFCD34D)), // amber
    (Color(0xFFF0F9FF), Color(0xFF0284C7), Color(0xFF0C3B5E), Color(0xFF7DD3FC)), // sky
    (Color(0xFFF5F3FF), Color(0xFF7C3AED), Color(0xFF3A2450), Color(0xFFD8B4FE)), // violet
    (Color(0xFFF1F5F9), Color(0xFF64748B), Color(0xFF334155), Color(0xFF94A3B8)), // slate
  ];

  // —— 行左紧急色条 ——
  static const barUrgent = Color(0xFFF43F5E);
  static const barSoon = Color(0xFFF59E0B);
  static const barCalm = Color(0xFF10B981);
  static const barDone = Color(0xFF94A3B8);

  // —— 抽屉渐变头 ——
  static const drawerCompGrad = [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFA855F7)]; // indigo→violet→purple
  static const drawerAwardGrad = [Color(0xFFF59E0B), Color(0xFFF97316), Color(0xFFF43F5E)]; // amber→orange→rose

  // 数字/等宽回退（wenku8.css: Segoe UI 优先）
  static const monoFallback = ['Segoe UI', 'Microsoft YaHei'];

  // —— 动效（motion_pack.js）——
  static const revealMs = 420; // 视图切换 cubic-bezier(.18,.72,.18,1)
  static const pressMs = 280; // 点击 .93→1.045→1
  static const drawerMs = 260; // 抽屉滑出
}
