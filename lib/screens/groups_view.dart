import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import '../main.dart' show kBrand, yptCardColor, yptGrey500, yptGrey600;
import 'group_room_screen.dart';

class GroupsView extends StatefulWidget {
  const GroupsView({super.key});
  @override
  State<GroupsView> createState() => _GroupsViewState();
}

class _GroupsViewState extends State<GroupsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadGroups();
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().loadGroups(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
        children: [
          if (st.groupsErrorText != null) ...[
            Text(st.groupsErrorText!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            const SizedBox(height: 12),
          ],
          const _SectionTitle('My groups'),
          if (st.groupsLoading && st.joinedGroups.isEmpty)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator()))
          else if (st.joinedGroups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                  child: Text('No groups yet',
                      style: TextStyle(color: yptGrey600(context)))),
            )
          else
            ...st.joinedGroups.map((g) => _GroupCard(group: g, joined: true)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );
}

class _GroupCard extends StatelessWidget {
  final Group group;
  final bool joined;
  const _GroupCard({required this.group, required this.joined});

  @override
  Widget build(BuildContext context) {
    // Official style: a flat text row, no card, title, then one grey
    // meta line (category · owner). The rounded InkWell matters on
    // web: without it the hover highlight is a square-cornered band.
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => GroupRoomScreen(group: group))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(
                '${group.category.isNotEmpty ? '${group.category} · ' : ''}'
                '${group.owner}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: yptGrey500(context), fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

/// Browse + search public groups (the Groups tab's round button).
/// Tapping a result opens its room, members are readable without
/// joining; joining itself stays in the official app.
class GroupSearchPage extends StatefulWidget {
  const GroupSearchPage({super.key});
  @override
  State<GroupSearchPage> createState() => _GroupSearchPageState();
}

class _GroupSearchPageState extends State<GroupSearchPage> {
  final _query = TextEditingController();
  List<Group> _all = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final st = context.read<AppState>();
      final countryId = st.user!.countryId;
      final out = <Group>[];
      final seen = <int>{};
      for (var page = 1; page <= 4; page++) {
        final gs = await st.api.browseGroups(countryId, page: page);
        if (gs.isEmpty) break;
        for (final g in gs) {
          if (seen.add(g.id)) out.add(g);
        }
      }
      if (!mounted) return;
      setState(() {
        _all = out;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final joinedIds = st.joinedGroups.map((g) => g.id).toSet();
    final q = _query.text.trim().toLowerCase();
    final results = q.isEmpty
        ? _all
        : _all
            .where((g) =>
                g.title.toLowerCase().contains(q) ||
                g.owner.toLowerCase().contains(q) ||
                g.category.toLowerCase().contains(q))
            .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find groups', style: TextStyle(fontSize: 17)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search groups',
                hintStyle: TextStyle(color: yptGrey600(context), fontSize: 14),
                prefixIcon:
                    Icon(Icons.search, size: 20, color: yptGrey500(context)),
                filled: true,
                fillColor: yptCardColor(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              style: const TextStyle(fontSize: 14.5),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _failed
                    ? Center(
                        child: Text('Could not load groups',
                            style: TextStyle(color: yptGrey500(context))))
                    : results.isEmpty
                        ? Center(
                            child: Text('No groups found',
                                style: TextStyle(color: yptGrey500(context))))
                        : ListView.builder(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: results.length,
                            itemBuilder: (_, i) {
                              final g = results[i];
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                      child:
                                          _GroupCard(group: g, joined: false)),
                                  if (joinedIds.contains(g.id))
                                    const Padding(
                                      padding: EdgeInsets.only(left: 10),
                                      child: Text('Joined',
                                          style: TextStyle(
                                              color: kBrand,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                ],
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
