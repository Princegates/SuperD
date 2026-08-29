import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/audit_log_entry.dart';
import '../../../models/commission_payment.dart';
import '../../../models/customer.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_incident.dart';
import '../../../models/driver_daily_fee.dart';
import '../../../models/driver_notice.dart';
import '../../../models/payment.dart';

/// Every payment ever recorded - the raw data behind the Console's Finance
/// tab. Aggregation (totals by status/method/etc) happens in the tab
/// itself rather than here, since it's cheap and there's only one
/// consumer so far.
final allPaymentsProvider = FutureProvider<List<Payment>>((ref) {
  return ref.watch(paymentRepositoryProvider).fetchAll();
});

/// Every commission record ever created - the raw data behind the
/// Console's Commission tab, same one-shot-fetch pattern as
/// [allPaymentsProvider].
final allCommissionPaymentsProvider = FutureProvider<List<CommissionPayment>>((
  ref,
) {
  return ref.watch(commissionRepositoryProvider).fetchAll();
});

/// Every daily fee record ever created - the raw data behind the
/// Console's Daily Fees tab, same one-shot-fetch pattern as
/// [allCommissionPaymentsProvider].
final allDriverDailyFeesProvider = FutureProvider<List<DriverDailyFee>>((ref) {
  return ref.watch(driverDailyFeeRepositoryProvider).fetchAll();
});

/// The most recent driver-rejected/driver-cancelled deliveries - the raw
/// data behind the Console Overview's "Rejections & cancellations" feed,
/// same one-shot-fetch pattern as [allCommissionPaymentsProvider].
final deliveryIncidentsProvider = FutureProvider<List<DeliveryIncident>>((ref) {
  return ref.watch(deliveryRepositoryProvider).fetchIncidents();
});

/// Every driver's current free-day balance, keyed by driver id - the raw
/// data behind Console > Daily Fees' incentive section.
final allFreeDayBalancesProvider = FutureProvider<Map<String, int>>((ref) {
  return ref.watch(driverDailyFeeRepositoryProvider).fetchAllFreeDayBalances();
});

/// The most recent audit log entries - only resolves any rows for a
/// super admin, since RLS hides everything from anyone else.
final auditLogProvider = FutureProvider<List<AuditLogEntry>>((ref) {
  return ref.watch(auditRepositoryProvider).fetchRecent();
});

/// Every notice ever posted, regardless of audience or status - the raw
/// data behind Console > Notices, same one-shot-fetch pattern as
/// [allCommissionPaymentsProvider].
final allDriverNoticesProvider = FutureProvider<List<DriverNotice>>((ref) {
  return ref.watch(driverNoticeRepositoryProvider).fetchAll();
});

/// The super-admin-only customer directory - live, so a name/address
/// correction from a new delivery shows up without a manual refresh. RLS
/// keeps this empty for anyone who isn't a super admin (a dispatcher or
/// auditor never sees it at all - see `0055_customer_directory.sql`).
final allCustomersProvider = StreamProvider<List<Customer>>((ref) {
  return ref.watch(customerRepositoryProvider).watchAll();
});

/// One customer's full delivery history (by phone), fetched on demand when
/// their row is expanded in Console > Customers rather than eagerly for
/// everyone in the directory.
final customerDeliveryHistoryProvider =
    FutureProvider.family<List<Delivery>, String>((ref, phone) {
      return ref.watch(customerRepositoryProvider).fetchDeliveryHistory(phone);
    });
