import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../main.dart' show kBrand, kCard;
import '../models.dart';
import '../ypt_api.dart';

/// Avatar Store (Desky parity, built 2026-11-06).
/// Browse studicon dolls and equip the ones you own. Nothing here
/// touches study time or the timer.
///
/// Endpoints (Desky's store_repository.dart + the captured-traffic
/// spec): famous/new/tag, my/list, wish and equip all go through
/// the main API (pi.tgclab.com) with the normal authed calls. The
/// catalog was first pointed at the picf.tgclab.com CDN, but the CDN
/// proved unreliable from the browser ("Load failed" live, 2026-11-06)
/// and pi returns the same shape, so the CDN is not used. All reads
/// accept any 2xx and surface the server's `m` message on failure.
///
/// What this store does NOT do: buy. There is no purchase endpoint
/// in Desky or the spec, and Desky's store only ever equips owned
/// items — so not-owned items show their flame price with a note
/// that buying happens in the official YPT app. The equip call
/// (POST /user/studicon) is confirmed only by Desky's code, not by
/// the spec; the live test (equip one, confirm it shows) is the
/// proof. After a successful equip the group room picks the new
/// doll up on its 20 s member poll — no app restart needed.
class AvatarStorePage extends StatefulWidget {
  const AvatarStorePage({super.key});
  @override
  State<AvatarStorePage> createState() => _AvatarStorePageState();
}

class _AvatarStorePageState extends State<AvatarStorePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  bool _loading = false;
  bool _failed = false;
  String? _error;

  Set<int> _ownedIds = {};
  List<StudiconItem> _famous = [];
  List<StudiconItem> _new = [];
  List<StudiconTag> _tags = [];
  List<StudiconItem> _wishlist = [];

  /// Equipped studicon id; -1 (or 0) = the default orange doll.
  /// Starts from the profile (reload/info `p.si`/`csd`/`ssd`).
  int _equippedId = -1;
  int? _equippingId;

  /// Tag filter for the Famous / New tabs; null = all.
  int? _selectedTagId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _equippedId =
        context.read<AppState>().user?.studiconId ?? -1;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
      _error = null;
    });
    try {
      final api = context.read<AppState>().api;
      final results = await Future.wait([
        api.fetchMyStudiconIds(),
        api.fetchFamousStudicons(),
        api.fetchNewStudicons(),
        api.fetchStudiconTags(),
        api.fetchWishlistStudicons(),
      ]);
      if (!mounted) return;
      final owned = results[0] as Set<int>;
      final famous = results[1] as List<StudiconItem>;
      final fresh = results[2] as List<StudiconItem>;
      final tags = results[3] as List<StudiconTag>;
      final wishlist = results[4] as List<StudiconItem>;
      setState(() {
        _ownedIds = owned;
        _famous = famous.map((i) => _markOwned(i, owned)).toList();
        _new = fresh.map((i) => _markOwned(i, owned)).toList();
        _tags = tags;
        _wishlist = wishlist.map((i) => _markOwned(i, owned)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
        _error = e.toString();
      });
    }
  }

  static StudiconItem _markOwned(StudiconItem item, Set<int> owned) =>
      item.copyWith(isOwned: owned.contains(item.id));

  /// The default orange doll, always owned. Equipped when the
  /// profile carries no studicon id.
  StudiconItem get _defaultDoll => StudiconItem(
        id: -1,
        name: 'Default doll',
        description: 'The classic orange YPT doll.',
        priceFlames: 0,
        isOwned: true,
        isEquipped: _equippedId <= 0,
      );

  List<StudiconItem> get _myAvatars {
    final byId = <int, StudiconItem>{-1: _defaultDoll};
    for (final list in [_famous, _new, _wishlist]) {
      for (final item in list) {
        if (item.isOwned) byId.putIfAbsent(item.id, () => item);
      }
    }
    return byId.values.toList();
  }

  List<StudiconItem> _tagged(List<StudiconItem> items) {
    final tagId = _selectedTagId;
    if (tagId == null) return items;
    return items
        .where((i) => i.tags.any((t) => t.id == tagId))
        .toList();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Equip an owned studicon. Optimistic local update, revert on
  /// failure so the UI never claims an equip the server refused.
  /// The profile refreshes in the background; the just-equipped id
  /// is kept as the local truth so a slow profile read cannot
  /// overwrite it with the stale value.
  Future<void> _equip(StudiconItem item) async {
    if (_equippingId != null || item.id == _equippedId) return;
    if (item.id != -1 && !_ownedIds.contains(item.id)) return;
    final previous = _equippedId;
    final st = context.read<AppState>();
    setState(() {
      _equippedId = item.id;
      _equippingId = item.id;
    });
    try {
      await st.api.equipStudicon(item.id);
      // Background profile refresh (best effort, never blocks).
      // ignore: unawaited_futures
      st.reloadProfile().catchError((_) {});
      if (!mounted) return;
      setState(() => _equippingId = null);
      _showMessage('Avatar "${item.name}" equipped');
    } on YptApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _equippedId = previous;
        _equippingId = null;
      });
      _showError(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _equippedId = previous;
        _equippingId = null;
      });
      _showError('Could not equip that avatar — check connection and retry.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0F),
        title: const Text('Avatar Store',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Reload',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: kBrand,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'My avatars'),
            Tab(text: 'Famous'),
            Tab(text: 'New'),
            Tab(text: 'Wishlist'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kBrand))
          : _failed
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off_outlined,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 14),
                        Text(
                          _error ?? 'Could not load avatars.',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _load,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kBrand,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _gridTab(_myAvatars, 'No avatars yet.'),
                          _catalogTab(_tagged(_famous), 'Nothing here yet.'),
                          _catalogTab(_tagged(_new), 'Nothing here yet.'),
                          _gridTab(_wishlist,
                              'Your wishlist is empty.'),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Text(
                        'Buying avatars happens in the official YPT app — here you can equip the ones you own.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
    );
  }

  /// A tab with a tag filter row (Famous / New). The tag list comes
  /// from GET /studicon/list/tag; filtering is client-side because
  /// no "list items by tag id" endpoint exists.
  Widget _catalogTab(List<StudiconItem> items, String emptyText) {
    return Column(
      children: [
        if (_tags.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _tagChip(null, 'All'),
                for (final tag in _tags) _tagChip(tag.id, tag.name),
              ],
            ),
          ),
        Expanded(child: _grid(items, emptyText)),
      ],
    );
  }

  Widget _tagChip(int? tagId, String label) {
    final selected = _selectedTagId == tagId;
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8, bottom: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _selectedTagId = tagId);
        },
        selectedColor: kBrand,
        backgroundColor: kCard,
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.grey[300],
          fontSize: 12,
        ),
        side: BorderSide(
            color: selected ? kBrand : Colors.grey[800]!),
      ),
    );
  }

  Widget _gridTab(List<StudiconItem> items, String emptyText) =>
      _grid(items, emptyText);

  Widget _grid(List<StudiconItem> items, String emptyText) {
    if (items.isEmpty) {
      return Center(
        child: Text(emptyText,
            style: const TextStyle(color: Colors.grey, fontSize: 13)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.72,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _itemCard(items[index]),
    );
  }

  Widget _itemCard(StudiconItem item) {
    final owned = item.id == -1 || _ownedIds.contains(item.id);
    final equipped = item.id == _equippedId ||
        (item.id == -1 && _equippedId <= 0);
    final equipping = _equippingId == item.id;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: equipped ? kBrand : Colors.grey[800]!,
          width: equipped ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Image.network(
              item.previewUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.person_outline,
                size: 56,
                color: Colors.white54,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Tooltip(
            message: item.description ?? item.name,
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (!owned)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_fire_department,
                    size: 13, color: Colors.orange),
                const SizedBox(width: 3),
                Text(
                  '${item.priceFlames} flames',
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            )
          else
            const SizedBox(height: 15),
          const SizedBox(height: 8),
          if (equipped)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'EQUIPPED',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else if (owned)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: equipping ? null : () => _equip(item),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: equipping
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Equip',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'Not owned',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
