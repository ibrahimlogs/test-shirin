import 'package:flutter/material.dart';

import '../../../core/values/app_color.dart';
import '../../../core/values/app_style.dart';

// ignore: must_be_immutable
class PersonalListWidgets extends StatelessWidget {
  String hint;
  final String data;

  VoidCallback onPressed;
  PersonalListWidgets({
    super.key,
    required this.hint,
    required this.data,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: TextButton(
        onPressed: onPressed,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(color: AppColors.pageBackgroundGray),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$hint : $data',
                  style: subTitleTextStyleGray,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
