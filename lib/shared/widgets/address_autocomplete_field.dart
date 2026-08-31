import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/geocode_search.dart';

/// A text field that suggests matching places as the user types, using the
/// same free Nominatim search already powering `LocationPickerScreen`'s
/// search box (`geocode_search.dart`) - no Google Places API key or
/// billing needed. Debounced (450ms) and gated at 3+ characters so it
/// doesn't fire a request per keystroke.
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
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final FormFieldValidator<String>? validator;

  /// Called with the picked suggestion's coordinates - the caller should
  /// use these the same way it would coordinates from the map picker (set
  /// lat/lng, refresh a price estimate, etc.). The field's own text is
  /// already updated to the suggestion's display name before this fires.
  final ValueChanged<GeocodeResult>? onPlaceSelected;

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  Timer? _debounce;
  List<GeocodeResult> _suggestions = const [];
  bool _isSearching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      if (_suggestions.isNotEmpty || _isSearching) {
        setState(() {
          _suggestions = const [];
          _isSearching = false;
        });
      }
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(query));
  }

  Future<void> _search(String query) async {
    final results = await searchAddress(query);
    if (!mounted) return;
    // The text may have moved on while this request was in flight - only
    // show results if they still match what's currently typed.
    if (widget.controller.text != query) return;
    setState(() {
      _suggestions = results;
      _isSearching = false;
    });
  }

  void _select(GeocodeResult result) {
    widget.controller
      ..text = result.displayName
      ..selection = TextSelection.collapsed(offset: result.displayName.length);
    setState(() => _suggestions = const []);
    FocusScope.of(context).unfocus();
    widget.onPlaceSelected?.call(result);
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
              suffixIcon: _isSearching
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
