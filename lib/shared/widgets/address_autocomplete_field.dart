import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../utils/geocode_search.dart';

/// Matches [searchAddress]'s signature so a caller can swap in
/// `searchAddressGoogle` (bound to a `SupabaseClient`) without this widget
/// knowing which provider it's talking to.
typedef AddressSearchFn =
    Future<List<GeocodeResult>> Function(String query, {String? sessionToken});

/// Matches `resolvePlaceLocationGoogle`'s signature - only needed for a
/// [AddressSearchFn] whose results carry a [GeocodeResult.placeId] instead
/// of a ready [GeocodeResult.location] (Google's Autocomplete/Details
/// split). Nominatim needs no resolver at all.
typedef PlaceLocationResolver =
    Future<LatLng?> Function(String placeId, {String? sessionToken});

/// A text field that suggests matching places as the user types. Free
/// OpenStreetMap Nominatim search by default (`geocode_search.dart`) - no
/// API key or billing needed; pass [search] (and [resolveLocation], if the
/// provider needs a separate lookup for coordinates) to use Google Places
/// instead. Debounced (450ms) and gated at 3+ characters so it doesn't
/// fire a request per keystroke either way.
///
/// Deliberately built on [TextFormField]'s `onChanged` rather than
/// listening to [controller] directly - `onChanged` only fires from actual
/// typing, never from a programmatic `controller.text = ...` assignment,
/// so picking a suggestion (or a caller setting the address from a map
/// pin elsewhere, e.g. reverse-geocoding) never re-triggers a search or
/// fights with this widget's own state.
class AddressAutocompleteField extends StatefulWidget {
  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.decoration,
    this.validator,
    this.onPlaceSelected,
    this.search = searchAddress,
    this.resolveLocation,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final FormFieldValidator<String>? validator;

  /// Called with the picked suggestion's coordinates - the caller should
  /// use these the same way it would coordinates from the map picker (set
  /// lat/lng, refresh a price estimate, etc.). The field's own text is
  /// already updated to the suggestion's display name before this fires,
  /// and [GeocodeResult.location] is always non-null by the time this
  /// fires, even for a provider that needed [resolveLocation] to fill it
  /// in first.
  final ValueChanged<GeocodeResult>? onPlaceSelected;

  /// Defaults to the free Nominatim search. Pass `searchAddressGoogle`
  /// (bound to a `SupabaseClient` via a closure) to use Google Places
  /// instead - see `google_places_search.dart`.
  final AddressSearchFn search;

  /// Required alongside [search] for a provider whose suggestions don't
  /// carry coordinates up front (Google's `placeId`-only Autocomplete
  /// results) - called once, when a suggestion is actually tapped, never
  /// per keystroke. Left null for Nominatim, whose results already carry
  /// [GeocodeResult.location].
  final PlaceLocationResolver? resolveLocation;

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  Timer? _debounce;
  List<GeocodeResult> _suggestions = const [];
  bool _isSearching = false;
  bool _isResolving = false;

  /// Carries one typed search through to its final selection as a single
  /// billed unit under Google's session pricing (see
  /// `google_places_search.dart`) - minted on the first keystroke of a new
  /// search, reused for every request until a selection is made or the
  /// field goes back to empty, then dropped so the next search starts a
  /// fresh (separately billed) session. Unused by Nominatim, which ignores
  /// the parameter entirely.
  String? _sessionToken;

  static final _random = Random.secure();

  static String _newSessionToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      _sessionToken = null;
      if (_suggestions.isNotEmpty || _isSearching) {
        setState(() {
          _suggestions = const [];
          _isSearching = false;
        });
      }
      return;
    }
    _sessionToken ??= _newSessionToken();
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(query));
  }

  Future<void> _search(String query) async {
    final results = await widget.search(query, sessionToken: _sessionToken);
    if (!mounted) return;
    // The text may have moved on while this request was in flight - only
    // show results if they still match what's currently typed.
    if (widget.controller.text != query) return;
    setState(() {
      _suggestions = results;
      _isSearching = false;
    });
  }

  Future<void> _select(GeocodeResult result) async {
    widget.controller
      ..text = result.displayName
      ..selection = TextSelection.collapsed(offset: result.displayName.length);
    setState(() => _suggestions = const []);
    FocusScope.of(context).unfocus();

    var resolved = result;
    if (result.location == null) {
      final placeId = result.placeId;
      final resolveLocation = widget.resolveLocation;
      if (placeId == null || resolveLocation == null) return;
      setState(() => _isResolving = true);
      final location = await resolveLocation(
        placeId,
        sessionToken: _sessionToken,
      );
      if (!mounted) return;
      setState(() => _isResolving = false);
      if (location == null) return;
      resolved = GeocodeResult(
        displayName: result.displayName,
        location: location,
      );
    }
    // The session this token covered is over either way - a fresh one
    // starts on the next search, billed separately.
    _sessionToken = null;
    widget.onPlaceSelected?.call(resolved);
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      onTapOutside: (_) {
        if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: widget.controller,
            decoration: widget.decoration.copyWith(
              suffixIcon: (_isSearching || _isResolving)
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            validator: widget.validator,
            onChanged: _onChanged,
          ),
          if (_suggestions.isNotEmpty)
            Card(
              margin: const EdgeInsets.only(top: 4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final result = _suggestions[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined, size: 20),
                      title: Text(
                        result.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _select(result),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
