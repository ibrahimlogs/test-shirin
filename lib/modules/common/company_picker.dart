import 'package:flutter/material.dart';

import 'company_directory.dart';

class CompanyPickerFormField extends FormField<CompanyOption> {
  CompanyPickerFormField({
    super.key,
    super.initialValue,
    super.onSaved,
    FormFieldValidator<CompanyOption>? validator,
    AutovalidateMode autovalidateMode = AutovalidateMode.disabled,
    String? labelText,
    ValueChanged<CompanyOption?>? onChanged,
  }) : super(
         validator:
             validator ??
             (value) => value == null ? 'Please select a company' : null,
         autovalidateMode: autovalidateMode,
         builder: (state) => _CompanyPickerFieldBody(
           state: state,
           labelText: labelText,
           onChanged: onChanged,
         ),
       );
}

class _CompanyPickerFieldBody extends StatefulWidget {
  final FormFieldState<CompanyOption> state;
  final String? labelText;
  final ValueChanged<CompanyOption?>? onChanged;

  const _CompanyPickerFieldBody({
    required this.state,
    this.labelText,
    this.onChanged,
  });

  @override
  State<_CompanyPickerFieldBody> createState() =>
      _CompanyPickerFieldBodyState();
}

class _CompanyPickerFieldBodyState extends State<_CompanyPickerFieldBody> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final error = widget.state.errorText;
    final selected = widget.state.value;

    return InputDecorator(
      isEmpty: selected == null,
      decoration: InputDecoration(
        labelText: widget.labelText ?? 'Company',
        border: const OutlineInputBorder(),
        errorText: error,
        isDense: true,
      ),
      child: InkWell(
        onTap: _openPicker,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            selected?.name ?? 'Select a company',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker() async {
    setState(() => _query = '');
    final choice = await showModalBottomSheet<CompanyOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        textCapitalization: TextCapitalization.none,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          hintText: 'Search companies...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (text) =>
                            setState(() => _query = text.trim().toLowerCase()),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<List<CompanyOption>>(
                    stream: watchActiveCompanies(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(child: Text('Error: ${snap.error}'));
                      }

                      final companies = snap.data ?? const <CompanyOption>[];
                      final filtered = companies.where((company) {
                        if (_query.isEmpty) return true;
                        return company.name.toLowerCase().contains(_query);
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text(
                            'No active companies found. Please contact admin.',
                          ),
                        );
                      }

                      return ListView.separated(
                        controller: controller,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final company = filtered[index];
                          return ListTile(
                            title: Text(company.name),
                            onTap: () => Navigator.pop(sheetContext, company),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (choice != null) {
      widget.state.didChange(choice);
      widget.onChanged?.call(choice);
    }
  }
}
