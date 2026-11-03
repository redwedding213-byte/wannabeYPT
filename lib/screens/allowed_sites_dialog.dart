import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart' show kBrand, kCard, kCard2;

class AllowedSite {
  final String name;
  final String url;

  const AllowedSite({required this.name, required this.url});

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  factory AllowedSite.fromJson(Map<String, dynamic> j) => AllowedSite(
        name: j['name'] as String? ?? '',
        url: j['url'] as String? ?? '',
      );
}

const List<AllowedSite> kDefaultAllowedSites = [
  AllowedSite(name: 'Notion', url: 'https://www.notion.so'),
  AllowedSite(name: 'Google Docs', url: 'https://docs.google.com'),
  AllowedSite(name: 'Khan Academy', url: 'https://www.khanacademy.org'),
  AllowedSite(name: 'Physics Wallah', url: 'https://www.pw.live'),
  AllowedSite(name: 'Desmos Calculator', url: 'https://www.desmos.com/calculator'),
  AllowedSite(name: 'ChatGPT', url: 'https://chatgpt.com'),
  AllowedSite(name: 'AnkiWeb', url: 'https://ankiweb.net'),
  AllowedSite(name: 'Wikipedia', url: 'https://www.wikipedia.org'),
];

class AllowedSitesDialog extends StatefulWidget {
  const AllowedSitesDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const AllowedSitesDialog(),
    );
  }

  @override
  State<AllowedSitesDialog> createState() => _AllowedSitesDialogState();
}

class _AllowedSitesDialogState extends State<AllowedSitesDialog> {
  static const _prefKey = 'allowed_sites_list_v1';
  List<AllowedSite> _sites = [];
  bool _loading = true;
  bool _adding = false;
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  String? _addError;

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSites() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_prefKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as List;
        final list = decoded
            .whereType<Map<String, dynamic>>()
            .map(AllowedSite.fromJson)
            .where((s) => s.url.isNotEmpty)
            .toList();
        if (list.isNotEmpty) {
          if (mounted) setState(() { _sites = list; _loading = false; });
          return;
        }
      } catch (_) {}
    }
    _sites = List.of(kDefaultAllowedSites);
    await _saveSites();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveSites() async {
    final sp = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_sites.map((s) => s.toJson()).toList());
    await sp.setString(_prefKey, encoded);
  }

  Future<void> _launchSite(AllowedSite site) async {
    try {
      final uri = Uri.parse(site.url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${site.url}')),
      );
    }
  }

  Future<void> _deleteSite(int index) async {
    setState(() {
      _sites.removeAt(index);
    });
    await _saveSites();
  }

  Future<void> _addCustomSite() async {
    final name = _nameCtrl.text.trim();
    var url = _urlCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _addError = 'Site name is required.');
      return;
    }
    if (url.isEmpty) {
      setState(() => _addError = 'Site URL is required.');
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    try {
      final uri = Uri.parse(url);
      if (uri.host.isEmpty) {
        setState(() => _addError = 'Please enter a valid website URL.');
        return;
      }
    } catch (_) {
      setState(() => _addError = 'Please enter a valid website URL.');
      return;
    }

    setState(() {
      _sites.add(AllowedSite(name: name, url: url));
      _nameCtrl.clear();
      _urlCtrl.clear();
      _adding = false;
      _addError = null;
    });
    await _saveSites();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: kBrand.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.shield_outlined, size: 20, color: kBrand),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Allowed Sites',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Approved websites & study resources for focus',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 19, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0x1AFFFFFF)),
              const SizedBox(height: 10),

              // Content
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: [
                          for (var i = 0; i < _sites.length; i++)
                            _siteTile(_sites[i], i),
                          if (_adding) _addSiteForm(),
                        ],
                      ),
              ),

              const SizedBox(height: 10),
              // Bottom Action
              if (!_adding)
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _adding = true;
                        _addError = null;
                      }),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add site', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[200],
                        side: const BorderSide(color: Color(0x33FFFFFF)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done', style: TextStyle(color: kBrand)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _siteTile(AllowedSite site, int index) {
    final host = Uri.tryParse(site.url)?.host ?? site.url;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x0FFFFFFF)),
      ),
      child: Row(
        children: [
          // Favicon / Globe icon
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              'https://www.google.com/s2/favicons?domain=$host&sz=32',
              width: 22,
              height: 22,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.language_rounded,
                size: 20,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  site.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  host,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Open button
          IconButton(
            tooltip: 'Open in new tab',
            icon: const Icon(Icons.open_in_new_rounded, size: 17, color: kBrand),
            onPressed: () => _launchSite(site),
          ),
          // Delete button
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.close_rounded, size: 16, color: Colors.grey[600]),
            onPressed: () => _deleteSite(index),
          ),
        ],
      ),
    );
  }

  Widget _addSiteForm() {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBrand.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Add Approved Site',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Site name (e.g. Physics Wallah)',
              hintStyle: TextStyle(color: Colors.grey, fontSize: 12.5),
              filled: true,
              fillColor: Color(0x14FFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _urlCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'URL (e.g. pw.live or https://...)',
              hintStyle: TextStyle(color: Colors.grey, fontSize: 12.5),
              filled: true,
              fillColor: Color(0x14FFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_addError != null) ...[
            const SizedBox(height: 6),
            Text(
              _addError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _adding = false;
                  _addError = null;
                }),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addCustomSite,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Save site'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
