import 'package:flutter/material.dart';
import 'package:retro_c64/widgets/workbench/workbench_shell.dart';

class WorkbenchScreen extends StatelessWidget {
  final VoidCallback? onRerunSetup;

  const WorkbenchScreen({super.key, this.onRerunSetup});

  @override
  Widget build(BuildContext context) {
    return WorkbenchShell(onRerunSetup: onRerunSetup);
  }
}
