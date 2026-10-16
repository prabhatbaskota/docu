import 'package:flutter/material.dart';

/// The one place snackbars are made. Flutter keeps a snackbar that has an
/// action on screen until dismissed unless `persist` is false, so every
/// message here times out by itself.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> toastOn(
  ScaffoldMessengerState messenger,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  messenger.hideCurrentSnackBar();
  return messenger.showSnackBar(SnackBar(
    content: Text(message),
    duration: duration,
    persist: false,
    behavior: SnackBarBehavior.floating,
    action: actionLabel == null
        ? null
        : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
  ));
}

void toast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  toastOn(ScaffoldMessenger.of(context), message,
      actionLabel: actionLabel, onAction: onAction, duration: duration);
}
