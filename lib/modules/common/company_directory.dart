import 'package:cloud_firestore/cloud_firestore.dart';

class CompanyOption {
  final String id;
  final String name;

  const CompanyOption({required this.id, required this.name});

  factory CompanyOption.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final rawName = (data['name'] ?? '').toString().trim();
    return CompanyOption(id: doc.id, name: rawName.isEmpty ? doc.id : rawName);
  }
}

Stream<List<CompanyOption>> watchActiveCompanies() {
  return FirebaseFirestore.instance
      .collection('companies')
      .where('active', isEqualTo: true)
      .snapshots()
      .map((snap) {
        final companies = snap.docs.map(CompanyOption.fromDoc).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        return companies;
      });
}
