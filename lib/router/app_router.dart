import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  NavItem(label: 'Dashboard', icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard_rounded, path: '/dashboard',
      allowedRoles: ['super_admin', 'branch_manager', 'cashier', 'waiter', 'kitchen', 'inventory', 'accountant']),
  NavItem(label: 'Tables', icon: Icons.table_restaurant_outlined, activeIcon: Icons.table_restaurant_rounded, path: '/tables',
      allowedRoles: ['branch_manager', 'cashier', 'waiter']),
  NavItem(label: 'Kitchen', icon: Icons.kitchen_outlined, activeIcon: Icons.kitchen_rounded, path: '/kitchen',
      allowedRoles: ['branch_manager', 'cashier', 'kitchen']),
  NavItem(label: 'Cashier', icon: Icons.point_of_sale_outlined, activeIcon: Icons.point_of_sale_rounded, path: '/cashier',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Payments', icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long_rounded, path: '/payment-history',
      allowedRoles: ['branch_manager', 'cashier', 'accountant']),
  NavItem(label: 'Menu', icon: Icons.restaurant_menu_outlined, activeIcon: Icons.restaurant_menu_rounded, path: '/menu',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Inventory', icon: Icons.inventory_2_outlined, activeIcon: Icons.inventory_2_rounded, path: '/inventory',
      allowedRoles: ['branch_manager', 'inventory']),
  NavItem(label: 'Bar', icon: Icons.local_bar_outlined, activeIcon: Icons.local_bar_rounded, path: '/bar',
      allowedRoles: ['branch_manager', 'inventory']),
  NavItem(label: 'Purchases', icon: Icons.shopping_cart_outlined, activeIcon: Icons.shopping_cart_rounded, path: '/purchases',
      allowedRoles: ['branch_manager', 'inventory']),
  NavItem(label: 'Expenses', icon: Icons.money_off_outlined, activeIcon: Icons.money_off_rounded, path: '/expenses',
      allowedRoles: ['branch_manager', 'accountant']),
  NavItem(label: 'Credit', icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet_rounded, path: '/credit',
      allowedRoles: ['branch_manager', 'cashier', 'accountant']),
  NavItem(label: 'Reservations', icon: Icons.event_seat_outlined, activeIcon: Icons.event_seat_rounded, path: '/reservations',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Customers', icon: Icons.people_outlined, activeIcon: Icons.people_rounded, path: '/customers',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Staff', icon: Icons.badge_outlined, activeIcon: Icons.badge_rounded, path: '/staff',
      allowedRoles: ['branch_manager']),
  NavItem(label: 'Attendance', icon: Icons.fingerprint_outlined, activeIcon: Icons.fingerprint_rounded, path: '/attendance',
      allowedRoles: ['branch_manager', 'cashier', 'waiter', 'kitchen', 'inventory']),
  NavItem(label: 'Reports', icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart_rounded, path: '/reports',
      allowedRoles: ['branch_manager', 'accountant']),
  NavItem(label: 'Settings', icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, path: '/settings',
      allowedRoles: ['super_admin', 'branch_manager']),
  NavItem(label: 'Loyalty', icon: Icons.stars_outlined, activeIcon: Icons.stars_rounded, path: '/loyalty',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Suppliers', icon: Icons.local_shipping_outlined, activeIcon: Icons.local_shipping_rounded, path: '/suppliers',
      allowedRoles: ['branch_manager', 'inventory']),
  NavItem(label: 'Branches', icon: Icons.store_outlined, activeIcon: Icons.store_rounded, path: '/branches',
      allowedRoles: ['super_admin', 'branch_manager']),
  NavItem(label: 'Shift Close', icon: Icons.lock_clock_outlined, activeIcon: Icons.lock_clock_rounded, path: '/shift-closing',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Audit Logs', icon: Icons.history_rounded, activeIcon: Icons.manage_history_rounded, path: '/audit-logs',
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
      if (isLoggedIn && isLoginPage) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (ctx, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (ctx, _) => const LoginScreen()),
      ShellRoute(
        builder: (ctx, state, child) => AppShell(currentPath: state.matchedLocation, child: child),
        routes: [
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
