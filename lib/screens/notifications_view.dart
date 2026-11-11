import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../main.dart' show kBrand, yptCardColor;
import '../models.dart';

/// Notification center (read-only apart from read flags): the
/// account's notifications, tap to mark one read, or mark all read.
/// The endpoints are Desky-derived and unproven live — a failed load
/// shows an error with a retry, never a crash or a fake list.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = false;
  bool _failed = false;
  List<NotificationItem> _items = [];
  final Set<int> _readLocal = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items = await context.read<AppState>().api.fetchNotifications();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  bool _isRead(NotificationItem n) => n.isRead || _readLocal.contains(n.id);

  Future<void> _markRead(NotificationItem n) async {
    if (_isRead(n)) return;
    setState(() => _readLocal.add(n.id));
    final ok =
        await context.read<AppState>().api.markNotificationRead(n.id);
    if (!ok && mounted) setState(() => _readLocal.remove(n.id));
  }

  Future<void> _markAllRead() async {
    final unread = _items.where((n) => !_isRead(n)).toList();
    if (unread.isEmpty) return;
    setState(() => _readLocal.addAll(unread.map((n) => n.id)));
    final ok =
        await context.read<AppState>().api.markAllNotificationsRead();
    if (!ok && mounted) {
      setState(() => _readLocal.removeAll(unread.map((n) => n.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _items.where((n) => !_isRead(n)).length;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text('Notifications',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Could not load notifications',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Text('No notifications.',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12)),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        for (final n in _items) _row(n),
                      ],
                    ),
    );
  }

  Widget _row(NotificationItem n) {
    final read = _isRead(n);
    return InkWell(
      onTap: () => _markRead(n),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
            color: yptCardColor(context), borderRadius: BorderRadius.circular(10)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: read ? Colors.transparent : kBrand,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.title,
                      style: TextStyle(
                          fontWeight:
                              read ? FontWeight.w400 : FontWeight.w600,
                          fontSize: 13.5)),
                  if (n.message.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(n.message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.grey[400], fontSize: 12.5)),
                  ],
                  const SizedBox(height: 4),
                  Text(
                      DateFormat('MMM d, h:mm a').format(n.createdAt),
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
