import 'package:flutter/material.dart';

import '../../common/company_directory.dart';

Future<CompanyOption?> showCompanyPickerDialog(
  BuildContext context, {
  String? initialCompanyId,
}) {
  return showModalBottomSheet<CompanyOption>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return _CompanyPickerStandalone(
          initialCompanyId: initialCompanyId,
          controller: controller,
          onClose: () => Navigator.pop(sheetContext),
        );
      },
    ),
  );
}

class _CompanyPickerStandalone extends StatelessWidget {
  const _CompanyPickerStandalone({
    required this.initialCompanyId,
    required this.controller,
    required this.onClose,
  });

  final String? initialCompanyId;
  final ScrollController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    String query = '';
    return StatefulBuilder(
      builder: (ctx, setState) {
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
                          setState(() => query = text.trim().toLowerCase()),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: onClose),
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
                      if (query.isEmpty) return true;
                      return company.name.toLowerCase().contains(query);
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
                        final selected = initialCompanyId == company.id;

                        return ListTile(
                          title: Text(company.name),
                          trailing: selected
                              ? const Icon(Icons.check, size: 18)
                              : null,
                          onTap: () => Navigator.pop(context, company),
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
    );
  }
}
