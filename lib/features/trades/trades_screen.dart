import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/trades_repository.dart';
import '../../widgets/common.dart';
import 'trade_form_screen.dart';

class TradesScreen extends ConsumerStatefulWidget {
  const TradesScreen({super.key});

  @override
  ConsumerState<TradesScreen> createState() => _TradesScreenState();
}

class _TradesScreenState extends ConsumerState<TradesScreen> {
  String? _account;

  @override
  Widget build(BuildContext context) {
    final trades = ref.watch(tradesProvider(TradeFilter(account: _account)));
    final summary = ref.watch(tradesSummaryProvider).valueOrNull ?? const <Rec>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _account == null,
                onSelected: (_) => setState(() => _account = null),
              ),
              const SizedBox(width: 8),
              for (final a in accountTypes) ...[
                ChoiceChip(
                  label: Text(pretty(a)),
                  selected: _account == a,
                  onSelected: (_) => setState(() => _account = a),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const TradeFormScreen()),
                ),
                icon: const Icon(Icons.add),
                label: const Text('New'),
              ),
            ],
          ),
        ),
        if (summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                for (final s in summary)
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${pretty(s.s('account_type'))} account',
                                style: Theme.of(context).textTheme.labelMedium),
                            Text('${s.i('trade_count')} trades, ${s.i('closed_count')} closed'),
                            Text('Net: ${formatMinor(s.i('net_minor'))}'),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: trades.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyState('$e'),
            data: (items) {
              if (items.isEmpty) {
                return const EmptyState(
                    'No trades recorded.\nResearch cases do not need trades; record a trade only when you actually take one.');
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final t = items[i];
                  final net = netMinor(t);
                  final adherence = t.sn('rule_adherence');
                  return Card(
                    child: ListTile(
                      title: Text('${t.s('instrument')} ${t.s('direction')}'),
                      subtitle: Text([
                        pretty(t.s('account_type')),
                        pretty(t.s('status')),
                        formatLocalDate(t.sn('opened_at')),
                        if (t.sn('case_title') != null) 'Case: ${t.s('case_title')}',
                        if (adherence != null) 'Rules $adherence',
                      ].join('  |  ')),
                      trailing: net == null
                          ? null
                          : Text(
                              formatMinor(net),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: net >= 0 ? Colors.green.shade700 : Theme.of(context).colorScheme.error,
                              ),
                            ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => TradeFormScreen(tradeId: t.s('id'))),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
