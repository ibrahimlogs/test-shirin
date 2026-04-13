import 'package:flutter/material.dart';
import 'package:nittoseiko_health_care/core/values/app_style.dart';

class SignUpEmailTextFieldWidget extends StatelessWidget {
  final TextEditingController controller;
  final String? Function(String?)? validator;

  const SignUpEmailTextFieldWidget({
    super.key,
    required this.controller,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        hintText: 'Email',
        labelText: 'Email',
        labelStyle: subTitleTextStyleGray,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
      ),
      validator: validator,
      autofillHints: const [AutofillHints.email],
    );
  }
}
