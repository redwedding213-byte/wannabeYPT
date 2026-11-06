import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../main.dart' show kBrand, kCard;
import '../models.dart';
import '../ypt_api.dart';

/// Flashcards / Books (Desky parity, built 2026-11-06).
/// Decks live on the server (POST /card/book/*); cards too
/// (POST /card/*). The server owns SM-2 scheduling — this screen
/// only reports the ease factor (1 hard, 2 good, 3 easy) through
/// POST /card/review. Nothing here touches study time or the timer.
///
/// The 2026-10-29 removal is the reason for the care here: deck
/// creation failed live because the old code demanded exactly HTTP
/// 200 and swallowed the server's error. The API layer now accepts
/// any 2xx and throws with the server's `m` message — and every
/// failure below shows that message in a SnackBar, never a generic
/// "couldn't do that".
class BooksPage extends StatefulWidget {
  const BooksPage({super.key});
  @override
  State<BooksPage> createState() => _BooksPageState();
}

/// Colour choices for new decks, including the brand orange and a
/// neutral grey — same palette as subjects.
const _palette = <int>[
  0xFFE8552D,
  4292557552,
  4294924032,
  4281775359,
  4280549375,
  4282827050,
  4294947910,
  0xFF888888,
];

class _BooksPageState extends State<BooksPage> {
  bool _loading = false;
  bool _failed = false;
  String? _error;
  bool _busy = false;
  List<FlashcardDeck> _decks = [];

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
      _error = null;
    });
    try {
      final decks = await context.read<AppState>().api.fetchDecks();
      if (!mounted) return;
      setState(() {
        _decks = decks;
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

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _createDeckDialog() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var color = _palette.first;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('New deck', style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Deck name'),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setDialog(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration:
                    const InputDecoration(hintText: 'Description (optional)'),
                maxLines: 2,
                minLines: 1,
              ),
              const SizedBox(height: 16),
              const Text('Colour',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _palette)
                    InkWell(
                      onTap: () => setDialog(() => color = c),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == c
                                ? Colors.white
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: titleCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) {
      titleCtrl.dispose();
      descCtrl.dispose();
      return;
    }
    final title = titleCtrl.text.trim();
    final desc = descCtrl.text.trim();
    titleCtrl.dispose();
    descCtrl.dispose();
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.createDeck(
            title: title,
            colorInt: color,
            description: desc.isEmpty ? null : desc,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      // Server state is ground truth: reload so the deck shows with
      // its real id (the create reply may not carry the book object).
      await _load();
    } on YptApiException catch (e) {
      if (mounted) setState(() => _busy = false);
      _showError(e.message);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _showError('Could not create that deck — check connection and retry.');
    }
  }

  Future<void> _deleteDeck(FlashcardDeck deck) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Delete deck', style: TextStyle(fontSize: 16)),
        content: Text(
            'Delete "${deck.title}" and all its cards permanently?',
            style: const TextStyle(fontSize: 13, color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final ok =
        await context.read<AppState>().api.deleteDeck(deck.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      await _load();
    } else {
      _showError('Could not delete that deck — try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0F),
        elevation: 0,
        title: const Text('Books',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'New deck',
            icon: const Icon(Icons.add, size: 22),
            onPressed: _busy ? null : _createDeckDialog,
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
                      Text('Could not load your decks',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12)),
                      if (_error != null) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(_error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 11)),
                        ),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _decks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.style_outlined,
                              size: 64, color: Colors.grey[600]),
                          const SizedBox(height: 16),
                          const Text('No decks yet',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(
                              'Create a deck and add cards to revise faster.',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 13)),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _busy ? null : _createDeckDialog,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Create deck'),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        for (final deck in _decks) _deckRow(deck),
                      ],
                    ),
    );
  }

  Widget _deckRow(FlashcardDeck deck) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: kCard, borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _DeckDetailPage(deck: deck)));
          // Card counts may have changed while inside.
          if (mounted) _load();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: deck.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deck.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    if (deck.description != null &&
                        deck.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(deck.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 12)),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                          '${deck.cardCount} card${deck.cardCount == 1 ? '' : 's'}',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12)),
                    ),
                  ],
                ),
              ),
              if (deck.cardCount > 0)
                TextButton.icon(
                  onPressed: () async {
                    final cards = await _fetchCardsForStudy(deck);
                    if (!mounted) return;
                    if (cards == null) return; // error already shown
                    if (cards.isEmpty) {
                      _showError('This deck has no cards yet.');
                      return;
                    }
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            _StudyPage(deck: deck, cards: cards)));
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Study'),
                  style: TextButton.styleFrom(foregroundColor: deck.color),
                ),
              IconButton(
                tooltip: 'Delete deck',
                icon: const Icon(Icons.delete_outline, size: 19),
                color: Colors.redAccent,
                onPressed: _busy ? null : () => _deleteDeck(deck),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Loads a deck's cards for a study session; null means the load
  /// failed (error already surfaced).
  Future<List<Flashcard>?> _fetchCardsForStudy(FlashcardDeck deck) async {
    try {
      return await context.read<AppState>().api.fetchCards(deck.id);
    } on YptApiException catch (e) {
      _showError(e.message);
      return null;
    } catch (_) {
      _showError('Could not load the cards — check connection and retry.');
      return null;
    }
  }
}

/// One deck: its cards, add/delete card, start a study session.
class _DeckDetailPage extends StatefulWidget {
  final FlashcardDeck deck;
  const _DeckDetailPage({required this.deck});

  @override
  State<_DeckDetailPage> createState() => _DeckDetailPageState();
}

class _DeckDetailPageState extends State<_DeckDetailPage> {
  bool _loading = false;
  bool _failed = false;
  String? _error;
  bool _busy = false;
  List<Flashcard> _cards = [];

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
      _error = null;
    });
    try {
      final cards =
          await context.read<AppState>().api.fetchCards(widget.deck.id);
      if (!mounted) return;
      setState(() {
        _cards = cards;
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

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _addCardDialog() async {
    final frontCtrl = TextEditingController();
    final backCtrl = TextEditingController();
    final hintCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('New card', style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: frontCtrl,
                autofocus: true,
                decoration:
                    const InputDecoration(hintText: 'Question (front)'),
                maxLines: 3,
                minLines: 1,
                onChanged: (_) => setDialog(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: backCtrl,
                decoration: const InputDecoration(hintText: 'Answer (back)'),
                maxLines: 3,
                minLines: 1,
                onChanged: (_) => setDialog(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hintCtrl,
                decoration:
                    const InputDecoration(hintText: 'Hint (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: frontCtrl.text.trim().isEmpty ||
                      backCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) {
      frontCtrl.dispose();
      backCtrl.dispose();
      hintCtrl.dispose();
      return;
    }
    final front = frontCtrl.text.trim();
    final back = backCtrl.text.trim();
    final hint = hintCtrl.text.trim();
    frontCtrl.dispose();
    backCtrl.dispose();
    hintCtrl.dispose();
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.createCard(
            deckId: widget.deck.id,
            front: front,
            back: back,
            hint: hint.isEmpty ? null : hint,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      await _load();
    } on YptApiException catch (e) {
      if (mounted) setState(() => _busy = false);
      _showError(e.message);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _showError('Could not add that card — check connection and retry.');
    }
  }

  Future<void> _deleteCard(Flashcard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Delete card', style: TextStyle(fontSize: 16)),
        content: const Text('Delete this card permanently?',
            style: TextStyle(fontSize: 13, color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final ok =
        await context.read<AppState>().api.deleteCard(card.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      await _load();
    } else {
      _showError('Could not delete that card — try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final deck = widget.deck;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0F),
        elevation: 0,
        title: Text(deck.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Add card',
            icon: const Icon(Icons.add, size: 22),
            onPressed: _busy ? null : _addCardDialog,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_cards.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            _StudyPage(deck: deck, cards: _cards)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text('Study ${_cards.length} card${_cards.length == 1 ? '' : 's'}'),
                  style: FilledButton.styleFrom(
                      backgroundColor: deck.color,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _failed
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Could not load the cards',
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 12)),
                            if (_error != null) ...[
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32),
                                child: Text(_error!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 11)),
                              ),
                            ],
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _cards.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.style_outlined,
                                    size: 64, color: Colors.grey[600]),
                                const SizedBox(height: 16),
                                const Text('No cards yet',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text('Add your first card to start revising.',
                                    style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 13)),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed:
                                      _busy ? null : _addCardDialog,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add card'),
                                ),
                              ],
                            ),
                          )
                        : ListView(
                            padding:
                                const EdgeInsets.fromLTRB(16, 4, 16, 32),
                            children: [
                              for (final card in _cards) _cardRow(card),
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Widget _cardRow(Flashcard card) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
          color: kCard, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.front,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(card.back,
                    style:
                        TextStyle(color: Colors.grey[400], fontSize: 13)),
                if (card.hint != null && card.hint!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('Hint: ${card.hint!}',
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 11)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete card',
            icon: const Icon(Icons.delete_outline, size: 19),
            color: Colors.redAccent,
            onPressed: _busy ? null : () => _deleteCard(card),
          ),
        ],
      ),
    );
  }
}

/// A review session: tap to flip, then rate Hard / Good / Easy.
/// The rating is reported to the server (POST /card/review) — the
/// server schedules the next review. A failed report never blocks
/// the session: the card still advances, exactly like Desky.
class _StudyPage extends StatefulWidget {
  final FlashcardDeck deck;
  final List<Flashcard> cards;
  const _StudyPage({required this.deck, required this.cards});

  @override
  State<_StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<_StudyPage> {
  int _index = 0;
  bool _flipped = false;
  bool _done = false;

  Flashcard get _card => widget.cards[_index];

  void _answer(int easeFactor) {
    final card = _card;
    // Fire and forget — the session moves on regardless.
    unawaited(context
        .read<AppState>()
        .api
        .submitCardReview(cardId: card.id, easeFactor: easeFactor));
    setState(() {
      if (_index + 1 >= widget.cards.length) {
        _done = true;
      } else {
        _index += 1;
        _flipped = false;
      }
    });
  }

  void _restart() {
    setState(() {
      _index = 0;
      _flipped = false;
      _done = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final deck = widget.deck;
    final total = widget.cards.length;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0F),
        elevation: 0,
        title: Text(deck.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Text(
                _done ? '$total / $total' : '${_index + 1} / $total',
                style: TextStyle(
                    color: Colors.grey[400], fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: _done ? 1 : (_index + 1) / total,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(deck.color),
          ),
        ),
      ),
      body: SafeArea(
        child: _done
            ? _sessionComplete(context)
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _flipped = !_flipped),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: kCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _flipped
                                  ? deck.color
                                  : Colors.white.withValues(alpha: 0.08),
                              width: 2,
                            ),
                          ),
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: deck.color.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _flipped ? 'ANSWER' : 'QUESTION',
                                  style: TextStyle(
                                    color: deck.color,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _flipped ? _card.back : _card.front,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  height: 1.4,
                                ),
                              ),
                              if (!_flipped &&
                                  _card.hint != null &&
                                  _card.hint!.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF222227),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.08)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.lightbulb_outline,
                                          size: 16, color: Colors.amber),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Hint: ${_card.hint!}',
                                          style: TextStyle(
                                              color: Colors.grey[400],
                                              fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const Spacer(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.touch_app_outlined,
                                      size: 16, color: Colors.grey[500]),
                                  const SizedBox(width: 6),
                                  Text('Tap to flip',
                                      style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (!_flipped)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: () =>
                              setState(() => _flipped = true),
                          icon: const Icon(Icons.visibility_outlined,
                              color: Colors.white),
                          label: const Text('Show answer',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          style: FilledButton.styleFrom(
                            backgroundColor: deck.color,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: _easeButton(
                              label: 'Hard',
                              icon: Icons.close_rounded,
                              color: Colors.redAccent,
                              onTap: () => _answer(1),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _easeButton(
                              label: 'Good',
                              icon: Icons.thumb_up_alt_outlined,
                              color: kBrand,
                              onTap: () => _answer(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _easeButton(
                              label: 'Easy',
                              icon: Icons
                                  .sentiment_very_satisfied_outlined,
                              color: Colors.green,
                              onTap: () => _answer(3),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _easeButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 20),
        label: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _sessionComplete(BuildContext context) {
    final total = widget.cards.length;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.celebration_rounded,
              size: 72, color: Colors.amber),
          const SizedBox(height: 20),
          const Text('Session complete!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text('You reviewed all $total card${total == 1 ? '' : 's'} in this deck.',
              style: TextStyle(color: Colors.grey[400], fontSize: 15)),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _restart,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Review again'),
                style: FilledButton.styleFrom(backgroundColor: kBrand),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_rounded, color: Colors.white),
                label: const Text('Done',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
