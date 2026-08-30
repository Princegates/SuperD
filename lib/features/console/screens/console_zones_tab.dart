import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_role.dart';
import '../../../models/zone.dart';
import '../../../models/zone_location.dart';
import '../../../shared/screens/location_picker_screen.dart';
import '../../../shared/utils/audit_log.dart';
import '../../../shared/utils/reverse_geocode.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../admin/providers/admin_providers.dart';

/// Super-admin management of zones and the named places within each one.
/// Drivers/vendors only ever pick a zone by name from a dropdown elsewhere
/// in the app - this is where that dropdown's contents (and what each zone
/// actually covers) get defined. An auditor can see this tab too (see
/// [UserRole.canViewAdminConsole]) but every control here is inert for
/// them, enforced server-side either way (`0054_auditor_role_
/// permissions.sql`).
class ConsoleZonesTab extends ConsumerWidget {
  const ConsoleZonesTab({super.key});

  Future<void> _addZone(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add zone'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Zone name'),
          onSubmitted: (v) {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop(v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Unfocus before popping - works around a Flutter framework
              // bug where an autofocused TextField's FocusNode isn't
              // always cleanly detached before this dialog's element tree
              // is torn down, tripping the framework's own
              // "_dependents.isEmpty" assertion and crashing the app.
              FocusScope.of(context).unfocus();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.of(context).pop(controller.text.trim());
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    await ref.read(vendorRepositoryProvider).createZone(name);
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'zone_created',
      entityType: 'zone',
      summary: 'Added zone $name',
    );
    ref.invalidate(zonesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonesState = ref.watch(zonesProvider);
    final isSuperAdmin =
        ref.watch(currentProfileProvider).valueOrNull?.role ==
        UserRole.superAdmin;

    return Scaffold(
      floatingActionButton: isSuperAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _addZone(context, ref),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add zone'),
            )
          : null,
      body: AsyncValueView<List<Zone>>(
        value: zonesState,
        data: (zones) {
          if (zones.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  isSuperAdmin
                      ? 'No zones yet. Tap "Add zone" to create the first '
                            'one.'
                      : 'No zones yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            );
          }
          final list = ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: zones.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _ZoneCard(zone: zones[index]),
          );
          // AbsorbPointer rather than threading a read-only flag into
          // _ZoneCard's own edit/rename/delete/location controls - an
          // auditor can see every zone's coverage and pricing, just can't
          // interact with any of it. RLS is the real backstop either way.
          return isSuperAdmin ? list : AbsorbPointer(child: list);
        },
      ),
    );
  }
}

class _ZoneCard extends ConsumerStatefulWidget {
  const _ZoneCard({required this.zone});

  final Zone zone;

  @override
  ConsumerState<_ZoneCard> createState() => _ZoneCardState();
}

class _ZoneCardState extends ConsumerState<_ZoneCard> {
  late final _baseFareController = TextEditingController(
    text: widget.zone.baseFare?.toStringAsFixed(2),
  );
  late final _pricePerKmController = TextEditingController(
    text: widget.zone.pricePerKm?.toStringAsFixed(2),
  );
  bool _isSavingPricing = false;
  String _locationFilter = '';

  Zone get zone => widget.zone;

  @override
  void dispose() {
    _baseFareController.dispose();
    _pricePerKmController.dispose();
    super.dispose();
  }

  Future<void> _savePricing() async {
    setState(() => _isSavingPricing = true);
    try {
      await ref
          .read(vendorRepositoryProvider)
          .updateZonePricing(
            zoneId: zone.id,
            baseFare: double.tryParse(_baseFareController.text.trim()),
            pricePerKm: double.tryParse(_pricePerKmController.text.trim()),
          );
      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: 'zone_pricing_changed',
        entityType: 'zone',
        entityId: zone.id,
        summary: 'Changed pricing for zone ${zone.name}',
      );
      ref.invalidate(zonesProvider);
    } finally {
      if (mounted) setState(() => _isSavingPricing = false);
    }
  }

  Future<void> _renameZone(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: zone.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename zone'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Zone name'),
          onSubmitted: (v) {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop(v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Unfocus before popping - works around a Flutter framework
              // bug where an autofocused TextField's FocusNode isn't
              // always cleanly detached before this dialog's element tree
              // is torn down, tripping the framework's own
              // "_dependents.isEmpty" assertion and crashing the app.
              FocusScope.of(context).unfocus();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.of(context).pop(controller.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == zone.name) return;

    final oldName = zone.name;
    await ref.read(vendorRepositoryProvider).renameZone(zone.id, name);
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'zone_renamed',
      entityType: 'zone',
      entityId: zone.id,
      summary: 'Renamed zone "$oldName" to "$name"',
    );
    ref.invalidate(zonesProvider);
  }

  Future<void> _deleteZone(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete zone?'),
        content: Text(
          'This removes "${zone.name}" from the zone list. It can\'t be '
          'undone, and only works if no vendor, driver, or delivery is '
          'still assigned to it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(vendorRepositoryProvider).deleteZone(zone.id);
    } on PostgrestException catch (e) {
      if (context.mounted) {
        final inUse = e.code == '23503';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              inUse
                  ? '"${zone.name}" is still assigned to a vendor, driver, '
                        'or delivery - reassign those first'
                  : 'Could not delete this zone',
            ),
          ),
        );
      }
      return;
    }
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'zone_deleted',
      entityType: 'zone',
      entityId: zone.id,
      summary: 'Deleted zone ${zone.name}',
    );
    ref.invalidate(zonesProvider);
  }

  Future<void> _addLocation(BuildContext context, WidgetRef ref) async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (context) =>
            LocationPickerScreen(title: 'Pin a location in ${zone.name}'),
      ),
    );
    if (picked == null || !context.mounted) return;

    final suggested = await reverseGeocode(picked.latitude, picked.longitude);
    if (!context.mounted) return;

    final controller = TextEditingController(text: suggested ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this location'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Location name'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Unfocus before popping - works around a Flutter framework
              // bug where an autofocused TextField's FocusNode isn't
              // always cleanly detached before this dialog's element tree
              // is torn down, tripping the framework's own
              // "_dependents.isEmpty" assertion and crashing the app.
              FocusScope.of(context).unfocus();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.of(context).pop(controller.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    await ref
        .read(vendorRepositoryProvider)
        .addZoneLocation(
          zoneId: zone.id,
          name: name,
          lat: picked.latitude,
          lng: picked.longitude,
        );
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'zone_location_added',
      entityType: 'zone',
      entityId: zone.id,
      summary: 'Added location $name to zone ${zone.name}',
    );
    ref.invalidate(zoneLocationsProvider(zone.id));
  }

  /// Adds many locations at once - one "Name, lat, lng" per line - for
  /// quickly building out a zone's coverage instead of pinning one at a
  /// time. Pasteable straight from a spreadsheet or a list of coordinates
  /// copied out of Google Maps.
  Future<void> _bulkAddLocations(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bulk add locations to ${zone.name}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'One location per line: Name, latitude, longitude',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 4),
              Text(
                'e.g. American House, 5.6234, -0.1712',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 10,
                minLines: 6,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Unfocus before popping - works around a Flutter framework
              // bug where an autofocused TextField's FocusNode isn't
              // always cleanly detached before this dialog's element tree
              // is torn down, tripping the framework's own
              // "_dependents.isEmpty" assertion and crashing the app.
              FocusScope.of(context).unfocus();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.of(context).pop(controller.text);
            },
            child: const Text('Add all'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !context.mounted) return;

    final parsed = <({String name, double lat, double lng})>[];
    var skipped = 0;
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final parts = line.split(',');
      if (parts.length < 3) {
        skipped++;
        continue;
      }
      final lat = double.tryParse(parts[parts.length - 2].trim());
      final lng = double.tryParse(parts[parts.length - 1].trim());
      final name = parts.sublist(0, parts.length - 2).join(',').trim();
      if (lat == null || lng == null || name.isEmpty) {
        skipped++;
        continue;
      }
      parsed.add((name: name, lat: lat, lng: lng));
    }

    if (parsed.isNotEmpty) {
      await ref
          .read(vendorRepositoryProvider)
          .addZoneLocationsBatch(zoneId: zone.id, locations: parsed);
      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: 'zone_locations_bulk_added',
        entityType: 'zone',
        entityId: zone.id,
        summary:
            'Added ${parsed.length} location(s) to zone ${zone.name} '
            'in bulk',
      );
      ref.invalidate(zoneLocationsProvider(zone.id));
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skipped == 0
                ? 'Added ${parsed.length} location(s).'
                : 'Added ${parsed.length} location(s) - skipped $skipped '
                      "line(s) that weren't in \"Name, lat, lng\" format.",
          ),
        ),
      );
    }
  }

  Future<void> _removeLocation(
    BuildContext context,
    WidgetRef ref,
    ZoneLocation location,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove location?'),
        content: Text('This removes "${location.name}" from ${zone.name}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Remove',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(vendorRepositoryProvider).deleteZoneLocation(location.id);
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'zone_location_removed',
      entityType: 'zone',
      entityId: zone.id,
      summary: 'Removed location ${location.name} from zone ${zone.name}',
    );
    ref.invalidate(zoneLocationsProvider(zone.id));
  }

  @override
  Widget build(BuildContext context) {
    final locationsState = ref.watch(zoneLocationsProvider(zone.id));

    return Card(
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                zone.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Zone options',
              onSelected: (action) {
                if (action == 'rename') _renameZone(context, ref);
                if (action == 'delete') _deleteZone(context, ref);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'rename',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Rename'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: AppTheme.danger),
                    title: Text(
                      'Delete',
                      style: TextStyle(color: AppTheme.danger),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        subtitle: locationsState.valueOrNull != null
            ? Text('${locationsState.valueOrNull!.length} location(s)')
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pricing override',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Leave blank to use the app-wide default from Console > '
                  'Settings.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _baseFareController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Base fare',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _pricePerKmController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Per km',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      // Reset the app-wide full-width minimum size (meant
                      // for a lone button stretched across a Column) -
                      // left as-is here, it demands unbounded width and
                      // squeezes the two Expanded fields above/beside it
                      // down to almost nothing. See console_reports_tab.dart.
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(64, 40),
                      ),
                      onPressed: _isSavingPricing ? null : _savePricing,
                      child: _isSavingPricing
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          AsyncValueView<List<ZoneLocation>>(
            value: locationsState,
            loading: (_) => const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                height: 24,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
            data: (locations) {
              final filtered = _locationFilter.isEmpty
                  ? locations
                  : locations
                        .where(
                          (l) => l.name.toLowerCase().contains(
                            _locationFilter.toLowerCase(),
                          ),
                        )
                        .toList();

              return Column(
                children: [
                  // Only worth showing once a zone has enough locations
                  // that scanning the list by eye stops being instant -
                  // no point cluttering a zone with three pins in it.
                  if (locations.length > 8)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search, size: 18),
                          hintText: 'Filter locations by name',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            setState(() => _locationFilter = value),
                      ),
                    ),
                  if (filtered.isEmpty && locations.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(
                        'No location matches "$_locationFilter".',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                  for (final location in filtered)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined, size: 20),
                      title: Text(location.name),
                      subtitle: location.hasCoordinates
                          ? Text(
                              '${location.lat!.toStringAsFixed(5)}, '
                              '${location.lng!.toStringAsFixed(5)}',
                            )
                          : null,
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(
                          Icons.close,
                          size: 18,
                          color: AppTheme.danger,
                        ),
                        onPressed: () =>
                            _removeLocation(context, ref, location),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Wrap(
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: () => _addLocation(context, ref),
                          icon: const Icon(
                            Icons.add_location_alt_outlined,
                            size: 18,
                          ),
                          label: const Text('Add location'),
                        ),
                        TextButton.icon(
                          onPressed: () => _bulkAddLocations(context, ref),
                          icon: const Icon(Icons.playlist_add, size: 18),
                          label: const Text('Bulk add'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
