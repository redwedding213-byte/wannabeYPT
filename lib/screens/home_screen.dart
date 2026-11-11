import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../main.dart' show kBrand, yptCardColor;
import '../models.dart';
import 'timer_view.dart';
import 'planner_view.dart';
import 'stats_view.dart';
import 'groups_view.dart';
import 'group_room_screen.dart';

/// Lets inner views (the Timer tab strip, the grid menu) switch the
/// shell's main tab, like the official app's home tabs do.
class TabBus {
  static final ValueNotifier<int> index = ValueNotifier<int>(0);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _roomRestoreTried = false;
  bool _showYesBanner = false;
  bool _bannerFollowUp = false;
  String? _bannerCheckedNick;

  @override
  void initState() {
    super.initState();
    TabBus.index.addListener(_syncTab);
    _restoreTab();
  }

  /// Banner rule: once per PERSON, not once per browser and not once
  /// per login. The flag is keyed by nickname, so logging out and back
  /// in never reshows it, but a different account on the same browser
  /// still gets counted once. A first-version browser-wide flag, if
  /// present, is adopted for whoever is signed in now.
  Future<void> _checkBanner(String nick) async {
    final sp = await SharedPreferences.getInstance();
    if (sp.getBool('yesBannerDone') == true) {
      await sp.setBool('yesBannerDone_$nick', true);
      await sp.remove('yesBannerDone');
    }
    if (!mounted) return;
    if (sp.getBool('yesBannerDone_$nick') != true) {
      setState(() => _showYesBanner = true);
    }
  }

  /// A browser refresh restarts the app — land back on the tab the
  /// user was on instead of always dumping them on Home.
  Future<void> _restoreTab() async {
    final sp = await SharedPreferences.getInstance();
    final t = sp.getInt('shellTab') ?? 0;
    if (t > 0 && t < 5 && mounted) _select(t);
  }

  /// If a group room was open when the page refreshed (and it was
  /// moments ago, not yesterday), reopen it once groups have loaded.
  void _maybeRestoreRoom(AppState st) {
    if (_roomRestoreTried || st.joinedGroups.isEmpty) return;
    _roomRestoreTried = true;
    SharedPreferences.getInstance().then((sp) {
      final id = sp.getInt('openGroupId');
      final at = sp.getInt('openGroupAt') ?? 0;
      if (id == null || !mounted) return;
      if (DateTime.now().millisecondsSinceEpoch - at > 15 * 60 * 1000) {
        return;
      }
      Group? g;
      for (final x in st.joinedGroups) {
        if (x.id == id) {
          g = x;
          break;
        }
      }
      if (g == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GroupRoomScreen(group: g!)));
        }
      });
    });
  }

  @override
  void dispose() {
    TabBus.index.removeListener(_syncTab);
    super.dispose();
  }

  void _syncTab() {
    final v = TabBus.index.value;
    if (v != _tab && mounted) setState(() => _tab = v);
  }

  void _select(int i) {
    setState(() => _tab = i);
    TabBus.index.value = i;
    SharedPreferences.getInstance()
        .then((sp) => sp.setInt('shellTab', i));
  }

  /// YES tap: mark this account counted, tell the owner someone is
  /// actively using the app (same Web3Forms key as feedback), then
  /// swap the strip to the "Wanna say something?" follow-up.
  /// The ping is best-effort — the strip swaps either way.
  Future<void> _pingYes() async {
    // Capture the account before any await (lint-safe).
    final nick = context.read<AppState>().user?.nickname;
    final sp = await SharedPreferences.getInstance();
    if (nick != null) await sp.setBool('yesBannerDone_$nick', true);
    if (mounted) setState(() => _bannerFollowUp = true);
    // The ping used to vanish silently on a single failed attempt.
    // Retry once, and tag each ping uniquely so rapid taps don't look
    // like duplicate spam to the mail provider.
    final pingId = DateTime.now().millisecondsSinceEpoch;
    final now =
        DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} IST';
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await http.post(
          Uri.parse('https://api.web3forms.com/submit'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'access_key': '66a73764-816f-423f-a78d-377042e1af8b',
            'name': '(app user)',
            'subject': 'wannabeYPT: someone is using the app',
            'message':
                'A user tapped YES on the banner. Someone is actively using wannabeYPT. Time: $stamp (Ping #$pingId)',
          }),
        );
        if (r.statusCode == 200) break;
      } catch (_) {}
      if (attempt == 0) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final user = st.user;
    if (user == null) return const SizedBox.shrink();
    // Check once per signed-in account (covers restored sessions and
    // account switches, which initState alone would miss).
    if (_bannerCheckedNick != user.nickname) {
      _bannerCheckedNick = user.nickname;
      _checkBanner(user.nickname);
    }
    _maybeRestoreRoom(st);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (_showYesBanner) _yesBanner(),
            Expanded(
              child: Stack(
                children: [
            // Full width, like the official app — the old 1020 cap
            // left a narrow column floating in black on wide screens.
            IndexedStack(
              index: _tab,
              children: const [
                TimerView(),
                PlannerView(),
                StatsView(),
                GroupsView(),
              ],
            ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 14,
                    child: Center(child: _navPill(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tiny strip above the tab content. First: "Using wannabeYPT?" +
  /// YES. After YES: "Wanna say something?" + Yes (opens the
  /// feedback dialog) / No (just hides). Real TextButtons, so the
  /// pointer turns into a hand on hover like any web button.
  Widget _yesBanner() {
    if (_bannerFollowUp) {
      return Container(
        height: 34,
        color: yptCardColor(context),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Wanna say something?',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _showYesBanner = false;
                  _bannerFollowUp = false;
                });
                _showFeedback(context);
              },
              style: _tinyButtonStyle(kBrand),
              child: const Text('YES',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _showYesBanner = false;
                  _bannerFollowUp = false;
                });
              },
              style: _tinyButtonStyle(Colors.grey),
              child: const Text('NO',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
            ),
          ],
        ),
      );
    }
    return Container(
      height: 34,
      color: yptCardColor(context),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Using wannabeYPT?',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: _pingYes,
            style: _tinyButtonStyle(kBrand),
            child: const Text('YES',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
          ),
        ],
      ),
    );
  }

  /// Keeps the strip tiny: no big default button padding.
  ButtonStyle _tinyButtonStyle(Color color) => TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  Widget _navPill(BuildContext context) {
    final items = <(IconData, IconData, String)>[
      (Icons.home_outlined, Icons.home, 'Home'),
      (Icons.check_circle_outline, Icons.check_circle, 'To-Do'),
      (Icons.bar_chart_outlined, Icons.bar_chart, 'Statistics'),
      (Icons.groups_outlined, Icons.groups, 'Groups'),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: yptCardColor(context),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < items.length; i++)
                InkWell(
                  onTap: () => _select(i),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: _tab == i
                          ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_tab == i ? items[i].$2 : items[i].$1,
                            size: 21,
                            color:
                                _tab == i ? Theme.of(context).colorScheme.onSurface : Colors.grey[500]),
                        const SizedBox(height: 2),
                        Text(items[i].$3,
                            style: TextStyle(
                                fontSize: 10,
                                color: _tab == i
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.grey[500],
                                fontWeight: _tab == i
                                    ? FontWeight.w700
                                    : FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // The official app's round side button changes with the tab:
        // on Groups it's the find-a-group action, elsewhere help.
        InkWell(
          onTap: () => _tab == 3
              ? Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const GroupSearchPage()))
              : _showAbout(context),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: yptCardColor(context),
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08)),
            ),
            child: Icon(
                _tab == 3 ? Icons.group_add_outlined : Icons.question_mark,
                size: 19,
                color: Colors.grey[400]),
          ),
        ),
      ],
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: yptCardColor(context),
        title: const Text('wannabeYPT', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Unofficial web client for YPT (Yeolpumta). Everything syncs with your own YPT account — timers started here show up in the official app, and the other way round.',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 10),
            StatefulBuilder(
              builder: (dialogCtx, setDialogState) {
                final st = dialogCtx.read<AppState>();
                return Row(
                  children: [
                    const Icon(Icons.light_mode_outlined,
                        size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('White mode',
                          style: TextStyle(fontSize: 13)),
                    ),
                    Switch(
                      value: st.lightTheme,
                      activeThumbColor: kBrand,
                      onChanged: (v) {
                        st.setLightTheme(v);
                        setDialogState(() {});
                      },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            StatefulBuilder(
              builder: (dialogCtx, setDialogState) {
                final st = dialogCtx.read<AppState>();
                return Row(
                  children: [
                    const Icon(Icons.videogame_asset_outlined,
                        size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Discord activity',
                          style: TextStyle(fontSize: 13)),
                    ),
                    Switch(
                      value: st.discordRpcEnabled,
                      activeColor: kBrand,
                      onChanged: (v) {
                        st.setDiscordRpcEnabled(v);
                        setDialogState(() {});
                      },
                    ),
                  ],
                );
              },
            ),
            const Text(
                'Experimental: shows your study subject on Discord when Discord is running on this machine. Needs a Discord app set up first.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey)),
            const SizedBox(height: 6),
            const Text('From the developer',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const SelectableText('Telegram: @wannabeypt',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SelectableText('Email: redwedding213@gmail.com',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 10),
            const Text('Recent updates',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
                '• Oct 24 Break counter now starts from your last session.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showFeedback(context);
            },
            child: const Text('Send feedback'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AppState>().logout();
            },
            child: const Text('Log out'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Feedback goes through Web3Forms (same public key as the Study
  /// Timer site), landing in the owner's inbox as 'wannabeYPT feedback'.
  void _showFeedback(BuildContext context) {
    final controller = TextEditingController();
    final contactController = TextEditingController();
    final nick = context.read<AppState>().user?.nickname ?? 'wannabeYPT user';
    var sending = false;
    var category = 'Bug';
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          backgroundColor: yptCardColor(context),
          title: const Text('Feedback', style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: ['Bug', 'Idea', 'Praise'].map((c) {
                    return ChoiceChip(
                      label: Text(c, style: const TextStyle(fontSize: 12.5)),
                      selected: category == c,
                      onSelected: (_) => setState(() => category = c),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 5,
                  minLines: 3,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'What should we fix or add?',
                    hintStyle:
                        TextStyle(color: Colors.grey[600], fontSize: 13.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: contactController,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText:
                        'How to reach you (optional) — email or Telegram name',
                    hintStyle:
                        TextStyle(color: Colors.grey[600], fontSize: 12.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: sending
                  ? null
                  : () async {
                      final msg = controller.text.trim();
                      if (msg.isEmpty) return;
                      setState(() => sending = true);
                      var ok = false;
                      try {
                        // Subject stays exactly 'wannabeYPT feedback'
                        // so the feedback watcher keeps matching it.
                        final body = <String, dynamic>{
                          'access_key':
                              '66a73764-816f-423f-a78d-377042e1af8b',
                          'name': nick,
                          'subject': 'wannabeYPT feedback',
                          'category': category,
                          'message': msg,
                        };
                        final contact = contactController.text.trim();
                        if (contact.isNotEmpty) body['contact'] = contact;
                        final r = await http.post(
                          Uri.parse('https://api.web3forms.com/submit'),
                          headers: const {
                            'Content-Type': 'application/json',
                            'Accept': 'application/json',
                          },
                          body: jsonEncode(body),
                        );
                        ok = r.statusCode == 200;
                      } catch (_) {}
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok
                            ? 'Feedback sent. Thank you!'
                            : 'Could not send. Please try again.'),
                      ));
                    },
              child: Text(sending ? 'Sending…' : 'Send'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      controller.dispose();
      contactController.dispose();
    });
  }
}
