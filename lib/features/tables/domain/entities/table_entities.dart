import 'package:equatable/equatable.dart';

class RestaurantTable extends Equatable {
  final String id;
  final String branchId;
  final String tableNumber;
  final String section;
  final int capacity;
  final String status;
  final String? currentSessionId;
  final bool billRequested;
  final DateTime? billRequestedAt;

  const RestaurantTable({
    required this.id,
    required this.branchId,
    required this.tableNumber,
    required this.section,
    required this.capacity,
    required this.status,
    this.currentSessionId,
    this.billRequested = false,
    this.billRequestedAt,
  });

  factory RestaurantTable.fromJson(Map<String, dynamic> json) {
    return RestaurantTable(
      id: json['id'] as String,
      branchId: json['branch_id'] as String,
      tableNumber: json['table_number'] as String,
      section: json['section'] as String? ?? 'Main',
      capacity: json['capacity'] as int? ?? 4,
      status: json['status'] as String? ?? 'available',
      currentSessionId: json['current_session_id'] as String?,
      billRequested: json['bill_requested'] as bool? ?? false,
      billRequestedAt: json['bill_requested_at'] != null
          ? DateTime.parse(json['bill_requested_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'branch_id': branchId,
        'table_number': tableNumber,
        'section': section,
        'capacity': capacity,
        'status': status,
        'bill_requested': billRequested,
        'bill_requested_at': billRequestedAt?.toIso8601String(),
      };

  bool get isAvailable => status == 'available';
  bool get isOccupied => status == 'occupied';
  bool get isReserved => status == 'reserved';
  bool get isCleaning => status == 'cleaning';

  @override
  List<Object?> get props => [
        id,
        tableNumber,
        status,
        section,
        currentSessionId,
        billRequested,
        billRequestedAt,
      ];
}

class TableSession extends Equatable {
  final String id;
  final String tableId;
  final String branchId;
  final String sessionNumber;
  final String status;
  final String? waiterId;
  final String? customerId;
  final int guestCount;
  final double totalAmount;
  final DateTime openedAt;
  final DateTime? closedAt;
  final bool billRequested;
  final DateTime? billRequestedAt;

  const TableSession({
    required this.id,
    required this.tableId,
    required this.branchId,
    required this.sessionNumber,
    required this.status,
    this.waiterId,
    this.customerId,
    this.guestCount = 1,
    this.totalAmount = 0,
    required this.openedAt,
    this.closedAt,
    this.billRequested = false,
    this.billRequestedAt,
  });

  factory TableSession.fromJson(Map<String, dynamic> json) {
    return TableSession(
      id: json['id'] as String,
      tableId: json['table_id'] as String,
      branchId: json['branch_id'] as String,
      sessionNumber: json['session_number'] as String,
      status: json['status'] as String? ?? 'open',
      waiterId: json['waiter_id'] as String?,
      customerId: json['customer_id'] as String?,
      guestCount: json['guest_count'] as int? ?? 1,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      openedAt: DateTime.parse(json['opened_at'] as String),
      closedAt: json['closed_at'] != null
          ? DateTime.parse(json['closed_at'] as String)
          : null,
      billRequested: json['bill_requested'] as bool? ?? false,
      billRequestedAt: json['bill_requested_at'] != null
          ? DateTime.parse(json['bill_requested_at'] as String)
          : null,
    );
  }

  bool get isOpen => status == 'open';
  bool get isClosed => status == 'closed';
  bool get isBilled => status == 'billed';

  @override
  List<Object?> get props => [
        id,
        tableId,
        sessionNumber,
        status,
        totalAmount,
        billRequested,
        billRequestedAt,
      ];
}
