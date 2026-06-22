import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:responsive_framework/responsive_framework.dart';
import '../constants/app_colors.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../router/app_router.dart';

class AppShell extends ConsumerWidget {
  final Widget child;
  final String currentPath;

  const AppShell({super.key, required this.child, required this.currentPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(authNotifierProvider);
    final profile = profileAsync.value;
    final navItems = getNavItemsForRole(profile?.role);
    final isWide = ResponsiveBreakpoints.of(context).isDesktop;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            _SideNavRail(
              navItems: navItems,
              currentPath: currentPath,
              profile: profile,
              onSignOut: () async {
                await ref.read(authNotifierProvider.notifier).signOut();
                if (context.mounted) context.go('/login');
              },
            ),
            Expanded(child: child),
          ],
        ),
      );
    }

    // Mobile: bottom nav (limited items)
    final mobileItems = navItems.take(5).toList();
    final currentIdx = mobileItems.indexWhere((i) => currentPath.startsWith(i.path));

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIdx < 0 ? 0 : currentIdx,
          onTap: (i) => context.go(mobileItems[i].path),
          items: mobileItems.map((item) => BottomNavigationBarItem(
            icon: Icon(item.icon),
            activeIcon: Icon(item.activeIcon),
            label: item.label,
          )).toList(),
        ),
      ),
    );
  }
}

class _SideNavRail extends StatefulWidget {
  final List<NavItem> navItems;
  final String currentPath;
  final dynamic profile;
  final VoidCallback onSignOut;

  const _SideNavRail({
    required this.navItems,
    required this.currentPath,
    required this.profile,
    required this.onSignOut,
  });

  @override
  State<_SideNavRail> createState() => _SideNavRailState();
}

class _SideNavRailState extends State<_SideNavRail> {
  bool _collapsed = false;

  String get _roleLabel {
    switch (widget.profile?.role) {
      case 'super_admin': return 'Super Admin';
      case 'branch_manager': return 'Manager';
      case 'cashier': return 'Cashier';
      case 'waiter': return 'Waiter';
      case 'kitchen': return 'Kitchen';
      case 'inventory': return 'Inventory';
      case 'accountant': return 'Accountant';
      default: return 'Staff';
    }
  }

  Color get _roleColor {
    switch (widget.profile?.role) {
      case 'branch_manager': return AppColors.roleManager;
      case 'cashier': return AppColors.roleCashier;
      case 'waiter': return AppColors.roleWaiter;
      case 'kitchen': return AppColors.roleKitchen;
      case 'inventory': return AppColors.roleInventory;
      default: return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _collapsed ? 72.0 : 240.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: w,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/katiyastationlogo.jpeg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                if (!_collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('KATIYA', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 1.5)),
                        Text('STATION RMS', style: GoogleFonts.outfit(fontSize: 9, color: AppColors.textSecondary, letterSpacing: 1)),
                      ],
                    ),
                  ),
                ],
                IconButton(
                  icon: Icon(_collapsed ? Icons.chevron_right : Icons.chevron_left, color: AppColors.textSecondary, size: 18),
                  onPressed: () => setState(() => _collapsed = !_collapsed),
                ),
              ],
            ),
          ),
          // Nav Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: widget.navItems.map((item) {
                final isActive = widget.currentPath.startsWith(item.path);
                return _NavTile(
                  item: item,
                  isActive: isActive,
                  collapsed: _collapsed,
                  onTap: () => context.go(item.path),
                );
              }).toList(),
            ),
          ),
          // User profile footer
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _roleColor.withValues(alpha: 0.2),
                  child: Text(
                    widget.profile?.fullName?.substring(0, 1).toUpperCase() ?? 'U',
                    style: TextStyle(color: _roleColor, fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                if (!_collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.profile?.fullName ?? 'User',
                          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(_roleLabel, style: GoogleFonts.outfit(fontSize: 11, color: _roleColor)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: AppColors.error, size: 18),
                    onPressed: widget.onSignOut,
                    tooltip: 'Sign Out',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final NavItem item;
  final bool isActive;
  final bool collapsed;
  final VoidCallback onTap;

  const _NavTile({required this.item, required this.isActive, required this.collapsed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: collapsed ? item.label : '',
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 12 : 16, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isActive ? Border.all(color: AppColors.primary.withValues(alpha: 0.25)) : null,
          ),
          child: Row(
            mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              // Red left accent bar on active item
              if (!collapsed)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 3,
                  height: 20,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              Icon(
                isActive ? item.activeIcon : item.icon,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
                size: 20,
              ),
              if (!collapsed) ...[
                const SizedBox(width: 10),
                Text(
                  item.label,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
