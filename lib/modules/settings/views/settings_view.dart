import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:nittoseiko_health_care/core/controller/firebase_service.dart';
import 'package:nittoseiko_health_care/modules/common/company_directory.dart';
import 'package:nittoseiko_health_care/modules/settings/widgets/update_alart_dialog_widegets.dart';

import '../../../core/values/app_color.dart';
import '../../../core/values/app_style.dart';
import '../widgets/account_section_widgets.dart';
import '../widgets/goal_Section_widgets.dart';
import '../widgets/sign_out_button_widgets.dart';

import 'package:nittoseiko_health_care/modules/settings/widgets/company_picker_dialog.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final FirebaseService _service = FirebaseService();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('You are not signed in.')),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || !(snapshot.data?.exists ?? false)) {
          return const Scaffold(
            body: Center(child: Text('No profile data found.')),
          );
        }

        final Map<String, dynamic> data =
            (snapshot.data!.data() as Map<String, dynamic>?) ?? const {};

        String readString(String key) {
          final v = data[key];
          if (v == null) return '';
          if (v is Timestamp) {
            final d = v.toDate();
            final mm = d.month.toString().padLeft(2, '0');
            final dd = d.day.toString().padLeft(2, '0');
            return '${d.year}-$mm-$dd';
          }
          return v.toString();
        }

        int readInt(String key, [int fallback = 0]) {
          final v = data[key];
          if (v == null) return fallback;
          if (v is num) return v.toInt();
          return int.tryParse(v.toString()) ?? fallback;
        }

        final nick = readString('nickName');
        final name = readString('name');
        final headerName = nick.isNotEmpty
            ? nick
            : (name.isNotEmpty
                  ? name
                  : (readString('email').isNotEmpty
                        ? readString('email')
                        : 'User'));

        final gender = readString('gender');
        final birthday = readString('birthday');
        final heightStr = readString('height');
        final weightStr = readString('weight');

        final companyName = readString('companyName');
        final companyId = readString('companyId');

        final personalCode = readString('personalCode');
        final goalInt = readInt('stepGoal', 10000);
        final goalStr = goalInt.toString();

        _service.settingsData = data;

        return Scaffold(
          backgroundColor: AppColors.pageBackgroundGray,
          body: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 10),

                TextButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) =>
                          const UpdateAlartDialogWidegets(title: 'Nick Name'),
                    );
                  },
                  child: Text(headerName, style: appbarTextStyleBlack),
                ),

                AccountSectionWidgets(
                  name: name,
                  gender: gender,
                  birthday: birthday,
                  height: heightStr,
                  weight: weightStr,
                  companyName: companyName,
                  personalCode: personalCode,
                  onPressedGender: () {
                    showDialog(
                      context: context,
                      builder: (context) => UpdateAlartDialogWidegets(
                        title: 'Gender',
                        initialValue: gender,
                      ),
                    );
                  },
                  onPressedBirthday: () {
                    showDialog(
                      context: context,
                      builder: (context) => UpdateAlartDialogWidegets(
                        title: 'Birthday',
                        initialValue: birthday,
                      ),
                    );
                  },
                  onPressedHeight: () {
                    showDialog(
                      context: context,
                      builder: (context) =>
                          const UpdateAlartDialogWidegets(title: 'Height'),
                    );
                  },
                  onPressedWeight: () {
                    showDialog(
                      context: context,
                      builder: (context) =>
                          const UpdateAlartDialogWidegets(title: 'Weight'),
                    );
                  },
                  onPressedPersonalCode: () {
                    showDialog(
                      context: context,
                      builder: (context) => UpdateAlartDialogWidegets(
                        title: 'Personal Code',
                        initialValue: personalCode,
                      ),
                    );
                  },
                  onPressedName: () {
                    showDialog(
                      context: context,
                      builder: (context) =>
                          const UpdateAlartDialogWidegets(title: 'Name'),
                    );
                  },
                  onPressedCompanyName: () async {
                    final uid = FirebaseAuth.instance.currentUser!.uid;
                    final CompanyOption? selected =
                        await showCompanyPickerDialog(
                          context,
                          initialCompanyId: companyId.isEmpty
                              ? null
                              : companyId,
                        );
                    if (selected == null) return;

                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .set({
                          'companyId': selected.id,
                          'companyName': selected.name,
                          'companyAssignedAt': FieldValue.serverTimestamp(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                  },
                ),

                GoalSectionWidgets(goal: goalStr),

                // Admin-only: Security Keys
                //                 StreamBuilder<bool>(
                //                   stream: watchIsAdmin(),
                //                   builder: (context, snap) {
                //                     final isAdmin = snap.data == true;
                //                     if (!isAdmin) return const SizedBox.shrink();
                //
                //                     return Padding(
                //                       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                //                       child: ElevatedButton.icon(
                //                         icon: const Icon(Icons.vpn_key),
                //                         label: const Text('Security Keys'),
                //                         onPressed: () {
                //                           Navigator.of(context).push(
                //                             MaterialPageRoute(builder: (_) => const SecurityKeysView()),
                //                           );
                //                         },
                //                       ),
                //                     );
                //                   },
                //                 ),
                // Step Activity button
                // Padding(
                //   padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                //   child: SizedBox(
                //     width: double.infinity,
                //     child: ElevatedButton.icon(
                //       style: ElevatedButton.styleFrom(
                //         padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                //         shape: RoundedRectangleBorder(
                //           borderRadius: BorderRadius.circular(12),
                //         ),
                //       ),
                //       icon: const Icon(Icons.insights),
                //       label: const Text(
                //         'Step Activity',
                //         style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                //       ),
                //       onPressed: () {
                //         Navigator.of(context).push(
                //           MaterialPageRoute(builder: (_) => const ActivityHistoryPage()),
                //         );
                //       },
                //     ),
                //   ),
                // ),

                // Admin-only
                // StreamBuilder<bool>(
                //   stream: watchIsAdmin(),
                //   builder: (context, snap) {
                //     final isAdmin = snap.data == true;
                //     if (!isAdmin) return const SizedBox.shrink();
                //
                //     return Padding(
                //       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                //       child: ElevatedButton.icon(
                //         icon: const Icon(Icons.business),
                //         label: const Text('Manage Companies'),
                //         onPressed: () {
                //           Navigator.of(context).push(
                //             MaterialPageRoute(builder: (_) => const CompaniesAdminPage()),
                //           );
                //         },
                //       ),
                //     );
                //   },
                // ),
                const SignOutButtonWidget(),
              ],
            ),
          ),
        );
      },
    );
  }
}
