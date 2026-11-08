import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../fiscal_year/fiscal_years_screen.dart';
import 'add_project_dialog.dart';

class ManageProjectsDialog extends StatefulWidget {
  final AppDatabase db;
  final String activeProjectId;
  final ValueChanged<String> onSelectProject;

  const ManageProjectsDialog({
    super.key,
    required this.db,
    required this.activeProjectId,
    required this.onSelectProject,
  });

  @override
  State<ManageProjectsDialog> createState() => _ManageProjectsDialogState();
}

class _ManageProjectsDialogState extends State<ManageProjectsDialog> {
  List<Project> _projects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _isLoading = true);
    final list = await widget.db.select(widget.db.projects).get();
    if (mounted) {
      setState(() {
        _projects = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _openAddProject() async {
    final created = await Navigator.of(context).push<Project>(
      MaterialPageRoute(
        builder: (ctx) => AddProjectDialog(db: widget.db),
      ),
    );

    if (created != null) {
      await _loadProjects();
      widget.onSelectProject(created.id);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مدیریت پروژه‌ها'),
          actions: [
            IconButton(
              icon: const Icon(Icons.swap_horiz_outlined),
              tooltip: 'مدیریت سال‌های مالی و انتقال دوره',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (ctx) => const FiscalYearsScreen()),
                );
                await _loadProjects();
              },
            ),
            IconButton(
              icon: const Icon(Icons.add_business_outlined),
              tooltip: 'تعریف پروژه جدید',
              onPressed: _openAddProject,
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _projects.isEmpty
                        ? const Center(child: Text('هیچ پروژه‌ای تعریف نشده است.'))
                        : ListView.separated(
                            itemCount: _projects.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final p = _projects[i];
                              final isActive = p.id == widget.activeProjectId;
                              final isLocked = p.status == 'locked';

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: (isActive ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest),
                                  foregroundColor: isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                                  child: Icon(isLocked ? Icons.lock : Icons.business),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p.name,
                                        style: TextStyle(
                                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    if (isActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.green.shade600),
                                        ),
                                        child: Text(
                                          'فعال',
                                          style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  isLocked ? 'وضعیت: قفل‌شده (فقط خواندنی)' : 'وضعیت: باز',
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                                ),
                                trailing: isActive
                                    ? null
                                    : TextButton(
                                        onPressed: () {
                                          widget.onSelectProject(p.id);
                                          Navigator.of(context).pop();
                                        },
                                        child: const Text('انتخاب'),
                                      ),
                              );
                            },
                          ),
              ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.swap_horiz),
                            label: const Text('انتقال و بستن سال مالی'),
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (ctx) => const FiscalYearsScreen()),
                              );
                              await _loadProjects();
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('تعریف پروژه جدید'),
                            onPressed: _openAddProject,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
