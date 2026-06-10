import 'package:flutter/material.dart';
import '../../dashboard/screens/dashboard_screen.dart';
import 'file_upload_screen.dart';
import 'pending_approval_screen.dart';
import 'subscription_screen.dart';
import 'rejected_screen.dart';
import 'admin_panel_screen.dart';

class AuthRouter extends StatelessWidget {
  final String status;
  final bool isAdmin;

  const AuthRouter({
    super.key,
    required this.status,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    if (isAdmin) {
      return const AdminPanelScreen();
    }

    switch (status) {
      case 'pending_admin':
        return const PendingApprovalScreen();

      case 'onboarding_required':
        return const FileUploadScreen();

      case 'onboarding_submitted':
      case 'configured':
        return const DashboardScreen();

      case 'scraper_generating':
      case 'scraper_review':
        return const PendingApprovalScreen();

      case 'active':
        return const DashboardScreen();

      case 'rejected':
        return const RejectedScreen();

      // stare statusy zostawione kompatybilnie
      case 'pending_file':
        return const FileUploadScreen();

      case 'pending_approval':
        return const PendingApprovalScreen();

      case 'awaiting_payment':
        return const SubscriptionScreen();

      default:
        return const DashboardScreen();
    }
  }
}