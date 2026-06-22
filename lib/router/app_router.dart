import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../core/widgets/app_shell.dart';

// Feature screens
import '../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../features/tables/presentation/screens/tables_screen.dart';
import '../features/orders/presentation/screens/order_screen.dart';
import '../features/kitchen/presentation/screens/kitchen_screen.dart';
import '../features/cashier/presentation/screens/cashier_screen.dart';
import '../features/payment_history/presentation/screens/payment_history_screen.dart';
import '../features/menu/presentation/screens/menu_management_screen.dart';
import '../features/inventory/presentation/screens/inventory_screen.dart';
import '../features/bar/presentation/screens/bar_screen.dart';
import '../features/purchase/presentation/screens/purchase_screen.dart';
import '../features/expense/presentation/screens/expense_screen.dart';
import '../features/credit/presentation/screens/credit_screen.dart';
import '../features/reservation/presentation/screens/reservation_screen.dart';
import '../features/customers/presentation/screens/customers_screen.dart';
import '../features/staff/presentation/screens/staff_screen.dart';
import '../features/attendance/presentation/screens/attendance_screen.dart';
import '../features/reports/presentation/screens/reports_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/notifications/presentation/screens/notifications_screen.dart';
import '../features/loyalty/presentation/screens/loyalty_screen.dart';
import '../features/suppliers/presentation/screens/supplier_screen.dart';
import '../features/branches/presentation/screens/branch_management_screen.dart';
import '../features/shift_closing/presentation/screens/shift_closing_screen.dart';
import '../features/audit_logs/presentation/screens/audit_log_screen.dart';
import '../features/super_admin/presentation/screens/super_admin_portal.dart';

// Nav items model
class NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String path;
  final List<String> allowedRoles;

  const NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.path,
    this.allowedRoles = const [],
  });
}

const List<NavItem> allNavItems = [
  NavItem(label: 'Super Admin', icon: LucideIcons.shieldCheck, activeIcon: LucideIcons.shieldCheck, path: '/super-admin',
      allowedRoles: ['super_admin']),
  NavItem(label: 'Dashboard', icon: LucideIcons.layoutDashboard, activeIcon: LucideIcons.layoutDashboard, path: '/dashboard',
      allowedRoles: ['branch_manager', 'cashier', 'waiter', 'kitchen', 'inventory', 'accountant']),
  NavItem(label: 'Tables', icon: LucideIcons.grid, activeIcon: LucideIcons.grid, path: '/tables',
      allowedRoles: ['branch_manager', 'cashier', 'waiter']),
  NavItem(label: 'Kitchen', icon: LucideIcons.chefHat, activeIcon: LucideIcons.chefHat, path: '/kitchen',
      allowedRoles: ['branch_manager', 'cashier', 'kitchen']),
  NavItem(label: 'Cashier', icon: LucideIcons.scan, activeIcon: LucideIcons.scan, path: '/cashier',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Payments', icon: LucideIcons.receipt, activeIcon: LucideIcons.receipt, path: '/payment-history',
      allowedRoles: ['branch_manager', 'cashier', 'accountant']),
  NavItem(label: 'Menu', icon: LucideIcons.utensils, activeIcon: LucideIcons.utensils, path: '/menu',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Inventory', icon: LucideIcons.package, activeIcon: LucideIcons.package, path: '/inventory',
      allowedRoles: ['branch_manager', 'inventory']),
  NavItem(label: 'Bar', icon: LucideIcons.wine, activeIcon: LucideIcons.wine, path: '/bar',
      allowedRoles: ['branch_manager', 'inventory']),
  NavItem(label: 'Purchases', icon: LucideIcons.shoppingCart, activeIcon: LucideIcons.shoppingCart, path: '/purchases',
      allowedRoles: ['branch_manager', 'inventory']),
  NavItem(label: 'Expenses', icon: LucideIcons.banknote, activeIcon: LucideIcons.banknote, path: '/expenses',
      allowedRoles: ['branch_manager', 'accountant']),
  NavItem(label: 'Credit', icon: LucideIcons.creditCard, activeIcon: LucideIcons.creditCard, path: '/credit',
      allowedRoles: ['branch_manager', 'cashier', 'accountant']),
  NavItem(label: 'Reservations', icon: LucideIcons.calendarCheck, activeIcon: LucideIcons.calendarCheck, path: '/reservations',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Customers', icon: LucideIcons.users, activeIcon: LucideIcons.users, path: '/customers',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Staff', icon: LucideIcons.badge, activeIcon: LucideIcons.badge, path: '/staff',
      allowedRoles: ['branch_manager']),
  NavItem(label: 'Attendance', icon: LucideIcons.fingerprint, activeIcon: LucideIcons.fingerprint, path: '/attendance',
      allowedRoles: ['branch_manager', 'cashier', 'waiter', 'kitchen', 'inventory']),
  NavItem(label: 'Reports', icon: LucideIcons.barChart3, activeIcon: LucideIcons.barChart3, path: '/reports',
      allowedRoles: ['branch_manager', 'accountant']),
  NavItem(label: 'Settings', icon: LucideIcons.settings, activeIcon: LucideIcons.settings, path: '/settings',
      allowedRoles: ['super_admin', 'branch_manager']),
  NavItem(label: 'Loyalty', icon: LucideIcons.star, activeIcon: LucideIcons.star, path: '/loyalty',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Suppliers', icon: LucideIcons.truck, activeIcon: LucideIcons.truck, path: '/suppliers',
      allowedRoles: ['branch_manager', 'inventory']),
  NavItem(label: 'Branches', icon: LucideIcons.store, activeIcon: LucideIcons.store, path: '/branches',
      allowedRoles: ['super_admin', 'branch_manager']),
  NavItem(label: 'Shift Close', icon: LucideIcons.lock, activeIcon: LucideIcons.lock, path: '/shift-closing',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Audit Logs', icon: LucideIcons.history, activeIcon: LucideIcons.history, path: '/audit-logs',
      allowedRoles: ['super_admin', 'branch_manager']),
];

List<NavItem> getNavItemsForRole(String? role) {
  if (role == null) return [];
  return allNavItems.where((item) => item.allowedRoles.contains(role)).toList();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = authState.value != null;
      final isLoginPage = state.matchedLocation == '/login';
      final isSplash = state.matchedLocation == '/';

      if (isSplash) return null;
      if (!isLoggedIn && !isLoginPage) return '/login';
      if (isLoggedIn) {
        final role = authState.value?.role;
        if (isLoginPage) {
          return role == 'super_admin' ? '/super-admin' : '/dashboard';
        }
        if (state.matchedLocation == '/dashboard' && role == 'super_admin') {
          return '/super-admin';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (ctx, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (ctx, _) => const LoginScreen()),
      ShellRoute(
        builder: (ctx, state, child) => AppShell(currentPath: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/super-admin', builder: (ctx, _) => const SuperAdminPortal()),
          GoRoute(path: '/dashboard', builder: (ctx, _) => const DashboardScreen()),
          GoRoute(path: '/tables', builder: (ctx, _) => const TablesScreen()),
          GoRoute(
            path: '/tables/:tableId/order',
            builder: (ctx, state) => OrderScreen(
              tableId: state.pathParameters['tableId']!,
              sessionId: state.uri.queryParameters['sessionId'] ?? '',
            ),
          ),
          GoRoute(path: '/kitchen', builder: (ctx, _) => const KitchenScreen()),
          GoRoute(
            path: '/cashier',
            builder: (ctx, state) => CashierScreen(
              sessionId: state.uri.queryParameters['sessionId'] ?? '',
              tableId: state.uri.queryParameters['tableId'] ?? '',
            ),
          ),
          GoRoute(path: '/payment-history', builder: (ctx, _) => const PaymentHistoryScreen()),
          GoRoute(path: '/menu', builder: (ctx, _) => const MenuManagementScreen()),
          GoRoute(path: '/inventory', builder: (ctx, _) => const InventoryScreen()),
          GoRoute(path: '/bar', builder: (ctx, _) => const BarScreen()),
          GoRoute(path: '/purchases', builder: (ctx, _) => const PurchaseScreen()),
          GoRoute(path: '/expenses', builder: (ctx, _) => const ExpenseScreen()),
          GoRoute(path: '/credit', builder: (ctx, _) => const CreditScreen()),
          GoRoute(path: '/reservations', builder: (ctx, _) => const ReservationScreen()),
          GoRoute(path: '/customers', builder: (ctx, _) => const CustomersScreen()),
          GoRoute(path: '/staff', builder: (ctx, _) => const StaffScreen()),
          GoRoute(path: '/attendance', builder: (ctx, _) => const AttendanceScreen()),
          GoRoute(path: '/reports', builder: (ctx, _) => const ReportsScreen()),
          GoRoute(path: '/settings', builder: (ctx, _) => const SettingsScreen()),
          GoRoute(path: '/notifications', builder: (ctx, _) => const NotificationsScreen()),
          GoRoute(path: '/loyalty', builder: (ctx, _) => const LoyaltyScreen()),
          GoRoute(path: '/suppliers', builder: (ctx, _) => const SupplierScreen()),
          GoRoute(path: '/branches', builder: (ctx, _) => const BranchManagementScreen()),
          GoRoute(path: '/shift-closing', builder: (ctx, _) => const ShiftClosingScreen()),
          GoRoute(path: '/audit-logs', builder: (ctx, _) => const AuditLogScreen()),
        ],
      ),
    ],
    errorBuilder: (ctx, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.error}')),
    ),
  );
});
